import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noma_chat/src/ui/services/icc_colour_profile.dart';

/// A string planted inside every hostile profile, so "did any of this reach
/// the classifier's answer or the output" is a substring search.
const String _canary = 'ICC-LEAK-CANARY';

/// The `rXYZ` / `gXYZ` / `bXYZ` tag data of the `Display P3.icc` macOS ships,
/// as the `s15Fixed16` words it stores, so the assertion is on bytes rather
/// than on a rounded decimal. The library must land on every one of these
/// having been told nothing but two chromaticity triples and a white point.
const List<int> _displayP3Colorants = [
  0x000083DF, 0x00003DBF, -0x45, //
  0x00004ABF, 0x0000B137, 0x00000AB9,
  0x00002838, 0x0000110B, 0x0000C8B9,
];

/// The colorants the profiles shipped by macOS carry, read out of them once and
/// pinned here. They are the independent reference: nothing in the library
/// produced these numbers, so a colorimetry change that quietly shifts the
/// emitted profile has to disagree with them to pass. Eight decimals is far
/// inside [IccColourProfile.tolerance], which is all a classification fixture
/// needs.
const Map<String, List<double>> _reference = {
  'Display P3': [
    0.51512146, 0.24119568, -0.00105286, //
    0.29197693, 0.69224548, 0.04188538,
    0.15710449, 0.06657410, 0.78407288,
  ],
  'sRGB IEC61966-2.1': [
    0.43606567, 0.22248840, 0.01391602, //
    0.38514709, 0.71687317, 0.09707642,
    0.14306641, 0.06060791, 0.71409607,
  ],
  'Adobe RGB (1998)': [
    0.60974121, 0.31111145, 0.01947021, //
    0.20527649, 0.62567139, 0.06086731,
    0.14918518, 0.06321716, 0.74456787,
  ],
  'DCI(P3) RGB': [
    0.48616028, 0.22668457, -0.00080872, //
    0.32385254, 0.71032715, 0.04322815,
    0.15419006, 0.06298828, 0.78247070,
  ],
  'Rec. ITU-R BT.2020': [
    0.67347717, 0.27903748, -0.00193787, //
    0.16566467, 0.67533875, 0.02998352,
    0.12504578, 0.04560852, 0.79684448,
  ],
};

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _s15(double value) => _u32((value * 65536).round() & 0xFFFFFFFF);

/// A minimal matrix/TRC profile: a header, three colorant tags, and whatever
/// the caller wants to lie about.
Uint8List _profile(
  List<double> colorants, {
  String colourSpace = 'RGB ',
  String signature = 'acsp',
  int? declaredSize,
  int? tagCount,
  int? tagOffset,
  int? tagSize,
  List<int> canary = const [],
  int chunkPrefix = 0,
}) {
  const int dataStart = 132 + 3 * 12;
  final header = List<int>.filled(128, 0);
  void put(int at, List<int> value) {
    for (var i = 0; i < value.length; i++) {
      header[at + i] = value[i];
    }
  }

  final size = declaredSize ?? dataStart + 3 * 20 + canary.length;
  put(0, _u32(size));
  put(8, _u32(0x04000000));
  put(12, 'mntr'.codeUnits);
  put(16, colourSpace.codeUnits);
  put(20, 'XYZ '.codeUnits);
  put(36, signature.codeUnits);

  final table = <int>[];
  for (var slot = 0; slot < 3; slot++) {
    table.addAll([
      ...['rXYZ', 'gXYZ', 'bXYZ'][slot].codeUnits,
      ..._u32(tagOffset ?? dataStart + slot * 20),
      ..._u32(tagSize ?? 20),
    ]);
  }

  final data = <int>[];
  for (var slot = 0; slot < 3; slot++) {
    data.addAll([
      ...'XYZ '.codeUnits, 0, 0, 0, 0, //
      ..._s15(colorants[slot * 3]),
      ..._s15(colorants[slot * 3 + 1]),
      ..._s15(colorants[slot * 3 + 2]),
    ]);
  }

  return Uint8List.fromList([
    ...List<int>.filled(chunkPrefix, 1),
    ...header,
    ..._u32(tagCount ?? 3),
    ...table,
    ...data,
    ...canary,
  ]);
}

img.IccProfile _wrap(Uint8List bytes) =>
    img.IccProfile('x', img.IccProfileCompression.none, bytes);

SourceColourSpace _classify(Uint8List bytes) =>
    IccColourProfile.classify(_wrap(bytes));

/// Every tag in [profile], by signature, as (offset, size).
Map<String, (int, int)> _tags(Uint8List profile) {
  final view = ByteData.sublistView(profile);
  final count = view.getUint32(128);
  return {
    for (var i = 0; i < count; i++)
      String.fromCharCodes(profile, 132 + i * 12, 136 + i * 12): (
        view.getUint32(136 + i * 12),
        view.getUint32(140 + i * 12),
      ),
  };
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

void main() {
  final profile = IccColourProfile.displayP3;
  final view = ByteData.sublistView(profile);
  final tags = _tags(profile);

  group(
    'the emitted profile is what ICC.1:2010 says a v4 display profile is',
    () {
      test('the header names itself correctly, field by field', () {
        expect(view.getUint32(0), profile.length, reason: 'declared size');
        expect(view.getUint32(4), 0, reason: 'preferred CMM: none');
        expect(view.getUint32(8), 0x04000000, reason: 'version 4.0.0.0');
        expect(String.fromCharCodes(profile, 12, 16), 'mntr');
        expect(String.fromCharCodes(profile, 16, 20), 'RGB ');
        expect(String.fromCharCodes(profile, 20, 24), 'XYZ ');
        expect(String.fromCharCodes(profile, 36, 40), 'acsp');
        expect(view.getUint32(40), 0, reason: 'primary platform: none');
        expect(view.getUint32(44), 0, reason: 'profile flags');
        expect(view.getUint32(64), 0, reason: 'rendering intent: perceptual');
        expect(
          [view.getInt32(68), view.getInt32(72), view.getInt32(76)],
          equals([0x0000F6D6, 0x00010000, 0x0000D32D]),
          reason: 'the PCS illuminant is D50, section 7.2.16',
        );
      });

      test('it carries no timestamp, no identity and no reserved noise', () {
        expect(
          profile.sublist(24, 36),
          everyElement(0),
          reason:
              'a creation date would stamp every photo with the second it was '
              'sent',
        );
        expect(view.getUint32(48), 0, reason: 'device manufacturer');
        expect(view.getUint32(52), 0, reason: 'device model');
        expect(profile.sublist(56, 64), everyElement(0), reason: 'attributes');
        expect(view.getUint32(80), 0, reason: 'profile creator');
        expect(profile.sublist(84, 100), everyElement(0), reason: 'profile ID');
        expect(profile.sublist(100, 128), everyElement(0), reason: 'reserved');
      });

      test('every required tag is present and none other', () {
        expect(
          tags.keys.toSet(),
          equals({
            'desc', 'cprt', 'wtpt', 'chad', //
            'rXYZ', 'gXYZ', 'bXYZ',
            'rTRC', 'gTRC', 'bTRC',
          }),
        );
      });

      test('every tag lies inside the profile and starts on a word', () {
        for (final tag in tags.entries) {
          final (offset, size) = tag.value;
          expect(offset % 4, 0, reason: '${tag.key} alignment');
          expect(offset, greaterThanOrEqualTo(132 + tags.length * 12));
          expect(
            offset + size,
            lessThanOrEqualTo(profile.length),
            reason: tag.key,
          );
        }
      });

      test('the three tone curves are one element, pointed at three times', () {
        expect(tags['rTRC'], tags['gTRC']);
        expect(tags['gTRC'], tags['bTRC']);
      });

      test('it is 512 bytes, and the same 512 bytes every time', () {
        expect(profile.length, 512);
        expect(IccColourProfile.displayP3, same(profile));
      });
    },
  );

  group('the numbers in it are Display P3, derived not copied', () {
    test('the colorants reproduce the reference set, word for word', () {
      for (final (slot, signature) in ['rXYZ', 'gXYZ', 'bXYZ'].indexed) {
        final (offset, size) = tags[signature]!;
        expect(size, 20);
        expect(String.fromCharCodes(profile, offset, offset + 4), 'XYZ ');
        for (var component = 0; component < 3; component++) {
          expect(
            view.getInt32(offset + 8 + component * 4),
            _displayP3Colorants[slot * 3 + component],
            reason: '$signature component $component',
          );
        }
      }
    });

    test('the media white point is the PCS illuminant', () {
      final (offset, _) = tags['wtpt']!;
      expect([
        view.getInt32(offset + 8),
        view.getInt32(offset + 12),
        view.getInt32(offset + 16),
      ], equals([0x0000F6D6, 0x00010000, 0x0000D32D]));
    });

    test('the tone curve is the sRGB transfer function, in five numbers', () {
      final (offset, size) = tags['rTRC']!;
      expect(size, 32);
      expect(String.fromCharCodes(profile, offset, offset + 4), 'para');
      expect(view.getUint16(offset + 8), 3, reason: 'function type 3');
      expect(
        [for (var i = 0; i < 5; i++) view.getInt32(offset + 12 + i * 4)],
        equals([0x00026666, 0x0000F2A7, 0x00000D59, 0x000013D0, 0x00000A5B]),
        reason: 'g=2.4, a=1/1.055, b=0.055/1.055, c=1/12.92, d=0.04045',
      );
    });

    test('the adaptation matrix is Bradford, D65 to D50', () {
      final (offset, size) = tags['chad']!;
      expect(size, 44);
      expect(String.fromCharCodes(profile, offset, offset + 4), 'sf32');
      final actual = [
        for (var i = 0; i < 9; i++) view.getInt32(offset + 8 + i * 4) / 65536,
      ];
      const expected = [
        1.04788208, 0.02291870, -0.05020142, //
        0.02958679, 0.99047852, -0.01705933,
        -0.00923157, 0.01507568, 0.75167847,
      ];
      for (var i = 0; i < 9; i++) {
        expect(actual[i], closeTo(expected[i], 1 / 65536), reason: 'cell $i');
      }
    });

    test('what we emit is what we would classify', () {
      expect(_classify(profile), SourceColourSpace.displayP3);
    });
  });

  group('classification names the space and nothing else', () {
    test('no profile at all is the common case, not a failure', () {
      expect(IccColourProfile.classify(null), SourceColourSpace.absent);
    });

    test('Display P3 and sRGB are recognised', () {
      expect(
        _classify(_profile(_reference['Display P3']!)),
        SourceColourSpace.displayP3,
      );
      expect(
        _classify(_profile(_reference['sRGB IEC61966-2.1']!)),
        SourceColourSpace.srgb,
      );
    });

    test('the chunk pair a conformant JPEG puts in front is stepped over', () {
      expect(
        _classify(_profile(_reference['Display P3']!, chunkPrefix: 2)),
        SourceColourSpace.displayP3,
      );
    });

    test('neighbouring spaces are not mistaken for either', () {
      for (final name in [
        'Adobe RGB (1998)',
        'DCI(P3) RGB',
        'Rec. ITU-R BT.2020',
      ]) {
        expect(
          _classify(_profile(_reference[name]!)),
          SourceColourSpace.unrecognised,
          reason: name,
        );
      }
    });

    test('a non-RGB device profile is not guessed at', () {
      expect(
        _classify(_profile(_reference['Display P3']!, colourSpace: 'CMYK')),
        SourceColourSpace.unrecognised,
      );
    });

    test('a profile off by more than the tolerance is not claimed', () {
      final drifted = [..._reference['Display P3']!];
      drifted[0] += IccColourProfile.tolerance * 2;

      expect(_classify(_profile(drifted)), SourceColourSpace.unrecognised);
    });

    test('a profile inside the tolerance still is', () {
      final drifted = [
        for (final v in _reference['Display P3']!)
          v + IccColourProfile.tolerance / 2,
      ];

      expect(_classify(_profile(drifted)), SourceColourSpace.displayP3);
    });
  });

  group('a hostile profile cannot crash the classifier or reach anything', () {
    final hostile = <String, Uint8List>{
      'empty': Uint8List(0),
      'a header and no more': Uint8List(64),
      'not a profile': _profile(
        _reference['Display P3']!,
        signature: 'evil',
        canary: _canary.codeUnits,
      ),
      'a size smaller than a header': _profile(
        _reference['Display P3']!,
        declaredSize: 8,
        canary: _canary.codeUnits,
      ),
      'a size larger than the bytes': _profile(
        _reference['Display P3']!,
        declaredSize: 0xFFFFFFF,
        canary: _canary.codeUnits,
      ),
      'a tag count no table could hold': _profile(
        _reference['Display P3']!,
        tagCount: 0xFFFFFFFF,
        canary: _canary.codeUnits,
      ),
      'a tag pointing past the end': _profile(
        _reference['Display P3']!,
        tagOffset: 0xFFFFFF00,
        canary: _canary.codeUnits,
      ),
      'a tag pointing into its own table': _profile(
        _reference['Display P3']!,
        tagOffset: 8,
        canary: _canary.codeUnits,
      ),
      'a tag size that runs off the end': _profile(
        _reference['Display P3']!,
        tagSize: 0xFFFFFFFF,
        canary: _canary.codeUnits,
      ),
    };

    for (final entry in hostile.entries) {
      test('${entry.key} is refused, not read', () {
        expect(_classify(entry.value), SourceColourSpace.unreadable);
      });
    }

    test('a deflate bomb is never inflated', () {
      final bomb = img.IccProfile(
        'bomb',
        img.IccProfileCompression.none,
        Uint8List(64 * 1024 * 1024),
      );
      bomb.compressed();
      expect(bomb.data.length, greaterThan(16 * 1024));

      expect(IccColourProfile.classify(bomb), SourceColourSpace.unreadable);
    });

    test('a profile that would inflate to something absurd is refused', () {
      final wide = img.IccProfile(
        'wide',
        img.IccProfileCompression.none,
        _profile(_reference['Display P3']!),
      )..compressed();

      expect(IccColourProfile.classify(wide), SourceColourSpace.displayP3);
    });

    test('none of them changes what we would emit', () {
      for (final payload in hostile.values) {
        _classify(payload);
      }

      expect(IccColourProfile.displayP3.length, 512);
      expect(_contains(IccColourProfile.displayP3, _canary.codeUnits), isFalse);
    });
  });

  group('the JPEG segment is the one ICC.1:2010 Annex B.4 specifies', () {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xE0, 0x00, 0x10, ...List<int>.filled(14, 0),
      0xFF, 0xDB, 0x00, 0x04, 0, 0,
    ]);

    test('it goes in behind the JFIF header, whole', () {
      final out = IccColourProfile.attachToJpeg(jpeg, profile)!;

      expect(out.length, jpeg.length + 530);
      expect(out.sublist(0, 20), equals(jpeg.sublist(0, 20)));
      expect([out[20], out[21]], equals([0xFF, 0xE2]));
      expect((out[22] << 8) | out[23], 528, reason: 'segment length');
      expect(String.fromCharCodes(out, 24, 35), 'ICC_PROFILE');
      expect(out[35], 0, reason: 'the signature is NUL terminated');
      expect([out[36], out[37]], equals([1, 1]), reason: 'chunk 1 of 1');
      expect(out.sublist(38, 38 + profile.length), equals(profile));
      expect(
        out.sublist(38 + profile.length),
        equals(jpeg.sublist(20)),
        reason: 'the rest of the file is untouched',
      );
    });

    test('a file that is not shaped like one is refused, not corrupted', () {
      expect(IccColourProfile.attachToJpeg(Uint8List(0), profile), isNull);
      expect(
        IccColourProfile.attachToJpeg(
          Uint8List.fromList([0xFF, 0xD9]),
          profile,
        ),
        isNull,
      );
      expect(
        IccColourProfile.attachToJpeg(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xFF]),
          profile,
        ),
        isNull,
        reason: 'an APP0 claiming to be longer than the file',
      );
    });

    test('a profile too large for a single segment is refused', () {
      expect(IccColourProfile.attachToJpeg(jpeg, Uint8List(0x10000)), isNull);
    });
  });
}
