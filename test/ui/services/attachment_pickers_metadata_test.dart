// `image_picker_platform_interface` (which also re-exports `XFile`) is a
// transitive dependency via `image_picker` — deliberately not promoted to a
// direct one here, since editing `pubspec.yaml` is out of scope for this
// change.
// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:noma_chat/noma_chat.dart';

/// Captures the options `AttachmentPickers` actually sends to the
/// `image_picker` platform channel, standing in for the real iOS/Android
/// implementations (which aren't available under `flutter test`).
class _CapturingImagePickerPlatform extends ImagePickerPlatform {
  ImagePickerOptions? lastImageOptions;
  MediaOptions? lastMediaOptions;

  XFile _fakeImage() => XFile.fromData(
    Uint8List.fromList([1, 2, 3, 4]),
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
  });
}
