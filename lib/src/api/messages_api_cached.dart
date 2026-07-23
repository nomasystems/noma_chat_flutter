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
///   network call. The TTL keys touched by each write (`messages:$roomId`,
///   `rooms:all`, `rooms:unread`) are invalidated BEFORE the underlying
///   datasource write, not after — a concurrent `cacheFirst` reader that
///   interleaves must never observe a "still fresh" TTL paired with a
///   cache write that hasn't landed yet.
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
        // The opaque cursor is seq-based and cannot be mapped onto the local
        // store's timestamp-keyed query, so the cache branch only honours
        // `limit` and always returns the most recent rows it holds. The
        // network branch is the source of truth for cursor-anchored pages;
        // the cache is purely the instant-paint shortcut for the newest page.
        final cachedResult = await _cache.getMessages(
          roomId,
          limit: pagination?.limit,
        );
        final cached = cachedResult.dataOrNull ?? const <ChatMessage>[];
        if (cached.isEmpty) return null;
        final visible = _stripHidden(
          _filterByClearedAt(cached, clearedAt),
          hiddenIds,
        );
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
          nextCursor: json['next'] as String?,
          prevCursor: json['prev'] as String?,
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
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) async {
    final result = await super.send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
      tempId: tempId,
      clientMessageId: clientMessageId,
    );
    if (result.isSuccess) {
      try {
        // Invalidate BEFORE writing: a concurrent cacheFirst reader that
        // slips in between these two steps must see either the pre-send
        // state (TTL still valid, stale-but-consistent snapshot) or a
        // forced re-resolve — never a "fresh" timestamp paired with a
        // cache write that hasn't landed yet.
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidateKeys(const ['rooms:all', 'rooms:unread']);
        final sent = result.dataOrThrow;
        // An ack_mode=async provisional echo must NOT land in the cache:
        // its id does not match the stored message, so the row would be a
        // permanent orphan next to the authoritative one the `new_message`
        // event (or the next list fetch) writes. The invalidations above
        // already force the next read to the network.
        if (!sent.isProvisional) {
          await _cache.saveMessages(roomId, [sent]);
        }
      } catch (e) {
        logger?.call('warn', 'messages.send: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) async {
    // No server-side unit GET exists; answer from the id-indexed local cache
    // first, then fall back to the base list-scan.
    final cached =
        (await _cache.getMessages(roomId)).dataOrNull ?? const <ChatMessage>[];
    final hit = cached.where((m) => m.id == messageId).firstOrNull;
    if (hit != null) return ChatSuccess(hit);
    return super.get(roomId, messageId);
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
        // Invalidate BEFORE writing — see the comment in `send()` for why
        // the ordering matters for a concurrent cacheFirst reader.
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidateKeys(const ['rooms:all', 'rooms:unread']);
        final cached =
            (await _cache.getMessages(roomId)).dataOrNull ??
            const <ChatMessage>[];
        final existing = cached.where((m) => m.id == messageId).firstOrNull;
        if (existing != null) {
          // copyWith preserves every field (isDeleted/isForwarded/isSystem,
          // mimeType/fileName/fileSize/thumbnailUrl, …) that a hand-rolled
          // ChatMessage(...) would drop, and stamps isEdited so a rehydrated
          // attachment renders intact and flagged as edited.
          final updated = existing.copyWith(
            text: text,
            metadata: metadata ?? existing.metadata,
            isEdited: true,
          );
          await _cache.updateMessage(roomId, updated);
        }
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
        // Invalidate BEFORE writing — see the comment in `send()` for why
        // the ordering matters for a concurrent cacheFirst reader.
        _cacheManager.invalidatePrefix('messages:$roomId');
        _cacheManager.invalidateKeys(const ['rooms:all', 'rooms:unread']);
        await _cache.deleteMessage(roomId, messageId);
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
        // Invalidate BEFORE writing — see the comment in `send()` for why
        // the ordering matters for a concurrent cacheFirst reader.
        _cacheManager.invalidateKeys(const ['rooms:all', 'rooms:unread']);
        await _cache.deleteUnread(roomId);
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
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) async {
    final result = await super.addReaction(roomId, messageId, emoji: emoji);
    if (result.isSuccess) {
      // Drop the stale aggregated-reactions cache so the next
      // `getReactions` re-fetches the authoritative counts the backend
      // recomputed after the add. The `ReactionAddedEvent` already
      // refreshes the live UI; this keeps a later cache-first read honest.
      _cacheManager.invalidate('reactions:$roomId:$messageId');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) async {
    final result = await super.deleteReaction(roomId, messageId, emoji: emoji);
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
  Future<ChatResult<void>> clearChat(String roomId) async {
    // Local teardown runs first so the UI reflects the cleared chat
    // immediately; a failure here is surfaced as the result.
    final localResult = await safeVoidCall(() async {
      final now = DateTime.now().toUtc();
      await _cache.setClearedAt(roomId, now);
      await _cache.clearMessages(roomId);
      await _cache.clearPendingMessages(roomId);
    });
    if (localResult.isFailure) return localResult;
    // The server-side read reset is authoritative: propagate its failure
    // instead of swallowing it, otherwise the caller forces unreadCount=0
    // locally while the backend unread stays set.
    return markRoomAsRead(roomId);
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      safeApiCall(() async => (await _cache.getClearedAt(roomId)).dataOrNull);
}
