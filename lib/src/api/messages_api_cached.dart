import '../_internal/cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/mappers/message_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import 'messages_api_rest.dart';

/// Cache-aware decorator over [RestMessagesApi].
///
/// Adds two patterns on top of the REST layer:
///
/// - **Cache resolve** on read methods that benefit from staleness
///   (`list`, `getRoomReceipts`, `getReactions`, `listPins`) — uses
///   the [CacheManager] policy to pick cache vs network.
/// - **Cache write-through** on mutating methods (`send`, `update`,
///   `delete`, `markRoomAsRead`, `pinMessage`, `unpinMessage`,
///   `clearChat`) — keeps the local cache fresh after a successful
///   network call.
///
/// Methods not listed simply inherit the REST-only behaviour.
class CachedMessagesApi extends RestMessagesApi {
  CachedMessagesApi({
    required super.rest,
    super.transport,
    required ChatLocalDatasource cache,
    required CacheManager cacheManager,
    super.logger,
  }) : _cache = cache,
       _cacheManager = cacheManager;

  final ChatLocalDatasource _cache;
  final CacheManager _cacheManager;

  /// Exposes the cache so the offline-queue decorator can reuse the
  /// same instance (it needs to invalidate cache prefixes from the
  /// same source of truth when an enqueued op eventually flushes).
  ChatLocalDatasource get cache => _cache;

  /// Exposes the cache manager — same rationale as [cache].
  CacheManager get cacheManager => _cacheManager;

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    final clearedAt = (await _cache.getClearedAt(roomId)).dataOrNull;
    final hiddenIds =
        (await _cache.getHiddenMessageIds(roomId)).dataOrNull ??
        const <String>{};
    return _cacheManager.resolve<ChatPaginatedResponse<ChatMessage>>(
      key: 'messages:$roomId',
      ttl: _cacheManager.config.ttlMessages,
      policy: cachePolicy,
      fromCache: () async {
        final cachedResult = await _cache.getMessages(
          roomId,
          limit: pagination?.limit,
          before: pagination?.before,
          after: pagination?.after,
        );
        final cached = cachedResult.dataOrNull ?? const <ChatMessage>[];
        if (cached.isEmpty) return null;
        final visible = _stripHidden(cached, hiddenIds);
        if (visible.isEmpty) return null;
        // Conservative: assume more exist if cache returned as many as
        // requested.
        return ChatPaginatedResponse(
          items: visible,
          hasMore: visible.length >= (pagination?.limit ?? 50),
        );
      },
      fromNetwork: () => safeApiCall(() async {
        final json = await rest.get(
          '/rooms/$roomId/messages',
          queryParams: {
            ...?pagination?.toQueryParams(),
            if (unreadOnly != null) 'unreadOnly': unreadOnly.toString(),
          },
        );
        final messages = MessageMapper.fromJsonList(
          json['messages'] as List? ?? [],
        );
        final filtered = _stripHidden(
          _filterByClearedAt(messages, clearedAt),
          hiddenIds,
        );
        return ChatPaginatedResponse(
          items: filtered,
          hasMore: (json['hasMore'] ?? false) as bool,
        );
      }),
      saveToCache: (data) => _cache.saveMessages(roomId, data.items),
    );
  }

  List<ChatMessage> _filterByClearedAt(
    List<ChatMessage> messages,
    DateTime? clearedAt,
  ) {
    if (clearedAt == null) return messages;
    return messages.where((m) => m.timestamp.isAfter(clearedAt)).toList();
  }

  /// Drops any message whose id sits in the locally-hidden set
  /// (`deleteMessageLocally` / "delete for me"). Applied to BOTH
  /// the cache branch (so a stale cached row doesn't survive the
  /// hide) and the network branch (so the next fetch doesn't bring
  /// the tombstone back). The hidden set lives in `_metaBox` via
  /// `hideMessageLocally` and is loaded once at the start of `list`.
  List<ChatMessage> _stripHidden(
    List<ChatMessage> messages,
    Set<String> hiddenIds,
  ) {
    if (hiddenIds.isEmpty) return messages;
    return messages.where((m) => !hiddenIds.contains(m.id)).toList();
  }

  @override
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
  }) async {
    final result = await super.send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
      tempId: tempId,
    );
    if (result.isSuccess) {
      try {
        await _cache.saveMessages(roomId, [result.dataOrThrow]);
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidate('rooms:all');
        _cacheManager.invalidate('rooms:unread');
      } catch (e) {
        logger?.call('warn', 'messages.send: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await super.update(
      roomId,
      messageId,
      text: text,
      metadata: metadata,
    );
    if (result.isSuccess) {
      try {
        final cached =
            (await _cache.getMessages(roomId)).dataOrNull ??
            const <ChatMessage>[];
        final existing = cached.where((m) => m.id == messageId).firstOrNull;
        if (existing != null) {
          final updated = ChatMessage(
            id: existing.id,
            from: existing.from,
            timestamp: existing.timestamp,
            text: text,
            messageType: existing.messageType,
            attachmentUrl: existing.attachmentUrl,
            referencedMessageId: existing.referencedMessageId,
            reaction: existing.reaction,
            reply: existing.reply,
            metadata: metadata ?? existing.metadata,
            receipt: existing.receipt,
          );
          await _cache.updateMessage(roomId, updated);
        }
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidate('rooms:all');
        _cacheManager.invalidate('rooms:unread');
      } catch (e) {
        logger?.call('warn', 'messages.update: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    final result = await super.delete(roomId, messageId);
    if (result.isSuccess) {
      try {
        await _cache.deleteMessage(roomId, messageId);
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidate('rooms:all');
        _cacheManager.invalidate('rooms:unread');
      } catch (e) {
        logger?.call('warn', 'messages.delete: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    final result = await super.markRoomAsRead(
      roomId,
      lastReadMessageId: lastReadMessageId,
    );
    if (result.isSuccess) {
      try {
        await _cache.deleteUnread(roomId);
        _cacheManager.invalidate('rooms:all');
        _cacheManager.invalidate('rooms:unread');
      } catch (e) {
        logger?.call(
          'warn',
          'messages.markRoomAsRead: cache update failed: $e',
        );
      }
    }
    return result;
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) => _cacheManager.resolve<ChatPaginatedResponse<ReadReceipt>>(
    key: 'receipts:$roomId',
    ttl: _cacheManager.config.ttlMessages,
    fromCache: () async {
      final cached =
          (await _cache.getReceipts(roomId)).dataOrNull ??
          const <ReadReceipt>[];
      return cached.isEmpty
          ? null
          : ChatPaginatedResponse(items: cached, hasMore: false);
    },
    fromNetwork: () => super.getRoomReceipts(roomId),
    saveToCache: (data) => _cache.saveReceipts(roomId, data.items),
  );

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId, {
    @Deprecated(
      'Use cachePolicy: CachePolicy.networkOnly instead. '
      'forceRefresh will be removed in 1.0.',
    )
    bool forceRefresh = false,
    CachePolicy? cachePolicy,
  }) {
    // Honor the typed policy if provided; otherwise fall back to the
    // legacy bool. Both true → networkOnly.
    final effectivePolicy =
        cachePolicy ?? (forceRefresh ? CachePolicy.networkOnly : null);
    if (effectivePolicy == CachePolicy.networkOnly) {
      _cacheManager.invalidate('reactions:$roomId:$messageId');
    }
    return _cacheManager.resolve<List<AggregatedReaction>>(
      key: 'reactions:$roomId:$messageId',
      ttl: _cacheManager.config.ttlMessages,
      fromCache: () async {
        final cached =
            (await _cache.getReactions(roomId, messageId)).dataOrNull ??
            const <AggregatedReaction>[];
        return cached.isEmpty ? null : cached;
      },
      fromNetwork: () =>
          super.getReactions(roomId, messageId, cachePolicy: effectivePolicy),
      saveToCache: (data) => _cache.saveReactions(roomId, messageId, data),
    );
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId,
  ) async {
    final result = await super.deleteReaction(roomId, messageId);
    if (result.isSuccess) {
      try {
        await _cache.deleteReactions(roomId, messageId);
        _cacheManager.invalidate('reactions:$roomId:$messageId');
      } catch (e) {
        logger?.call(
          'warn',
          'messages.deleteReaction: cache update failed: $e',
        );
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) async {
    final result = await super.pinMessage(roomId, messageId);
    if (result.isSuccess) _cacheManager.invalidate('pins:$roomId');
    return result;
  }

  @override
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) async {
    final result = await super.unpinMessage(roomId, messageId);
    if (result.isSuccess) {
      _cacheManager.invalidate('pins:$roomId');
      _cache.deletePin(roomId, messageId);
    }
    return result;
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  }) => _cacheManager.resolve<ChatPaginatedResponse<MessagePin>>(
    key: 'pins:$roomId',
    ttl: _cacheManager.config.ttlMessages,
    fromCache: () async {
      final cached =
          (await _cache.getPins(roomId)).dataOrNull ?? const <MessagePin>[];
      return cached.isEmpty
          ? null
          : ChatPaginatedResponse(items: cached, hasMore: false);
    },
    fromNetwork: () => super.listPins(roomId, pagination: pagination),
    saveToCache: (data) => _cache.savePins(roomId, data.items),
  );

  @override
  Future<ChatResult<void>> clearChat(String roomId) => safeVoidCall(() async {
    final now = DateTime.now().toUtc();
    await _cache.setClearedAt(roomId, now);
    await _cache.clearMessages(roomId);
    await _cache.clearPendingMessages(roomId);
    await markRoomAsRead(roomId);
  });

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      safeApiCall(() async => (await _cache.getClearedAt(roomId)).dataOrNull);
}
