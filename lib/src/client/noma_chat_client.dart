import 'dart:async';

import '../api/attachments_api.dart';
import '../api/auth_api.dart';
import '../api/contacts_api.dart';
import '../api/members_api.dart';
import '../api/messages_api.dart';
import '../api/presence_api.dart';
import '../api/rooms_api.dart';
import '../api/users_api.dart';
import '../config/chat_config.dart';
import '../events/chat_event.dart';
import '../models/room.dart';
import '../models/room_user.dart';
import '../_internal/cache/cache_manager.dart';
import '../_internal/cache/local_datasource.dart';
import '../_internal/cache/offline_queue.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../models/message.dart';
import '../_internal/mappers/user_mapper.dart';
import '../_internal/transport/event_parser.dart';
import '../_internal/transport/transport_manager.dart';
import '../_internal/transport/ws_transport.dart';
import '../_internal/transport/sse_transport.dart';

import '../core/result.dart';
import 'chat_client.dart';

/// Default [ChatClient] implementation.
///
/// Composes the HTTP REST client, transport manager (WebSocket + SSE
/// fallback), local cache, and offline queue. Most apps should construct it
/// via [NomaChat.create] rather than instantiating it directly.
class NomaChatClient implements ChatClient {
  final TransportManager _transport;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final OfflineQueue? _offlineQueue;
  final bool _enableCatchUp;
  final void Function(String level, String message)? _logger;
  StreamSubscription<ChatEvent>? _eventSub;
  DateTime? _disconnectedAt;
  bool _hasConnectedOnce = false;

  /// Called when an offline queue send completes; receives the room id, the
  /// optimistic temp id and the server-confirmed message.
  void Function(String roomId, String tempId, ChatMessage message)?
  onOfflineMessageSent;

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
  late final MessagesApi messages;
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
  }) : _transport =
           transportManager ??
           TransportManager(
             ws: WsTransport(config: config),
             sse: SseTransport(config: config),
             eventBufferSize: config.eventBufferSize,
           ),
       _cache = config.localDatasource,
       _cacheManager = config.cacheConfig != null
           ? CacheManager(config: config.cacheConfig!)
           : null,
       _offlineQueue = config.cacheConfig != null
           ? OfflineQueue(
               maxRetries: config.cacheConfig!.offlineQueueMaxRetries,
               store: config.localDatasource,
               logger: config.logger,
             )
           : null,
       _enableCatchUp = config.enableReconnectCatchUp,
       _logger = config.logger {
    MessageMapper.logger = config.logger;
    UserMapper.logger = config.logger;
    EventParser.logger = config.logger;
    final rest = restClient ?? RestClient(config: config);
    final cache = _cache;
    final cacheManager = _cacheManager;

    auth = AuthApi(rest: rest);
    users = UsersApi(
      rest: rest,
      cache: cache,
      cacheManager: cacheManager,
      logger: config.logger,
    );
    rooms = RoomsApi(
      rest: rest,
      cache: cache,
      cacheManager: cacheManager,
      logger: config.logger,
    );
    members = MembersApi(rest: rest, userId: config.userId);
    messages = MessagesApi(
      rest: rest,
      transport: _transport,
      cache: cache,
      cacheManager: cacheManager,
      offlineQueue: _offlineQueue,
      logger: config.logger,
    );
    contacts = ContactsApi(
      rest: rest,
      transport: _transport,
      cache: cache,
      cacheManager: cacheManager,
      offlineQueue: _offlineQueue,
      logger: config.logger,
    );
    presence = PresenceApi(rest: rest);
    attachments = AttachmentsApi(rest: rest);
  }

  @override
  Stream<ChatEvent> get events => _transport.events;

  @override
  ChatConnectionState get connectionState => _transport.state;

  @override
  Stream<ChatConnectionState> get stateChanges => _transport.stateChanges;

  @override
  Future<void> connect() async {
    await _offlineQueue?.restore();
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
  Future<void> logout() async {
    await disconnect();
    _offlineQueue?.clear();
    _cacheManager?.clear();
    await _cache?.clear();
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _transport.dispose();
    await _cache?.dispose();
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
    await _offlineQueue.processQueue((op) async {
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
    });
  }

  Future<Result<dynamic>> _executeOfflineOp(PendingOperation op) async {
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
        final userRole = op.role != null
            ? switch (op.role!) {
                'owner' => RoomRole.owner,
                'admin' => RoomRole.admin,
                _ => RoomRole.member,
              }
            : null;
        return members.add(op.roomId, userIds: [op.userId], userRole: userRole);
      case PendingRemoveMember():
        return members.remove(op.roomId, op.userId);
    }
  }
}
