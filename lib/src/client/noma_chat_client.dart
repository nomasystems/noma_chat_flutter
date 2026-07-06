import 'dart:async';

import '../api/attachments_api.dart';
import '../api/auth_api.dart';
import '../api/contacts_api.dart';
import '../api/members_api.dart';
import '../api/presence_api.dart';
import '../api/rooms_api.dart';
import '../api/users_api.dart';
import '../config/chat_config.dart';
import '../events/chat_event.dart';
import '../models/room.dart';
import '../_internal/api_factory.dart';
import '../_internal/cache/cache_manager.dart';
import '../cache/local_datasource.dart';
import '../_internal/cache/offline_queue.dart';
import '../_internal/http/chat_exception.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../models/message.dart';
import '../_internal/mappers/user_mapper.dart';
import '../_internal/transport/event_parser.dart';
import '../_internal/transport/transport_manager.dart';

import '../core/result.dart';
import 'chat_client.dart';

/// Default [ChatClient] implementation.
///
/// Composes the HTTP REST client, transport manager (WebSocket + SSE
/// fallback), local cache, and offline queue. Most apps should construct it
/// via [NomaChat.create] rather than instantiating it directly.
class NomaChatClient implements ChatClient {
  final TransportManager _transport;
  late final RestClient _rest;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  late final OfflineQueue? _offlineQueue;
  final bool _enableCatchUp;
  final void Function(String level, String message)? _logger;
  final void Function()? _onAuthFailure;
  StreamSubscription<ChatEvent>? _eventSub;
  DateTime? _disconnectedAt;
  bool _hasConnectedOnce = false;
  Future<void>? _connecting;
  final Set<String> _permanentlyFailedOperationIds = {};

  /// Called when an offline queue send completes; receives the room id, the
  /// optimistic temp id and the server-confirmed message.
  void Function(String roomId, String tempId, ChatMessage message)?
  onOfflineMessageSent;

  /// Called when the offline queue gives up on a pending operation
  /// (`queue_full`, `ttl_expired`, or `max_retries` — see
  /// [OfflineQueue.onOperationDropped]). Defaults to recording the
  /// operation id in [permanentlyFailedOperationIds] so the host UI can
  /// show a "delivery failed" indicator via
  /// [isOperationPermanentlyFailed] without wiring anything itself.
  /// Overridable — assign a new closure to replace the default entirely
  /// (call [isOperationPermanentlyFailed] yourself from the override if
  /// you still want the built-in marker).
  late void Function(PendingOperation op, String reason) onOperationDropped;

  /// Ids of pending operations the offline queue gave up retrying,
  /// recorded by the default [onOperationDropped] handler. Cleared on
  /// [logout]. Empty if [onOperationDropped] was overridden with a
  /// closure that doesn't call [_markOperationPermanentlyFailed].
  Set<String> get permanentlyFailedOperationIds =>
      Set.unmodifiable(_permanentlyFailedOperationIds);

  /// Whether [operationId] was dropped by the offline queue after
  /// exhausting retries. Drive a "delivery failed" badge in the UI from
  /// this — pair with [PendingOperation.id] captured at enqueue time.
  bool isOperationPermanentlyFailed(String operationId) =>
      _permanentlyFailedOperationIds.contains(operationId);

  void _markOperationPermanentlyFailed(PendingOperation op, String reason) {
    _permanentlyFailedOperationIds.add(op.id);
  }

  DateTime? get lastDisconnectedAt => _disconnectedAt;

  @override
  late final AuthApi auth;
  @override
  late final UsersApi users;
  @override
  late final RoomsApi rooms;
  @override
  late final MembersApi members;
  @override
  late final ChatMessagesApi messages;
  @override
  late final ContactsApi contacts;
  @override
  late final PresenceApi presence;
  @override
  late final AttachmentsApi attachments;

  NomaChatClient({
    required ChatConfig config,
    RestClient? restClient,
    TransportManager? transportManager,
  }) : _transport = transportManager ?? TransportManager.fromConfig(config),
       _cache = config.localDatasource,
       _cacheManager = config.cacheConfig != null
           ? CacheManager(
               config: config.cacheConfig!,
               datasource: config.localDatasource,
               onMetric: config.metricCallback,
             )
           : null,
       _enableCatchUp = config.enableReconnectCatchUp,
       _logger = config.logger,
       _onAuthFailure = config.onAuthFailure {
    onOperationDropped = _markOperationPermanentlyFailed;
    _offlineQueue = config.cacheConfig != null
        ? OfflineQueue(
            maxRetries: config.cacheConfig!.offlineQueueMaxRetries,
            store: config.localDatasource,
            logger: config.logger,
            metricCallback: config.metricCallback,
            // Forwards through the field instead of binding
            // `_markOperationPermanentlyFailed` directly so a caller can
            // reassign `onOperationDropped` after construction (e.g. right
            // after `NomaChat.create()`) and still have it take effect —
            // `OfflineQueue.onOperationDropped` itself is fixed at
            // construction time.
            onOperationDropped: (op, reason) => onOperationDropped(op, reason),
          )
        : null;
    MessageMapper.logger = config.logger;
    UserMapper.logger = config.logger;
    EventParser.logger = config.logger;
    _rest = restClient ?? RestClient(config: config);

    final apiFactory = ApiFactory(
      rest: _rest,
      userId: config.userId,
      transport: _transport,
      cache: _cache,
      cacheManager: _cacheManager,
      offlineQueue: _offlineQueue,
      logger: config.logger,
    );

    auth = apiFactory.auth();
    users = apiFactory.users();
    rooms = apiFactory.rooms();
    members = apiFactory.members();
    messages = apiFactory.messages();
    contacts = apiFactory.contacts();
    presence = apiFactory.presence();
    attachments = apiFactory.attachments();

    // Bind the drain executor now that every sub-API is wired. The queue
    // is constructed earlier in the constructor body (so MessagesApi /
    // ContactsApi could receive a non-null reference for `enqueue`) but
    // the executor closure can only be set here because it captures
    // `this.messages`/`this.contacts` etc. that don't exist until this
    // point. This decouples OfflineQueue from the call-graph "circle" —
    // the queue owns its own drain logic via the bound executor instead
    // of having the host pass a closure every time it calls into the
    // queue.
    _offlineQueue?.bindExecutor(_offlineQueueExecutor);
  }

  Future<bool> _offlineQueueExecutor(PendingOperation op) async {
    try {
      final result = await _executeOfflineOp(op);
      if (result.isFailure && result.failureOrNull is AuthFailure) {
        _logger?.call('warn', 'Offline queue: auth failure, stopping');
        return false;
      }
      if (result.isSuccess &&
          op is PendingSendMessage &&
          op.tempId != null &&
          result.dataOrNull is ChatMessage) {
        onOfflineMessageSent?.call(
          op.roomId,
          op.tempId!,
          result.dataOrNull as ChatMessage,
        );
      }
      return result.isSuccess;
    } catch (e) {
      _logger?.call(
        'warn',
        'Offline queue: failed to execute ${op.runtimeType}: $e',
      );
      return false;
    }
  }

  @override
  Stream<ChatEvent> get events => _transport.events;

  @override
  ChatConnectionState get connectionState => _transport.state;

  @override
  Stream<ChatConnectionState> get stateChanges => _transport.stateChanges;

  @override
  Future<void> connect() {
    // Re-entrancy guard: a second connect() fired before the first
    // finishes (e.g. two lifecycle callbacks in quick succession) awaits
    // the in-flight call instead of racing it — otherwise both could
    // observe the same non-null `_eventSub`, cancel it twice, and
    // reassign the field out of order, leaking one subscription.
    final inFlight = _connecting;
    if (inFlight != null) return inFlight;
    final future = _connectOnce();
    _connecting = future;
    return future.whenComplete(() => _connecting = null);
  }

  Future<void> _connectOnce() async {
    await _offlineQueue?.restore();
    // Cancel any prior subscription before re-subscribing: a repeated
    // connect() (the documented background→foreground cycle) would
    // otherwise stack duplicate _onTransportEvent handlers and leak the
    // previous subscription.
    await _eventSub?.cancel();
    _eventSub = _transport.events.listen(_onTransportEvent);
    await _transport.connect();
  }

  @override
  Future<void> disconnect() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _transport.disconnect();
  }

  @override
  Future<void> notifyTokenRotated() => _transport.notifyTokenRotated();

  @override
  Future<void> refresh() => _transport.refresh();

  @override
  Future<void> refreshRoom(String roomId) =>
      _transport.refresh(singleRoomId: roomId);

  @override
  void cancelPendingRequests([String reason = 'cancelled']) {
    _rest.cancelPending(reason);
  }

  @override
  Future<void> logout() async {
    cancelPendingRequests('logout');
    await disconnect();
    _offlineQueue?.clear();
    _permanentlyFailedOperationIds.clear();
    _cacheManager?.clear();
    await _cache?.clear();
  }

  @override
  Future<void> dispose() async {
    cancelPendingRequests('dispose');
    await _eventSub?.cancel();
    _eventSub = null;
    await _transport.dispose();
    await _cacheManager?.dispose();
    await _cache?.dispose();
  }

  /// Hydrates the in-memory cache TTL timestamps from persistent
  /// storage. Called once at boot by [NomaChat.create] so `cacheFirst`
  /// honours the configured TTLs across cold starts.
  Future<void> restoreCacheTimestamps() async {
    await _cacheManager?.restore();
  }

  void _onTransportEvent(ChatEvent event) {
    switch (event) {
      case ConnectedEvent():
        if (_hasConnectedOnce) {
          _processOfflineQueue();
          if (_enableCatchUp) _catchUpUnreads();
        }
        _hasConnectedOnce = true;
        _disconnectedAt = null;
      case DisconnectedEvent():
        _disconnectedAt ??= DateTime.now();
      case ErrorEvent(exception: ChatAuthException(terminal: true)):
        // The realtime transport reported a terminal auth failure — the
        // account was globally banned / deactivated mid-session (WS close
        // 4007 or an `account_deactivated` auth_error). The REST
        // onAuthFailure path never fires here because an idle socket makes
        // no HTTP request, so route to the host logout flow explicitly.
        _logger?.call('warn', 'Realtime terminal auth failure, logging out');
        _onAuthFailure?.call();
      default:
        break;
    }
  }

  Future<void> _catchUpUnreads() async {
    final result = await rooms.getUserRooms(type: 'unread');
    result.fold(
      (failure) {
        _logger?.call('warn', 'Catch-up unreads failed: $failure');
      },
      (userRooms) {
        for (final room in userRooms.rooms) {
          if (room.unreadMessages > 0) {
            _transport.emitSynthetic(
              ChatEvent.unreadUpdated(
                roomId: room.roomId,
                count: room.unreadMessages,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _processOfflineQueue() async {
    if (_offlineQueue == null || _offlineQueue.isEmpty) return;
    await _offlineQueue.drain();
  }

  Future<ChatResult<dynamic>> _executeOfflineOp(PendingOperation op) async {
    switch (op) {
      case PendingSendMessage():
        return messages.send(
          op.roomId,
          text: op.text,
          messageType: op.messageType,
          referencedMessageId: op.referencedMessageId,
          reaction: op.reaction,
          attachmentUrl: op.attachmentUrl,
          sourceRoomId: op.sourceRoomId,
          metadata: op.metadata,
          tempId: op.tempId,
          clientMessageId: op.clientMessageId,
        );
      case PendingSendDirectMessage():
        return contacts.sendDirectMessage(
          op.contactUserId,
          text: op.text,
          messageType: op.messageType,
          referencedMessageId: op.referencedMessageId,
          reaction: op.reaction,
          attachmentUrl: op.attachmentUrl,
          metadata: op.metadata,
        );
      case PendingEditMessage():
        return messages.update(
          op.roomId,
          op.messageId,
          text: op.text,
          metadata: op.metadata,
        );
      case PendingDeleteMessage():
        return messages.delete(op.roomId, op.messageId);
      case PendingDeleteReaction():
        return messages.deleteReaction(op.roomId, op.messageId);
      case PendingAddReaction():
        return messages.addReaction(op.roomId, op.messageId, emoji: op.emoji);
      case PendingPinMessage():
        return messages.pinMessage(op.roomId, op.messageId);
      case PendingUnpinMessage():
        return messages.unpinMessage(op.roomId, op.messageId);
      case PendingStarMessage():
        return messages.starMessage(op.roomId, op.messageId);
      case PendingUnstarMessage():
        return messages.unstarMessage(op.roomId, op.messageId);
      case PendingCreateRoom():
        final audience = switch (op.audience) {
          'public' => RoomAudience.public,
          _ => RoomAudience.contacts,
        };
        return rooms.create(
          audience: audience,
          name: op.name,
          members: op.members,
          subject: op.subject,
        );
      case PendingUpdateRoomConfig():
        return rooms.updateConfig(
          op.roomId,
          name: op.name,
          subject: op.subject,
          avatarUrl: op.avatar,
        );
      case PendingAddMember():
        // The backend assigns no per-invite role (see ChatMembersApi.invite);
        // a role, if any, is applied separately via updateRole.
        return members.invite(op.roomId, userIds: [op.userId]);
      case PendingRemoveMember():
        return members.remove(op.roomId, op.userId);
    }
  }
}
