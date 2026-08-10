import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What the source file said its pixels were, as far as this can tell.
///
/// Only the identity is carried forward. The bytes that expressed it are read,
/// classified and dropped — see [IccColourProfile].
enum SourceColourSpace {
  /// The file carried no ICC profile. The overwhelmingly common case, and the
  /// one where sRGB is already the right reading.
  absent,

  /// A profile whose colorants are sRGB's, to within [IccColourProfile.tolerance].
  srgb,

  /// A profile whose colorants are Display P3's, to within
  /// [IccColourProfile.tolerance].
  displayP3,

  /// A well-formed RGB profile for a colour space this does not emit — Adobe
  /// RGB, Rec. 2020, ProPhoto, or a LUT-based profile with no colorant tags.
  unrecognised,

  /// The profile bytes were not a profile: truncated, mis-signed, a tag table
  /// pointing outside itself, or a `deflate` stream that would not inflate
  /// within its budget.
  unreadable,
}

/// Reads the *identity* of a source colour space and, for the one wide-gamut
/// space phone cameras produce, synthesises a canonical profile to replace it.
///
/// `ImageMetadataScrubber` rebuilds a picked image from its pixels so that no
/// byte of the source container survives. That closes every metadata channel at
/// once, but it also throws away the ICC profile, and `image`'s decoder is not
/// colour managed: a Display P3 capture keeps its P3 numbers and arrives with
/// nothing to read them by, so the receiver reads them as sRGB and the photo
/// looks oversaturated.
///
/// The fix is the one the orientation handling already uses: classify, discard,
/// re-synthesise. The source profile is parsed only far enough to answer *which
/// space is this*, the bytes that answered it are dropped with the rest of the
/// container, and the output carries a profile this file builds from published
/// constants — chromaticity coordinates, a white point, a Bradford matrix and
/// five transfer-curve parameters. Nothing derived from the input reaches the
/// output except a single value out of [SourceColourSpace], which is the same
/// shape of promise the orientation path makes with its one validated integer.
///
/// The emitted profile is therefore auditable line by line rather than trusted
/// as a blob: [displayP3] recomputes Apple's shipped `Display P3.icc` colorants
/// bit for bit from [_displayP3Primaries] alone, which is what the tests pin.
/// It carries no creation timestamp and no vendor string — a wall clock in the
/// header would stamp every photo with the second it was sent, and a package
/// name would fingerprint every photo as having come through this SDK.
///
/// Only Display P3 is emitted. A source classified [SourceColourSpace.srgb] is
/// left untagged, because untagged already means sRGB to every receiver and a
/// redundant half-kilobyte on the most common photo in the world is a real
/// cost. Everything else is left untagged too, and named as such through the
/// metric, because the alternative — forwarding a profile this did not build —
/// is the exfiltration channel the rebuild exists to close.
class IccColourProfile {
  IccColourProfile._();

  /// How far a source colorant may sit from a reference one and still be
  /// called that space, as an absolute distance in PCS XYZ on any of the nine
  /// components.
  ///
  /// The profiles macOS ships put 0.00018 between `sRGB IEC61966-2.1` and this
  /// file's computed sRGB, and 0.00001 between `Display P3.icc` and its
  /// computed P3 — while the nearest space that must *not* match is `DCI(P3)
  /// RGB` at 0.032 from Display P3 and Apple RGB at 0.043 from sRGB. This sits
  /// an order of magnitude clear of both edges.
  static const double tolerance = 0.002;

  /// The canonical Display P3 profile, built from [_displayP3Primaries].
  ///
  /// 512 bytes carrying the same ten tags as the 536-byte profile Apple ships,
  /// whose colorant and tone curve tags it reproduces byte for byte. It is
  /// shorter only because it claims a shorter copyright.
  static final Uint8List displayP3 = _build(
    _displayP3Primaries,
    _displayP3Description,
  );

  /// The `iCCP` chunk name for [displayP3]. PNG requires 1-79 Latin-1 bytes.
  static const String pngProfileName = _displayP3Description;

  /// Classifies [profile] without letting any of it escape.
  ///
  /// Every read is bounds checked against the buffer that was actually handed
  /// over, never against the size the profile claims for itself, and the only
  /// thing that leaves is one enum value. Returns [SourceColourSpace.absent]
  /// for `null`.
  static SourceColourSpace classify(img.IccProfile? profile) {
    if (profile == null) return SourceColourSpace.absent;
    try {
      if (profile.compression == img.IccProfileCompression.deflate &&
          profile.data.length > _maxCompressedSize) {
        return SourceColourSpace.unreadable;
      }
      final raw = profile.decompressed();
      if (raw.length > _maxProfileSize) return SourceColourSpace.unreadable;
      final start = _profileStart(raw);
      if (start == null) return SourceColourSpace.unreadable;
      final colorants = _colorantsIn(raw, start);
      if (colorants == null) return SourceColourSpace.unrecognised;
      for (final candidate in _knownSpaces.entries) {
        if (_matches(colorants, candidate.value)) return candidate.key;
      }
      return SourceColourSpace.unrecognised;
    } on Object {
      return SourceColourSpace.unreadable;
    }
  }

  /// [jpeg] with [profile] embedded as the `APP2` segment ICC.1:2010 Annex B.4
  /// specifies — `ICC_PROFILE\0`, a 1-based chunk number, a chunk count, then
  /// the profile — or `null` if it does not fit or [jpeg] is not shaped the way
  /// the encoder writes.
  ///
  /// Written here rather than through `image`'s `iccProfile`, whose encoder
  /// omits the two chunk bytes: a colour-managed reader would take the first
  /// two bytes of the profile header as the chunk pair and parse rubbish.
  static Uint8List? attachToJpeg(Uint8List jpeg, Uint8List profile) {
    if (profile.length > _maxSegmentPayload) return null;
    final at = _firstSegmentBoundary(jpeg);
    if (at == null) return null;
    final segment =
        (_Bytes()
              ..u8(_marker)
              ..u8(_app2)
              ..u16(2 + _jpegSignature.length + 1 + 2 + profile.length)
              ..ascii(_jpegSignature)
              ..u8(0)
              ..u8(1)
              ..u8(1)
              ..bytes(profile))
            .take();
    final out = Uint8List(jpeg.length + segment.length);
    out
      ..setRange(0, at, jpeg)
      ..setRange(at, at + segment.length, segment)
      ..setRange(at + segment.length, out.length, jpeg, at);
    return out;
  }

  static final Map<SourceColourSpace, List<double>> _knownSpaces = {
    SourceColourSpace.srgb: _colorantsOf(_srgbPrimaries),
    SourceColourSpace.displayP3: _colorantsOf(_displayP3Primaries),
  };

  static bool _matches(List<double> actual, List<double> reference) {
    for (var i = 0; i < reference.length; i++) {
      if ((actual[i] - reference[i]).abs() > tolerance) return false;
    }
    return true;
  }

  /// Where the profile header begins inside [raw].
  ///
  /// Zero for a PNG `iCCP` chunk and for anything `image`'s own JPEG encoder
  /// wrote. Two for a conformant JPEG, whose `APP2` chunk number and chunk
  /// count `image`'s decoder hands back along with the profile. A profile split
  /// across several segments is not reassembled — the decoder keeps only the
  /// last of them — so it is refused rather than misread.
  static int? _profileStart(Uint8List raw) {
    if (_hasSignature(raw, 0)) return 0;
    if (_hasSignature(raw, _jpegChunkHeader)) {
      return raw[0] == 1 && raw[1] == 1 ? _jpegChunkHeader : null;
    }
    return null;
  }

  static bool _hasSignature(Uint8List raw, int start) =>
      start + _headerSize + _tagCountSize <= raw.length &&
      _isAscii(raw, start + _signatureOffset, _fileSignature);

  /// The nine PCS XYZ colorant components, red then green then blue, or `null`
  /// when this is a well-formed profile that simply is not matrix/TRC RGB — a
  /// Gray or CMYK device, or a LUT-based profile with no colorant tags.
  ///
  /// Throws [_MalformedProfile] when the file contradicts itself: a size
  /// smaller than a header, a size larger than the bytes handed over, a tag
  /// table that does not fit, or a tag whose data lies outside the profile.
  /// Those are the shapes a crafted file takes, and they are worth telling
  /// apart from a photo that is merely Adobe RGB.
  static List<double>? _colorantsIn(Uint8List raw, int start) {
    final view = ByteData.sublistView(raw);
    final end = start + view.getUint32(start);
    if (end < start + _headerSize + _tagCountSize || end > raw.length) {
      throw const _MalformedProfile();
    }
    if (!_isAscii(raw, start + _dataColourSpaceOffset, _colourSpaceRgb)) {
      return null;
    }
    final count = view.getUint32(start + _headerSize);
    final tableStart = start + _headerSize + _tagCountSize;
    if (tableStart + count * _tagEntrySize > end) {
      throw const _MalformedProfile();
    }
    if (count < _colorantSlots.length || count > _maxTagCount) return null;

    final colorants = List<double>.filled(_colorantSlots.length * 3, 0);
    var found = 0;
    for (var i = 0; i < count; i++) {
      final entry = tableStart + i * _tagEntrySize;
      final slot = _colorantSlots.indexOf(_readAscii(raw, entry, 4));
      if (slot < 0) continue;
      final tag = start + view.getUint32(entry + 4);
      final size = view.getUint32(entry + 8);
      if (tag < tableStart || tag + size > end) {
        throw const _MalformedProfile();
      }
      if (size < _xyzTypeSize || !_isAscii(raw, tag, _pcsXyz)) return null;
      for (var component = 0; component < 3; component++) {
        colorants[slot * 3 + component] =
            view.getInt32(tag + _typeHeaderSize + component * 4) / _fixedOne;
      }
      found++;
    }
    return found == _colorantSlots.length ? colorants : null;
  }

  /// The offset just past the `APP0` the encoder writes, which is where a JFIF
  /// file may first carry an `APP2`.
  static int? _firstSegmentBoundary(Uint8List jpeg) {
    if (jpeg.length < 4 || jpeg[0] != _marker || jpeg[1] != _soi) return null;
    if (jpeg[2] != _marker || jpeg[3] != _app0) return 2;
    if (jpeg.length < 6) return null;
    final at = 4 + ((jpeg[4] << 8) | jpeg[5]);
    return at <= jpeg.length ? at : null;
  }

  static bool _isAscii(Uint8List raw, int at, String expected) {
    if (at + expected.length > raw.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (raw[at + i] != expected.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _readAscii(Uint8List raw, int at, int length) =>
      at + length <= raw.length
      ? String.fromCharCodes(raw, at, at + length)
      : '';

  /// Lays out a v4 matrix/TRC display profile: the header, the tag table, then
  /// the tag elements, each padded to a four-byte boundary with its declared
  /// size left unpadded, as ICC.1:2010 section 7.3 requires. The three tone
  /// curves are one element pointed at three times, which is how the profiles
  /// Apple ships stay under 600 bytes.
  static Uint8List _build(_Primaries primaries, String description) {
    final colorants = _colorantsOf(primaries);
    final curve = _parametricCurveType(
      _sRgbCurveFunction,
      _sRgbCurveParameters,
    );
    final tags = <String, Uint8List>{
      'desc': _multiLocalizedUnicodeType(description),
      'cprt': _multiLocalizedUnicodeType(_copyright),
      'wtpt': _xyzType(_pcsIlluminant),
      'rXYZ': _xyzType(colorants.sublist(0, 3)),
      'gXYZ': _xyzType(colorants.sublist(3, 6)),
      'bXYZ': _xyzType(colorants.sublist(6, 9)),
      'rTRC': curve,
      'gTRC': curve,
      'bTRC': curve,
      'chad': _s15Fixed16ArrayType(_adaptationOf(primaries)),
    };

    final elements = <Uint8List>[];
    final elementOffsets = <int>[];
    final table = _Bytes()..u32(tags.length);
    var at = _headerSize + _tagCountSize + tags.length * _tagEntrySize;
    for (final tag in tags.entries) {
      var index = elements.indexWhere((held) => identical(held, tag.value));
      if (index < 0) {
        index = elements.length;
        elements.add(tag.value);
        elementOffsets.add(at);
        at += tag.value.length + _padding(tag.value.length);
      }
      table
        ..ascii(tag.key)
        ..u32(elementOffsets[index])
        ..u32(tag.value.length);
    }

    final body = _Bytes();
    for (final element in elements) {
      body
        ..bytes(element)
        ..zeros(_padding(element.length));
    }

    final header = _Bytes()
      ..u32(at)
      ..zeros(4)
      ..u32(_profileVersion)
      ..ascii(_deviceClassDisplay)
      ..ascii(_colourSpaceRgb)
      ..ascii(_pcsXyz)
      ..zeros(_dateTimeSize)
      ..ascii(_fileSignature)
      ..zeros(4)
      ..u32(_profileFlags)
      ..zeros(4)
      ..zeros(4)
      ..zeros(_deviceAttributesSize)
      ..u32(_renderingIntentPerceptual)
      ..s15Fixed16All(_pcsIlluminant)
      ..zeros(4)
      ..zeros(_profileIdSize)
      ..zeros(_reservedSize);

    return (_Bytes()
          ..bytes(header.take())
          ..bytes(table.take())
          ..bytes(body.take()))
        .take();
  }

  static int _padding(int length) => (4 - (length % 4)) % 4;

  /// `XYZType`, ICC.1:2010 section 10.31.
  static Uint8List _xyzType(List<double> xyz) =>
      (_Bytes()
            ..ascii(_pcsXyz)
            ..zeros(4)
            ..s15Fixed16All(xyz))
          .take();

  /// `s15Fixed16ArrayType`, ICC.1:2010 section 10.22.
  static Uint8List _s15Fixed16ArrayType(List<double> values) =>
      (_Bytes()
            ..ascii(_s15Fixed16ArraySignature)
            ..zeros(4)
            ..s15Fixed16All(values))
          .take();

  /// `parametricCurveType`, ICC.1:2010 section 10.16. Function type 3 is
  /// `Y = (aX + b)^g` above `X = d` and `Y = cX` below it, which is the sRGB
  /// and Display P3 transfer function exactly, in five numbers.
  static Uint8List _parametricCurveType(
    int function,
    List<double> parameters,
  ) =>
      (_Bytes()
            ..ascii(_parametricCurveSignature)
            ..zeros(4)
            ..u16(function)
            ..zeros(2)
            ..s15Fixed16All(parameters))
          .take();

  /// `multiLocalizedUnicodeType`, ICC.1:2010 section 10.13: one `en-US` record
  /// of UTF-16BE, which is what a v4 `desc` and `cprt` must be.
  static Uint8List _multiLocalizedUnicodeType(String text) {
    final units = text.codeUnits;
    return (_Bytes()
          ..ascii(_multiLocalizedUnicodeSignature)
          ..zeros(4)
          ..u32(1)
          ..u32(_mlucRecordSize)
          ..ascii(_mlucLanguage)
          ..ascii(_mlucCountry)
          ..u32(units.length * 2)
          ..u32(_typeHeaderSize + 4 + 4 + _mlucRecordSize)
          ..utf16All(units))
        .take();
  }
}

/// The nine PCS XYZ colorant components of [primaries], red then green then
/// blue, chromatically adapted from its own white to the D50 the PCS is
/// defined at — which is what an ICC matrix profile stores.
///
/// SMPTE RP 177: turn each chromaticity into an XYZ direction, solve for the
/// three scale factors that make the primaries sum to the white point, then
/// scale.
List<double> _colorantsOf(_Primaries primaries) {
  final red = _xyzOf(primaries.red);
  final green = _xyzOf(primaries.green);
  final blue = _xyzOf(primaries.blue);
  final white = _xyzOf(primaries.white);
  final scales = _transform(
    _invert(<double>[
      red[0], green[0], blue[0], //
      red[1], green[1], blue[1],
      red[2], green[2], blue[2],
    ]),
    white,
  );
  final adaptation = _adaptationOf(primaries);
  final out = <double>[];
  for (final (index, primary) in [red, green, blue].indexed) {
    out.addAll(
      _transform(adaptation, [
        primary[0] * scales[index],
        primary[1] * scales[index],
        primary[2] * scales[index],
      ]),
    );
  }
  return out;
}

/// The Bradford chromatic adaptation from the white of [primaries] to the PCS
/// D50, which is what the `chad` tag records: cone responses under each white,
/// their ratio applied on the diagonal, back out of cone space.
List<double> _adaptationOf(_Primaries primaries) {
  final source = _transform(_bradford, _xyzOf(primaries.white));
  final destination = _transform(_bradford, _pcsIlluminant);
  return _multiply(
    _invert(_bradford),
    _multiply(<double>[
      destination[0] / source[0], 0, 0, //
      0, destination[1] / source[1], 0,
      0, 0, destination[2] / source[2],
    ], _bradford),
  );
}

List<double> _xyzOf(_Chromaticity c) => [c.x / c.y, 1, (1 - c.x - c.y) / c.y];

List<double> _transform(List<double> m, List<double> v) => [
  for (var row = 0; row < 3; row++)
    m[row * 3] * v[0] + m[row * 3 + 1] * v[1] + m[row * 3 + 2] * v[2],
];

List<double> _multiply(List<double> a, List<double> b) => [
  for (var row = 0; row < 3; row++)
    for (var column = 0; column < 3; column++)
      a[row * 3] * b[column] +
          a[row * 3 + 1] * b[3 + column] +
          a[row * 3 + 2] * b[6 + column],
];

List<double> _invert(List<double> m) {
  final cofactor = <double>[
    m[4] * m[8] - m[5] * m[7],
    m[2] * m[7] - m[1] * m[8],
    m[1] * m[5] - m[2] * m[4],
    m[5] * m[6] - m[3] * m[8],
    m[0] * m[8] - m[2] * m[6],
    m[2] * m[3] - m[0] * m[5],
    m[3] * m[7] - m[4] * m[6],
    m[1] * m[6] - m[0] * m[7],
    m[0] * m[4] - m[1] * m[3],
  ];
  final determinant =
      m[0] * cofactor[0] + m[1] * cofactor[3] + m[2] * cofactor[6];
  return [for (final value in cofactor) value / determinant];
}

/// A profile that contradicts its own layout, which [IccColourProfile.classify]
/// turns into [SourceColourSpace.unreadable].
class _MalformedProfile implements Exception {
  const _MalformedProfile();
}

class _Chromaticity {
  const _Chromaticity(this.x, this.y);

  final double x;
  final double y;
}

class _Primaries {
  const _Primaries({
    required this.red,
    required this.green,
    required this.blue,
    required this.white,
  });

  final _Chromaticity red;
  final _Chromaticity green;
  final _Chromaticity blue;
  final _Chromaticity white;
}

/// CIE D65, as IEC 61966-2-1 and SMPTE EG 432-1 both specify it.
const _Chromaticity _d65 = _Chromaticity(0.3127, 0.3290);

/// IEC 61966-2-1 (sRGB).
const _Primaries _srgbPrimaries = _Primaries(
  red: _Chromaticity(0.640, 0.330),
  green: _Chromaticity(0.300, 0.600),
  blue: _Chromaticity(0.150, 0.060),
  white: _d65,
);

/// SMPTE RP 431-2 primaries on a D65 white: Display P3, the space every
/// wide-gamut phone camera writes.
const _Primaries _displayP3Primaries = _Primaries(
  red: _Chromaticity(0.680, 0.320),
  green: _Chromaticity(0.265, 0.690),
  blue: _Chromaticity(0.150, 0.060),
  white: _d65,
);

/// The PCS illuminant, D50, as ICC.1:2010 section 7.2.16 gives it. Rounded to
/// `s15Fixed16` these are the 0x0000F6D6 / 0x00010000 / 0x0000D32D every
/// profile in circulation carries.
const List<double> _pcsIlluminant = [0.9642, 1.0, 0.8249];

/// The Bradford cone response matrix.
const List<double> _bradford = [
  0.8951, 0.2664, -0.1614, //
  -0.7502, 1.7135, 0.0367,
  0.0389, -0.0685, 1.0296,
];

const double _sRgbGamma = 2.4;
const double _sRgbScale = 1.055;
const double _sRgbOffset = 0.055;
const double _sRgbSlope = 12.92;
const double _sRgbThreshold = 0.04045;
const int _sRgbCurveFunction = 3;

/// IEC 61966-2-1's transfer function rearranged into function type 3's
/// `g, a, b, c, d`. Display P3 uses the same curve.
const List<double> _sRgbCurveParameters = [
  _sRgbGamma,
  1 / _sRgbScale,
  _sRgbOffset / _sRgbScale,
  1 / _sRgbSlope,
  _sRgbThreshold,
];

const String _displayP3Description = 'Display P3';
const String _copyright = 'Public Domain';

const int _headerSize = 128;
const int _tagCountSize = 4;
const int _tagEntrySize = 12;
const int _typeHeaderSize = 8;
const int _xyzTypeSize = 20;
const int _signatureOffset = 36;
const int _dataColourSpaceOffset = 16;
const int _dateTimeSize = 12;
const int _deviceAttributesSize = 8;
const int _profileIdSize = 16;
const int _reservedSize = 28;
const int _mlucRecordSize = 12;
const int _profileVersion = 0x04000000;
const int _profileFlags = 0;
const int _renderingIntentPerceptual = 0;
const double _fixedOne = 65536;
const String _fileSignature = 'acsp';
const String _deviceClassDisplay = 'mntr';
const String _colourSpaceRgb = 'RGB ';
const String _pcsXyz = 'XYZ ';
const String _s15Fixed16ArraySignature = 'sf32';
const String _parametricCurveSignature = 'para';
const String _multiLocalizedUnicodeSignature = 'mluc';
const String _mlucLanguage = 'en';
const String _mlucCountry = 'US';
const List<String> _colorantSlots = ['rXYZ', 'gXYZ', 'bXYZ'];

/// A profile large enough to hold every display profile in circulation and
/// small enough that inflating one cannot be an attack: 16 KiB of `deflate`
/// expands to at most ~16 MB, an order of magnitude under the pixel buffer
/// `ImageMetadataScrubber` already allows itself.
const int _maxCompressedSize = 16 * 1024;
const int _maxProfileSize = 1024 * 1024;
const int _maxTagCount = 256;

const int _marker = 0xFF;
const int _soi = 0xD8;
const int _app0 = 0xE0;
const int _app2 = 0xE2;
const String _jpegSignature = 'ICC_PROFILE';

/// The chunk number and chunk count that follow `ICC_PROFILE\0` in an `APP2`.
const int _jpegChunkHeader = 2;

/// A JPEG segment's length field counts itself, so its payload stops two short
/// of the 16 bits it is written in.
const int _maxSegmentPayload = 0xFFFF - 2 - _jpegSignature.length - 1 - 2;

class _Bytes {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void u8(int value) => _builder.addByte(value);

  void u16(int value) => _builder
    ..addByte((value >> 8) & 0xFF)
    ..addByte(value & 0xFF);

  void u32(int value) => _builder
    ..addByte((value >> 24) & 0xFF)
    ..addByte((value >> 16) & 0xFF)
    ..addByte((value >> 8) & 0xFF)
    ..addByte(value & 0xFF);

  void s15Fixed16All(List<double> values) {
    for (final value in values) {
      u32((value * _fixedOne).round() & 0xFFFFFFFF);
    }
  }

  void utf16All(List<int> units) {
    for (final unit in units) {
      u16(unit);
    }
  }

  void ascii(String value) => _builder.add(value.codeUnits);

  void bytes(List<int> value) => _builder.add(value);

  void zeros(int count) => _builder.add(Uint8List(count));

  Uint8List take() => _builder.takeBytes();
}
