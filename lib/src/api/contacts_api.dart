import '../_internal/cache/cache_manager.dart';
import '../_internal/cache/cache_policy.dart';
import '../_internal/cache/local_datasource.dart';
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

import '../client/chat_client.dart';

import '../_internal/transport/transport_manager.dart';

/// REST implementation of [ChatContactsApi] (contacts list + DMs + block list).
class ContactsApi implements ChatContactsApi {
  static int _pendingSeq = 0;
  final RestClient _rest;
  final TransportManager? _transport;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final OfflineQueue? _offlineQueue;
  final void Function(String level, String message)? _logger;

  ContactsApi({
    required RestClient rest,
    TransportManager? transport,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    OfflineQueue? offlineQueue,
    void Function(String level, String message)? logger,
  }) : _rest = rest,
       _transport = transport,
       _cache = cache,
       _cacheManager = cacheManager,
       _offlineQueue = offlineQueue,
       _logger = logger;

  @override
  Future<Result<PaginatedResponse<ChatContact>>> list({
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) {
    if (_cacheManager != null && _cache != null && pagination == null) {
      return _cacheManager.resolve<PaginatedResponse<ChatContact>>(
        key: 'contacts',
        ttl: _cacheManager.config.ttlUsers,
        policy: cachePolicy,
        fromCache: () async {
          final cached = await _cache.getContacts();
          if (cached.isEmpty) return null;
          return PaginatedResponse(items: cached, hasMore: false);
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get(
            '/contacts',
            queryParams: pagination?.toQueryParams(),
          );
          final contacts = (json['contacts'] as List? ?? [])
              .map((e) => UserMapper.contactFromJson(e as Map<String, dynamic>))
              .toList();
          return PaginatedResponse(
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
      return PaginatedResponse(
        items: contacts,
        hasMore: (json['hasMore'] ?? false) as bool,
        totalCount: totalCount,
      );
    });
  }

  @override
  Future<Result<void>> add(String contactUserId) async {
    final result = await safeVoidCall(
      () => _rest.postVoid('/contacts', data: {'userId': contactUserId}),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('contacts');
    }
    return result;
  }

  @override
  Future<Result<void>> remove(String contactUserId) async {
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
  Future<Result<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
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
        },
      );
      return MessageMapper.fromJson(json);
    });
    if (result.isSuccess && _cache != null) {
      try {
        final msg = result.dataOrNull!;
        await _cache.saveMessages(contactUserId, [msg]);
        _cacheManager?.invalidatePrefix('messages:$contactUserId');
      } catch (e) {
        _logger?.call(
          'warn',
          'contacts.sendDirectMessage: cache update failed: $e',
        );
      }
    } else if (result.isFailure &&
        result.failureOrNull is NetworkFailure &&
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
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    CursorPaginationParams? pagination,
  }) => safeApiCall(() async {
    final json = await _rest.get(
      '/contacts/$contactUserId/messages',
      queryParams: pagination?.toQueryParams(),
    );
    return PaginatedResponse(
      items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
    );
  });

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getConversationMessages(
    String conversationId, {
    CursorPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/conversations/$conversationId/messages',
      queryParams: pagination?.toQueryParams(),
    );
    return PaginatedResponse(
      items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<Result<ChatPresence>> getPresence(String contactUserId) =>
      safeApiCall(() async {
        final json = await _rest.get('/contacts/$contactUserId/presence');
        return PresenceMapper.fromJson(json);
      });

  // Typing in DMs

  @override
  Future<Result<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) {
    if (_transport != null && _transport.isWsConnected) {
      _transport.sendDmTyping(contactUserId, activity: activity.name);
      return Future.value(const Success(null));
    }
    return safeVoidCall(
      () => _rest.postVoid(
        '/contacts/$contactUserId/activity',
        data: {'activity': activity.name},
      ),
    );
  }

  // Block

  @override
  Future<Result<void>> block(String userId) =>
      safeVoidCall(() => _rest.putVoid('/contacts/$userId/block'));

  @override
  Future<Result<void>> unblock(String userId) =>
      safeVoidCall(() => _rest.delete('/contacts/$userId/block'));

  @override
  Future<Result<PaginatedResponse<String>>> listBlocked({
    PaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/blocked',
      queryParams: pagination?.toQueryParams(),
    );
    final blocked = (json['blockedUsers'] as List? ?? []).cast<String>();
    return PaginatedResponse(
      items: blocked,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });
}
