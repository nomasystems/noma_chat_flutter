import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/services/jpeg_metadata_stripper.dart';

/// Builds a segment with the two-byte length prefix a real JPEG carries.
/// The length counts itself, hence `payload.length + 2`.
List<int> _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xFF, marker, (length >> 8) & 0xFF, length & 0xFF, ...payload];
}

/// An EXIF payload holding a GPS IFD pointer — the tag that leaks where a
/// photo was taken, which is the whole reason the stripper exists.
final List<int> _exifWithGps = [
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
  0x4D, 0x4D, 0x00, 0x2A, // big-endian TIFF header
  0x00, 0x00, 0x00, 0x08,
  0x00, 0x01, // one directory entry
  0x88, 0x25, // tag 0x8825 = GPS IFD pointer
  0x00, 0x04, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x1A,
];

/// An EXIF payload carrying both the orientation the photo needs to render
/// upright and the GPS pointer it must never travel with.
List<int> _exifWithOrientationAndGps(
  int orientation, {
  bool littleEndian = false,
}) {
  List<int> u16(int value) => littleEndian
      ? [value & 0xFF, (value >> 8) & 0xFF]
      : [(value >> 8) & 0xFF, value & 0xFF];
  List<int> u32(int value) => littleEndian
      ? [
          value & 0xFF,
          (value >> 8) & 0xFF,
          (value >> 16) & 0xFF,
          (value >> 24) & 0xFF,
        ]
      : [
          (value >> 24) & 0xFF,
          (value >> 16) & 0xFF,
          (value >> 8) & 0xFF,
          value & 0xFF,
        ];
  return [
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    if (littleEndian) ...[0x49, 0x49] else ...[0x4D, 0x4D],
    ...u16(0x002A),
    ...u32(8), // IFD0 sits right after the header
    ...u16(2), // two directory entries, in tag order
    ...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0x00, 0x00,
    ...u16(0x8825), ...u16(4), ...u32(1), ...u32(0x1A),
    ...u32(0), // no further IFD
  ];
}

/// The whole APP1 segment the stripper is expected to synthesise: 36 bytes,
/// one tag, nothing copied from the source photo.
List<int> _rebuiltOrientationSegment(int orientation) => [
  0xFF, 0xE1, // APP1
  0x00, 0x22, // 34 bytes, counting this field
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
  0x4D, 0x4D, 0x00, 0x2A, // big-endian TIFF header
  0x00, 0x00, 0x00, 0x08, // IFD0 right after it
  0x00, 0x01, // one entry
  0x01, 0x12, // Orientation
  0x00, 0x03, // SHORT
  0x00, 0x00, 0x00, 0x01, // count 1
  0x00, orientation, 0x00, 0x00, // the value, then padding
  0x00, 0x00, 0x00, 0x00, // no further IFD
];

const List<int> _soi = [0xFF, 0xD8];
final List<int> _jfif = _segment(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00]);
final List<int> _quantTable = _segment(0xDB, [0x00, 0x10, 0x0B]);
// Start of scan, then entropy-coded data and the end-of-image marker.
const List<int> _scan = [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x3F, 0x00];
const List<int> _pixels = [0xAA, 0xBB, 0xCC, 0xDD, 0xFF, 0xD9];

Uint8List _bytes(List<int> parts) => Uint8List.fromList(parts);

bool _containsExifMarker(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xE1) return true;
  }
  return false;
}

void main() {
  group('JpegMetadataStripper', () {
    test('removes the EXIF segment carrying GPS coordinates', () {
      final input = _bytes([
        ..._soi,
        ..._jfif,
        ..._segment(0xE1, _exifWithGps),
        ..._quantTable,
        ..._scan,
        ..._pixels,
      ]);
      expect(_containsExifMarker(input), isTrue, reason: 'fixture sanity');

      final out = JpegMetadataStripper.strip(input);

      expect(_containsExifMarker(out), isFalse);
      expect(out.length, lessThan(input.length));
      // The GPS tag bytes must not survive anywhere in the output.
      expect(out.join(','), isNot(contains('136,37')));
    });

    test('keeps the image data and the JFIF segment byte for byte', () {
      final input = _bytes([
        ..._soi,
        ..._jfif,
        ..._segment(0xE1, _exifWithGps),
        ..._quantTable,
        ..._scan,
        ..._pixels,
      ]);

      final out = JpegMetadataStripper.strip(input);

      expect(
        out,
        equals(
          _bytes([..._soi, ..._jfif, ..._quantTable, ..._scan, ..._pixels]),
        ),
      );
    });

    test('drops XMP and comment segments too', () {
      final input = _bytes([
        ..._soi,
        ..._segment(0xED, [0x50, 0x68, 0x6F, 0x74, 0x6F]), // APP13 / IPTC
        ..._segment(0xFE, [0x68, 0x69]), // comment
        ..._quantTable,
        ..._scan,
        ..._pixels,
      ]);

      final out = JpegMetadataStripper.strip(input);

      expect(
        out,
        equals(_bytes([..._soi, ..._quantTable, ..._scan, ..._pixels])),
      );
    });

    test('copies everything after the scan verbatim', () {
      // Entropy-coded data can contain 0xFF bytes; the walk must not try to
      // interpret them as markers once the scan has started.
      const trickyPixels = [0xFF, 0x00, 0xFF, 0xD0, 0x12, 0xFF, 0xD9];
      final input = _bytes([
        ..._soi,
        ..._quantTable,
        ..._scan,
        ...trickyPixels,
      ]);

      final out = JpegMetadataStripper.strip(input);

      expect(out, equals(input));
    });

    test('tolerates 0xFF padding between segments', () {
      final input = _bytes([
        ..._soi,
        0xFF, 0xFF, // legal fill bytes
        ..._segment(0xE1, _exifWithGps),
        ..._quantTable,
        ..._scan,
        ..._pixels,
      ]);

      final out = JpegMetadataStripper.strip(input);

      expect(_containsExifMarker(out), isFalse);
    });

    group(
      'returns the input untouched when it cannot parse with confidence',
      () {
        test('a PNG', () {
          final png = _bytes([
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
            0x01,
          ]);
          expect(JpegMetadataStripper.strip(png), same(png));
        });

        test('an empty or tiny buffer', () {
          final tiny = _bytes([0xFF, 0xD8]);
          expect(JpegMetadataStripper.strip(tiny), same(tiny));
          final empty = Uint8List(0);
          expect(JpegMetadataStripper.strip(empty), same(empty));
        });

        test('a segment length that runs past the end', () {
          final truncated = _bytes([
            ..._soi,
            0xFF,
            0xE1,
            0x00,
            0x40,
            0x01,
            0x02,
          ]);
          expect(JpegMetadataStripper.strip(truncated), same(truncated));
        });

        test('a length field below the two bytes it counts', () {
          final malformed = _bytes([..._soi, 0xFF, 0xE1, 0x00, 0x01, 0x00]);
          expect(JpegMetadataStripper.strip(malformed), same(malformed));
        });

        test('a file that never reaches a scan', () {
          final noScan = _bytes([
            ..._soi,
            ..._jfif,
            ..._segment(0xE1, _exifWithGps),
          ]);
          expect(JpegMetadataStripper.strip(noScan), same(noScan));
        });

        test('padding that runs to the end of the buffer', () {
          // Without a bounds check after the padding walk this reads past the
          // end and throws, in exactly the malformed case the class promises
          // to survive.
          final trailingFill = _bytes([..._soi, 0xFF, 0xFF]);
          expect(JpegMetadataStripper.strip(trailingFill), same(trailingFill));
        });

        test('a byte that is not a marker where one is expected', () {
          final garbage = _bytes([..._soi, 0x42, 0x43, 0x44, 0x45]);
          expect(JpegMetadataStripper.strip(garbage), same(garbage));
        });
      },
    );

    test('is idempotent', () {
      final input = _bytes([
        ..._soi,
        ..._jfif,
        ..._segment(0xE1, _exifWithGps),
        ..._quantTable,
        ..._scan,
        ..._pixels,
      ]);

      final once = JpegMetadataStripper.strip(input);
      final twice = JpegMetadataStripper.strip(once);

      expect(twice, equals(once));
    });

    group('orientation', () {
      test('survives as a rebuilt segment while the GPS pointer beside it does '
          'not, so a photo shot sideways still renders upright', () {
        final input = _bytes([
          ..._soi,
          ..._jfif,
          ..._segment(0xE1, _exifWithOrientationAndGps(6)),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(
            _bytes([
              ..._soi,
              ..._jfif,
              ..._rebuiltOrientationSegment(6),
              ..._quantTable,
              ..._scan,
              ..._pixels,
            ]),
          ),
        );
        expect(
          out.join(','),
          isNot(contains('136,37')),
          reason: 'the GPS IFD pointer must not survive anywhere',
        );
      });

      test('is read out of a little-endian EXIF block too', () {
        final input = _bytes([
          ..._soi,
          ..._segment(0xE1, _exifWithOrientationAndGps(8, littleEndian: true)),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(
            _bytes([
              ..._soi,
              ..._rebuiltOrientationSegment(8),
              ..._quantTable,
              ..._scan,
              ..._pixels,
            ]),
          ),
          reason: 'the rebuilt block is always big-endian, whatever came in',
        );
      });

      test('1 means upright, so nothing is written back at all', () {
        final input = _bytes([
          ..._soi,
          ..._segment(0xE1, _exifWithOrientationAndGps(1)),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(_bytes([..._soi, ..._quantTable, ..._scan, ..._pixels])),
        );
      });

      test('an out-of-range value is not trusted, and the block goes', () {
        final input = _bytes([
          ..._soi,
          ..._segment(0xE1, _exifWithOrientationAndGps(9)),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(_bytes([..._soi, ..._quantTable, ..._scan, ..._pixels])),
        );
      });

      test('an EXIF block with a broken TIFF header is dropped whole', () {
        final broken = _exifWithOrientationAndGps(6)
          ..[8] =
              0x00 // corrupt the 0x002A magic
          ..[9] = 0x00;
        final input = _bytes([
          ..._soi,
          ..._segment(0xE1, broken),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(_bytes([..._soi, ..._quantTable, ..._scan, ..._pixels])),
          reason: 'a block we cannot walk keeps nothing, orientation included',
        );
      });

      test('an XMP APP1 is still dropped, orientation logic or not', () {
        // "http://ns.adobe.com/xap/1.0/\0" — an APP1 that is not EXIF.
        final xmp = <int>[
          ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
          0x00,
          0x3C,
          0x78,
          0x3E,
        ];
        final input = _bytes([
          ..._soi,
          ..._segment(0xE1, xmp),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final out = JpegMetadataStripper.strip(input);

        expect(
          out,
          equals(_bytes([..._soi, ..._quantTable, ..._scan, ..._pixels])),
        );
      });

      test('a rebuilt block survives a second pass unchanged', () {
        final input = _bytes([
          ..._soi,
          ..._jfif,
          ..._segment(0xE1, _exifWithOrientationAndGps(3)),
          ..._quantTable,
          ..._scan,
          ..._pixels,
        ]);

        final once = JpegMetadataStripper.strip(input);
        final twice = JpegMetadataStripper.strip(once);

        expect(twice, equals(once));
        expect(_containsExifMarker(twice), isTrue);
      });

      test('an MP4 is left alone: the walk never starts', () {
        // `ftyp` box header — the hold-to-record clips that come through the
        // same send path as the stills.
        final mp4 = _bytes([
          0x00, 0x00, 0x00, 0x18, //
          0x66, 0x74, 0x79, 0x70,
          0x6D, 0x70, 0x34, 0x32,
        ]);

        expect(JpegMetadataStripper.strip(mp4), same(mp4));
      });
    });
  });
}
