part of 'chat_ui_adapter.dart';

/// Routes a `ChatEvent` to the right adapter helpers. The big switch lives
/// here so the facade only carries a one-line delegate (`_router.handle`),
/// keeping the public adapter focused on lifecycle + public API.
///
/// As a `part of` collaborator the router can read the adapter's private
/// state directly; pulling the methods into a free function or a separate
/// library would force a wide dependency-injection surface for no real win
/// (the router lives and dies with the adapter).
class _ChatEventRouter {
  _ChatEventRouter(this._adapter);

  final ChatUiAdapter _adapter;

  void handle(ChatEvent event) {
    if (_adapter._disposed) return;
    switch (event) {
      case NewMessageEvent(:final message, :final roomId):
        _onNewMessage(message, roomId);
      case MessageUpdatedEvent(:final roomId, :final messageId):
        _adapter._refreshMessage(roomId, messageId);
      case MessageDeletedEvent(:final roomId, :final messageId):
        _onMessageDeleted(roomId, messageId);
      case UserActivityEvent(:final roomId, :final userId, :final activity):
        _onUserActivity(roomId, userId, activity);
      case DmActivityEvent(:final contactId, :final userId, :final activity):
        _onDmActivity(contactId, userId, activity);
      case UnreadUpdatedEvent(:final roomId, :final count):
        _adapter._updateRoomUnread(roomId, count);
      case RoomDeletedEvent(:final roomId):
        _adapter.roomListController.removeRoom(roomId);
        _adapter.removeChatController(roomId);
        _adapter._cache?.deleteRoom(roomId);
      case RoomCreatedEvent(:final roomId):
        // Same rationale as NewMessageEvent above: don't add a ghost
        // placeholder with no metadata. Confirm via detail first.
        _adapter._addRoomFromDetail(roomId);
      case RoomUpdatedEvent(:final roomId):
        _adapter._cache?.deleteRoomDetail(roomId);
        _adapter._enrichRoomFromDetail(roomId);
      case PresenceChangedEvent(:final userId, :final online, :final status):
        _adapter._presence.update(userId, online, status);
      case ReceiptUpdatedEvent(:final roomId, :final messageId, :final status):
        _adapter._chatControllers[roomId]?.updateReceipt(messageId, status);
        _adapter._updateRoomListReceipt(roomId, messageId, status);
      case ReactionAddedEvent(
        :final roomId,
        :final messageId,
        :final userId,
        :final reaction,
      ):
        if (userId != _adapter.currentUser.id) {
          _adapter._refreshReactions(roomId, messageId);
          _adapter._updateRoomReactionPreview(
            roomId,
            reaction,
            userId,
            messageId,
          );
        }
      case ReactionDeletedEvent(:final roomId, :final messageId):
        if (!_adapter._pendingReactionDeletes.contains(messageId)) {
          _adapter._refreshReactions(roomId, messageId);
        }
      case UserJoinedEvent(:final roomId, :final userId):
        _adapter._handleUserJoined(roomId, userId);
        _adapter._addSystemMessage(roomId, 'user_joined', userId);
      case UserLeftEvent(:final roomId, :final userId):
        _adapter._handleUserLeft(roomId, userId);
        _adapter._addSystemMessage(roomId, 'user_left', userId);
      case UserRoleChangedEvent(:final roomId, :final userId):
        _adapter._enrichRoomFromDetail(roomId);
        _adapter._addSystemMessage(roomId, 'user_role_changed', userId);
      case ConnectedEvent():
        _onConnected();
      case DisconnectedEvent():
        _adapter.connectionStateNotifier.value =
            ChatConnectionState.disconnected;
      case ErrorEvent():
        _adapter.connectionStateNotifier.value = ChatConnectionState.error;
        _adapter.onError?.call(event);
      case BroadcastEvent(:final message):
        _adapter.onBroadcast?.call(message);
    }
  }

  void _onNewMessage(ChatMessage message, String roomId) {
    _adapter._chatControllers[roomId]?.addMessage(message);
    _adapter._cache?.saveMessages(roomId, [message]);
    if (_adapter.roomListController.getRoomById(roomId) == null) {
      // Don't add a placeholder RoomListItem(id:) yet. If we do, the UI
      // briefly shows a "ghost" room with the raw roomId as title (no
      // name/custom/avatar). Instead, fetch the detail first and only add
      // the room when we have enough metadata to render it correctly.
      _adapter._addRoomFromDetail(roomId, lastMessage: message);
    } else {
      _adapter._updateRoomLastMessage(roomId, message);
    }
    if (message.from == _adapter.currentUser.id) return;
    final existing = _adapter.roomListController.getRoomById(roomId);
    if (existing != null) {
      if (existing.hidden) {
        _adapter.roomListController.updateRoom(existing.copyWith(hidden: false));
        _adapter.client.rooms.unhide(roomId);
      }
      _adapter._updateRoomUnread(roomId, existing.unreadCount + 1);
    }
    // Fire-and-forget delivery receipt. Best-effort: failure here only
    // means the sender will see the message in `sent` state for longer.
    unawaited(
      _adapter.client.messages
          .sendReceipt(
            roomId,
            message.id,
            status: ReceiptStatus.delivered,
          )
          .catchError(
            (_) => const Failure<void>(
              UnexpectedFailure('delivery receipt failed'),
            ),
          ),
    );
  }

  void _onMessageDeleted(String roomId, String messageId) {
    final controller = _adapter._chatControllers[roomId];
    if (controller != null) {
      final msg = controller.messages
          .where((m) => m.id == messageId)
          .firstOrNull;
      if (msg != null) {
        controller.updateMessage(msg.copyWith(isDeleted: true, text: ''));
      }
    }
    _adapter._cache?.deleteMessage(roomId, messageId);
    final room = _adapter.roomListController.getRoomById(roomId);
    if (room != null && room.lastMessageId == messageId) {
      _adapter.roomListController.updateRoom(
        room.copyWith(
          lastMessage: _adapter.l10n.messageDeleted,
          lastMessageIsDeleted: true,
        ),
      );
      unawaited(
        _adapter.client.rooms.updateCachedRoomPreview(
          roomId,
          lastMessage: _adapter.l10n.messageDeleted,
          lastMessageIsDeleted: true,
        ),
      );
    }
  }

  void _onUserActivity(String roomId, String userId, ChatActivity activity) {
    if (userId == _adapter.currentUser.id) return;
    final isTyping = activity == ChatActivity.startsTyping;
    _adapter._chatControllers[roomId]?.setTyping(userId, isTyping);
    _adapter.roomListController.setRoomTyping(roomId, userId, isTyping);
    if (isTyping && !_adapter._userCache.containsKey(userId)) {
      unawaited(_adapter._ensureUserCached(userId));
    }
  }

  void _onDmActivity(String contactId, String userId, ChatActivity activity) {
    if (userId == _adapter.currentUser.id) return;
    var roomId = _adapter._dmRoomByContact[contactId];
    if (roomId == null) {
      final match = _adapter.roomListController.allRooms
          .where((r) => r.otherUserId == contactId)
          .firstOrNull;
      if (match != null) {
        roomId = match.id;
        _adapter._dmRoomByContact[contactId] = roomId;
      }
    }
    if (roomId == null) return;
    final isTyping = activity == ChatActivity.startsTyping;
    _adapter._chatControllers[roomId]?.setTyping(userId, isTyping);
    _adapter.roomListController.setRoomTyping(roomId, userId, isTyping);
    if (isTyping && !_adapter._userCache.containsKey(userId)) {
      unawaited(_adapter._ensureUserCached(userId));
    }
  }

  void _onConnected() {
    final wasConnected = _adapter.connectionStateNotifier.value ==
        ChatConnectionState.connected;
    _adapter.connectionStateNotifier.value = ChatConnectionState.connected;
    // Refresh the presence cache after a (re)connection so that contact
    // online states reflect the current server snapshot. CHT does not
    // re-emit presence_changed events for state already known before the
    // disconnect, so without this refresh the cache could go stale.
    if (!wasConnected) {
      unawaited(_adapter._presence.bootstrap());
    }
    _adapter.onReconnected?.call();
  }
}
