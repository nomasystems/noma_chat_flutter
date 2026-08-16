import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `ChatMessagesController.sendAttachment` paints an optimistic bubble
/// immediately (before the upload even starts) and leaves it visibly
/// failed — instead of blank — when the upload itself fails. Also verifies
/// `attachmentId` reaches the persisted message on success.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  final bytes = Uint8List.fromList(List<int>.filled(16, 7));

  test('paints an optimistic pending bubble synchronously before the upload '
      'resolves', () async {
    final controller = adapter.getChatController('r1');
    expect(controller.messages, isEmpty);

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
      fileName: 'pic.png',
    );

    // The optimistic bubble is added synchronously, before the async
    // upload call is even awaited once.
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.messageType, MessageType.attachment);
    expect(controller.isPending(controller.messages.single.id), isTrue);

    await future;
  });

  test(
    'confirms the bubble with attachmentId on a successful upload',
    () async {
      final controller = adapter.getChatController('r1');

      final result = await adapter.messages.sendAttachment(
        'r1',
        bytes: bytes,
        mimeType: 'image/png',
        fileName: 'pic.png',
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.attachmentId, isNotNull);
      expect(controller.messages, hasLength(1));
      final confirmed = controller.messages.single;
      expect(controller.isFailed(confirmed.id), isFalse);
      expect(confirmed.attachmentId, isNotNull);
    },
  );

  test('marks the optimistic bubble visibly failed (not silently dropped) '
      'when the upload fails', () async {
    client.attachments.failNextUpload = true;
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
      fileName: 'pic.png',
    );

    expect(result.isFailure, isTrue);
    // The bubble stays in the list — visible and marked failed — instead
    // of vanishing.
    expect(controller.messages, hasLength(1));
    expect(controller.isFailed(controller.messages.single.id), isTrue);
  });

  test('a dangerous extension is refused on the upload path too, not only at '
      'pick time', () async {
    // The pickers are not the only door into the upload: a host that builds
    // the bytes itself (web drag-and-drop, a share-intent handler) reaches
    // `sendAttachment` directly. The deny-list floor has to hold here, under
    // the *default* policy — no whitelist configured.
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'application/octet-stream',
      fileName: 'payload.exe',
    );

    expect(result.isFailure, isTrue);
    final failure = result.failureOrNull;
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure! as ValidationFailure).errors,
      allOf(
        containsPair(
          'kind',
          AttachmentPolicyViolationKind.extensionDenied.name,
        ),
        containsPair('extension', 'exe'),
      ),
    );
    expect(client.attachments.uploadCount, 0);
    expect(controller.messages, isEmpty);
  });

  test('an uncommon-but-safe extension uploads under the default policy — '
      'the floor is a deny-list, not a whitelist (D-13)', () async {
    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'application/octet-stream',
      fileName: 'checksum-export.xyz',
    );

    expect(result.isSuccess, isTrue);
    expect(client.attachments.uploadCount, 1);
  });

  test('a policy violation never paints a bubble at all', () async {
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'application/x-executable',
      policy: const AttachmentPolicy(allowedMimeTypes: {'image/*'}),
    );

    expect(result.isFailure, isTrue);
    expect(controller.messages, isEmpty);
  });
}
