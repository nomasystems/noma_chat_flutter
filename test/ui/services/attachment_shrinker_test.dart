import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/services/attachment_shrinker.dart';

/// A per-pixel pattern with enough local detail that JPEG can't compress it
/// to near nothing at any resolution — unlike a flat fill or a smooth
/// gradient, which would make every step's output collapse to a few bytes
/// and defeat a test that wants to see the size actually track the
/// resolution and quality it was encoded at.
img.Image _busyImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x * 37 + y * 91) % 256;
      final g = (x * 53 ^ y * 17) % 256;
      final b = (x ~/ 3 + y ~/ 5) % 256;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

void main() {
  group('DefaultAttachmentShrinker.fit', () {
    test(
      'an oversized image is reduced until it fits, as a renamed JPEG',
      () async {
        final source = _busyImage(800, 600);
        final bytes = img.encodePng(source);

        // Two steps, computed here with the same public `image` API the
        // shrinker uses internally, so the cap below is derived from real
        // measurements rather than a guess: it sits strictly between what
        // the first step produces and what the second one does, so the
        // first step is guaranteed to still be too big and the second one
        // is guaranteed to fit.
        const firstStep = ShrinkStep(maxDimension: 500, quality: 90);
        const secondStep = ShrinkStep(maxDimension: 150, quality: 50);
        final firstStepBytes = img.encodeJpg(
          img.copyResize(
            source,
            width: firstStep.maxDimension,
            interpolation: img.Interpolation.average,
          ),
          quality: firstStep.quality,
        );
        final secondStepBytes = img.encodeJpg(
          img.copyResize(
            source,
            width: secondStep.maxDimension,
            interpolation: img.Interpolation.average,
          ),
          quality: secondStep.quality,
        );
        expect(
          secondStepBytes.length,
          lessThan(firstStepBytes.length),
          reason: 'the fixture must make the smaller step the smaller file',
        );
        final maxBytes = secondStepBytes.length + 500;
        expect(
          firstStepBytes.length,
          greaterThan(maxBytes),
          reason:
              'the first step must still be over the cap for this test '
              'to exercise more than one step',
        );

        const shrinker = DefaultAttachmentShrinker(
          steps: [firstStep, secondStep],
        );
        final out = await shrinker.fit(
          bytes,
          mimeType: 'image/png',
          maxBytes: maxBytes,
          fileName: 'photo.png',
        );

        expect(out, isNotNull);
        expect(out!.bytes.length, lessThanOrEqualTo(maxBytes));
        expect(out.mimeType, 'image/jpeg');
        expect(out.fileName, 'photo.jpg');
        final decodedOut = img.decodeImage(out.bytes)!;
        expect(
          decodedOut.width <= secondStep.maxDimension &&
              decodedOut.height <= secondStep.maxDimension,
          isTrue,
          reason:
              'the first step did not fit, so the second one must have '
              'run and produced the smaller resize',
        );
      },
    );

    test(
      'a payload already under the cap is returned as null, untouched',
      () async {
        final source = _busyImage(40, 40);
        final bytes = img.encodePng(source);
        const shrinker = DefaultAttachmentShrinker();
        final out = await shrinker.fit(
          bytes,
          mimeType: 'image/png',
          maxBytes: bytes.length + 1,
          fileName: 'tiny.png',
        );
        expect(out, isNull);
      },
    );

    test('a non-image mime type is declined without re-encoding', () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(1000, (i) => i % 256),
      );
      const shrinker = DefaultAttachmentShrinker();
      final out = await shrinker.fit(
        bytes,
        mimeType: 'application/pdf',
        maxBytes: 10,
        fileName: 'document.pdf',
      );
      expect(out, isNull);
    });

    test('bytes that are not a decodable image come back as null', () async {
      final bytes = Uint8List.fromList(List<int>.filled(200, 0xAB));
      const shrinker = DefaultAttachmentShrinker();
      final out = await shrinker.fit(
        bytes,
        mimeType: 'image/jpeg',
        maxBytes: 10,
        fileName: 'broken.jpg',
      );
      expect(out, isNull);
    });

    test('an empty step list never re-encodes anything', () async {
      final source = _busyImage(200, 200);
      final bytes = img.encodePng(source);
      const shrinker = DefaultAttachmentShrinker(steps: []);
      final out = await shrinker.fit(
        bytes,
        mimeType: 'image/png',
        maxBytes: 10,
        fileName: 'photo.png',
      );
      expect(out, isNull);
    });

    test('a file name without an extension still gets .jpg', () async {
      final source = _busyImage(800, 600);
      final bytes = img.encodePng(source);
      const step = ShrinkStep(maxDimension: 100, quality: 40);
      final stepBytes = img.encodeJpg(
        img.copyResize(
          source,
          width: step.maxDimension,
          interpolation: img.Interpolation.average,
        ),
        quality: step.quality,
      );
      final maxBytes = stepBytes.length + 500;
      expect(
        bytes.length,
        greaterThan(maxBytes),
        reason: 'the source must be over the cap for a shrink to run at all',
      );
      const shrinker = DefaultAttachmentShrinker(steps: [step]);
      final out = await shrinker.fit(
        bytes,
        mimeType: 'image/png',
        maxBytes: maxBytes,
        fileName: 'IMG_20260905',
      );
      expect(out, isNotNull);
      expect(out!.fileName, 'IMG_20260905.jpg');
    });
  });

  group('AttachmentPolicy.shrinkEnabled', () {
    test(
      'shrinkEnabled: false leaves the picked bytes exactly intact',
      () async {
        final source = _busyImage(800, 600);
        final bytes = img.encodePng(source);
        final pick = AttachmentPickResult(bytes: bytes, mimeType: 'image/png');
        final policy = AttachmentPolicy.unrestricted.copyWith(
          shrinkEnabled: false,
          maxBytes: 1 << 30,
        );

        final result = await AttachmentPickers.shrinkToPolicy(
          pick,
          policy: policy,
          shrinker: const DefaultAttachmentShrinker(
            steps: [ShrinkStep(maxDimension: 10, quality: 10)],
          ),
        );

        expect(identical(result, pick), isTrue);
        expect(identical(result.bytes, bytes), isTrue);
        expect(result.mimeType, 'image/png');
      },
    );

    test('shrinkEnabled: true (the default) lets the shrinker run', () async {
      final source = _busyImage(800, 600);
      final bytes = img.encodePng(source);
      const step = ShrinkStep(maxDimension: 100, quality: 40);
      final stepBytes = img.encodeJpg(
        img.copyResize(
          source,
          width: step.maxDimension,
          interpolation: img.Interpolation.average,
        ),
        quality: step.quality,
      );
      // Derived from a real measurement (see the first group's fixture note)
      // rather than a guessed constant: comfortably above what the shrunk
      // step produces, comfortably below the untouched PNG.
      final maxBytes = stepBytes.length + 500;
      expect(bytes.length, greaterThan(maxBytes));

      final pick = AttachmentPickResult(bytes: bytes, mimeType: 'image/png');
      final policy = AttachmentPolicy(
        maxBytesByMimePrefix: {'image/': maxBytes},
      );

      final result = await AttachmentPickers.shrinkToPolicy(
        pick,
        policy: policy,
        shrinker: const DefaultAttachmentShrinker(steps: [step]),
      );

      expect(identical(result, pick), isFalse);
      expect(result.mimeType, 'image/jpeg');
      expect(result.bytes.length, lessThanOrEqualTo(maxBytes));
    });
  });

  group('AttachmentPolicy.defaultShrinkSteps', () {
    test('is five steps, largest dimension first', () {
      const steps = AttachmentPolicy.defaultShrinkSteps;
      expect(steps.length, 5);
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i].maxDimension, lessThan(steps[i - 1].maxDimension));
      }
    });
  });
}
