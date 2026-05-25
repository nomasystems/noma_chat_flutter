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
}
