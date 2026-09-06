// `image_picker_platform_interface` (which also re-exports `XFile`) is a
// transitive dependency via `image_picker` — the same deliberate exception
// `attachment_pickers_metadata_test.dart` takes to stand in for the platform
// picker under `flutter test`.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:noma_chat/noma_chat.dart';

/// `file_picker`'s native channel, mocked the way
/// `noma_chat_view_file_pick_test.dart` mocks it, so the generic file pick
/// can be driven without an OS dialog. Name and codec copied from
/// `MethodChannelFilePicker`.
const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// An engine that always answers, and always re-labels: whatever it is handed
/// comes back as a fixed-size `image/jpeg` under a `.jpg` name.
///
/// That is not a caricature — it is what a real shrinker does to a HEIC or a
/// PNG it re-encodes. The question these tests ask is whether the policy is
/// weighed on the file the user picked or on the engine's answer.
class _RelabellingShrinker implements AttachmentShrinker {
  const _RelabellingShrinker();

  /// Every answer weighs this much, so a size assertion reads as a number
  /// rather than as whatever an encoder happened to produce.
  static const int outputBytes = 8;

  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async => ShrunkAttachment(
    bytes: Uint8List(outputBytes),
    mimeType: 'image/jpeg',
    fileName: 'shrunk.jpg',
  );
}

/// Hands back one file of the caller's choosing on every still-image pick.
///
/// The name travels as the path, not as `name:`: on `dart:io` that named
/// argument is documented as ignored, and `XFile.name` reads the last path
/// segment — which is exactly what a real picker hands over.
class _FixedImagePickerPlatform extends ImagePickerPlatform {
  _FixedImagePickerPlatform({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(bytes, path: name, name: name, mimeType: mimeType);
}

void mockPickedFile({required String name, required Uint8List bytes}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_filePickerChannel, (call) async {
        if (call.method != 'any') return null;
        return [
          {
            'name': name,
            'path': null,
            'bytes': bytes,
            'size': bytes.length,
            'identifier': null,
          },
        ];
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, null);
  });

  group('pickFile weighs the type on the pick and the size on the payload', () {
    test(
      'a document a shrinker re-labels as an image is still a document',
      () async {
        mockPickedFile(name: 'report.pdf', bytes: Uint8List(64));
        AttachmentRejection? rejection;

        final pick = await AttachmentPickers.pickFile(
          policy: const AttachmentPolicy(allowedMimeTypes: {'image/jpeg'}),
          shrinker: const _RelabellingShrinker(),
          onRejected: (r) => rejection = r,
        );

        expect(
          pick,
          isNull,
          reason:
              'the mime whitelist has to be weighed before the shrinker runs, '
              'or a rename walks a rejected file past it',
        );
        expect(rejection, isNotNull);
        expect(rejection!.reason, AttachmentRejectReason.mimeNotAllowed);
        expect(rejection!.mimeType, 'application/pdf');
        expect(rejection!.fileName, 'report.pdf');
      },
    );

    test(
      'a denied extension survives the rename the shrinker performs',
      () async {
        mockPickedFile(name: 'installer.apk', bytes: Uint8List(64));
        AttachmentRejection? rejection;

        final pick = await AttachmentPickers.pickFile(
          shrinker: const _RelabellingShrinker(),
          onRejected: (r) => rejection = r,
        );

        expect(pick, isNull);
        expect(rejection!.reason, AttachmentRejectReason.mimeNotAllowed);
        expect(rejection!.fileName, 'installer.apk');
      },
    );

    test(
      'an image over the cap that the engine brings under it is sent',
      () async {
        mockPickedFile(name: 'holiday.jpg', bytes: Uint8List(4096));

        final pick = await AttachmentPickers.pickFile(
          policy: const AttachmentPolicy(
            allowedMimeTypes: {'image/jpeg'},
            maxBytes: 128,
          ),
          shrinker: const _RelabellingShrinker(),
        );

        expect(pick, isNotNull);
        expect(pick!.size, 8, reason: 'the reduced payload is what travels');
        expect(pick.mimeType, 'image/jpeg');
        expect(pick.fileName, 'shrunk.jpg');
      },
    );

    test('and one the engine cannot bring under it is still refused', () async {
      mockPickedFile(name: 'holiday.jpg', bytes: Uint8List(4096));
      AttachmentRejection? rejection;

      final pick = await AttachmentPickers.pickFile(
        policy: const AttachmentPolicy(
          allowedMimeTypes: {'image/jpeg'},
          maxBytes: 4,
        ),
        shrinker: const _RelabellingShrinker(),
        onRejected: (r) => rejection = r,
      );

      expect(pick, isNull);
      expect(rejection!.reason, AttachmentRejectReason.tooLarge);
      expect(
        rejection!.sizeBytes,
        8,
        reason: 'the rejection reports the payload, not the raw pick',
      );
    });
  });

  group('the gallery and camera picks are weighed the same way', () {
    test('a HEIC a shrinker re-encodes to JPEG is judged as a HEIC', () async {
      ImagePickerPlatform.instance = _FixedImagePickerPlatform(
        name: 'photo.heic',
        mimeType: 'image/heic',
        bytes: Uint8List(64),
      );
      AttachmentRejection? rejection;

      final pick = await AttachmentPickers.pickImageFromGallery(
        policy: const AttachmentPolicy(allowedMimeTypes: {'image/jpeg'}),
        shrinker: const _RelabellingShrinker(),
        onRejected: (r) => rejection = r,
      );

      expect(pick, isNull);
      expect(rejection!.reason, AttachmentRejectReason.mimeNotAllowed);
      expect(rejection!.mimeType, 'image/heic');
    });

    test('the deny-list reaches this path too, on the picked name', () async {
      ImagePickerPlatform.instance = _FixedImagePickerPlatform(
        name: 'dropper.apk',
        mimeType: 'image/jpeg',
        bytes: Uint8List(64),
      );
      AttachmentRejection? rejection;

      final pick = await AttachmentPickers.pickImageFromGallery(
        onRejected: (r) => rejection = r,
      );

      expect(pick, isNull);
      expect(rejection!.reason, AttachmentRejectReason.mimeNotAllowed);
      expect(rejection!.fileName, 'dropper.apk');
    });

    test('an oversized photo the engine reduces is sent', () async {
      ImagePickerPlatform.instance = _FixedImagePickerPlatform(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(4096),
      );

      final pick = await AttachmentPickers.pickImageFromGallery(
        policy: const AttachmentPolicy(
          allowedMimeTypes: {'image/jpeg'},
          maxBytes: 128,
        ),
        shrinker: const _RelabellingShrinker(),
      );

      expect(pick, isNotNull);
      expect(pick!.size, 8);
    });
  });
}
