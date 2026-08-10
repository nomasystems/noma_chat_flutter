// `image_picker_platform_interface` (which also re-exports `XFile`) is a
// transitive dependency via `image_picker` — deliberately not promoted to a
// direct one here, since editing `pubspec.yaml` is out of scope for this
// change.
// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:noma_chat/noma_chat.dart';

/// A string planted in the EXIF of the picked photo, so "did the metadata
/// travel" is a substring search over the bytes the picker hands back.
const String _canary = 'GPS-LEAK-CANARY';

/// What a phone hands the picker: a real JPEG with a real EXIF block holding
/// a GPS position.
Uint8List _photoWithGps() {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 32; x++) {
      image.setPixelRgb(x, y, x * 8, y * 8, 90);
    }
  }
  image.exif.gpsIfd[0x0002] = img.IfdValueRational(41, 1);
  image.exif.imageIfd[0x010F] = img.IfdValueAscii(_canary);
  return img.encodeJpg(image, quality: 90);
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

/// Captures the options `AttachmentPickers` actually sends to the
/// `image_picker` platform channel, standing in for the real iOS/Android
/// implementations (which aren't available under `flutter test`).
class _CapturingImagePickerPlatform extends ImagePickerPlatform {
  ImagePickerOptions? lastImageOptions;
  MediaOptions? lastMediaOptions;

  XFile _fakeImage() => XFile.fromData(
    _photoWithGps(),
    name: 'photo.jpg',
    mimeType: 'image/jpeg',
  );

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastImageOptions = options;
    return _fakeImage();
  }

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    lastMediaOptions = options;
    return [_fakeImage()];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturingImagePickerPlatform fakePlatform;

  setUp(() {
    fakePlatform = _CapturingImagePickerPlatform();
    ImagePickerPlatform.instance = fakePlatform;
  });

  group('AttachmentPickers strips full metadata from picked stills', () {
    // Regression coverage for the GPS/EXIF leak: `image_picker` copies the
    // source PHAsset's full metadata (including GPS + capture time) onto
    // the picked file's re-encoded copy on iOS unless the caller opts out
    // via `requestFullMetadata: false`. Without that flag these assertions
    // fail (the default is `true`).
    test('pickImageFromCamera opts out of full metadata', () async {
      await AttachmentPickers.pickImageFromCamera();

      expect(fakePlatform.lastImageOptions?.requestFullMetadata, isFalse);
    });

    test('pickImageFromGallery opts out of full metadata', () async {
      await AttachmentPickers.pickImageFromGallery();

      expect(fakePlatform.lastImageOptions?.requestFullMetadata, isFalse);
    });

    test('pickMultipleMedia opts out of full metadata', () async {
      await AttachmentPickers.pickMultipleMedia();

      expect(
        fakePlatform.lastMediaOptions?.imageOptions.requestFullMetadata,
        isFalse,
      );
    });

    test('the bytes handed back carry no EXIF at all', () async {
      expect(
        _contains(_photoWithGps(), _canary.codeUnits),
        isTrue,
        reason: 'fixture sanity',
      );

      final pick = await AttachmentPickers.pickImageFromGallery();

      expect(pick, isNotNull);
      expect(_contains(pick!.bytes, _canary.codeUnits), isFalse);
      expect(img.decodeJpg(pick.bytes)!.exif.isEmpty, isTrue);
    });

    test('and the outcome reaches the metric sink once', () async {
      final events = <(String, Map<String, dynamic>)>[];

      await AttachmentPickers.pickImageFromGallery(
        onMetric: (metric, data) => events.add((metric, data)),
      );

      expect(events, hasLength(1));
      expect(events.single.$1, 'image_metadata_strip');
      expect(events.single.$2['outcome'], 'stripped');
    });
  });

  group(
    'a metric sink that throws is the host\'s problem, not the user\'s',
    () {
      test(
        'the pick still comes back, cleaned, and is not called a rejection',
        () async {
          final rejections = <AttachmentRejection>[];

          final pick = await AttachmentPickers.pickImageFromGallery(
            onMetric: (_, _) => throw StateError('telemetry is down'),
            onRejected: rejections.add,
          );

          expect(
            pick,
            isNotNull,
            reason:
                'a broken telemetry sink used to surface to the user as '
                '"your photo is unreadable"',
          );
          expect(rejections, isEmpty);
          expect(_contains(pick!.bytes, _canary.codeUnits), isFalse);
        },
      );

      test('a multi-pick keeps every result', () async {
        final picks = await AttachmentPickers.pickMultipleMedia(
          onMetric: (_, _) => throw StateError('telemetry is down'),
        );

        expect(picks, hasLength(1));
      });
    },
  );
}
