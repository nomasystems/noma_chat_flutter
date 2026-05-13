import '../_internal/cache/cache_manager.dart';
import '../_internal/cache/cache_policy.dart';
import '../_internal/cache/local_datasource.dart';
import '../_internal/cache/offline_queue.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../_internal/transport/transport_manager.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/report.dart';
import '../models/scheduled_message.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatMessagesApi]; assigns monotonic temp ids to
/// optimistic sends and integrates with the offline queue.
class MessagesApi implements ChatMessagesApi {
  static int _pendingSeq = 0;
  final RestClient _rest;
  final TransportManager? _transport;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final OfflineQueue? _offlineQueue;
  final void Function(String level, String message)? _logger;

  MessagesApi({
    required RestClient rest,
    TransportManager? transport,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    OfflineQueue? offlineQueue,
    void Function(String level, String message)? logger,
  })  : _rest = rest,
        _transport = transport,
        _cache = cache,
        _cacheManager = cacheManager,
        _offlineQueue = offlineQueue,
        _logger = logger;

  @override
  Future<Result<ChatMessage>> get(String roomId, String messageId) =>
      safeApiCall(() async {
        final json =
            await _rest.get('/rooms/$roomId/messages/$messageId');
        return MessageMapper.fromJson(json);
      });

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> list(
    String roomId, {
    CursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) async {
    final clearedAt = await _cache?.getClearedAt(roomId);

    if (_cacheManager != null && _cache != null) {
      final key = 'messages:$roomId';
      return _cacheManager.resolve<PaginatedResponse<ChatMessage>>(
        key: key,
        ttl: _cacheManager.config.ttlMessages,
        policy: cachePolicy,
        fromCache: () async {
          final cached = await _cache.getMessages(
            roomId,
            limit: pagination?.limit,
            before: pagination?.before,
            after: pagination?.after,
          );
          if (cached.isEmpty) return null;
          // Conservative: assume more exist if cache returned as many as requested.
          return PaginatedResponse(items: cached, hasMore: cached.length >= (pagination?.limit ?? 50));
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get('/rooms/$roomId/messages', queryParams: {
            ...?pagination?.toQueryParams(),
            if (unreadOnly != null) 'unreadOnly': unreadOnly.toString(),
          });
          final messages = MessageMapper.fromJsonList(json['messages'] as List? ?? []);
          final filtered = _filterByClearedAt(messages, clearedAt);
          return PaginatedResponse(
            items: filtered,
            hasMore: (json['hasMore'] ?? false) as bool,
          );
        }),
        saveToCache: (data) => _cache.saveMessages(roomId, data.items),
      );
    }
    return safeApiCall(() async {
      final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/messages', queryParams: {
        ...?pagination?.toQueryParams(),
        if (unreadOnly != null) 'unreadOnly': unreadOnly.toString(),
      });
      final messages = MessageMapper.fromJsonList(json['messages'] as List? ?? []);
      final filtered = _filterByClearedAt(messages, clearedAt);
      return PaginatedResponse(
        items: filtered,
        hasMore: (json['hasMore'] ?? false) as bool,
        totalCount: totalCount,
      );
    });
  }

  List<ChatMessage> _filterByClearedAt(
    List<ChatMessage> messages,
    DateTime? clearedAt,
  ) {
    if (clearedAt == null) return messages;
    return messages
        .where((m) => m.timestamp.isAfter(clearedAt))
        .toList();
  }

  @override
  Future<Result<ChatMessage>> send(
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
    final result = await safeApiCall(() async {
      final json = await _rest.post('/rooms/$roomId/messages', data: {
        if (text != null) 'text': text,
        'messageType': messageType.name,
        if (referencedMessageId != null)
          'referencedMessageId': referencedMessageId,
        if (reaction != null) 'emoji': reaction,
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
        if (metadata != null) 'metadata': metadata,
      });
      return MessageMapper.fromJson(json);
    });
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.saveMessages(roomId, [result.dataOrNull!]);
        _cacheManager?.invalidatePrefix('messages:$roomId');
      } catch (e) {
        _logger?.call('warn', 'messages.send: cache update failed: $e');
      }
    } else if (result.isFailure &&
        result.failureOrNull is NetworkFailure &&
        _offlineQueue != null) {
      _offlineQueue.enqueue(PendingSendMessage(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}-${_pendingSeq++}',
        roomId: roomId,
        text: text,
        messageType: messageType,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        sourceRoomId: sourceRoomId,
        metadata: metadata,
        tempId: tempId,
      ));
    }
    return result;
  }

  @override
  Future<Result<void>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) {
    if (_transport == null || !_transport.isWsConnected) {
      return Future.value(
          const Failure(NetworkFailure('WebSocket not connected')));
    }
    _transport.sendMessage(
      roomId,
      text: text,
      messageType: messageType.name,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
    );
    return Future.value(const Success(null));
  }

  @override
  Future<Result<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await safeVoidCall(() => _rest.putVoid(
          '/rooms/$roomId/messages/$messageId',
          data: {
            'text': text,
            if (metadata != null) 'metadata': metadata,
          },
        ));
    if (result.isSuccess && _cache != null) {
      try {
        final cached = await _cache.getMessages(roomId);
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
        _cacheManager?.invalidatePrefix('messages:$roomId');
      } catch (e) {
        _logger?.call('warn', 'messages.update: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<Result<void>> delete(String roomId, String messageId) async {
    final result = await safeVoidCall(
        () => _rest.delete('/rooms/$roomId/messages/$messageId'));
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.deleteMessage(roomId, messageId);
        _cacheManager?.invalidatePrefix('messages:$roomId');
      } catch (e) {
        _logger?.call('warn', 'messages.delete: cache update failed: $e');
      }
    } else if (result.isFailure &&
        result.failureOrNull is NetworkFailure &&
        _offlineQueue != null) {
      _offlineQueue.enqueue(PendingDeleteMessage(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}-${_pendingSeq++}',
        roomId: roomId,
        messageId: messageId,
      ));
    }
    return result;
  }

  // Receipts

  @override
  Future<Result<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) {
    if (_transport != null && _transport.isWsConnected) {
      _transport.sendReceipt(roomId, messageId, status: status);
      return Future.value(const Success(null));
    }
    return safeVoidCall(() => _rest.putVoid(
          '/rooms/$roomId/messages/$messageId/receipts',
          data: {'status': status.name},
        ));
  }

  @override
  Future<Result<void>> markRoomAsRead(String roomId,
      {String? lastReadMessageId}) async {
    final result =
        await safeVoidCall(() => _rest.postVoid('/rooms/$roomId/read', data: {
              if (lastReadMessageId != null)
                'lastReadMessageId': lastReadMessageId,
            }));
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.deleteUnread(roomId);
        _cacheManager?.invalidate('rooms:all');
        _cacheManager?.invalidate('rooms:unread');
      } catch (e) {
        _logger?.call('warn', 'messages.markRoomAsRead: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<Result<PaginatedResponse<ReadReceipt>>> getRoomReceipts(String roomId) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<PaginatedResponse<ReadReceipt>>(
        key: 'receipts:$roomId',
        ttl: _cacheManager.config.ttlMessages,
        fromCache: () async {
          final cached = await _cache.getReceipts(roomId);
          return cached.isEmpty ? null : PaginatedResponse(items: cached, hasMore: false);
        },
        fromNetwork: () => safeApiCall(() async {
          final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/receipts');
          final receipts = (json['receipts'] as List? ?? [])
              .map((e) => MessageMapper.readReceiptFromJson(e as Map<String, dynamic>))
              .toList();
          return PaginatedResponse(items: receipts, hasMore: (json['hasMore'] ?? false) as bool, totalCount: totalCount);
        }),
        saveToCache: (data) => _cache.saveReceipts(roomId, data.items),
      );
    }
    return safeApiCall(() async {
      final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/receipts');
      final receipts = (json['receipts'] as List? ?? [])
          .map((e) => MessageMapper.readReceiptFromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedResponse(items: receipts, hasMore: (json['hasMore'] ?? false) as bool, totalCount: totalCount);
    });
  }

  // Typing

  @override
  Future<Result<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) {
    if (_transport != null && _transport.isWsConnected) {
      _transport.sendTyping(roomId, activity: activity.name);
      return Future.value(const Success(null));
    }
    final userId = _rest.userId;
    if (userId == null) {
      return Future.value(
          const Failure(ValidationFailure(message: 'userId required for typing')));
    }
    return safeVoidCall(() => _rest.putVoid(
            '/rooms/$roomId/users/$userId/activity',
            data: {
              'activity': activity.name,
              'from': userId,
            },
          ));
  }

  // Threads

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    CursorPaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount(
          '/rooms/$roomId/messages/$messageId/thread',
          queryParams: pagination?.toQueryParams(),
        );
        return PaginatedResponse(
          items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  // Reactions

  @override
  Future<Result<List<AggregatedReaction>>> getReactions(
      String roomId, String messageId, {bool forceRefresh = false}) {
    if (_cacheManager != null && _cache != null) {
      if (forceRefresh) {
        _cacheManager.invalidate('reactions:$roomId:$messageId');
      }
      return _cacheManager.resolve<List<AggregatedReaction>>(
        key: 'reactions:$roomId:$messageId',
        ttl: _cacheManager.config.ttlMessages,
        fromCache: () async {
          final cached = await _cache.getReactions(roomId, messageId);
          return cached.isEmpty ? null : cached;
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get('/rooms/$roomId/messages/$messageId/reactions');
          return (json['reactions'] as List? ?? [])
              .map((e) => MessageMapper.reactionFromJson(e as Map<String, dynamic>))
              .toList();
        }),
        saveToCache: (data) => _cache.saveReactions(roomId, messageId, data),
      );
    }
    return safeApiCall(() async {
      final json = await _rest.get('/rooms/$roomId/messages/$messageId/reactions');
      return (json['reactions'] as List? ?? [])
          .map((e) => MessageMapper.reactionFromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Result<void>> deleteReaction(String roomId, String messageId) =>
      safeVoidCall(() =>
          _rest.delete('/rooms/$roomId/messages/$messageId/reactions'));

  // Pins

  @override
  Future<Result<void>> pinMessage(String roomId, String messageId) async {
    final result = await safeVoidCall(() =>
        _rest.putVoid('/rooms/$roomId/messages/$messageId/pin'));
    if (result.isSuccess) _cacheManager?.invalidate('pins:$roomId');
    return result;
  }

  @override
  Future<Result<void>> unpinMessage(String roomId, String messageId) async {
    final result = await safeVoidCall(() =>
        _rest.delete('/rooms/$roomId/messages/$messageId/pin'));
    if (result.isSuccess) {
      _cacheManager?.invalidate('pins:$roomId');
      _cache?.deletePin(roomId, messageId);
    }
    return result;
  }

  @override
  Future<Result<PaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    PaginationParams? pagination,
  }) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<PaginatedResponse<MessagePin>>(
        key: 'pins:$roomId',
        ttl: _cacheManager.config.ttlMessages,
        fromCache: () async {
          final cached = await _cache.getPins(roomId);
          return cached.isEmpty ? null : PaginatedResponse(items: cached, hasMore: false);
        },
        fromNetwork: () => safeApiCall(() async {
          final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/pins',
              queryParams: pagination?.toQueryParams());
          final pins = (json['pins'] as List? ?? [])
              .map((e) => MessageMapper.pinFromJson(e as Map<String, dynamic>))
              .toList();
          return PaginatedResponse(items: pins, hasMore: (json['hasMore'] ?? false) as bool, totalCount: totalCount);
        }),
        saveToCache: (data) => _cache.savePins(roomId, data.items),
      );
    }
    return safeApiCall(() async {
      final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/pins',
          queryParams: pagination?.toQueryParams());
      final pins = (json['pins'] as List? ?? [])
          .map((e) => MessageMapper.pinFromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedResponse(items: pins, hasMore: (json['hasMore'] ?? false) as bool, totalCount: totalCount);
    });
  }

  // Search

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    PaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount('/messages/search', queryParams: {
          'q': query,
          'roomId': roomId,
          ...?pagination?.toQueryParams(),
        });
        return PaginatedResponse(
          items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  // Reports

  @override
  Future<Result<void>> report(
          String roomId, String messageId, {required String reason}) =>
      safeVoidCall(() => _rest.postVoid(
            '/rooms/$roomId/messages/$messageId/report',
            data: {'reason': reason},
          ));

  @override
  Future<Result<PaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    PaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/reports',
            queryParams: pagination?.toQueryParams());
        final reports = (json['reports'] as List? ?? [])
            .map((e) =>
                MessageMapper.reportFromJson(e as Map<String, dynamic>))
            .toList();
        return PaginatedResponse(
          items: reports,
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  // Scheduled messages

  @override
  Future<Result<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) =>
      safeApiCall(() async {
        final json =
            await _rest.post('/rooms/$roomId/scheduled-messages', data: {
          'sendAt': sendAt.toUtc().toIso8601String(),
          if (text != null) 'text': text,
          if (metadata != null) 'metadata': metadata,
        });
        return MessageMapper.scheduledFromJson(json);
      });

  @override
  Future<Result<PaginatedResponse<ScheduledMessage>>> listScheduled(
          String roomId) =>
      safeApiCall(() async {
        final (json, totalCount) =
            await _rest.getWithTotalCount('/rooms/$roomId/scheduled-messages');
        final items = (json['scheduledMessages'] as List? ?? [])
            .map((e) =>
                MessageMapper.scheduledFromJson(e as Map<String, dynamic>))
            .toList();
        return PaginatedResponse(
          items: items,
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  @override
  Future<Result<void>> cancelScheduled(String roomId, String scheduledId) =>
      safeVoidCall(() => _rest
          .delete('/rooms/$roomId/scheduled-messages/$scheduledId'));

  @override
  Future<Result<void>> clearChat(String roomId) async {
    try {
      final now = DateTime.now().toUtc();
      await _cache?.setClearedAt(roomId, now);
      await _cache?.clearMessages(roomId);
      await _cache?.clearPendingMessages(roomId);
      await markRoomAsRead(roomId);
      return const Success(null);
    } catch (e) {
      return Failure(
        UnexpectedFailure(e.toString()),
      );
    }
  }

  @override
  Future<DateTime?> getClearedAt(String roomId) async {
    return _cache?.getClearedAt(roomId);
  }
}

