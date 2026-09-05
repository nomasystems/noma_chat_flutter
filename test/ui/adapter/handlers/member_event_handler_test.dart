import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
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
  late List<String> membersChanged;
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
    membersChanged = [];
    ensuredUsers = [];
    handler = MemberEventHandler(
      client: client,
      chatControllers: registry,
      cache: null,
      roomListController: roomList,
      userCacheService: userCache,
      l10n: () => ChatUiLocalizations.en,
      currentUser: () => me,
      displayNameFor: (userId) {
        if (userId == me.id) return me.displayName ?? '';
        return userCache.find(userId)?.displayName ?? '';
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
      notifyRoomMembersChanged: (roomId) {
        membersChanged.add(roomId);
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
      // The roster-changed signal fires unconditionally, even with no
      // open controller, so a GroupMembersView can refresh.
      expect(membersChanged, ['r1']);
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

    test(
      'waits for the name before composing with a cold user cache',
      () async {
        await handler.addSystemMessage('r1', 'user_joined', alice.id);
        final msg = controller.messages.last;
        expect(msg.text, 'Alice joined');
        expect(msg.text, isNot(contains(alice.id)));
        expect(
          msg.metadata?[SystemMessageMetadataKeys.userLabel],
          alice.displayName,
        );
      },
    );

    test('waits for the actor name of a kick with a cold user cache', () async {
      await handler.addSystemMessage(
        'r1',
        'user_left',
        bob.id,
        actorUserId: alice.id,
      );
      final metadata = controller.messages.last.metadata;
      expect(metadata?[SystemMessageMetadataKeys.userLabel], 'Bob');
      expect(metadata?[SystemMessageMetadataKeys.actorLabel], 'Alice');
    });

    test('still posts the banner when the name never resolves', () async {
      await handler.addSystemMessage('r1', 'user_joined', 'unknown-user');
      final msg = controller.messages.last;
      expect(msg.isSystem, isTrue);
      expect(msg.metadata?[SystemMessageMetadataKeys.userId], 'unknown-user');
      // The sentence names a member, never the id it could not resolve,
      // and the blank label is the sentinel a later paint repairs.
      expect(msg.text, isNot(contains('unknown-user')));
      expect(
        msg.text,
        ChatUiLocalizations.en.userJoined(ChatUiLocalizations.en.member),
      );
      expect(msg.metadata?[SystemMessageMetadataKeys.userLabel], '');
    });

    test('a banner minted unnamed reads the name once it lands', () async {
      await handler.addSystemMessage('r1', 'user_joined', 'unknown-user');

      expect(
        localizedSystemMessageTextFromMetadata(
          controller.messages.last.metadata,
          ChatUiLocalizations.en,
          resolveDisplayName: (id) => id == 'unknown-user' ? 'Carol' : null,
        ),
        'Carol joined',
      );
    });

    test('carries the ingredients that let the banner be re-localized', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_joined', alice.id);
      final metadata = controller.messages.last.metadata;
      expect(metadata?[SystemMessageMetadataKeys.event], 'user_joined');
      expect(metadata?[SystemMessageMetadataKeys.userId], alice.id);
      expect(metadata?[SystemMessageMetadataKeys.userLabel], 'Alice');
      expect(
        localizedSystemMessageTextFromMetadata(
          metadata,
          ChatUiLocalizations.es,
        ),
        'Alice se ha unido',
      );
    });

    test('marks who is the local user on a kick', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_left', me.id, actorUserId: alice.id);
      final metadata = controller.messages.last.metadata;
      expect(metadata?[SystemMessageMetadataKeys.actorUserId], alice.id);
      expect(metadata?[SystemMessageMetadataKeys.actorLabel], 'Alice');
      expect(metadata?[SystemMessageMetadataKeys.userIsSelf], isTrue);
      expect(metadata?[SystemMessageMetadataKeys.actorIsSelf], isNull);
      expect(
        localizedSystemMessageTextFromMetadata(
          metadata,
          ChatUiLocalizations.es,
        ),
        'Alice te ha eliminado',
      );
    });

    test('produces unique system message ids when called repeatedly', () {
      userCache.insert(alice);
      handler.addSystemMessage('r1', 'user_joined', alice.id);
      handler.addSystemMessage('r1', 'user_left', alice.id);
      final ids = controller.messages.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('membershipBannerFilter', () {
    late MemoryChatLocalDatasource cache;
    late ChatController controller;
    late List<List<String>> asked;

    MemberEventHandler handlerWithFilter(
      bool Function(String roomId, String eventType)? filter,
    ) => MemberEventHandler(
      client: client,
      chatControllers: registry,
      cache: cache,
      roomListController: roomList,
      userCacheService: userCache,
      l10n: () => ChatUiLocalizations.en,
      currentUser: () => me,
      displayNameFor: (userId) {
        if (userId == me.id) return me.displayName ?? '';
        return userCache.find(userId)?.displayName ?? '';
      },
      ensureUserCached: (userId) async {
        await userCache.ensureCached(userId);
      },
      addRoomFromDetail: (roomId, {lastMessage}) {
        addedFromDetail.add(roomId);
      },
      removeChatController: registry.remove,
      notifyRoomMembersChanged: membersChanged.add,
      isDisposed: () => false,
      swallowCacheThrow: swallow,
      membershipBannerFilter: filter == null
          ? null
          : (roomId, eventType) {
              asked.add([roomId, eventType]);
              return filter(roomId, eventType);
            },
    );

    setUp(() {
      cache = MemoryChatLocalDatasource();
      controller = ChatController(initialMessages: const [], currentUser: me);
      registry['r1'] = controller;
      userCache.insert(alice);
      asked = [];
    });

    test('a filter that vetoes drops the banner and the cache row', () async {
      final filtered = handlerWithFilter((_, _) => false);

      await filtered.addSystemMessage('r1', 'user_joined', alice.id);

      expect(controller.messages, isEmpty);
      final cached = await cache.getMessages('r1');
      expect(cached.dataOrNull, isEmpty);
    });

    test('the veto covers leaves and role changes too', () async {
      final filtered = handlerWithFilter((_, _) => false);

      await filtered.addSystemMessage('r1', 'user_left', alice.id);
      await filtered.addSystemMessage('r1', 'user_role_changed', alice.id);

      expect(controller.messages, isEmpty);
      expect(asked, [
        ['r1', 'user_left'],
        ['r1', 'user_role_changed'],
      ]);
    });

    test('a filter that allows keeps the banner and caches it', () async {
      final filtered = handlerWithFilter((_, _) => true);

      await filtered.addSystemMessage('r1', 'user_joined', alice.id);

      expect(controller.messages.single.text, 'Alice joined');
      final cached = await cache.getMessages('r1');
      expect(cached.dataOrNull?.single.isSystem, isTrue);
    });

    test('the decision is taken per room and per event', () async {
      final filtered = handlerWithFilter(
        (roomId, eventType) => roomId == 'r1' && eventType == 'user_joined',
      );

      await filtered.addSystemMessage('r1', 'user_joined', alice.id);
      await filtered.addSystemMessage('r1', 'user_left', alice.id);

      expect(controller.messages.map((m) => m.text), ['Alice joined']);
    });

    test('no filter keeps the banner, as before the hook existed', () async {
      final plain = handlerWithFilter(null);

      await plain.addSystemMessage('r1', 'user_joined', alice.id);

      expect(controller.messages.single.text, 'Alice joined');
      expect(asked, isEmpty);
    });

    test('a vetoed banner still registers an unknown room', () async {
      final filtered = handlerWithFilter((_, _) => false);

      await filtered.addSystemMessage('r2', 'user_joined', alice.id);

      expect(addedFromDetail, ['r2']);
    });

    test('a vetoed banner leaves a known room alone', () async {
      roomList.addRoom(const RoomListItem(id: 'r1', name: 'Room'));
      final filtered = handlerWithFilter((_, _) => false);

      await filtered.addSystemMessage('r1', 'user_joined', alice.id);

      expect(addedFromDetail, isEmpty);
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
