import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The line that gives [MembershipBannerFilter] its value: the filter has to
/// travel from whichever public entry point the consumer used down to
/// `MemberEventHandler`, which is the only place that can act on it. The
/// handler's own tests build it by hand, so a broken wire would leave them
/// green and the hook dead in production.
void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  const room = ChatRoom(
    id: 'r1',
    name: 'Room1',
    audience: RoomAudience.contacts,
    members: ['u1', 'u2'],
  );

  Future<void> drain() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  List<ChatMessage> banners(ChatUiAdapter adapter, String roomId) => adapter
      .getChatController(roomId)
      .messages
      .where((m) => m.isSystem)
      .toList();

  MockChatClient seededClient() {
    final client = MockChatClient(currentUserId: 'u1');
    client.seedRoom(room);
    return client;
  }

  void listRoom(ChatUiAdapter adapter) {
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'Room1'),
    );
  }

  group('ChatUiAdapter hands the filter to the member event handler', () {
    late MockChatClient client;

    setUp(() {
      client = seededClient();
    });

    tearDown(() async {
      await client.dispose();
    });

    test('a vetoed membership event mints no banner', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        membershipBannerFilter: (roomId, eventType) => false,
      )..start();
      listRoom(adapter);
      adapter.getChatController('r1');

      client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'));
      await drain();

      expect(banners(adapter, 'r1'), isEmpty);

      await adapter.dispose();
    });

    test('a membership event the filter allows still mints one', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        membershipBannerFilter: (roomId, eventType) => true,
      )..start();
      listRoom(adapter);
      adapter.getChatController('r1');

      client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'));
      await drain();

      expect(banners(adapter, 'r1').length, 1);

      await adapter.dispose();
    });

    test('with no filter the adapter behaves as it always did', () async {
      final adapter = ChatUiAdapter(client: client, currentUser: currentUser)
        ..start();
      listRoom(adapter);
      adapter.getChatController('r1');

      client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'));
      await drain();

      expect(banners(adapter, 'r1').length, 1);

      await adapter.dispose();
    });

    test('the room and the event type reach the filter, for all three '
        'membership events', () async {
      final asked = <(String, String)>[];
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        membershipBannerFilter: (roomId, eventType) {
          asked.add((roomId, eventType));
          return false;
        },
      )..start();
      listRoom(adapter);
      adapter.getChatController('r1');

      client
        ..emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'))
        ..emitEvent(const UserLeftEvent(roomId: 'r1', userId: 'u2'))
        ..emitEvent(
          const UserRoleChangedEvent(
            roomId: 'r1',
            userId: 'u2',
            role: RoomRole.admin,
          ),
        );
      await drain();

      expect(asked, [
        ('r1', 'user_joined'),
        ('r1', 'user_left'),
        ('r1', 'user_role_changed'),
      ]);

      await adapter.dispose();
    });
  });

  group('the facade hands it down too', () {
    test('NomaChat.fromClient threads the filter to the handler', () async {
      final client = seededClient();
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: currentUser,
        cache: MemoryChatLocalDatasource(),
        membershipBannerFilter: (roomId, eventType) => false,
      );
      await chat.connect();
      listRoom(chat.adapter);
      chat.adapter.getChatController('r1');

      client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'));
      await drain();

      expect(banners(chat.adapter, 'r1'), isEmpty);

      await chat.dispose();
      await client.dispose();
    });

    test('a facade built without one keeps minting banners', () async {
      final client = seededClient();
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: currentUser,
        cache: MemoryChatLocalDatasource(),
      );
      await chat.connect();
      listRoom(chat.adapter);
      chat.adapter.getChatController('r1');

      client.emitEvent(const UserJoinedEvent(roomId: 'r1', userId: 'u2'));
      await drain();

      expect(banners(chat.adapter, 'r1').length, 1);

      await chat.dispose();
      await client.dispose();
    });
  });
}
