import 'dart:typed_data';

/// Removes the metadata segments of a JPEG, most importantly the EXIF block
/// that carries GPS coordinates and the capture timestamp.
///
/// This exists because `image_picker_android` copies EXIF from the source
/// file unconditionally whenever it resizes (any `imageQuality < 100`), and
/// offers no flag to suppress it. Without this pass, a photo sent to a room
/// would tell every member who downloads the original where it was taken.
///
/// The walk is deliberately conservative. Anything unexpected — not a JPEG,
/// a truncated segment, a length that runs past the end — returns the input
/// unchanged rather than guessing. Corrupting someone's photo is a far worse
/// outcome than leaving metadata on it, so every doubt resolves to "leave it
/// alone".
class JpegMetadataStripper {
  JpegMetadataStripper._();

  static const int _marker = 0xFF;
  static const int _soi = 0xD8;
  static const int _sos = 0xDA;
  static const int _app1 = 0xE1;
  static const int _app13 = 0xED;
  static const int _comment = 0xFE;

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
      while (markerStart + 1 < bytes.length && bytes[markerStart + 1] == _marker) {
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
      }
      i = segmentEnd;
    }

    // Ran off the end without reaching a scan: the file is truncated, so
    // hand back the original rather than a re-assembled guess.
    return bytes;
  }
}
