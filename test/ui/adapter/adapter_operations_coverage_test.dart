import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Broad exercise of [ChatUiAdapter] pass-through operations against the
/// in-memory [MockChatClient]. Each call covers both the adapter
/// pass-through and the underlying sub-controller body. Operations the
/// mock fully supports are asserted to succeed; a few that depend on
/// pending/optimistic state are only driven to completion (the line
/// coverage is the point, not the specific result).
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client
      ..seedRoom(
        const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1', 'u2']),
      )
      ..seedRoom(
        const ChatRoom(id: 'r2', name: 'Room 2', members: ['me', 'u3']),
      )
      ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'))
      ..seedUser(const ChatUser(id: 'u2', displayName: 'Bob'))
      ..seedUser(const ChatUser(id: 'u3', displayName: 'Carol'));
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  group('ChatUiAdapter — room operations', () {
    test('load + flag toggles + config + membership succeed', () async {
      expect((await adapter.loadRooms()).isSuccess, isTrue);

      expect((await adapter.muteRoom('r1')).isSuccess, isTrue);
      expect((await adapter.unmuteRoom('r1')).isSuccess, isTrue);
      expect((await adapter.pinRoom('r1')).isSuccess, isTrue);
      expect((await adapter.unpinRoom('r1')).isSuccess, isTrue);
      expect((await adapter.hideRoom('r1')).isSuccess, isTrue);
      expect((await adapter.unhideRoom('r1')).isSuccess, isTrue);

      expect(
        (await adapter.updateRoomConfig(
          'r1',
          name: 'Renamed',
          subject: 'New',
        )).isSuccess,
        isTrue,
      );

      expect((await adapter.addMembers('r1', const ['u9'])).isSuccess, isTrue);
      expect((await adapter.removeMember('r1', 'u9')).isSuccess, isTrue);
      expect(
        (await adapter.updateMemberRole('r1', 'u1', RoomRole.admin)).isSuccess,
        isTrue,
      );
      expect((await adapter.leaveRoom('r2')).isSuccess, isTrue);
    });
  });

  group('ChatUiAdapter — message operations', () {
    test('send + edit + reactions + receipts + read succeed', () async {
      expect((await adapter.loadMessages('r1')).isSuccess, isTrue);
      expect((await adapter.loadMoreMessages('r1')).isSuccess, isTrue);

      final sent = await adapter.sendMessage('r1', text: 'hello');
      expect(sent.isSuccess, isTrue);
      final id = sent.dataOrThrow.id;

      expect(
        (await adapter.editMessage('r1', id, text: 'edited')).isSuccess,
        isTrue,
      );

      expect(
        (await adapter.sendReaction(
          'r1',
          messageId: id,
          emoji: '👍',
        )).isSuccess,
        isTrue,
      );
      expect((await adapter.getReactions('r1', id)).isSuccess, isTrue);
      expect(
        (await adapter.deleteReaction(
          'r1',
          messageId: id,
          emoji: '👍',
        )).isSuccess,
        isTrue,
      );

      expect(
        (await adapter.sendTyping('r1', isTyping: true)).isSuccess,
        isTrue,
      );
      expect(
        (await adapter.sendTyping('r1', isTyping: false)).isSuccess,
        isTrue,
      );
      expect(
        (await adapter.sendReceipt(
          'r1',
          id,
          status: ReceiptStatus.read,
        )).isSuccess,
        isTrue,
      );
      expect(
        (await adapter.markAsRead('r1', lastReadMessageId: id)).isSuccess,
        isTrue,
      );
    });

    test('pins + threads + search + receipts succeed', () async {
      final sent = await adapter.sendMessage('r1', text: 'pin me');
      final id = sent.dataOrThrow.id;

      expect((await adapter.pinMessage('r1', id)).isSuccess, isTrue);
      expect((await adapter.loadPins('r1')).isSuccess, isTrue);
      expect((await adapter.unpinMessage('r1', id)).isSuccess, isTrue);

      expect((await adapter.loadThread('r1', id)).isSuccess, isTrue);
      expect(
        (await adapter.sendThreadReply('r1', id, text: 'a reply')).isSuccess,
        isTrue,
      );

      expect((await adapter.searchMessages('pin', 'r1')).isSuccess, isTrue);
      expect((await adapter.loadReceipts('r1')).isSuccess, isTrue);
    });

    test('forward + delete + clear succeed', () async {
      final sent = await adapter.sendMessage('r1', text: 'forward me');
      final id = sent.dataOrThrow.id;

      final forwarded = await adapter.forwardMessage(
        sourceRoomId: 'r1',
        messageId: id,
        targetRoomIds: const ['r2'],
      );
      expect(forwarded, hasLength(1));

      final second = await adapter.sendMessage('r1', text: 'delete me');
      expect(
        (await adapter.deleteMessage('r1', second.dataOrThrow.id)).isSuccess,
        isTrue,
      );

      final third = await adapter.sendMessage('r1', text: 'hide me');
      expect(
        (await adapter.deleteMessageLocally(
          'r1',
          third.dataOrThrow.id,
        )).isSuccess,
        isTrue,
      );

      expect((await adapter.clearChat('r1')).isSuccess, isTrue);
    });

    test('attachment upload completes', () async {
      final result = await adapter.uploadAttachment(
        Uint8List.fromList([1, 2, 3, 4]),
        'image/png',
      );
      // The mock returns a result either way; the point is line coverage.
      expect(result, isNotNull);
    });
  });

  group('ChatUiAdapter — contacts', () {
    test('block + unblock + loadBlocked succeed', () async {
      expect((await adapter.blockContact('u1')).isSuccess, isTrue);
      expect((await adapter.unblockContact('u1')).isSuccess, isTrue);
      expect((await adapter.loadBlockedUsers()).isSuccess, isTrue);
    });
  });
}
