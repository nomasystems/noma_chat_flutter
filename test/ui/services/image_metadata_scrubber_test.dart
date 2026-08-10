import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noma_chat/src/ui/services/icc_colour_profile.dart';
import 'package:noma_chat/src/ui/services/image_metadata_scrubber.dart';

/// A string planted inside every payload that must not reach the output, so
/// "did this survive" is a substring search rather than an offset.
const String _canary = 'GPS-LEAK-CANARY';

/// A grid of flat 16x16 cells, each a colour that names its own column and
/// row. 16x16 is the 4:2:0 macroblock, so cell centres survive a JPEG round
/// trip intact — and no two of the eight orientations produce the same grid.
img.Image _pattern({int cols = 4, int rows = 2}) {
  final image = img.Image(width: cols * 16, height: rows * 16);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 20 + (x ~/ 16) * 55, 20 + (y ~/ 16) * 90, 120);
    }
  }
  return image;
}

/// [source] transformed the way the EXIF Orientation table says a reader must
/// transform it: values 1-4 keep the frame, 5-8 transpose it.
img.Image _upright(img.Image source, int orientation) {
  final w = source.width;
  final h = source.height;
  final flips = orientation >= 5;
  final out = img.Image(width: flips ? h : w, height: flips ? w : h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = source.getPixel(x, y);
      final (int dx, int dy) = switch (orientation) {
        2 => (w - 1 - x, y),
        3 => (w - 1 - x, h - 1 - y),
        4 => (x, h - 1 - y),
        5 => (y, x),
        6 => (h - 1 - y, x),
        7 => (h - 1 - y, w - 1 - x),
        8 => (y, w - 1 - x),
        _ => (x, y),
      };
      out.setPixelRgb(dx, dy, p.r, p.g, p.b);
    }
  }
  return out;
}

Uint8List _jpeg(img.Image image, {int? orientation}) {
  final copy = img.Image.from(image);
  if (orientation != null) copy.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(copy, quality: 92, chroma: img.JpegChroma.yuv420);
}

/// A JPEG carrying real EXIF: a GPS position, and a maker field holding the
/// canary so its survival is visible without parsing anything.
Uint8List _jpegWithGps({int? orientation}) {
  final image = _pattern();
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  image.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
  image.exif.gpsIfd[0x0002] = img.IfdValueRational(41, 1);
  image.exif.imageIfd[0x010F] = img.IfdValueAscii(_canary);
  return img.encodeJpg(image, quality: 92, chroma: img.JpegChroma.yuv420);
}

/// The two-byte length prefix a real JPEG segment carries; it counts itself.
List<int> _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xFF, marker, (length >> 8) & 0xFF, length & 0xFF, ...payload];
}

/// Splices [extra] in right behind the start-of-image marker.
Uint8List _spliced(Uint8List jpeg, List<int> extra) =>
    Uint8List.fromList([jpeg[0], jpeg[1], ...extra, ...jpeg.sublist(2)]);

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// An `ICC_PROFILE` APP2 whose two tag table entries claim overlapping byte
/// ranges: one signature on a colour-tag whitelist, one not, over the same
/// data. Reading the table to decide what may stay is what this defeats.
List<int> _iccWithOverlappingTags() {
  const headerSize = 128;
  const tagCount = 2;
  const tableEnd = headerSize + 4 + tagCount * 12;
  final body = <int>[
    0x58, 0x59, 0x5A, 0x20, 0, 0, 0, 0, // 'XYZ ' and its reserved word
    ..._canary.codeUnits,
    0,
  ];
  final header = List<int>.filled(headerSize, 0);
  void put(int at, List<int> value) {
    for (var i = 0; i < value.length; i++) {
      header[at + i] = value[i];
    }
  }

  put(0, _u32(tableEnd + body.length));
  put(8, _u32(0x02100000));
  put(12, 'mntr'.codeUnits);
  put(16, 'RGB '.codeUnits);
  put(20, 'XYZ '.codeUnits);
  put(36, 'acsp'.codeUnits);
  return _segment(0xE2, [
    ...'ICC_PROFILE'.codeUnits, 0x00, //
    1, 1,
    ...header,
    ..._u32(tagCount),
    // 'wtpt' claims the whole run; 'mmod' claims the same bytes from an
    // offset inside it, so one tag's data is another tag's header.
    ...'wtpt'.codeUnits, ..._u32(tableEnd), ..._u32(body.length),
    ...'mmod'.codeUnits, ..._u32(tableEnd + 4), ..._u32(body.length - 4),
    ...body,
  ]);
}

/// A matrix/TRC profile for whatever [colorants] describe, with the canary
/// buried in it. Real profiles from real cameras carry a description, a
/// copyright and a maker note; this stands in for all of them.
Uint8List _iccWith(List<double> colorants) {
  const int dataStart = 132 + 3 * 12;
  final canary = [..._canary.codeUnits, 0];
  final header = List<int>.filled(128, 0);
  void put(int at, List<int> value) {
    for (var i = 0; i < value.length; i++) {
      header[at + i] = value[i];
    }
  }

  put(0, _u32(dataStart + 3 * 20 + canary.length));
  put(8, _u32(0x04000000));
  put(12, 'mntr'.codeUnits);
  put(16, 'RGB '.codeUnits);
  put(20, 'XYZ '.codeUnits);
  put(36, 'acsp'.codeUnits);

  final table = <int>[];
  final data = <int>[];
  for (var slot = 0; slot < 3; slot++) {
    table.addAll([
      ...['rXYZ', 'gXYZ', 'bXYZ'][slot].codeUnits,
      ..._u32(dataStart + slot * 20),
      ..._u32(20),
    ]);
    data.addAll([
      ...'XYZ '.codeUnits, 0, 0, 0, 0, //
      for (var component = 0; component < 3; component++)
        ..._u32((colorants[slot * 3 + component] * 65536).round() & 0xFFFFFFFF),
    ]);
  }
  return Uint8List.fromList([
    ...header,
    ..._u32(3),
    ...table,
    ...data,
    ...canary,
  ]);
}

/// Display P3, sRGB and Adobe RGB as their PCS colorants, taken from the
/// profiles macOS ships rather than from anything the library computes.
const List<double> _p3Colorants = [
  0.51512146, 0.24119568, -0.00105286, //
  0.29197693, 0.69224548, 0.04188538,
  0.15710449, 0.06657410, 0.78407288,
];
const List<double> _srgbColorants = [
  0.43606567, 0.22248840, 0.01391602, //
  0.38514709, 0.71687317, 0.09707642,
  0.14306641, 0.06060791, 0.71409607,
];
const List<double> _adobeColorants = [
  0.60974121, 0.31111145, 0.01947021, //
  0.20527649, 0.62567139, 0.06086731,
  0.14918518, 0.06321716, 0.74456787,
];

Uint8List _jpegTagged(List<double> colorants) {
  final image = _pattern()
    ..iccProfile = img.IccProfile(
      'ICC_PROFILE',
      img.IccProfileCompression.none,
      _iccWith(colorants),
    );
  return img.encodeJpg(image, quality: 92, chroma: img.JpegChroma.yuv420);
}

/// The ICC profile carried by [jpeg]'s `APP2`, or `null` if it has none.
/// Reads the segment the way ICC.1:2010 Annex B.4 says it is written, which
/// is the point: `image`'s own decoder would accept a segment missing the
/// chunk pair.
Uint8List? _embeddedProfile(Uint8List jpeg) {
  var at = 2;
  while (at + 3 < jpeg.length && jpeg[at] == 0xFF) {
    final marker = jpeg[at + 1];
    final length = (jpeg[at + 2] << 8) | jpeg[at + 3];
    if (marker == 0xDA) return null;
    if (marker == 0xE2) {
      expect(String.fromCharCodes(jpeg, at + 4, at + 15), 'ICC_PROFILE');
      expect(jpeg[at + 15], 0);
      expect([jpeg[at + 16], jpeg[at + 17]], equals([1, 1]));
      return Uint8List.sublistView(jpeg, at + 18, at + 2 + length);
    }
    at += 2 + length;
  }
  return null;
}

/// Every marker between the start-of-image and the scan, which is where a
/// JPEG keeps everything that is not entropy-coded pixel data.
List<String> _headerMarkers(Uint8List bytes) {
  final markers = <String>[];
  var at = 2;
  while (at + 3 < bytes.length && bytes[at] == 0xFF) {
    final marker = bytes[at + 1];
    markers.add('0x${marker.toRadixString(16).toUpperCase()}');
    if (marker == 0xDA) break;
    at += 2 + ((bytes[at + 2] << 8) | bytes[at + 3]);
  }
  return markers;
}

bool _contains(Uint8List haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

/// Compares the centre of every 16x16 cell, which is where JPEG's block
/// artefacts are smallest.
void expectSamePicture(img.Image actual, img.Image expected) {
  expect(actual.width, expected.width, reason: 'width');
  expect(actual.height, expected.height, reason: 'height');
  for (var y = 8; y < expected.height; y += 16) {
    for (var x = 8; x < expected.width; x += 16) {
      final a = actual.getPixel(x, y);
      final e = expected.getPixel(x, y);
      expect(a.r, closeTo(e.r, 16), reason: 'red at $x,$y');
      expect(a.g, closeTo(e.g, 16), reason: 'green at $x,$y');
      expect(a.b, closeTo(e.b, 16), reason: 'blue at $x,$y');
    }
  }
}

bool _samePicture(img.Image a, img.Image b) {
  if (a.width != b.width || a.height != b.height) return false;
  for (var y = 8; y < b.height; y += 16) {
    for (var x = 8; x < b.width; x += 16) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      if ((pa.r - pb.r).abs() > 16) return false;
      if ((pa.g - pb.g).abs() > 16) return false;
      if ((pa.b - pb.b).abs() > 16) return false;
    }
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nothing but the pixels comes out', () {
    test('the rebuilt JPEG carries no segment the source put there', () async {
      final input = _spliced(_jpegWithGps(), [
        ..._segment(0xE1, [
          ...'http://ns.adobe.com/xap/1.0/'.codeUnits, 0x00, //
          ..._canary.codeUnits,
        ]),
        ..._segment(0xED, [...'Photoshop 3.0'.codeUnits, ..._canary.codeUnits]),
        ..._segment(0xEB, [...'JP'.codeUnits, 0x00, ..._canary.codeUnits]),
        ..._segment(0xFE, _canary.codeUnits),
        ..._iccWithOverlappingTags(),
      ]);
      expect(_contains(input, _canary.codeUnits), isTrue, reason: 'fixture');

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(
        _headerMarkers(out),
        equals(['0xE0', '0xDB', '0xC0', '0xC4', '0xDA']),
        reason:
            'a JFIF the encoder writes from constants, the tables the '
            'decoder needs, the frame header, and the scan',
      );
    });

    test('an XMP APP1 does not survive', () async {
      final xmp = _segment(0xE1, [
        ...'http://ns.adobe.com/xap/1.0/'.codeUnits, 0x00, //
        ...'<x:xmpmeta>$_canary</x:xmpmeta>'.codeUnits,
      ]);

      final out = await ImageMetadataScrubber.scrub(
        _spliced(_jpeg(_pattern()), xmp),
      );

      expect(_contains(out, 'ns.adobe.com'.codeUnits), isFalse);
      expect(_contains(out, _canary.codeUnits), isFalse);
    });

    test('an ICC profile whose tags claim overlapping ranges does not '
        'survive', () async {
      final input = _spliced(_jpeg(_pattern()), _iccWithOverlappingTags());

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(_contains(out, 'ICC_PROFILE'.codeUnits), isFalse);
      expect(_headerMarkers(out), isNot(contains('0xE2')));
    });

    test('the EXIF block with the GPS position does not survive', () async {
      final out = await ImageMetadataScrubber.scrub(_jpegWithGps());

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(_headerMarkers(out), isNot(contains('0xE1')));
      expect(img.decodeJpg(out)!.exif.isEmpty, isTrue);
    });

    test('the MP4 a Motion Photo appends is not forwarded', () async {
      // A complete JPEG, then a whole clip glued on past the end-of-image,
      // carrying the `udta` box that holds its own location.
      final trailer = <int>[
        0x00, 0x00, 0x00, 0x18, //
        ...'ftyp'.codeUnits, ...'mp42'.codeUnits,
        ...'udta'.codeUnits, ..._canary.codeUnits,
      ];
      final input = Uint8List.fromList([..._jpeg(_pattern()), ...trailer]);

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(_contains(out, 'udta'.codeUnits), isFalse);
      expect(_contains(out, 'ftyp'.codeUnits), isFalse);
    });

    test('the second image an MPO appends is not forwarded', () async {
      final input = Uint8List.fromList([
        ..._jpeg(_pattern()),
        ..._jpegWithGps(),
      ]);

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(_headerMarkers(out), isNot(contains('0xE1')));
    });

    test('the picture itself is unharmed', () async {
      final source = _pattern();

      final out = await ImageMetadataScrubber.scrub(_jpeg(source));

      expectSamePicture(img.decodeJpg(out)!, source);
    });
  });

  group('a PNG is rebuilt too, and stays a PNG', () {
    Uint8List pngWithText() {
      final image = _pattern()
        ..addTextData({'Comment': _canary, 'Software': 'Somebody\'s camera'});
      return img.encodePng(image);
    }

    test('its text chunks do not survive', () async {
      final input = pngWithText();
      expect(_contains(input, _canary.codeUnits), isTrue, reason: 'fixture');

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(_contains(out, 'tEXt'.codeUnits), isFalse);
      expect(img.decodePng(out)!.textData, anyOf(isNull, isEmpty));
    });

    test('an eXIf chunk does not survive either', () async {
      final base = img.encodePng(_pattern());
      final chunk = _pngChunk('eXIf', [
        0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, //
        ..._canary.codeUnits,
      ]);
      final input = Uint8List.fromList([
        ...base.sublist(0, base.length - 12),
        ...chunk,
        ...base.sublist(base.length - 12),
      ]);

      final out = await ImageMetadataScrubber.scrub(input);

      expect(_contains(out, 'eXIf'.codeUnits), isFalse);
      expect(_contains(out, _canary.codeUnits), isFalse);
    });

    test('transparency and pixels come through untouched', () async {
      final source = img.Image(width: 16, height: 16, numChannels: 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          source.setPixelRgba(x, y, x * 15, y * 15, 60, x < 8 ? 0 : 255);
        }
      }

      final out = await ImageMetadataScrubber.scrub(img.encodePng(source));
      final back = img.decodePng(out)!;

      expect(back.hasAlpha, isTrue);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final a = source.getPixel(x, y);
          final b = back.getPixel(x, y);
          expect([b.r, b.g, b.b, b.a], equals([a.r, a.g, a.b, a.a]));
        }
      }
    });

    test('the outcome names the format', () async {
      final events = <Map<String, dynamic>>[];

      await ImageMetadataScrubber.scrub(
        pngWithText(),
        onMetric: (_, data) => events.add(data),
      );

      expect(events.single['outcome'], 'stripped');
      expect(events.single['format'], 'png');
    });
  });

  group('orientation is baked into the pixels', () {
    for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('$orientation is applied, once', () async {
        final source = _pattern();
        final expected = _upright(source, orientation);

        final out = await ImageMetadataScrubber.scrub(
          _jpegWithGps(orientation: orientation),
        );
        final back = img.decodeJpg(out)!;

        expectSamePicture(back, expected);
        expect(
          _headerMarkers(out),
          isNot(contains('0xE1')),
          reason:
              'the picture is upright as pixels, so there is no tag to '
              'write and nothing for a reader to apply a second time',
        );
        expect(back.exif.imageIfd.hasOrientation, isFalse);
      });
    }

    test('a transposing value turns the frame exactly once', () async {
      // Applied twice, 6 would be a 180 turn and the output would be 64x32
      // again — the frame is what tells one from the other.
      final out = await ImageMetadataScrubber.scrub(
        _jpeg(_pattern(), orientation: 6),
      );
      final back = img.decodeJpg(out)!;

      expect([back.width, back.height], equals([32, 64]));
    });

    for (final orientation in [2, 3, 4]) {
      test('$orientation, which undoes itself, is not applied twice', () async {
        final source = _pattern();

        final out = await ImageMetadataScrubber.scrub(
          _jpeg(source, orientation: orientation),
        );

        expect(
          _samePicture(img.decodeJpg(out)!, source),
          isFalse,
          reason:
              'applying a mirror or a 180 turn twice is the identity, so '
              'an unchanged picture is the signature of a double pass',
        );
      });
    }
  });

  group('what it cannot rebuild, it hands back', () {
    // A complete, decodable JPEG with an EXIF block laundered under 0xC8 —
    // a marker that carries a length like any segment, which is what used to
    // walk a payload past the whitelist while the pass reported success.
    final laundered = _spliced(_jpeg(_pattern()), [
      ..._segment(0xC8, [
        ...'Exif'.codeUnits, 0x00, 0x00, //
        ..._canary.codeUnits,
      ]),
    ]);

    test('the file comes back byte for byte', () async {
      final out = await ImageMetadataScrubber.scrub(laundered);

      expect(out, same(laundered));
    });

    test('and the outcome says so instead of claiming success', () async {
      final events = <Map<String, dynamic>>[];

      await ImageMetadataScrubber.scrub(
        laundered,
        onMetric: (_, data) => events.add(data),
      );

      expect(events, hasLength(1));
      expect(events.single['outcome'], isNot('stripped'));
      expect(events.single['outcome'], 'not_stripped');
      expect(events.single['reason'], 'decode_failed');
      expect(events.single['format'], 'jpeg');
    });

    test('a truncated JPEG is not guessed at', () async {
      final truncated = Uint8List.sublistView(_jpegWithGps(), 0, 60);
      final events = <Map<String, dynamic>>[];

      final out = await ImageMetadataScrubber.scrub(
        truncated,
        onMetric: (_, data) => events.add(data),
      );

      expect(out, same(truncated));
      expect(events.single['outcome'], 'not_stripped');
      expect(events.single['reason'], 'decode_failed');
    });

    test('a header declaring more pixels than any camera takes is refused '
        'before a single one is allocated', () async {
      // A PNG IHDR claiming 40000x40000: 1.6 gigapixels, and 4.8 GB of RGB
      // if the dimensions were taken at face value.
      // The IHDR's width and height, at a fixed offset behind the signature
      // and the chunk header, with the chunk's checksum made good again so
      // the dimensions are what the decoder rejects it for.
      final tampered = Uint8List.fromList(img.encodePng(_pattern()))
        ..setRange(16, 24, [
          ..._u32(40000), //
          ..._u32(40000),
        ]);
      tampered.setRange(29, 33, _u32(_crc32(tampered.sublist(12, 29))));
      final events = <Map<String, dynamic>>[];

      final out = await ImageMetadataScrubber.scrub(
        tampered,
        onMetric: (_, data) => events.add(data),
      );

      expect(out, same(tampered));
      expect(events.single['reason'], 'too_many_pixels');
    });

    test(
      'a format with no encoder is passed through, and named as such',
      () async {
        for (final input in <Uint8List>[
          // an MP4, a PDF, and the HEIC an iPhone writes
          Uint8List.fromList([
            0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'mp42'.codeUnits, //
          ]),
          Uint8List.fromList('%PDF-1.7\n$_canary'.codeUnits),
          Uint8List.fromList([
            0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits, //
          ]),
        ]) {
          final events = <Map<String, dynamic>>[];

          final out = await ImageMetadataScrubber.scrub(
            input,
            onMetric: (_, data) => events.add(data),
          );

          expect(out, same(input));
          expect(events.single, equals({'outcome': 'unsupported_format'}));
        }
      },
    );

    test('an empty buffer is not a crash', () async {
      final empty = Uint8List(0);

      expect(await ImageMetadataScrubber.scrub(empty), same(empty));
    });
  });

  group('the outcome is reported', () {
    test(
      'exactly once, naming the format, with no bytes or names in it',
      () async {
        final events = <(String, Map<String, dynamic>)>[];

        await ImageMetadataScrubber.scrub(
          _jpegWithGps(),
          onMetric: (metric, data) => events.add((metric, data)),
        );

        expect(events, hasLength(1));
        expect(events.single.$1, 'image_metadata_strip');
        expect(
          events.single.$2,
          equals({
            'outcome': 'stripped',
            'format': 'jpeg',
            'colour_profile': 'absent',
          }),
        );
      },
    );

    test('a profile that is not one is called out, and never reaches the '
        'output', () async {
      final source = _pattern()
        ..iccProfile = img.IccProfile(
          'p3',
          img.IccProfileCompression.none,
          Uint8List.fromList(List<int>.generate(140, (i) => i)),
        );
      final events = <Map<String, dynamic>>[];

      final out = await ImageMetadataScrubber.scrub(
        img.encodeJpg(source, quality: 92),
        onMetric: (_, data) => events.add(data),
      );

      expect(events.single['colour_profile'], 'unreadable_dropped');
      expect(events.single['outcome'], 'stripped');
      expect(_headerMarkers(out), isNot(contains('0xE2')));
    });

    test('nothing is emitted when no sink was wired', () async {
      await ImageMetadataScrubber.scrub(_jpegWithGps());
    });
  });

  group('colour comes through as a value, never as bytes', () {
    Future<(Uint8List, Map<String, dynamic>)> scrub(Uint8List input) async {
      final events = <Map<String, dynamic>>[];
      final out = await ImageMetadataScrubber.scrub(
        input,
        onMetric: (_, data) => events.add(data),
      );
      expect(events, hasLength(1));
      return (out, events.single);
    }

    test('a Display P3 source comes out tagged Display P3', () async {
      final (out, metric) = await scrub(_jpegTagged(_p3Colorants));

      expect(_embeddedProfile(out), equals(IccColourProfile.displayP3));
      expect(metric['colour_profile'], 'display_p3_reissued');
      expect(metric['outcome'], 'stripped');
    });

    test('and not one byte of the profile it came with', () async {
      final input = _jpegTagged(_p3Colorants);
      expect(_contains(input, _canary.codeUnits), isTrue, reason: 'fixture');

      final (out, _) = await scrub(input);

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(
        _embeddedProfile(out),
        equals(IccColourProfile.displayP3),
        reason: 'the profile out is a function of our constants alone',
      );
    });

    test('a profile arriving with the chunk pair a phone writes is read the '
        'same way', () async {
      final input = IccColourProfile.attachToJpeg(
        img.encodeJpg(_pattern(), quality: 92),
        _iccWith(_p3Colorants),
      )!;

      final (out, metric) = await scrub(input);

      expect(metric['colour_profile'], 'display_p3_reissued');
      expect(_contains(out, _canary.codeUnits), isFalse);
    });

    test('what this writes, this reads back as what it wrote', () async {
      final (once, _) = await scrub(_jpegTagged(_p3Colorants));

      final (twice, metric) = await scrub(once);

      expect(metric['colour_profile'], 'display_p3_reissued');
      expect(_embeddedProfile(twice), equals(IccColourProfile.displayP3));
    });

    test('an untagged source stays untagged, because untagged already means '
        'sRGB', () async {
      final (out, metric) = await scrub(_jpeg(_pattern()));

      expect(_embeddedProfile(out), isNull);
      expect(_headerMarkers(out), isNot(contains('0xE2')));
      expect(metric['colour_profile'], 'absent');
    });

    test('an sRGB source is dropped rather than re-stated', () async {
      final (out, metric) = await scrub(_jpegTagged(_srgbColorants));

      expect(_embeddedProfile(out), isNull);
      expect(metric['colour_profile'], 'srgb_dropped');
      expect(_contains(out, _canary.codeUnits), isFalse);
    });

    test('a space this does not emit is dropped and said so', () async {
      final (out, metric) = await scrub(_jpegTagged(_adobeColorants));

      expect(_embeddedProfile(out), isNull);
      expect(metric['colour_profile'], 'unrecognised_dropped');
      expect(_contains(out, _canary.codeUnits), isFalse);
    });

    test('the profile costs 530 bytes and only when it is written', () async {
      final (tagged, _) = await scrub(_jpegTagged(_p3Colorants));
      final (plain, _) = await scrub(_jpegTagged(_srgbColorants));

      expect(tagged.length - plain.length, 530);
    });

    test('the picture is unharmed by the tagging', () async {
      final source = _pattern();
      final image = img.Image.from(source)
        ..iccProfile = img.IccProfile(
          'ICC_PROFILE',
          img.IccProfileCompression.none,
          _iccWith(_p3Colorants),
        );

      final (out, _) = await scrub(
        img.encodeJpg(image, quality: 92, chroma: img.JpegChroma.yuv420),
      );

      expectSamePicture(img.decodeJpg(out)!, source);
    });

    group('a PNG is tagged the same way', () {
      Uint8List pngTagged(List<double> colorants) => img.encodePng(
        _pattern()
          ..iccProfile = img.IccProfile(
            'Display P3',
            img.IccProfileCompression.none,
            _iccWith(colorants),
          ),
      );

      test('a Display P3 PNG comes out with our profile in its iCCP', () async {
        expect(
          _contains(_iccWith(_p3Colorants), _canary.codeUnits),
          isTrue,
          reason: 'fixture; the chunk itself is deflated, so look before',
        );

        final (out, metric) = await scrub(pngTagged(_p3Colorants));

        expect(metric['colour_profile'], 'display_p3_reissued');
        expect(_contains(out, 'iCCP'.codeUnits), isTrue);
        expect(
          img.decodePng(out)!.iccProfile!.decompressed(),
          equals(IccColourProfile.displayP3),
          reason: 'ours entire, so nothing of theirs',
        );
        expect(
          IccColourProfile.displayP3.length,
          512,
          reason:
              'the encoder deflates what it is handed; it must not have '
              'deflated the one copy everything else shares',
        );
      });

      test('an untagged PNG gains no chunk', () async {
        final (out, metric) = await scrub(img.encodePng(_pattern()));

        expect(_contains(out, 'iCCP'.codeUnits), isFalse);
        expect(img.decodePng(out)!.iccProfile, isNull);
        expect(metric['colour_profile'], 'absent');
      });

      test('an sRGB PNG gains no chunk either', () async {
        final (out, metric) = await scrub(pngTagged(_srgbColorants));

        expect(_contains(out, 'iCCP'.codeUnits), isFalse);
        expect(metric['colour_profile'], 'srgb_dropped');
        expect(_contains(out, _canary.codeUnits), isFalse);
      });
    });

    test(
      'a file that could not be rebuilt says nothing about colour',
      () async {
        final truncated = Uint8List.sublistView(
          _jpegTagged(_p3Colorants),
          0,
          60,
        );

        final (out, metric) = await scrub(truncated);

        expect(out, same(truncated));
        expect(metric['outcome'], 'not_stripped');
        expect(metric.containsKey('colour_profile'), isFalse);
      },
    );
  });

  group('a host sink that throws never reaches the send', () {
    test('on the success path the bytes still come back clean', () async {
      final out = await ImageMetadataScrubber.scrub(
        _jpegWithGps(),
        onMetric: (_, _) => throw StateError('telemetry is down'),
      );

      expect(_contains(out, _canary.codeUnits), isFalse);
      expect(out.length, greaterThan(0));
    });

    test('on the failure path the original still comes back', () async {
      final broken = Uint8List.sublistView(_jpegWithGps(), 0, 60);

      final out = await ImageMetadataScrubber.scrub(
        broken,
        onMetric: (_, _) => throw StateError('telemetry is down'),
      );

      expect(out, same(broken));
    });

    test('and for a format it does not handle', () async {
      final pdf = Uint8List.fromList('%PDF-1.7'.codeUnits);

      final out = await ImageMetadataScrubber.scrub(
        pdf,
        onMetric: (_, _) => throw StateError('telemetry is down'),
      );

      expect(out, same(pdf));
    });
  });
}

List<int> _pngChunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final crc = _crc32(body);
  return [..._u32(data.length), ...body, ..._u32(crc)];
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
