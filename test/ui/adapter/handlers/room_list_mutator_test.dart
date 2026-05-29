import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_list_mutator.dart';

void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const alice = ChatUser(id: 'u2', displayName: 'Alice');
  const bob = ChatUser(id: 'u3', displayName: 'Bob');

  late MockChatClient client;
  late RoomListController roomList;
  late Map<String, ChatUser> userDirectory;
  late Map<String, ChatController> chatControllers;
  late List<String> ensuredUsers;
  late List<String> removedControllers;
  late Set<String> blockedUserIds;
  late RoomListMutator mutator;

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    roomList = RoomListController();
    userDirectory = {alice.id: alice, bob.id: bob};
    chatControllers = {};
    ensuredUsers = [];
    removedControllers = [];
    blockedUserIds = <String>{};
    mutator = RoomListMutator(
      roomListController: roomList,
      cache: null,
      client: client,
      l10n: ChatUiLocalizations.en,
      currentUser: () => me,
      findCachedUser: (id) => userDirectory[id],
      ensureUserCached: (id) async {
        ensuredUsers.add(id);
      },
      findChatController: (roomId) => chatControllers[roomId],
      removeChatController: (roomId) {
        removedControllers.add(roomId);
        chatControllers.remove(roomId);
      },
      blockedUserIds: () => blockedUserIds,
      isUserBlocked: (id) => blockedUserIds.contains(id),
      computeEffectiveTitle:
          ({required currentItem, otherMembers = const [], isDmOverride}) {
            if ((isDmOverride ?? false) && otherMembers.isNotEmpty) {
              final name = otherMembers.first.displayName?.trim();
              if (name != null && name.isNotEmpty) return name;
            }
            return null;
          },
      isDisposed: () => false,
    );
  });

  tearDown(() async {
    await client.dispose();
    roomList.dispose();
  });

  group('updateRoomLastMessage', () {
    test('is a no-op when the room is not in the list', () {
      mutator.updateRoomLastMessage(
        'r_missing',
        ChatMessage(
          id: 'm1',
          from: alice.id,
          timestamp: DateTime(2026, 5, 20),
          text: 'hola',
        ),
      );
      expect(roomList.allRooms, isEmpty);
    });

    test('writes preview, sender name and receipt for incoming text', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Team'));
      mutator.updateRoomLastMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: alice.id,
          timestamp: DateTime(2026, 5, 20),
          text: 'hola',
        ),
      );
      final room = roomList.getRoomById('r1');
      expect(room?.lastMessage, 'hola');
      expect(room?.lastMessageUserId, alice.id);
      expect(room?.lastMessageSenderName, 'Alice');
      expect(room?.lastMessageReceipt, isNull);
    });

    test('outgoing messages stamp ReceiptStatus.sent and no sender name', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Team'));
      mutator.updateRoomLastMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: me.id,
          timestamp: DateTime(2026, 5, 20),
          text: 'mine',
        ),
      );
      final room = roomList.getRoomById('r1');
      expect(room?.lastMessageReceipt, ReceiptStatus.sent);
      expect(room?.lastMessageSenderName, isNull);
    });

    test('triggers ensureUserCached when the sender is unknown', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Team'));
      mutator.updateRoomLastMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: 'unknown',
          timestamp: DateTime(2026, 5, 20),
          text: 'hi',
        ),
      );
      expect(ensuredUsers, ['unknown']);
    });

    test('deleted messages render the l10n tombstone preview', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Team'));
      mutator.updateRoomLastMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: alice.id,
          timestamp: DateTime(2026, 5, 20),
          text: 'gone',
          isDeleted: true,
        ),
      );
      final room = roomList.getRoomById('r1');
      expect(room?.lastMessage, ChatUiLocalizations.en.messageDeleted);
      expect(room?.lastMessageIsDeleted, isTrue);
    });
  });

  group('updateRoomListReceipt', () {
    test('updates the receipt only when the message is the last one', () {
      roomList.addRoom(
        RoomListItem(
          id: 'r1',
          name: 'Team',
          lastMessageId: 'm1',
          lastMessageUserId: me.id,
          lastMessageReceipt: ReceiptStatus.sent,
        ),
      );
      mutator.updateRoomListReceipt('r1', 'm1', ReceiptStatus.read);
      expect(
        roomList.getRoomById('r1')?.lastMessageReceipt,
        ReceiptStatus.read,
      );
    });

    test('is a no-op when the messageId does not match the last one', () {
      roomList.addRoom(
        RoomListItem(
          id: 'r1',
          name: 'Team',
          lastMessageId: 'm1',
          lastMessageUserId: me.id,
          lastMessageReceipt: ReceiptStatus.sent,
        ),
      );
      mutator.updateRoomListReceipt('r1', 'm_other', ReceiptStatus.read);
      expect(
        roomList.getRoomById('r1')?.lastMessageReceipt,
        ReceiptStatus.sent,
      );
    });

    test('is a no-op when the last message is from another user', () {
      roomList.addRoom(
        RoomListItem(
          id: 'r1',
          name: 'Team',
          lastMessageId: 'm1',
          lastMessageUserId: alice.id,
        ),
      );
      mutator.updateRoomListReceipt('r1', 'm1', ReceiptStatus.read);
      expect(roomList.getRoomById('r1')?.lastMessageReceipt, isNull);
    });
  });

  group('updateRoomUnread', () {
    test('writes the new unread count', () {
      roomList.addRoom(
        const RoomListItem(id: 'r1', name: 'Team', unreadCount: 3),
      );
      mutator.updateRoomUnread('r1', 0);
      expect(roomList.getRoomById('r1')?.unreadCount, 0);
    });

    test('is a no-op when the room is missing', () {
      mutator.updateRoomUnread('r_missing', 5);
      expect(roomList.allRooms, isEmpty);
    });
  });

  group('refreshLastSenderNamesFor', () {
    test('stamps the sender name when the cache acquires the user', () {
      roomList.addRoom(
        RoomListItem(id: 'r1', name: 'Team', lastMessageUserId: alice.id),
      );
      mutator.refreshLastSenderNamesFor(const [alice]);
      expect(roomList.getRoomById('r1')?.lastMessageSenderName, 'Alice');
    });

    test('ignores messages whose sender is the current user', () {
      roomList.addRoom(
        RoomListItem(id: 'r1', name: 'Team', lastMessageUserId: me.id),
      );
      mutator.refreshLastSenderNamesFor(const [me]);
      expect(roomList.getRoomById('r1')?.lastMessageSenderName, isNull);
    });

    test('is a no-op when the list is empty', () {
      roomList.addRoom(
        RoomListItem(id: 'r1', name: 'Team', lastMessageUserId: alice.id),
      );
      mutator.refreshLastSenderNamesFor(const []);
      expect(roomList.getRoomById('r1')?.lastMessageSenderName, isNull);
    });
  });

  group('refreshDmTitlesForUsers', () {
    test('rewrites effectiveDisplayName for DM rooms whose other matches', () {
      roomList.addRoom(
        const RoomListItem(
          id: 'dm-with-u2',
          otherUserId: 'u2',
          effectiveDisplayName: 'u2',
        ),
      );
      mutator.refreshDmTitlesForUsers(const [alice]);
      expect(roomList.getRoomById('dm-with-u2')?.effectiveDisplayName, 'Alice');
    });

    test('does not touch DM rows whose other is not in the user set', () {
      roomList.addRoom(
        const RoomListItem(
          id: 'dm-with-u3',
          otherUserId: 'u3',
          effectiveDisplayName: 'u3',
        ),
      );
      mutator.refreshDmTitlesForUsers(const [alice]);
      expect(roomList.getRoomById('dm-with-u3')?.effectiveDisplayName, 'u3');
    });
  });

  group('refreshDmAvatarsForUsers', () {
    test('propagates avatar changes to the matching DM rooms', () {
      roomList.addRoom(
        const RoomListItem(
          id: 'dm-with-u2',
          otherUserId: 'u2',
          avatarUrl: null,
        ),
      );
      const updatedAlice = ChatUser(
        id: 'u2',
        displayName: 'Alice',
        avatarUrl: 'https://example/avatar.png',
      );
      mutator.refreshDmAvatarsForUsers(const [updatedAlice]);
      expect(
        roomList.getRoomById('dm-with-u2')?.avatarUrl,
        'https://example/avatar.png',
      );
    });

    test('is a no-op when the avatar is unchanged', () {
      roomList.addRoom(
        const RoomListItem(
          id: 'dm-with-u2',
          otherUserId: 'u2',
          avatarUrl: 'same.png',
        ),
      );
      const sameAlice = ChatUser(
        id: 'u2',
        displayName: 'Alice',
        avatarUrl: 'same.png',
      );
      var notifications = 0;
      void listener() => notifications++;
      roomList.addListener(listener);
      mutator.refreshDmAvatarsForUsers(const [sameAlice]);
      roomList.removeListener(listener);
      expect(notifications, 0);
    });
  });

  group('removeBlockedRooms', () {
    test('drops DM rows whose other was blocked and disposes controllers', () {
      roomList.addRoom(const RoomListItem(id: 'dm-with-u2', otherUserId: 'u2'));
      roomList.addRoom(const RoomListItem(id: 'dm-with-u3', otherUserId: 'u3'));
      blockedUserIds.add('u2');
      mutator.removeBlockedRooms();
      expect(roomList.allRooms.map((r) => r.id), ['dm-with-u3']);
      expect(removedControllers, ['dm-with-u2']);
    });

    test('is a no-op when there are no blocked users', () {
      roomList.addRoom(const RoomListItem(id: 'dm-with-u2', otherUserId: 'u2'));
      mutator.removeBlockedRooms();
      expect(roomList.allRooms, hasLength(1));
      expect(removedControllers, isEmpty);
    });
  });

  group('updateRoomReactionPreview', () {
    test('renders the l10n self-reaction preview when the actor is me', () {
      final controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: alice.id,
            timestamp: DateTime(2026, 5, 20),
            text: 'snippet text',
          ),
        ],
        currentUser: me,
      );
      controller.setRoomId('r1');
      chatControllers['r1'] = controller;
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Team'));

      mutator.updateRoomReactionPreview('r1', 'fire', me.id, 'm1');

      final room = roomList.getRoomById('r1');
      expect(
        room?.lastMessage,
        ChatUiLocalizations.en.reactionPreviewSelf('fire', 'snippet text'),
      );
      expect(room?.lastMessageType, MessageType.reaction);
      expect(room?.lastMessageReactionEmoji, 'fire');
      controller.dispose();
    });
  });
}
