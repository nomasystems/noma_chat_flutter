import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/adapter/handlers/member_event_handler.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const alice = ChatUser(id: 'u2', displayName: 'Alice');
  const bob = ChatUser(id: 'u3', displayName: 'Bob');

  late MockChatClient client;
  late ChatControllerRegistry registry;
  late RoomListController roomList;
  late UserCacheService userCache;
  late List<String> addedFromDetail;
  late List<String> removedControllers;
  late List<String> ensuredUsers;
  late MemberEventHandler handler;

  ChatResult<void> swallow(Object _) =>
      const ChatFailureResult<void>(UnexpectedFailure('cache mutator threw'));

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
    client.seedUser(alice);
    client.seedUser(bob);
    registry = ChatControllerRegistry();
    roomList = RoomListController();
    userCache = UserCacheService(api: client.users, isDisposed: () => false);
    addedFromDetail = [];
    removedControllers = [];
    ensuredUsers = [];
    handler = MemberEventHandler(
      client: client,
      chatControllers: registry,
      cache: null,
      roomListController: roomList,
      userCacheService: userCache,
      l10n: ChatUiLocalizations.en,
      currentUser: () => me,
      displayNameFor: (userId) {
        if (userId == me.id) return me.displayName ?? userId;
        return userCache.find(userId)?.displayName ?? userId;
      },
      ensureUserCached: (userId) async {
        ensuredUsers.add(userId);
        final fetched = await userCache.ensureCached(userId);
        if (fetched != null) {
          /* no-op */
        }
      },
      addRoomFromDetail: (roomId, {lastMessage}) {
        addedFromDetail.add(roomId);
      },
      removeChatController: (roomId) {
        removedControllers.add(roomId);
        registry.remove(roomId);
      },
      isDisposed: () => false,
      swallowCacheThrow: swallow,
    );
  });

  tearDown(() async {
    await client.dispose();
    roomList.dispose();
  });

  group('handleUserJoined', () {
    test('self-join with unknown room triggers addRoomFromDetail', () {
      handler.handleUserJoined('r1', me.id);
      expect(addedFromDetail, ['r1']);
    });

    test('self-join with known room is a no-op', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Existing'));
      handler.handleUserJoined('r1', me.id);
      expect(addedFromDetail, isEmpty);
    });

    test('foreign join without active controller is a no-op', () {
      handler.handleUserJoined('r1', alice.id);
      expect(addedFromDetail, isEmpty);
    });

    test(
      'foreign join with active controller fetches user and appends',
      () async {
        final controller = ChatController(
          initialMessages: const [],
          currentUser: me,
          otherUsers: const [],
        );
        registry['r1'] = controller;

        handler.handleUserJoined('r1', alice.id);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(controller.otherUsers.map((u) => u.id), contains(alice.id));
      },
    );
  });

  group('handleUserLeft', () {
    test('self-leave with kick flips isParticipating to false', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Room'));
      handler.handleUserLeft('r1', me.id, actorUserId: alice.id);
      final room = roomList.getRoomById('r1');
      expect(room?.isParticipating, isFalse);
    });

    test('self-leave without actor leaves room state untouched', () {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Room'));
      handler.handleUserLeft('r1', me.id);
      final room = roomList.getRoomById('r1');
      expect(room?.isParticipating, isTrue);
    });

    test('foreign leave drops user from controller otherUsers', () {
      final controller = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [alice, bob],
      );
      registry['r1'] = controller;

      handler.handleUserLeft('r1', alice.id);
      expect(controller.otherUsers.map((u) => u.id), [bob.id]);
    });

    test('foreign leave without active controller is a no-op', () {
      expect(() => handler.handleUserLeft('r1', alice.id), returnsNormally);
    });
  });

  group('handleUserRejoined', () {
    test('self-rejoin flips isParticipating back to true', () {
      roomList.addRoom(
        const RoomListItem(id: 'r1', name: 'Room', isParticipating: false),
      );
      handler.handleUserRejoined('r1', me.id);
      final room = roomList.getRoomById('r1');
      expect(room?.isParticipating, isTrue);
    });

    test('foreign rejoin is a no-op for room state', () {
      roomList.addRoom(
        const RoomListItem(id: 'r1', name: 'Room', isParticipating: false),
      );
      handler.handleUserRejoined('r1', alice.id);
      final room = roomList.getRoomById('r1');
      expect(room?.isParticipating, isFalse);
    });
  });

  group('addSystemMessage', () {
    late ChatController controller;

    setUp(() {
      controller = ChatController(initialMessages: const [], currentUser: me);
      registry['r1'] = controller;
    });

    test('user_joined posts the i18n joined banner', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_joined', alice.id);
      final msg = controller.messages.last;
      expect(msg.isSystem, isTrue);
      expect(msg.text, contains('Alice'));
      expect(msg.text, contains('joined'));
    });

    test('user_left without actor posts the leave banner', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_left', alice.id);
      final msg = controller.messages.last;
      expect(msg.text, contains('Alice'));
      expect(msg.text, contains('left'));
    });

    test('user_left kick targeting me renders "removed you"', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_left', me.id, actorUserId: alice.id);
      final msg = controller.messages.last;
      expect(msg.text, contains('Alice'));
      expect(msg.text, contains('you'));
    });

    test('user_left kick performed by me renders "You removed Bob"', () {
      userCache.insert(bob);
      handler.addSystemMessage('r1', 'user_left', bob.id, actorUserId: me.id);
      final msg = controller.messages.last;
      expect(msg.text, contains('You'));
      expect(msg.text, contains('Bob'));
    });

    test('addSystemMessage on unknown room is a no-op', () {
      handler.addSystemMessage('unknown-room', 'user_joined', alice.id);
      // No controller registered for "unknown-room" — nothing to assert
      // beyond "doesn't throw". `r1` should also stay empty.
      expect(controller.messages, isEmpty);
    });

    test('triggers ensureUserCached for unknown user', () {
      handler.addSystemMessage('r1', 'user_joined', alice.id);
      expect(ensuredUsers, contains(alice.id));
    });

    test('produces unique system message ids when called repeatedly', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_joined', alice.id);
      handler.addSystemMessage('r1', 'user_left', alice.id);
      final ids = controller.messages.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('deleteKickedChat', () {
    test(
      'removes the room from the list and disposes its controller',
      () async {
        roomList.addRoom(const RoomListItem(id: 'r1', name: 'Room'));
        final controller = ChatController(
          initialMessages: const [],
          currentUser: me,
        );
        registry['r1'] = controller;

        await handler.deleteKickedChat('r1');

        expect(roomList.getRoomById('r1'), isNull);
        expect(removedControllers, contains('r1'));
      },
    );

    test('is safe to call without a registered controller', () async {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Room'));
      await handler.deleteKickedChat('r1');
      expect(roomList.getRoomById('r1'), isNull);
    });
  });
}
