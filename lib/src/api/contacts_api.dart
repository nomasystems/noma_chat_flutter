import '../_internal/cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../_internal/cache/offline_queue.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../_internal/mappers/presence_mapper.dart';
import '../_internal/mappers/user_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/presence.dart';
import '../events/chat_event.dart';

import 'package:uuid/uuid.dart';

import '../client/chat_client.dart';

const Uuid _uuid = Uuid();

/// REST implementation of [ChatContactsApi] (contacts list + DMs + block list).
class ContactsApi implements ChatContactsApi {
  static int _pendingSeq = 0;
  final RestClient _rest;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final OfflineQueue? _offlineQueue;

  ContactsApi({
    required RestClient rest,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    OfflineQueue? offlineQueue,
  }) : _rest = rest,
       _cache = cache,
       _cacheManager = cacheManager,
       _offlineQueue = offlineQueue;

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatContact>>> list({
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) {
    if (_cacheManager != null && _cache != null && pagination == null) {
      return _cacheManager.resolve<ChatPaginatedResponse<ChatContact>>(
        key: 'contacts',
        ttl: _cacheManager.config.ttlUsers,
        policy: cachePolicy,
        fromCache: () async {
          final cached =
              (await _cache.getContacts()).dataOrNull ?? const <ChatContact>[];
          if (cached.isEmpty) return null;
          return ChatPaginatedResponse(items: cached, hasMore: false);
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get(
            '/contacts',
            queryParams: pagination?.toQueryParams(),
          );
          final contacts = (json['contacts'] as List? ?? [])
              .map((e) => UserMapper.contactFromJson(e as Map<String, dynamic>))
              .toList();
          return ChatPaginatedResponse(
            items: contacts,
            hasMore: (json['hasMore'] ?? false) as bool,
          );
        }),
        saveToCache: (data) => _cache.saveContacts(data.items),
      );
    }
    return safeApiCall(() async {
      final (json, totalCount) = await _rest.getWithTotalCount(
        '/contacts',
        queryParams: pagination?.toQueryParams(),
      );
      final contacts = (json['contacts'] as List? ?? [])
          .map((e) => UserMapper.contactFromJson(e as Map<String, dynamic>))
          .toList();
      return ChatPaginatedResponse(
        items: contacts,
        hasMore: (json['hasMore'] ?? false) as bool,
        totalCount: totalCount,
      );
    });
  }

  @override
  Future<ChatResult<void>> add(String contactUserId) async {
    final result = await safeVoidCall(
      () => _rest.postVoid('/contacts', data: {'userId': contactUserId}),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('contacts');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> remove(String contactUserId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/contacts/$contactUserId'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('contacts');
    }
    return result;
  }

  // Direct messages

  @override
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    // Always carry a clientMessageId, mirroring the room send path: the
    // server-side dedup only covers messages that have one, and it is the
    // only correlation key between the (possibly provisional) echo and the
    // authoritative `new_message` event under ack_mode=async.
    final effectiveClientMessageId = clientMessageId ?? _uuid.v4();
    final result = await safeApiCall(() async {
      final json = await _rest.post(
        '/contacts/$contactUserId/messages',
        data: {
          if (text != null) 'text': text,
          'messageType': messageType.name,
          if (referencedMessageId != null)
            'referencedMessageId': referencedMessageId,
          if (reaction != null) 'emoji': reaction,
          if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
          if (metadata != null) 'metadata': metadata,
          'clientMessageId': effectiveClientMessageId,
        },
      );
      // HTTP 204 (empty body): the backend accepted the message but silently
      // dropped it because the recipient has blocked the sender (WhatsApp
      // parity). Synthesize a local `sent` message instead of mapping an
      // id-less phantom — it shows as sent and never advances to
      // delivered/read, exactly what a blocked sender sees. `silentlyDropped`
      // lets the caller distinguish this from a normal send.
      if (json.isEmpty) {
        return ChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}-${_pendingSeq++}',
          from: _rest.userId ?? '',
          timestamp: DateTime.now(),
          text: text,
          messageType: messageType,
          referencedMessageId: referencedMessageId,
          clientMessageId: effectiveClientMessageId,
          reaction: reaction,
          attachmentUrl: attachmentUrl,
          metadata: metadata,
          receipt: ReceiptStatus.sent,
          silentlyDropped: true,
        );
      }
      return MessageMapper.stampIfProvisional(
        MessageMapper.fromJson(json),
        effectiveClientMessageId,
      );
    });
    final failure = result.failureOrNull;
    // A DM send is non-idempotent, so only enqueue when the request
    // provably never reached the server: a network failure, or a
    // pre-response timeout. A receive timeout might already have created
    // the message server-side; re-sending it would duplicate.
    final canQueueDirectSend =
        failure is NetworkFailure ||
        (failure is TimeoutFailure && failure.kind.isPreResponse);
    if (result.isSuccess && _cache != null) {
      // The DM timeline is keyed by the backend-resolved 1:1 roomId,
      // which the POST /contacts/{id}/messages response does not carry
      // (see map_nmessage_for_dm_send in CHT). Caching the message under
      // contactUserId only creates an orphan box nothing reads and leaves
      // the real messages:<roomId> entry stale, so we skip the per-room
      // write-through and let the WS NewMessageEvent — which carries the
      // roomId — populate it. We still bust the room-list previews so the
      // conversation surfaces and reorders immediately.
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    } else if (result.isFailure &&
        canQueueDirectSend &&
        _offlineQueue != null) {
      _offlineQueue.enqueue(
        PendingSendDirectMessage(
          id: 'pending-${DateTime.now().microsecondsSinceEpoch}-${_pendingSeq++}',
          contactUserId: contactUserId,
          text: text,
          messageType: messageType,
          referencedMessageId: referencedMessageId,
          reaction: reaction,
          attachmentUrl: attachmentUrl,
          metadata: metadata,
          // Reuse the same idempotency key on every retry so the server
          // dedups a delivery that actually succeeded before the failure
          // surfaced (returns the persisted message, no duplicate).
          clientMessageId: effectiveClientMessageId,
        ),
      );
    }
    return result;
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    ChatCursorPaginationParams? pagination,
  }) => safeApiCall(() async {
    final json = await _rest.get(
      '/contacts/$contactUserId/messages',
      queryParams: pagination?.toQueryParams(),
    );
    return ChatPaginatedResponse(
      items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      nextCursor: json['next'] as String?,
      prevCursor: json['prev'] as String?,
    );
  });

  /// Fetches messages of a resolved 1:1 conversation by its
  /// [conversationId] — the backend-assigned DM room id.
  ///
  /// Discoverability: [conversationId] is an opaque, backend-resolved id, not
  /// a value the consumer invents. Obtain it from an event or listing that
  /// carries it — e.g. `NewMessageEvent.roomId` for a DM, or the `roomId`
  /// on a room-list/unread entry — then reuse it here. When all you hold is
  /// the peer's user id, call [getDirectMessages] instead (it resolves the
  /// room for you). An empty/whitespace [conversationId] is rejected up
  /// front with a [ValidationFailure] rather than hitting a malformed path.
  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>>
  getConversationMessages(
    String conversationId, {
    ChatCursorPaginationParams? pagination,
  }) {
    if (conversationId.trim().isEmpty) {
      return Future.value(
        const ChatFailureResult(
          ValidationFailure(message: 'conversationId must not be empty'),
        ),
      );
    }
    return safeApiCall(() async {
      final (json, totalCount) = await _rest.getWithTotalCount(
        '/conversations/$conversationId/messages',
        queryParams: pagination?.toQueryParams(),
      );
      return ChatPaginatedResponse(
        items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
        hasMore: (json['hasMore'] ?? false) as bool,
        totalCount: totalCount,
        nextCursor: json['next'] as String?,
        prevCursor: json['prev'] as String?,
      );
    });
  }

  @override
  Future<ChatResult<ChatPresence>> getPresence(String contactUserId) =>
      safeApiCall(() async {
        final json = await _rest.get('/contacts/$contactUserId/presence');
        return PresenceMapper.fromJson(json);
      });

  // Typing in DMs

  /// Sends a typing activity to a DM contact.
  ///
  /// Always uses the `postContactActivity` REST operation
  /// (`POST /contacts/{id}/activity`): the backend's WS `typing` frame is
  /// room-scoped (it requires a `roomId` and rejects contact-addressed
  /// frames), so REST is the only route that reaches the peer as a
  /// contact-activity event. The backend's contact-activity endpoint only
  /// models typing (`startsTyping` / `stopsTyping`), so this is its full
  /// surface.
  @override
  Future<ChatResult<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) => safeVoidCall(
    () => _rest.postVoid(
      '/contacts/$contactUserId/activity',
      data: {'activity': activity.name},
    ),
  );

  // Block

  @override
  Future<ChatResult<void>> block(String userId) =>
      safeVoidCall(() => _rest.putVoid('/contacts/$userId/block'));

  @override
  Future<ChatResult<void>> unblock(String userId) =>
      safeVoidCall(() => _rest.delete('/contacts/$userId/block'));

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/blocked',
      queryParams: pagination?.toQueryParams(),
    );
    final blocked = (json['blockedUsers'] as List? ?? []).cast<String>();
    return ChatPaginatedResponse(
      items: blocked,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });
}
