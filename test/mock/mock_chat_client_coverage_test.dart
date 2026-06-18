import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Exercises the [MockChatClient] surface that the adapter/widget suites do
/// not reach: lifecycle no-ops, seed helpers, the managed-user sub-API, the
/// starred-message preview resolver, and the attachment sub-API. The mock is
/// shipped in `lib/src/mock` for consumers building tests against the SDK, so
/// its behaviour is part of the package contract.
void main() {
  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
  });

  tearDown(() async {
    await client.dispose();
  });

  group('lifecycle no-ops', () {
    test('token rotation, refresh and cancellation complete quietly', () async {
      await client.notifyTokenRotated();
      await client.refresh();
      await client.refreshRoom('r1');
      client.cancelPendingRequests();
      client.cancelPendingRequests('custom reason');
      client.onOfflineMessageSent = (_, _, _) {};
    });
  });

  group('seed helpers', () {
    test('seedRoomMeta drives unread badge, pin and mute flags', () async {
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'Team', members: ['u1', 'u2', 'u3']),
      );
      client.seedRoomMeta('r1', unread: 5, pinned: true, muted: true);

      final rooms = (await client.rooms.getUserRooms()).dataOrThrow;
      expect(rooms.rooms.single.unreadMessages, 5);

      final detail = (await client.rooms.get('r1')).dataOrThrow;
      expect(detail.muted, isTrue);
      expect(detail.pinned, isTrue);
    });

    test('addMessage replaces an existing message id in place', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['u1']));
      final ts = DateTime(2026, 1, 1);
      client.addMessage(
        'r1',
        ChatMessage(id: 'm1', from: 'u1', timestamp: ts, text: 'first'),
      );
      client.addMessage(
        'r1',
        ChatMessage(id: 'm1', from: 'u1', timestamp: ts, text: 'edited'),
      );

      final listed = (await client.messages.list('r1')).dataOrThrow.items;
      expect(listed.where((m) => m.id == 'm1'), hasLength(1));
      expect(listed.single.text, 'edited');
    });
  });

  group('users sub-API edge methods', () {
    test('create registers a new profile', () async {
      final created = (await client.users.create(
        displayName: 'Created',
        avatarUrl: 'https://x/a.png',
        bio: 'hi',
        email: 'c@x.io',
        custom: const {'k': 'v'},
      )).dataOrThrow;
      expect(created.displayName, 'Created');
      expect((await client.users.get(created.id)).dataOrThrow.bio, 'hi');
    });

    test('deleteCurrentUser removes the signed-in profile', () async {
      final result = await client.users.deleteCurrentUser();
      expect(result.isSuccess, isTrue);
      expect((await client.users.get('u1')).isFailure, isTrue);
    });

    test('managed-user methods return their canned shapes', () async {
      expect(
        (await client.users.searchManaged(externalId: 'e')).isFailure,
        isTrue,
      );
      expect(
        (await client.users.createManaged(externalIds: ['e'])).dataOrThrow,
        isEmpty,
      );
      final page = (await client.users.getManagedByParent('p')).dataOrThrow;
      expect(page.items, isEmpty);
      expect(
        (await client.users.deleteManaged('m', fromUserId: 'u1')).isSuccess,
        isTrue,
      );
      expect((await client.users.getManagedConfig('m')).isSuccess, isTrue);
      expect(
        (await client.users.updateManagedConfig(
          'm',
          configuration: const UserConfiguration(),
        )).isSuccess,
        isTrue,
      );
    });
  });

  group('rooms + members edge methods', () {
    test('discover matches a seeded room by name', () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Team Alpha'));
      final found = (await client.rooms.discover('team')).dataOrThrow;
      expect(found.items.single.id, 'r1');
    });

    test('joinWithToken adds the current user to the room', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['u2']));
      final result = await client.members.joinWithToken('r1', token: 't');
      expect(result.isSuccess, isTrue);
      final members = (await client.members.list('r1')).dataOrThrow.items;
      expect(members.map((m) => m.userId), contains('u1'));
    });
  });

  group('messages edge methods', () {
    test('send with a reaction type emits a reactionAdded event', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['u1']));
      final events = <ChatEvent>[];
      final sub = client.events.listen(events.add);
      addTearDown(sub.cancel);

      await client.messages.send(
        'r1',
        messageType: MessageType.reaction,
        reaction: '👍',
        referencedMessageId: 'm1',
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<ReactionAddedEvent>(), isNotEmpty);
    });

    test('sendViaWs delegates to send', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['u1']));
      final sent = (await client.messages.sendViaWs(
        'r1',
        text: 'hi',
      )).dataOrThrow;
      expect(sent.text, 'hi');
    });

    test('markRoomAsDelivered records and resets the call log', () async {
      await client.messages.markRoomAsDelivered(
        'r1',
        lastDeliveredMessageId: 'm1',
      );
      expect(client.messages.markRoomAsDeliveredCalls, hasLength(1));
      client.messages.resetMarkRoomAsDeliveredCalls();
      expect(client.messages.markRoomAsDeliveredCalls, isEmpty);
    });

    test('starred-message preview resolves every message type', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['u1']));
      final ts = DateTime(2026, 1, 1);
      ChatMessage msg(
        String id, {
        String? text,
        MessageType type = MessageType.regular,
        String? fileName,
        bool deleted = false,
      }) => ChatMessage(
        id: id,
        from: 'u1',
        timestamp: ts,
        text: text,
        messageType: type,
        fileName: fileName,
        isDeleted: deleted,
      );

      client.addMessage('r1', msg('m_txt', text: 'hello'));
      client.addMessage('r1', msg('m_del', text: 'x', deleted: true));
      client.addMessage('r1', msg('m_audio', type: MessageType.audio));
      client.addMessage('r1', msg('m_loc', type: MessageType.location));
      client.addMessage(
        'r1',
        msg('m_att', type: MessageType.attachment, fileName: 'doc.pdf'),
      );
      client.addMessage('r1', msg('m_att2', type: MessageType.attachment));
      client.addMessage('r1', msg('m_fwd', type: MessageType.forward));
      client.addMessage('r1', msg('m_reg', type: MessageType.regular));

      for (final id in [
        'm_txt',
        'm_del',
        'm_audio',
        'm_loc',
        'm_att',
        'm_att2',
        'm_fwd',
        'm_reg',
      ]) {
        await client.messages.starMessage('r1', id);
      }
      // A starred id whose message is not stored → null preview branch.
      await client.messages.starMessage('r1', 'ghost');
      // A starred id pointing at a room with no message store at all.
      await client.messages.starMessage('r-unseeded', 'orphan');

      final starred = (await client.messages.listStarred()).dataOrThrow;
      expect(starred.items, isNotEmpty);
      final byId = {for (final s in starred.items) s.messageId: s.preview};
      expect(byId['m_txt'], 'hello');
      expect(byId['m_del'], 'This message was deleted');
      expect(byId['m_audio'], contains('Voice'));
      expect(byId['m_loc'], contains('Location'));
      expect(byId['m_att'], contains('doc.pdf'));
      expect(byId['m_att2'], contains('Attachment'));
      expect(byId['m_fwd'], 'Forwarded');
      expect(byId['m_reg'], contains('Attachment'));

      await client.messages.unstarMessage('r1', 'm_txt');
      final afterUnstar = (await client.messages.listStarred()).dataOrThrow;
      expect(
        afterUnstar.items.map((s) => s.messageId),
        isNot(contains('m_txt')),
      );
    });
  });

  group('contacts + attachments edge methods', () {
    test('getConversationMessages returns an empty page', () async {
      final page = (await client.contacts.getConversationMessages(
        'c1',
      )).dataOrThrow;
      expect(page.items, isEmpty);
    });

    test(
      'attachment sub-API returns canned upload/url/download shapes',
      () async {
        final upload = (await client.attachments.upload(
          Uint8List(0),
          'image/png',
        )).dataOrThrow;
        expect(upload.attachmentId, isNotEmpty);

        final signed = (await client.attachments.signedUrl(
          'a1',
          roomId: 'r1',
        )).dataOrThrow;
        expect(signed.url, contains('a1'));

        expect(
          (await client.attachments.download('a1')).dataOrThrow,
          isA<Uint8List>(),
        );
        expect(
          (await client.attachments.downloadFromUrl('https://x/a')).dataOrThrow,
          isA<Uint8List>(),
        );
        expect(
          (await client.attachments.listInRoom('r1')).dataOrThrow.items,
          isEmpty,
        );
        expect(
          (await client.attachments.deleteInRoom('r1', 'm1')).isSuccess,
          isTrue,
        );
      },
    );
  });
}
