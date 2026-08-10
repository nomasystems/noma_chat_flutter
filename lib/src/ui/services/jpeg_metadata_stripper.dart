import 'dart:typed_data';

/// Removes the metadata segments of a JPEG, most importantly the EXIF block
/// that carries GPS coordinates and the capture timestamp.
///
/// This exists because `image_picker_android` copies EXIF from the source
/// file unconditionally whenever it resizes (any `imageQuality < 100`), and
/// offers no flag to suppress it. Without this pass, a photo sent to a room
/// would tell every member who downloads the original where it was taken.
///
/// Exactly one tag survives: TIFF **Orientation** (`0x0112`). Neither
/// `image_picker_android` nor the `camera` plugin rotates the pixels it
/// writes — `ImageResizer` decodes with `BitmapFactory` and CameraX records
/// `setTargetRotation` in EXIF — so dropping that tag makes every photo shot
/// with the phone turned render sideways for every recipient. It is safe to
/// keep because it is not copied: the original APP1 is discarded whole and a
/// fresh 36-byte one is synthesised holding a single SHORT whose only legal
/// values are 1-8. Nothing from the source block — GPS, timestamps, maker
/// notes, the thumbnail, serial numbers — can ride along, because none of the
/// source bytes are in the output.
///
/// The walk is deliberately conservative. Anything unexpected — not a JPEG,
/// a truncated segment, a length that runs past the end — returns the input
/// unchanged rather than guessing. Corrupting someone's photo is a far worse
/// outcome than leaving metadata on it, so every doubt resolves to "leave it
/// alone". An EXIF block that cannot be parsed with that same confidence is
/// dropped whole, orientation included.
class JpegMetadataStripper {
  JpegMetadataStripper._();

  static const int _marker = 0xFF;
  static const int _soi = 0xD8;
  static const int _sos = 0xDA;
  static const int _app1 = 0xE1;
  static const int _app13 = 0xED;
  static const int _comment = 0xFE;

  static const int _orientationTag = 0x0112;
  static const int _typeShort = 3;
  static const int _typeLong = 4;

  /// `Exif\0\0`, the APP1 identifier that tells EXIF apart from XMP.
  static const List<int> _exifIdentifier = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];

  /// Segments carrying metadata rather than image data: EXIF and XMP (APP1),
  /// IPTC/Photoshop resources (APP13), and free-text comments.
  ///
  /// APP0 (JFIF) is deliberately kept — decoders rely on it and it holds no
  /// personal data.
  static bool _isMetadata(int marker) =>
      marker == _app1 || marker == _app13 || marker == _comment;

  /// Returns [bytes] without its metadata segments, or [bytes] itself when
  /// the input is not a JPEG or cannot be parsed with full confidence.
  static Uint8List strip(Uint8List bytes) {
    if (bytes.length < 4) return bytes;
    if (bytes[0] != _marker || bytes[1] != _soi) return bytes;

    final kept = BytesBuilder(copy: false)..add(<int>[_marker, _soi]);
    var i = 2;

    while (i + 1 < bytes.length) {
      if (bytes[i] != _marker) return bytes;

      // Padding between segments is legal: any run of 0xFF bytes collapses
      // into the marker prefix of the next segment.
      var markerStart = i;
      while (markerStart + 1 < bytes.length &&
          bytes[markerStart + 1] == _marker) {
        markerStart++;
      }
      // Padding that runs to the end of the buffer leaves no marker to read.
      if (markerStart + 1 >= bytes.length) return bytes;
      final marker = bytes[markerStart + 1];
      final segmentStart = markerStart + 2;

      // Start of scan: the entropy-coded image data follows and has no
      // length prefix, so copy the remainder verbatim and stop walking.
      if (marker == _sos) {
        kept.add(Uint8List.sublistView(bytes, i));
        return kept.toBytes();
      }

      if (segmentStart + 1 >= bytes.length) return bytes;
      final length = (bytes[segmentStart] << 8) | bytes[segmentStart + 1];
      // The length field counts itself, so anything under 2 is malformed.
      if (length < 2) return bytes;
      final segmentEnd = segmentStart + length;
      if (segmentEnd > bytes.length) return bytes;

      if (!_isMetadata(marker)) {
        kept.add(Uint8List.sublistView(bytes, i, segmentEnd));
      } else if (marker == _app1) {
        final orientation = _readOrientation(
          bytes,
          segmentStart + 2,
          segmentEnd,
        );
        // 1 is "already upright": re-stating it buys nothing over saying
        // nothing at all, so the segment goes like every other APP1.
        if (orientation != null && orientation != 1) {
          kept.add(_orientationSegment(orientation));
        }
      }
      i = segmentEnd;
    }

    // Ran off the end without reaching a scan: the file is truncated, so
    // hand back the original rather than a re-assembled guess.
    return bytes;
  }

  /// Reads the IFD0 Orientation value out of the APP1 payload spanning
  /// [payloadStart] (inclusive) to [segmentEnd] (exclusive), or `null` when
  /// the block is not EXIF, carries no orientation, or cannot be walked with
  /// full confidence.
  static int? _readOrientation(
    Uint8List bytes,
    int payloadStart,
    int segmentEnd,
  ) {
    var cursor = payloadStart;
    for (final expected in _exifIdentifier) {
      if (cursor >= segmentEnd || bytes[cursor] != expected) return null;
      cursor++;
    }

    // Offsets inside an EXIF block are relative to the start of its own TIFF
    // header, which is also what carries the byte order for every field.
    final tiff = cursor;
    if (tiff + 8 > segmentEnd) return null;
    final bool bigEndian;
    if (bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D) {
      bigEndian = true;
    } else if (bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49) {
      bigEndian = false;
    } else {
      return null;
    }

    int readU16(int at) => bigEndian
        ? (bytes[at] << 8) | bytes[at + 1]
        : (bytes[at + 1] << 8) | bytes[at];
    int readU32(int at) => bigEndian
        ? (bytes[at] << 24) |
              (bytes[at + 1] << 16) |
              (bytes[at + 2] << 8) |
              bytes[at + 3]
        : (bytes[at + 3] << 24) |
              (bytes[at + 2] << 16) |
              (bytes[at + 1] << 8) |
              bytes[at];

    if (readU16(tiff + 2) != 0x002A) return null;
    final ifd0 = tiff + readU32(tiff + 4);
    if (ifd0 < tiff + 8 || ifd0 + 2 > segmentEnd) return null;
    final entryCount = readU16(ifd0);
    final entriesEnd = ifd0 + 2 + entryCount * 12;
    if (entriesEnd > segmentEnd) return null;

    for (var index = 0; index < entryCount; index++) {
      final entry = ifd0 + 2 + index * 12;
      if (readU16(entry) != _orientationTag) continue;
      if (readU32(entry + 4) != 1) return null;
      // A single SHORT (or the LONG some encoders write instead) fits in the
      // entry's inline value field, so no out-of-line offset is ever followed.
      final value = switch (readU16(entry + 2)) {
        _typeShort => readU16(entry + 8),
        _typeLong => readU32(entry + 8),
        _ => 0,
      };
      return value >= 1 && value <= 8 ? value : null;
    }
    return null;
  }

  /// A complete APP1 segment built from scratch whose entire content is the
  /// Orientation tag — 36 bytes, none of them from the source photo.
  static Uint8List _orientationSegment(int orientation) => Uint8List.fromList([
    _marker, _app1,
    0x00, 0x22, // 34: the length field plus the 32 bytes after it
    ..._exifIdentifier,
    0x4D, 0x4D, 0x00, 0x2A, // big-endian TIFF header…
    0x00, 0x00, 0x00, 0x08, // …with IFD0 immediately after it
    0x00, 0x01, // exactly one entry
    0x01, 0x12, // Orientation
    0x00, 0x03, // SHORT
    0x00, 0x00, 0x00, 0x01, // count 1
    0x00, orientation, 0x00, 0x00, // value, then the unused half of the field
    0x00, 0x00, 0x00, 0x00, // no further IFD
  ]);
}
