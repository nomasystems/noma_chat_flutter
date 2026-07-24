import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Wraps a [ChatClient] but routes `messages.getRoomReceipts` to a
/// canned receipts list. The rest delegates to the mock unchanged.
class _ReceiptsClient implements ChatClient {
  _ReceiptsClient(this._delegate, List<ReadReceipt> receipts)
    : _messages = _ReceiptsMessagesApi(_delegate.messages, receipts);

  final ChatClient _delegate;
  final _ReceiptsMessagesApi _messages;

  @override
  ChatMessagesApi get messages => _messages;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _delegate.rooms;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;
  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _delegate.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

class _ReceiptsMessagesApi implements ChatMessagesApi {
  _ReceiptsMessagesApi(this._delegate, this.receipts);
  final ChatMessagesApi _delegate;
  final List<ReadReceipt> receipts;

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) async =>
      ChatSuccess(ChatPaginatedResponse(items: receipts, hasMore: false));

  // Methods exercised by `messages.load` delegate explicitly; the rest
  // of the contract is satisfied by noSuchMethod (unused in this test).
  // getClearedAt must be explicit (not via noSuchMethod): the wrapped
  // MockMessagesApi declares it concretely, so it cannot be reached
  // through noSuchMethod forwarding.
  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      _delegate.getClearedAt(roomId);

  @override
  Future<ChatResult<void>> setLocalClearedAt(
    String roomId,
    DateTime clearedAt,
  ) => _delegate.setLocalClearedAt(roomId, clearedAt);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) => _delegate.list(
    roomId,
    pagination: pagination,
    unreadOnly: unreadOnly,
    cachePolicy: cachePolicy,
  );

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => _delegate.markRoomAsRead(roomId, lastReadMessageId: lastReadMessageId);

  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) => _delegate.markRoomAsDelivered(
    roomId,
    lastDeliveredMessageId: lastDeliveredMessageId,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      (_delegate as dynamic).noSuchMethod(invocation);
}

void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  test('load() rehydrates delivered cursors and reads by messageId order, '
      'not by timestamp', () async {
    final mockClient = MockChatClient(currentUserId: 'u1');
    addTearDown(mockClient.dispose);
    mockClient.seedRoom(
      const ChatRoom(
        id: 'r1',
        name: 'Room1',
        audience: RoomAudience.contacts,
        members: ['u1', 'u2'],
      ),
    );
    for (var i = 1; i <= 3; i++) {
      mockClient.addMessage(
        'r1',
        ChatMessage(
          id: 'm$i',
          from: 'u1',
          timestamp: t0.add(Duration(minutes: i)),
          text: 'm$i',
        ),
      );
    }

    // u2's row: read cursor on m1, delivered cursor on m2. The
    // lastReadAt timestamp is LATER than every message — the legacy
    // timestamp comparison would over-mark all three as read; the
    // messageId-order semantics must mark only m1.
    final client = _ReceiptsClient(mockClient, [
      ReadReceipt(
        userId: 'u2',
        lastReadMessageId: 'm1',
        lastReadAt: t0.add(const Duration(hours: 1)),
        lastDeliveredMessageId: 'm2',
        lastDeliveredAt: t0.add(const Duration(hours: 1)),
      ),
    ]);
    final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    addTearDown(adapter.dispose);
    adapter.start();

    final controller = adapter.getChatController(
      'r1',
      otherUsers: const [ChatUser(id: 'u2', displayName: 'Bob')],
    );
    final result = await adapter.messages.load('r1');
    expect(result.isSuccess, isTrue);
    // The rehydration runs fire-and-forget after load resolves.
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.receiptStatuses['m1'], ReceiptStatus.read);
    expect(controller.receiptStatuses['m2'], ReceiptStatus.delivered);
    expect(controller.receiptStatuses['m3'], isNull);
  });
}
