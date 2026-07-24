import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../events/chat_event.dart';
import '../../../models/message.dart';
import '../../../models/user.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../services/chat_controller_registry.dart';
import '../services/dm_contact_registry.dart';
import '../services/pending_reactions_registry.dart';
import '../services/user_cache_service.dart';
import '../services/presence_registry.dart';

/// Bundle of dependencies the [ChatEventRouter] needs. Grouped into
/// a struct so the constructor isn't a 30-parameter list. The
/// adapter constructs one and hands it to the router.
class ChatEventRouterDeps {
  const ChatEventRouterDeps({
    required this.client,
    required this.controllers,
    required this.roomList,
    required this.dmContacts,
    required this.userCacheService,
    required this.pendingReactions,
    required this.presence,
    required this.cache,
    required this.connectionStateNotifier,
    required this.l10n,
    required this.autoMarkAsRead,
    required this.autoConfirmDelivery,
    required this.currentUser,
    required this.setCurrentUser,
    required this.activeRoomId,
    required this.isDisposed,
    required this.findCachedUser,
    required this.cacheUsersFn,
    required this.ensureUserCachedFn,
    required this.markAsReadFn,
    required this.confirmDeliveredFn,
    required this.refreshMessageFn,
    required this.refreshReactionsFn,
    required this.handleUserJoinedFn,
    required this.handleUserLeftFn,
    required this.handleUserRejoinedFn,
    required this.addSystemMessageFn,
    required this.addRoomFromDetailFn,
    required this.enrichRoomFromDetailFn,
    required this.updateRoomLastMessage,
    required this.updateRoomListReceipt,
    required this.updateRoomReactionPreview,
    required this.updateRoomUnread,
    required this.removeChatController,
    required this.onAdminMessage,
    required this.onBroadcast,
    required this.onError,
    required this.onReconnected,
    required this.onRoomRemoved,
    required this.triggerResync,
  });

  final ChatClient client;
  final ChatControllerRegistry controllers;
  final RoomListController roomList;
  final DmContactRegistry dmContacts;
  final UserCacheService userCacheService;
  final PendingReactionsRegistry pendingReactions;
  final PresenceRegistry presence;
  final ChatLocalDatasource? cache;
  final ValueNotifier<ChatConnectionState> connectionStateNotifier;
  final ChatUiLocalizations l10n;
  final bool autoMarkAsRead;
  final bool autoConfirmDelivery;
  final ChatUser Function() currentUser;
  final void Function(ChatUser user) setCurrentUser;
  final String? Function() activeRoomId;
  final bool Function() isDisposed;
  final ChatUser? Function(String userId) findCachedUser;
  final void Function(Iterable<ChatUser> users) cacheUsersFn;
  final Future<void> Function(String userId) ensureUserCachedFn;
  final Future<ChatResult<void>> Function(
    String roomId, {
    String? lastReadMessageId,
  })
  markAsReadFn;
  final Future<ChatResult<void>> Function(String roomId, String messageId)
  confirmDeliveredFn;
  final void Function(String roomId, String messageId) refreshMessageFn;
  final void Function(String roomId, String messageId) refreshReactionsFn;
  final void Function(String roomId, String userId) handleUserJoinedFn;
  final void Function(String roomId, String userId, {String? actorUserId})
  handleUserLeftFn;
  final void Function(String roomId, String userId) handleUserRejoinedFn;
  final void Function(
    String roomId,
    String systemType,
    String userId, {
    String? actorUserId,
  })
  addSystemMessageFn;
  final void Function(String roomId, {ChatMessage? lastMessage})
  addRoomFromDetailFn;
  final void Function(String roomId) enrichRoomFromDetailFn;
  final void Function(String roomId, ChatMessage message) updateRoomLastMessage;
  final void Function(String roomId, String messageId, ReceiptStatus status)
  updateRoomListReceipt;
  final void Function(
    String roomId,
    String reaction,
    String userId,
    String messageId,
  )
  updateRoomReactionPreview;
  final void Function(String roomId, int count) updateRoomUnread;
  final void Function(String roomId) removeChatController;

  /// Callbacks are read via getter so the adapter can set them
  /// post-construction (`adapter.onBroadcast = ...`) and the router
  /// always picks up the latest value. Direct field capture would
  /// snapshot `null` at construction time.
  final void Function(ChatMessage message, String roomId)? Function()
  onAdminMessage;
  final void Function(String message)? Function() onBroadcast;
  final void Function(ChatEvent event)? Function() onError;
  final void Function()? Function() onReconnected;
  final void Function(String roomId, String? reason, String? adminReason)?
  Function()
  onRoomRemoved;

  /// Fired on every fresh reconnect (state transitions into `connected`
  /// from a non-connected state) — wired by the adapter to its
  /// `resync()`, gated by `enableReconnectResync` and debounced there.
  /// Sits alongside the existing presence bootstrap in [ChatEventRouter
  /// ._onConnected] rather than as a second reconnect-detection point, so
  /// there's exactly one place that decides "we just reconnected".
  final void Function() triggerResync;
}

/// Routes a `ChatEvent` to the right handlers / services / callbacks.
///
/// Dependencies arrive via [ChatEventRouterDeps] so the adapter is
/// the only place that knows how everything wires together — and the
/// router can be unit-tested per event type with a mock deps struct.
class ChatEventRouter {
  ChatEventRouter(this._deps);

  final ChatEventRouterDeps _deps;

  /// Tracks "was the last-known state `connected`?" from the `ChatEvent`
  /// stream ALONE — deliberately independent of `_connectionStateNotifier`,
  /// which is ALSO fed by `client.stateChanges` (see `ChatUiAdapter
  /// ._handleStateChange`). A transport's `connected` state transition is
  /// always emitted on `stateChanges` before the matching `ConnectedEvent`
  /// on `events` (mirrored by every transport: `WsTransport._dispatch`'s
  /// `auth_ok` case, `SseTransport._doConnect`, `MockChatClient.connect`),
  /// so reading `_connectionStateNotifier.value` from inside `_onConnected`
  /// would see `connected` already latched in by the state-stream listener
  /// and treat EVERY reconnect as "already connected" — permanently
  /// disabling the presence bootstrap + resync below. Flipped in
  /// [_onConnected] and by the `DisconnectedEvent`/`ErrorEvent` cases in
  /// [handle], never by anything state-stream-derived.
  bool _lastKnownConnectedFromEvents = false;

  // -- Delegated accessors so the migrated body still compiles --
  ChatClient get _client => _deps.client;
  ChatControllerRegistry get _controllers => _deps.controllers;
  RoomListController get _roomList => _deps.roomList;
  DmContactRegistry get _dmContacts => _deps.dmContacts;
  UserCacheService get _userCacheService => _deps.userCacheService;
  PendingReactionsRegistry get _pendingReactions => _deps.pendingReactions;
  PresenceRegistry get _presence => _deps.presence;
  ChatLocalDatasource? get _cache => _deps.cache;
  ValueNotifier<ChatConnectionState> get _connectionStateNotifier =>
      _deps.connectionStateNotifier;
  ChatUiLocalizations get _l10n => _deps.l10n;
  bool get _autoMarkAsRead => _deps.autoMarkAsRead;
  bool get _autoConfirmDelivery => _deps.autoConfirmDelivery;
  bool _isDisposed() => _deps.isDisposed();
  ChatUser _currentUser() => _deps.currentUser();
  void _setCurrentUser(ChatUser user) => _deps.setCurrentUser(user);
  String? _activeRoomId() => _deps.activeRoomId();
  ChatUser? _findCachedUser(String userId) => _deps.findCachedUser(userId);
  void _cacheUsersFn(Iterable<ChatUser> users) => _deps.cacheUsersFn(users);
  Future<void> _ensureUserCachedFn(String userId) =>
      _deps.ensureUserCachedFn(userId);
  Future<ChatResult<void>> _markAsReadFn(
    String roomId, {
    String? lastReadMessageId,
  }) => _deps.markAsReadFn(roomId, lastReadMessageId: lastReadMessageId);
  Future<ChatResult<void>> _confirmDeliveredFn(
    String roomId,
    String messageId,
  ) => _deps.confirmDeliveredFn(roomId, messageId);
  void _refreshMessageFn(String roomId, String messageId) =>
      _deps.refreshMessageFn(roomId, messageId);
  void _refreshReactionsFn(String roomId, String messageId) =>
      _deps.refreshReactionsFn(roomId, messageId);
  void _handleUserJoinedFn(String roomId, String userId) =>
      _deps.handleUserJoinedFn(roomId, userId);
  void _handleUserLeftFn(String roomId, String userId, {String? actorUserId}) =>
      _deps.handleUserLeftFn(roomId, userId, actorUserId: actorUserId);
  void _handleUserRejoinedFn(String roomId, String userId) =>
      _deps.handleUserRejoinedFn(roomId, userId);
  void _addSystemMessageFn(
    String roomId,
    String systemType,
    String userId, {
    String? actorUserId,
  }) => _deps.addSystemMessageFn(
    roomId,
    systemType,
    userId,
    actorUserId: actorUserId,
  );
  void _addRoomFromDetailFn(String roomId, {ChatMessage? lastMessage}) =>
      _deps.addRoomFromDetailFn(roomId, lastMessage: lastMessage);
  void _enrichRoomFromDetailFn(String roomId) =>
      _deps.enrichRoomFromDetailFn(roomId);
  void _updateRoomLastMessage(String roomId, ChatMessage message) =>
      _deps.updateRoomLastMessage(roomId, message);
  void _updateRoomListReceipt(
    String roomId,
    String messageId,
    ReceiptStatus status,
  ) => _deps.updateRoomListReceipt(roomId, messageId, status);
  void _updateRoomReactionPreview(
    String roomId,
    String reaction,
    String userId,
    String messageId,
  ) => _deps.updateRoomReactionPreview(roomId, reaction, userId, messageId);
  void _updateRoomUnread(String roomId, int count) =>
      _deps.updateRoomUnread(roomId, count);
  void _removeChatController(String roomId) =>
      _deps.removeChatController(roomId);
  void Function(ChatMessage message, String roomId)? get _onAdminMessage =>
      _deps.onAdminMessage();
  void Function(String message)? get _onBroadcast => _deps.onBroadcast();
  void Function(ChatEvent event)? get _onError => _deps.onError();
  void Function()? get _onReconnected => _deps.onReconnected();
  void Function(String, String?, String?)? get _onRoomRemoved =>
      _deps.onRoomRemoved();

  /// Resets the reconnect-detection latch for an explicit, adapter-driven
  /// disconnect (`ChatUiAdapter.disconnect`/`signOut`). Those calls cancel
  /// the router's event subscription BEFORE telling the transport to
  /// disconnect (so a burst of teardown noise from the transport never
  /// reaches [handle]) — which means the `DisconnectedEvent` case in
  /// [handle] that would normally clear [_lastKnownConnectedFromEvents]
  /// never fires. Left stale at `true`, the next [_onConnected] would read
  /// `wasConnected: true` and silently skip the presence bootstrap + resync,
  /// exactly the resume-after-background path `ChatPauseAction.disconnect`
  /// depends on. Call this once subscriptions are torn down, alongside
  /// resetting `connectionStateNotifier` itself.
  void markDisconnected() {
    _lastKnownConnectedFromEvents = false;
  }

  void handle(ChatEvent event) {
    if (_isDisposed()) return;
    switch (event) {
      case NewMessageEvent(:final message, :final roomId):
        _onNewMessage(message, roomId);
      case MessageUpdatedEvent(:final roomId, :final messageId, :final message):
        if (message != null) {
          // Server bundled the row inline — apply directly and skip the
          // REST follow-up. Used by `do_admin_put_message` and the
          // standard `user_client:put_messages` paths.
          //
          // A `message_updated` event is, by definition, an edit: the
          // backend only emits it from the edit paths. The inline preview
          // (`chat_engine_vo:format_nmsg/1`) omits `text_history`, so the
          // parsed row would carry isEdited=false and clobber the sender's
          // optimistic badge / hide it for other viewers. Force the flag
          // here so the WhatsApp-style "edited" marker is consistent for
          // everyone and survives a cache reload, independent of whether
          // the payload happens to include the edit signal.
          final edited = message.copyWith(isEdited: true);
          final controller = _controllers[roomId];
          controller?.updateMessage(edited);
          _cache?.updateMessage(roomId, edited);
          // If the edited message is the room's CURRENT last message, refresh
          // the chat-list preview too — otherwise the open chat updates but
          // the list row keeps the pre-edit text (reported 2026-05-28: an
          // edit didn't refresh in the chat list for any viewer). Guarded to
          // the last message so editing older messages doesn't clobber the
          // preview with stale (earlier) content.
          if (_roomList.getRoomById(roomId)?.lastMessageId == messageId) {
            _updateRoomLastMessage(roomId, edited);
          }
        } else {
          _refreshMessageFn(roomId, messageId);
        }
      case MessageDeletedEvent(:final roomId, :final messageId):
        _onMessageDeleted(roomId, messageId);
      case UserActivityEvent(:final roomId, :final userId, :final activity):
        _onUserActivity(roomId, userId, activity);
      case DmActivityEvent(:final contactId, :final userId, :final activity):
        _onDmActivity(contactId, userId, activity);
      case UnreadUpdatedEvent(:final roomId, :final count):
        _updateRoomUnread(roomId, count);
      case RoomDeletedEvent(:final roomId, :final reason, :final adminReason):
        if (_roomList.deletedRoomIds.contains(roomId)) {
          // The user already deleted this chat locally (WhatsApp "Delete
          // chat"). A late membership-revocation echo (leave / kick /
          // group deleted) must NOT resurrect it — drop the row and the
          // cached rows so it stays gone.
          _roomList.removeRoom(roomId);
          _removeChatController(roomId);
          _cache?.deleteRoom(roomId);
        } else {
          // Any other room_deleted — per-room ban, kick, voluntary leave,
          // or the group being deleted — KEEPS the chat read-only with
          // full history (WhatsApp parity) instead of pruning it. The
          // backend strips event metadata on the wire (reason is usually
          // null), and the polling list-diff synthesizes a reason-less
          // room_deleted for any room that dropped out of the listing, so
          // gating the read-only path on reason=='banned' wiped left and
          // kicked rooms on the very next sync. Keeping every non-deleted
          // room read-only is self-healing: even if some other path
          // clears the marker, the next reason-less room_deleted re-marks
          // it. `markKicked` persists the id so the room survives cold
          // starts (the enricher re-hydrates it from cache since the
          // backend stops returning it). An admin re-add clears the flag
          // via `_handleUserRejoined`.
          final room = _roomList.getRoomById(roomId);
          if (room != null && room.isParticipating) {
            _roomList.updateRoom(room.copyWith(isParticipating: false));
          }
          _cache?.markKicked(roomId);
        }
        try {
          _onRoomRemoved?.call(roomId, reason, adminReason);
        } catch (_) {
          // Defensive: host snackbar code must not be allowed to break
          // the event pipeline.
        }
      case RoomCreatedEvent(:final roomId):
        // Same rationale as NewMessageEvent above: don't add a ghost
        // placeholder with no metadata. Confirm via detail first.
        _addRoomFromDetailFn(roomId);
      case RoomUpdatedEvent(:final roomId):
        _cache?.deleteRoomDetail(roomId);
        _enrichRoomFromDetailFn(roomId);
      case PresenceChangedEvent(
        :final userId,
        :final online,
        :final status,
        :final lastSeen,
      ):
        _presence.update(userId, online, status, lastSeen: lastSeen);
      case ReceiptUpdatedEvent(
        :final roomId,
        :final messageId,
        :final status,
        :final fromUserId,
      ):
        _controllers[roomId]?.updateReceipt(
          messageId,
          status,
          fromUserId: fromUserId,
        );
        _updateRoomListReceipt(roomId, messageId, status);
      case MessageDeliveredEvent():
        _onMessageDelivered(event);
      case MessageAckedEvent():
        _onMessageAcked(event);
      case ReactionAddedEvent(
        :final roomId,
        :final messageId,
        :final userId,
        :final reaction,
      ):
        if (userId != _currentUser().id) {
          _refreshReactionsFn(roomId, messageId);
          _updateRoomReactionPreview(roomId, reaction, userId, messageId);
        }
      case ReactionDeletedEvent(:final roomId, :final messageId):
        if (!_pendingReactions.isPendingDelete(messageId)) {
          _refreshReactionsFn(roomId, messageId);
        }
      case UserJoinedEvent(:final roomId, :final userId):
        _handleUserJoinedFn(roomId, userId);
        // WhatsApp-parity: if I was previously kicked from this room
        // and an admin re-added me, clear the `isParticipating=false`
        // flag so the banner disappears and the composer reactivates.
        _handleUserRejoinedFn(roomId, userId);
        _addSystemMessageFn(roomId, 'user_joined', userId);
      case UserLeftEvent(:final roomId, :final userId, :final actorUserId):
        _handleUserLeftFn(roomId, userId, actorUserId: actorUserId);
        _addSystemMessageFn(
          roomId,
          'user_left',
          userId,
          actorUserId: actorUserId,
        );
      case UserRoleChangedEvent(:final roomId, :final userId):
        _enrichRoomFromDetailFn(roomId);
        _addSystemMessageFn(roomId, 'user_role_changed', userId);
      case ConnectedEvent():
        _onConnected();
      case DisconnectedEvent():
        _lastKnownConnectedFromEvents = false;
        _connectionStateNotifier.value = ChatConnectionState.disconnected;
      case ErrorEvent():
        _lastKnownConnectedFromEvents = false;
        _connectionStateNotifier.value = ChatConnectionState.error;
        _onError?.call(event);
      case BroadcastEvent(:final message):
        _onBroadcast?.call(message);
      case UserUpdatedEvent():
        _onUserUpdated(event);
    }
  }

  /// Applies a `user_updated` WS event (profile change) to local state:
  /// refreshes the user cache so any [UserAvatar]/[RoomTile] referencing
  /// the user re-renders, and mirrors the change onto `currentUser` when
  /// the event targets self (typically a profile edit pushed from
  /// another device).
  void _onUserUpdated(UserUpdatedEvent event) {
    final existing = _findCachedUser(event.userId);
    final merged = (existing ?? ChatUser(id: event.userId)).copyWith(
      displayName: event.displayName ?? existing?.displayName,
      avatarUrl: event.avatarFieldPresent
          ? event.avatarUrl
          : existing?.avatarUrl,
      bio: event.bio ?? existing?.bio,
      email: event.email ?? existing?.email,
    );
    _cacheUsersFn([merged]);
    if (event.userId == _currentUser().id) {
      _setCurrentUser(
        _currentUser().copyWith(
          displayName: event.displayName ?? _currentUser().displayName,
          avatarUrl: event.avatarFieldPresent
              ? event.avatarUrl
              : _currentUser().avatarUrl,
          bio: event.bio ?? _currentUser().bio,
          email: event.email ?? _currentUser().email,
        ),
      );
    }
  }

  /// Applies a `message_delivered` cursor: flips delivered ticks on the
  /// open controller (cursor semantics — every message at-or-before the
  /// event's message) and mirrors the freshest aggregate onto the
  /// room-list row. DM-form events (no roomId) resolve the conversation
  /// through the confirmer's DM mapping; unresolvable events are
  /// dropped — the next room sync re-derives the listing tick anyway.
  void _onMessageDelivered(MessageDeliveredEvent event) {
    final resolvedRoomId = event.roomId ?? _dmContacts.roomIdFor(event.userId);
    if (resolvedRoomId == null) return;
    final controller = _controllers[resolvedRoomId];
    if (controller == null) {
      // Room not open: best-effort freshness for the room-list tick.
      // The mutator only applies it when the event's message IS the
      // row's own last message; anything else rehydrates on open.
      _updateRoomListReceipt(
        resolvedRoomId,
        event.messageId,
        ReceiptStatus.delivered,
      );
      return;
    }
    controller.applyDeliveryCursor(
      userId: event.userId,
      messageId: event.messageId,
      seq: event.seq,
    );
    // Mirror the aggregate of the newest own message onto the row so
    // the chat-list tick moves in lockstep with the bubbles.
    for (final m in controller.messages.reversed) {
      if (m.from != _currentUser().id) continue;
      final status = controller.receiptStatuses[m.id];
      if (status != null) {
        _updateRoomListReceipt(resolvedRoomId, m.id, status);
      }
      return;
    }
  }

  /// Records the server-assigned seq of an own message (single gray
  /// tick confirmation). The seq feeds numeric cursor coverage in the
  /// controller; hosts correlate WS sends via the event's metadata.
  void _onMessageAcked(MessageAckedEvent event) {
    final toUserId = event.toUserId;
    final resolvedRoomId =
        event.roomId ??
        (toUserId != null ? _dmContacts.roomIdFor(toUserId) : null);
    if (resolvedRoomId == null) return;
    _controllers[resolvedRoomId]?.recordMessageSeq(event.messageId, event.seq);
  }

  void _onNewMessage(ChatMessage message, String roomId) {
    _controllers[roomId]?.addMessage(message);
    _cache?.saveMessages(roomId, [message]);
    // An own message carrying a clientMessageId is the authoritative echo
    // of a send this device (or the offline queue) fired — the adapter
    // keys pending-store rows by that same value (tempId), so drop the
    // row here. Covers the ack_mode=async window where the REST 201 never
    // returned but the send actually landed.
    final cmid = message.clientMessageId;
    if (message.from == _currentUser().id && cmid != null) {
      unawaited(
        (_cache?.deletePendingMessage(roomId, cmid) ??
                Future.value(const ChatSuccess<void>(null)))
            .catchError(
              (_) => const ChatFailureResult<void>(
                UnexpectedFailure('deletePendingMessage failed'),
              ),
            ),
      );
    }
    // Ensure the sender's profile lands in `_userCache` so bubble
    // resolvers (`displayNameFor`, `findCachedUser`) can render their
    // displayName + avatar instead of the raw UUID — important for
    // groups where the sender may not be in `controller.otherUsers`
    // (the controller is only hydrated lazily by the consumer).
    if (message.from != _currentUser().id) {
      unawaited(_ensureUserCachedFn(message.from));
    }
    // Admin-sent message hook: hosts can show a tailored snackbar /
    // banner via `adapter.onAdminMessage`. The bubble already
    // self-identifies via the "admin" meta-row label; this callback
    // is for app-level UX surfacing, not for the bubble itself.
    if (message.metadata?['adminSent'] == true) {
      try {
        _onAdminMessage?.call(message, roomId);
      } catch (_) {
        // Defensive: a host's snackbar implementation must never
        // be allowed to break the event pipeline.
      }
    }
    // Resurrection of a per-user DELETED chat. WhatsApp parity: deleting a
    // chat removes it from both lists, but a fresh message from a 1:1 peer
    // brings it back EMPTY (only the new message; prior history stays
    // hidden behind the preserved `clearedAt` cutoff). Clearing the deleted
    // marker BEFORE the re-add below lets the row surface again — the
    // `clearedAt` cutoff is intentionally left in place. Archived (hidden)
    // rooms are NOT touched here: they must STAY archived on a new message.
    if (_roomList.deletedRoomIds.contains(roomId)) {
      _roomList.clearDeleted(roomId);
      // Client surface first — this is where `ChatRoomsController.delete`
      // persists the marker (survives even when the adapter's own `cache:`
      // is `null`, e.g. WB). Adapter cache is a backstop for hosts that DO
      // wire one directly.
      unawaited(
        _client.rooms
            .clearRoomDeleted(roomId)
            .catchError(
              (_) => const ChatFailureResult<void>(
                UnexpectedFailure('clearRoomDeleted threw'),
              ),
            ),
      );
      unawaited(
        (_cache?.clearDeletedRoom(roomId) ?? Future<void>.value()).catchError(
          (_) {},
        ),
      );
    }
    if (_roomList.getRoomById(roomId) == null) {
      // Don't add a placeholder RoomListItem(id:) yet. If we do, the UI
      // briefly shows a "ghost" room with the raw roomId as title (no
      // name/custom/avatar). Instead, fetch the detail first and only add
      // the room when we have enough metadata to render it correctly.
      _addRoomFromDetailFn(roomId, lastMessage: message);
    } else {
      _updateRoomLastMessage(roomId, message);
    }
    if (message.from == _currentUser().id) return;
    final isActiveRoom = _autoMarkAsRead && _activeRoomId() == roomId;
    final existing = _roomList.getRoomById(roomId);
    if (existing != null) {
      // Archived (hidden) rooms STAY archived when a new message arrives —
      // WhatsApp parity. (Previously this un-hid the room, which conflated
      // "Archive" with the now-separate "Delete" semantics.) The unread
      // badge below still updates so the archived row reflects the new count.
      //
      // If the user is right now looking at this conversation, treat the
      // message as instantly read — mirrors WhatsApp's "you're in the
      // chat, you saw it the moment it landed" behaviour. The chat list
      // unread badge never blips up to 1 just to drop back to 0.
      _updateRoomUnread(roomId, isActiveRoom ? 0 : existing.unreadCount + 1);
      // Mention badge ("@"): bump the per-room mention counter when the
      // incoming message tags the current user and the chat isn't already
      // open. `_updateRoomUnread(…, 0)` clears it on read; the next
      // `loadRooms` reconciles it against the authoritative server count.
      if (!isActiveRoom && _messageMentionsMe(message)) {
        final cur = _roomList.getRoomById(roomId);
        if (cur != null) {
          _roomList.updateRoom(
            cur.copyWith(unreadMentions: cur.unreadMentions + 1),
          );
        }
      }
    }
    if (isActiveRoom) {
      // Read receipt with the just-arrived messageId as high-water mark.
      // The backend fans `receipt_updated` to the sender so their bubble
      // flips ✓✓ → ✓✓-blue in real time, exactly as WhatsApp does. The
      // read receipt implies delivery server-side, so no separate
      // delivered confirmation is needed here.
      unawaited(_markAsReadFn(roomId, lastReadMessageId: message.id));
    } else if (_autoConfirmDelivery) {
      // Fire-and-forget delivered-cursor confirmation, coalesced per
      // room. Best-effort: failure here only means the sender sees the
      // message in `sent` state for longer.
      unawaited(_confirmDeliveredFn(roomId, message.id));
    }
  }

  /// True when [message] tags the current user via `metadata.mentions`
  /// (the userId list the composer stamps, see [MessageInput]). Used to
  /// light up the room tile's "@" badge in real time.
  bool _messageMentionsMe(ChatMessage message) {
    final raw = message.metadata?['mentions'];
    if (raw is! List) return false;
    return raw.contains(_currentUser().id);
  }

  void _onMessageDeleted(String roomId, String messageId) {
    final controller = _controllers[roomId];
    if (controller != null) {
      final msg = controller.messages
          .where((m) => m.id == messageId)
          .firstOrNull;
      if (msg != null) {
        controller.updateMessage(msg.copyWith(isDeleted: true, text: ''));
      }
    }
    // After the optimistic flip, also re-fetch the message from REST so
    // metadata flags set server-side (e.g. `adminDeleted` when an admin
    // moderated the message via the panel) reach this client. Without
    // the refresh the bubble would render the generic "this message
    // was deleted" instead of "Deleted by admin" — same data is
    // already on the server doc, just not in the local cache yet
    // because the WS event only carries (roomId, messageId).
    _refreshMessageFn(roomId, messageId);
    _cache?.deleteMessage(roomId, messageId);
    final room = _roomList.getRoomById(roomId);
    if (room != null && room.lastMessageId == messageId) {
      _roomList.updateRoom(
        room.copyWith(
          lastMessage: _l10n.messageDeleted,
          lastMessageIsDeleted: true,
        ),
      );
      unawaited(
        _client.rooms.updateCachedRoomPreview(
          roomId,
          lastMessage: _l10n.messageDeleted,
          lastMessageIsDeleted: true,
        ),
      );
    }
  }

  void _onUserActivity(String roomId, String userId, ChatActivity activity) {
    if (userId == _currentUser().id) return;
    final isTyping = activity == ChatActivity.startsTyping;
    _controllers[roomId]?.setTyping(userId, isTyping);
    _roomList.setRoomTyping(roomId, userId, isTyping);
    if (isTyping && !_userCacheService.contains(userId)) {
      unawaited(_ensureUserCachedFn(userId));
    }
  }

  void _onDmActivity(String contactId, String userId, ChatActivity activity) {
    if (userId == _currentUser().id) return;
    var roomId = _dmContacts.roomIdFor(contactId);
    if (roomId == null) {
      final match = _roomList.allRooms
          .where((r) => r.otherUserId == contactId)
          .firstOrNull;
      if (match != null) {
        roomId = match.id;
        _dmContacts.bind(contactId, roomId);
      }
    }
    if (roomId == null) return;
    final isTyping = activity == ChatActivity.startsTyping;
    _controllers[roomId]?.setTyping(userId, isTyping);
    _roomList.setRoomTyping(roomId, userId, isTyping);
    if (isTyping && !_userCacheService.contains(userId)) {
      unawaited(_ensureUserCachedFn(userId));
    }
  }

  void _onConnected() {
    final wasConnected = _lastKnownConnectedFromEvents;
    _lastKnownConnectedFromEvents = true;
    _connectionStateNotifier.value = ChatConnectionState.connected;
    // Refresh the presence cache after a (re)connection so that contact
    // online states reflect the current server snapshot. CHT does not
    // re-emit presence_changed events for state already known before the
    // disconnect, so without this refresh the cache could go stale.
    if (!wasConnected) {
      unawaited(_presence.bootstrap());
      // Centralized reconnect-resync trigger (room list + active room) —
      // deliberately the ONLY place that reacts to "we just reconnected"
      // for this purpose, so an app-resume racing this event can't fire a
      // second resync. See `ChatUiAdapter.resync` for what it does and its
      // own debounce.
      _deps.triggerResync();
    }
    _onReconnected?.call();
  }
}
