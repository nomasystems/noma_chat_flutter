import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  // Needed so the plugin MethodChannels exist; with no registered handler
  // they throw `MissingPluginException`, which the pickers swallow.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentPickResult', () {
    test('exposes bytes, mime, file name and derived size', () {
      final result = AttachmentPickResult(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        mimeType: 'image/png',
        fileName: 'photo.png',
      );

      expect(result.bytes, [1, 2, 3, 4]);
      expect(result.mimeType, 'image/png');
      expect(result.fileName, 'photo.png');
      expect(result.size, 4);
    });

    test('file name defaults to null', () {
      final result = AttachmentPickResult(
        bytes: Uint8List(0),
        mimeType: 'application/octet-stream',
      );

      expect(result.fileName, isNull);
      expect(result.size, 0);
    });
  });

  group('AttachmentPickers — plugin failures are swallowed', () {
    test('pickImageFromCamera returns null and logs a warning', () async {
      final logs = <String>[];

      final result = await AttachmentPickers.pickImageFromCamera(
        logger: (level, message) => logs.add('$level:$message'),
      );

      expect(result, isNull);
      expect(logs.any((l) => l.startsWith('warn:')), isTrue);
    });

    test('pickImageFromGallery returns null on plugin failure', () async {
      expect(await AttachmentPickers.pickImageFromGallery(), isNull);
    });

    test('pickVideoFromGallery returns null on plugin failure', () async {
      expect(await AttachmentPickers.pickVideoFromGallery(), isNull);
    });

    test('pickMultipleMedia returns an empty list on plugin failure', () async {
      expect(await AttachmentPickers.pickMultipleMedia(), isEmpty);
    });

    test('pickFile returns null on plugin failure', () async {
      final logs = <String>[];

      final result = await AttachmentPickers.pickFile(
        allowedExtensions: const ['pdf'],
        logger: (level, message) => logs.add('$level:$message'),
      );

      expect(result, isNull);
      expect(logs.any((l) => l.startsWith('warn:')), isTrue);
    });
  });

  group('AttachmentPickers — onRejected is no longer a silent drop', () {
    test('pickImageFromGallery reports onRejected on plugin failure', () async {
      AttachmentRejection? rejection;

      await AttachmentPickers.pickImageFromGallery(
        onRejected: (r) => rejection = r,
      );

      expect(rejection, isNotNull);
      expect(rejection!.reason, AttachmentRejectReason.unreadable);
    });

    test('pickVideoFromGallery reports onRejected on plugin failure', () async {
      AttachmentRejection? rejection;

      await AttachmentPickers.pickVideoFromGallery(
        onRejected: (r) => rejection = r,
      );

      expect(rejection, isNotNull);
      expect(rejection!.reason, AttachmentRejectReason.unreadable);
    });

    test('pickMultipleMedia reports onRejected on plugin failure', () async {
      AttachmentRejection? rejection;

      await AttachmentPickers.pickMultipleMedia(
        onRejected: (r) => rejection = r,
      );

      expect(rejection, isNotNull);
      expect(rejection!.reason, AttachmentRejectReason.unreadable);
    });

    test('pickFile reports onRejected on plugin failure', () async {
      AttachmentRejection? rejection;

      await AttachmentPickers.pickFile(
        allowedExtensions: const ['pdf'],
        onRejected: (r) => rejection = r,
      );

      expect(rejection, isNotNull);
      expect(rejection!.reason, AttachmentRejectReason.unreadable);
    });

    test('onRejected being null does not change any return value '
        '(fully backward compatible)', () async {
      expect(await AttachmentPickers.pickImageFromGallery(), isNull);
      expect(await AttachmentPickers.pickMultipleMedia(), isEmpty);
    });
  });

  group('AttachmentRejection', () {
    test('fromPolicyViolation(tooLarge) carries size/mime context and a '
        'ready-to-show message', () {
      final violation = AttachmentPolicyViolation.tooLarge(
        mimeType: 'video/mp4',
        actualBytes: 200 * 1024 * 1024,
        maxBytes: 100 * 1024 * 1024,
      );
      final rejection = AttachmentRejection.fromPolicyViolation(
        violation,
        fileName: 'movie.mp4',
        sizeBytes: 200 * 1024 * 1024,
      );

      expect(rejection.reason, AttachmentRejectReason.tooLarge);
      expect(rejection.fileName, 'movie.mp4');
      expect(rejection.sizeBytes, 200 * 1024 * 1024);
      expect(rejection.mimeType, 'video/mp4');
      expect(rejection.message, isNotEmpty);
    });

    test('fromPolicyViolation(mimeNotAllowed) carries the mime type', () {
      final violation = AttachmentPolicyViolation.mimeNotAllowed(
        'application/x-executable',
      );
      final rejection = AttachmentRejection.fromPolicyViolation(violation);

      expect(rejection.reason, AttachmentRejectReason.mimeNotAllowed);
      expect(rejection.mimeType, 'application/x-executable');
      expect(rejection.message, contains('application/x-executable'));
    });

    test('unreadable() carries no size/mime context', () {
      final rejection = AttachmentRejection.unreadable(fileName: 'weird.bin');
      expect(rejection.reason, AttachmentRejectReason.unreadable);
      expect(rejection.fileName, 'weird.bin');
      expect(rejection.sizeBytes, isNull);
      expect(rejection.mimeType, isNull);
    });

    test('toString includes the reason and message', () {
      final rejection = AttachmentRejection.unreadable();
      expect(rejection.toString(), contains('unreadable'));
    });
  });
}
