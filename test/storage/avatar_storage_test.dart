import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';

class _MockChatClient extends Mock implements ChatClient {}

class _MockAttachmentsApi extends Mock implements ChatAttachmentsApi {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  late _MockChatClient client;
  late _MockAttachmentsApi attachments;
  late DefaultAvatarStorage storage;

  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  AttachmentUploadResult uploadResult({String? url}) =>
      AttachmentUploadResult(attachmentId: 'a1', url: url, raw: const {});

  setUp(() {
    client = _MockChatClient();
    attachments = _MockAttachmentsApi();
    when(() => client.attachments).thenReturn(attachments);
    storage = DefaultAvatarStorage(client);
  });

  group('DefaultAvatarStorage.upload', () {
    test('returns the url from a successful attachment upload', () async {
      when(
        () => attachments.upload(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) async => ChatSuccess(uploadResult(url: 'https://cdn/a1.jpg')),
      );

      final url = await storage.upload(bytes, 'image/jpeg', AvatarKind.user);

      expect(url, 'https://cdn/a1.jpg');
      final captured = verify(
        () => attachments.upload(
          captureAny(),
          captureAny(),
          onProgress: any(named: 'onProgress'),
        ),
      ).captured;
      expect(captured[0], bytes);
      expect(captured[1], 'image/jpeg');
    });

    test('throws AvatarStorageException when the upload fails', () async {
      when(
        () => attachments.upload(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const ChatFailureResult(NetworkFailure()));

      expect(
        () => storage.upload(bytes, 'image/jpeg', AvatarKind.room),
        throwsA(isA<AvatarStorageException>()),
      );
    });

    test('throws AvatarStorageException when the url is empty', () async {
      when(
        () => attachments.upload(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => ChatSuccess(uploadResult(url: '')));

      expect(
        () => storage.upload(bytes, 'image/jpeg', AvatarKind.user),
        throwsA(isA<AvatarStorageException>()),
      );
    });

    test('throws AvatarStorageException when the url is null', () async {
      when(
        () => attachments.upload(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => ChatSuccess(uploadResult()));

      expect(
        () => storage.upload(bytes, 'image/jpeg', AvatarKind.user),
        throwsA(isA<AvatarStorageException>()),
      );
    });
  });

  group('DefaultAvatarStorage no-op surfaces', () {
    test('delete completes without touching the client', () async {
      await storage.delete('https://cdn/a1.jpg');
      verifyNever(() => client.attachments);
    });

    test('thumbnailUrl returns null', () async {
      final thumb = await storage.thumbnailUrl(
        'https://cdn/a1.jpg',
        targetSizePx: 96,
      );
      expect(thumb, isNull);
    });
  });

  group('AvatarStorageException', () {
    test('toString includes the message and the cause when present', () {
      final ex = AvatarStorageException('upload failed', 'root');
      expect(ex.toString(), contains('upload failed'));
      expect(ex.toString(), contains('root'));
    });

    test('toString omits the cause when absent', () {
      final ex = AvatarStorageException('upload failed');
      expect(ex.toString(), contains('upload failed'));
      expect(ex.toString(), isNot(contains('cause:')));
    });
  });
}
