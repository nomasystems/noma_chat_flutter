import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Scripts the two reads the room list is built from — the listing
/// (`getUserRooms`) and the per-room detail (`get`) — so a write policy can
/// be planted on either of them independently.
class _PolicyRoomsApi implements ChatRoomsApi {
  _PolicyRoomsApi(this._delegate);
  final ChatRoomsApi _delegate;

  /// Rows the listing answers with, exactly as the mapper would build them.
  List<UnreadRoom> listing = const [];

  /// Policy the detail read answers with; `null` makes the read fail, which
  /// is how a room list survives an offline pass.
  RoomWritePolicy? detailPolicy = RoomWritePolicy.members;
  RoomRole detailRole = RoomRole.member;

  /// Whether the detail read reports the user as moderation-muted.
  bool detailSelfMuted = false;

  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async => ChatSuccess(UserRooms(rooms: listing));

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) async {
    final policy = detailPolicy;
    if (policy == null) {
      return const ChatFailureResult(NetworkFailure('offline'));
    }
    return ChatSuccess(
      RoomDetail(
        id: roomId,
        name: 'Announcements',
        type: RoomType.group,
        memberCount: 4,
        userRole: detailRole,
        config: RoomConfig(writePolicy: policy),
        selfMuted: detailSelfMuted,
      ),
    );
  }

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() =>
      _delegate.getDeletedRoomIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PolicyClient implements ChatClient {
  _PolicyClient(this._delegate) : rooms = _PolicyRoomsApi(_delegate.rooms);

  final MockChatClient _delegate;

  @override
  final _PolicyRoomsApi rooms;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;
  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;
  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient mock;
  late _PolicyClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    client = _PolicyClient(mock);
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  UnreadRoom row(
    String id, {
    RoomWritePolicy writePolicy = RoomWritePolicy.members,
    bool selfMuted = false,
  }) => UnreadRoom(
    roomId: id,
    unreadMessages: 0,
    writePolicy: writePolicy,
    selfMuted: selfMuted,
  );

  test('the detail read is what the row believes when it lands', () async {
    client.rooms.listing = [row('r1')];
    client.rooms.detailPolicy = RoomWritePolicy.ownerOnly;

    await adapter.loadRooms(forceNetwork: true);

    final item = adapter.roomListController.getRoomById('r1');
    expect(item, isNotNull);
    expect(item!.writePolicy, RoomWritePolicy.ownerOnly);
    expect(item.isReadOnly, isTrue);
    expect(item.readOnlyReason, ReadOnlyReason.ownerOnly);
  });

  test(
    'the listing carries the policy when the detail read never lands',
    () async {
      client.rooms.listing = [
        row('r1', writePolicy: RoomWritePolicy.ownerOnly),
      ];
      client.rooms.detailPolicy = null;

      await adapter.loadRooms(forceNetwork: true);

      final item = adapter.roomListController.getRoomById('r1');
      expect(item, isNotNull);
      expect(item!.writePolicy, RoomWritePolicy.ownerOnly);
      expect(item.isReadOnly, isTrue);
    },
  );

  test('a members-only listing leaves the room writable', () async {
    client.rooms.listing = [row('r1')];
    client.rooms.detailPolicy = null;

    await adapter.loadRooms(forceNetwork: true);

    final item = adapter.roomListController.getRoomById('r1');
    expect(item!.writePolicy, RoomWritePolicy.members);
    expect(item.isReadOnly, isFalse);
    expect(item.readOnlyReason, isNull);
  });

  test('the owner of an owner-only room still writes', () async {
    client.rooms.listing = [row('r1')];
    client.rooms.detailPolicy = RoomWritePolicy.ownerOnly;
    client.rooms.detailRole = RoomRole.owner;

    await adapter.loadRooms(forceNetwork: true);

    final item = adapter.roomListController.getRoomById('r1');
    expect(item!.writePolicy, RoomWritePolicy.ownerOnly);
    expect(item.isReadOnly, isFalse);
  });

  test(
    'the listing carries the moderation mute when no detail lands',
    () async {
      client.rooms.listing = [row('r1', selfMuted: true)];
      client.rooms.detailPolicy = null;

      await adapter.loadRooms(forceNetwork: true);

      final item = adapter.roomListController.getRoomById('r1');
      expect(item, isNotNull);
      expect(item!.selfMuted, isTrue);
      expect(item.isReadOnly, isTrue);
      expect(item.readOnlyReason, ReadOnlyReason.selfMuted);
    },
  );

  test('the detail lifts a mute the listing still reported', () async {
    client.rooms.listing = [row('r1', selfMuted: true)];
    client.rooms.detailPolicy = RoomWritePolicy.members;
    client.rooms.detailSelfMuted = false;

    await adapter.loadRooms(forceNetwork: true);

    final item = adapter.roomListController.getRoomById('r1');
    expect(item!.selfMuted, isFalse);
    expect(item.isReadOnly, isFalse);
    expect(item.readOnlyReason, isNull);
  });

  test('a room_updated event closes an open room in place', () async {
    client.rooms.listing = [row('r1')];
    client.rooms.detailPolicy = RoomWritePolicy.members;

    await adapter.loadRooms(forceNetwork: true);
    expect(
      adapter.roomListController.getRoomById('r1')!.writePolicy,
      RoomWritePolicy.members,
    );

    client.rooms.detailPolicy = RoomWritePolicy.ownerOnly;
    mock.emitEvent(const RoomUpdatedEvent(roomId: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final item = adapter.roomListController.getRoomById('r1');
    expect(item!.writePolicy, RoomWritePolicy.ownerOnly);
    expect(item.isReadOnly, isTrue);
  });

  test('a room_updated event reopens a room the owner unlocked', () async {
    client.rooms.listing = [row('r1', writePolicy: RoomWritePolicy.ownerOnly)];
    client.rooms.detailPolicy = RoomWritePolicy.ownerOnly;

    await adapter.loadRooms(forceNetwork: true);
    expect(adapter.roomListController.getRoomById('r1')!.isReadOnly, isTrue);

    client.rooms.detailPolicy = RoomWritePolicy.members;
    mock.emitEvent(const RoomUpdatedEvent(roomId: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final item = adapter.roomListController.getRoomById('r1');
    expect(item!.writePolicy, RoomWritePolicy.members);
    expect(item.isReadOnly, isFalse);
  });
}
