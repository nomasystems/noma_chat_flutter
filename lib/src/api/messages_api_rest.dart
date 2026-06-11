import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../cache/cache_policy.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../_internal/transport/transport_manager.dart';
import '../client/chat_client.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/starred_message.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/report.dart';
import '../models/scheduled_message.dart';

const Uuid _uuid = Uuid();

/// REST-only implementation of [ChatMessagesApi]. The plain network
/// layer with no cache integration and no offline queue — both live
/// in dedicated decorators ([CachedMessagesApi],
/// [OfflineQueuedMessagesApi]) so each concern stays cohesive and
/// independently testable.
///
/// Construction sites pick the layer they need:
///
/// - `PollingTransport` / `ManualTransport` instantiate this directly
///   — they want REST-only against the backend and don't share the
///   primary cache.
/// - The primary chain wraps this in cache + queue decorators.
class RestMessagesApi implements ChatMessagesApi {
  RestMessagesApi({required this.rest, this.transport, this.logger});

  @protected
  final RestClient rest;

  @protected
  final TransportManager? transport;

  @protected
  final void Function(String level, String message)? logger;

  /// Monotonic counter shared across instances — used to disambiguate
  /// optimistic / pending message ids generated within the same
  /// millisecond. Decorators (cache, offline queue) read this from
  /// the base layer when they need to assign a pending id.
  @protected
  static int pendingSeq = 0;

  /// Resolves a single message by id. The backend exposes no unit GET on
  /// `/rooms/{roomId}/messages/{messageId}` (only PUT/DELETE), so this
  /// scans the most recent page of the list endpoint. Older messages
  /// outside that page are not found here; the cache decorator answers
  /// from the id-indexed local store first.
  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) async {
    final page = await list(roomId);
    switch (page) {
      case ChatSuccess(:final data):
        final found = data.items.where((m) => m.id == messageId).firstOrNull;
        return found != null
            ? ChatSuccess(found)
            : const ChatFailureResult(NotFoundFailure('message not found'));
      case ChatFailureResult(:final failure):
        return ChatFailureResult(failure);
    }
  }

  /// Lists messages in the room identified by [roomId].
  ///
  /// [pagination] — bidirectional cursor paging params. To load older history
  /// pass [ChatPaginatedResponse.prevCursor] as the cursor with
  /// `direction: ChatCursorDirection.older`; to catch up on newer messages pass
  /// [ChatPaginatedResponse.nextCursor] with `direction: ChatCursorDirection.newer`.
  /// When `null` the server returns the most recent page (newest messages).
  ///
  /// [unreadOnly] — when `true` returns only messages the current user has not
  /// read yet. Defaults to `null` (all messages).
  ///
  /// [cachePolicy] — cache strategy. The cache decorator layer honours this;
  /// the REST layer ignores it and always fetches from the network.
  ///
  /// Returns [ChatSuccess] holding a [ChatPaginatedResponse] of [ChatMessage]
  /// items, newest-first. [ChatPaginatedResponse.hasMore] indicates whether
  /// an older page exists.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.messages.list(
  ///   roomId,
  ///   pagination: ChatCursorPaginationParams(limit: 30),
  /// );
  /// switch (result) {
  ///   case ChatSuccess(:final data): renderMessages(data.items);
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> list(
    String roomId, {
    ChatCursorPaginationParams? pagination,
    bool? unreadOnly,
    CachePolicy? cachePolicy,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/messages',
      queryParams: {
        ...?pagination?.toQueryParams(),
        if (unreadOnly != null) 'unreadOnly': unreadOnly.toString(),
      },
    );
    final messages = MessageMapper.fromJsonList(
      json['messages'] as List? ?? [],
    );
    return ChatPaginatedResponse(
      items: messages,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
      nextCursor: json['next'] as String?,
      prevCursor: json['prev'] as String?,
    );
  });

  /// Sends a message to the room identified by [roomId] via HTTP POST.
  ///
  /// At least one of [text] or [attachmentUrl] (or [reaction]) should be
  /// provided; the server rejects requests with no content.
  ///
  /// [text] — message body text. Supports Markdown if enabled server-side.
  ///
  /// [messageType] — semantic type of the message. Defaults to
  /// [MessageType.regular]. Use [MessageType.reaction] when [reaction] is set
  /// and [MessageType.forwarded] when [sourceRoomId] is set.
  ///
  /// [referencedMessageId] — ID of the message being replied to or reacted to.
  ///
  /// [reaction] — emoji string (e.g. `'👍'`). Set [messageType] to
  /// [MessageType.reaction] when using this field.
  ///
  /// [attachmentUrl] — publicly reachable URL of the attached file. Use
  /// [AttachmentsApi.upload] to obtain the URL before calling [send].
  ///
  /// [sourceRoomId] — room the message was forwarded from. Set [messageType]
  /// to [MessageType.forwarded] when using this field.
  ///
  /// [metadata] — arbitrary JSON attached to the message. Visible to all
  /// members; do not store secrets here.
  ///
  /// [tempId] — client-generated optimistic ID. Ignored by the REST layer
  /// (used by the offline queue decorator to correlate pending items).
  ///
  /// [clientMessageId] — idempotency key for the send. When omitted the SDK
  /// generates a UUID v4 automatically, so a message retried after a transient
  /// 429/5xx (see [RetryInterceptor]) is de-duplicated server-side instead of
  /// creating a duplicate. Pass your own value only when you need to correlate
  /// the send with an external id; passing the same value twice is safe and
  /// returns the already-created message.
  ///
  /// Returns [ChatSuccess] holding the server-confirmed [ChatMessage].
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.messages.send(
  ///   roomId,
  ///   text: 'Hello!',
  /// );
  /// switch (result) {
  ///   case ChatSuccess(:final data): appendMessage(data);
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
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
    String? clientMessageId,
  }) => safeApiCall(() async {
    // Always carry a clientMessageId. The server-side dedup is a partial
    // unique index over docs that have one, so without it a message retried
    // after a transient 429/5xx would be persisted twice. Autogenerating a
    // UUID v4 when the caller omits the key makes retries safe for every
    // consumer (defaults-sane, Stream/Sendbird style).
    final effectiveClientMessageId = clientMessageId ?? _uuid.v4();
    final json = await rest.post(
      '/rooms/$roomId/messages',
      data: {
        if (text != null) 'text': text,
        'messageType': messageType.name,
        if (referencedMessageId != null)
          'referencedMessageId': referencedMessageId,
        if (reaction != null) 'emoji': reaction,
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
        if (metadata != null) 'metadata': metadata,
        'clientMessageId': effectiveClientMessageId,
      },
    );
    return MessageMapper.fromJson(json);
  });

  @override
  Future<ChatResult<ChatMessage>> sendViaWs(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) {
    if (transport != null && transport!.isWsConnected) {
      transport!.sendMessage(
        roomId,
        text: text,
        messageType: messageType.name,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        sourceRoomId: sourceRoomId,
        metadata: metadata,
      );
      final tempId =
          'temp-ws-${DateTime.now().microsecondsSinceEpoch}-${pendingSeq++}';
      return Future.value(
        ChatSuccess(
          ChatMessage(
            id: tempId,
            from: rest.userId ?? '',
            timestamp: DateTime.now(),
            text: text,
            messageType: messageType,
            attachmentUrl: attachmentUrl,
            referencedMessageId: referencedMessageId,
            reaction: reaction,
            metadata: metadata,
            receipt: ReceiptStatus.sent,
          ),
        ),
      );
    }
    return send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
    );
  }

  @override
  Future<ChatResult<void>> update(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => safeVoidCall(
    () => rest.putVoid(
      '/rooms/$roomId/messages/$messageId',
      data: {'text': text, if (metadata != null) 'metadata': metadata},
    ),
  );

  /// Deletes the message identified by [messageId] in [roomId].
  ///
  /// The current user must be the message author or have admin/owner role in
  /// the room. After a successful delete, other members receive a
  /// [MessageDeletedEvent] in real time.
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.messages.delete(roomId, messageId);
  /// if (result.isSuccess) removeMessageFromUi(messageId);
  /// ```
  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) =>
      safeVoidCall(() => rest.delete('/rooms/$roomId/messages/$messageId'));

  @override
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) {
    if (transport != null && transport!.isWsConnected) {
      transport!.sendReceipt(roomId, messageId, status: status);
      return Future.value(const ChatSuccess(null));
    }
    return safeVoidCall(
      () => rest.putVoid(
        '/rooms/$roomId/messages/$messageId/receipts',
        data: {'status': status.name},
      ),
    );
  }

  @override
  Future<ChatResult<void>> markRoomAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => safeVoidCall(
    () => rest.postVoid(
      '/rooms/$roomId/read',
      data: {
        if (lastReadMessageId != null) 'lastReadMessageId': lastReadMessageId,
      },
    ),
  );

  @override
  Future<ChatResult<void>> markRoomAsDelivered(
    String roomId, {
    required String lastDeliveredMessageId,
  }) {
    if (transport != null && transport!.isWsConnected) {
      transport!.sendDelivered(roomId, lastDeliveredMessageId);
      return Future.value(const ChatSuccess(null));
    }
    // REST fallback: the legacy per-message receipt endpoint with
    // `status=delivered` is rerouted server-side to the same delivered
    // cursor, preserving the consolidated semantics.
    return safeVoidCall(
      () => rest.putVoid(
        '/rooms/$roomId/messages/$lastDeliveredMessageId/receipts',
        data: {'status': ReceiptStatus.delivered.name},
      ),
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ReadReceipt>>> getRoomReceipts(
    String roomId,
  ) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/receipts',
    );
    final receipts = (json['receipts'] as List? ?? [])
        .map(
          (e) => MessageMapper.readReceiptFromJson(e as Map<String, dynamic>),
        )
        .toList();
    return ChatPaginatedResponse(
      items: receipts,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) {
    if (transport != null && transport!.isWsConnected) {
      transport!.sendTyping(roomId, activity: activity.name);
      return Future.value(const ChatSuccess(null));
    }
    final userId = rest.userId;
    if (userId == null) {
      return Future.value(
        const ChatFailureResult(
          ValidationFailure(message: 'userId required for typing'),
        ),
      );
    }
    return safeVoidCall(
      () => rest.putVoid(
        '/rooms/$roomId/users/$userId/activity',
        data: {'activity': activity.name, 'from': userId},
      ),
    );
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getThread(
    String roomId,
    String messageId, {
    ChatCursorPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/messages/$messageId/thread',
      queryParams: pagination?.toQueryParams(),
    );
    return ChatPaginatedResponse(
      items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

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
  }) => safeApiCall(() async {
    final json = await rest.get('/rooms/$roomId/messages/$messageId/reactions');
    return (json['reactions'] as List? ?? [])
        .map((e) => MessageMapper.reactionFromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
  }) => safeVoidCall(
    () => rest.postVoid(
      '/rooms/$roomId/messages/$messageId/reactions',
      data: {'emoji': emoji},
    ),
  );

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
  }) => safeVoidCall(
    () => rest.delete(
      '/rooms/$roomId/messages/$messageId/reactions',
      queryParams: emoji != null ? {'emoji': emoji} : null,
    ),
  );

  @override
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) =>
      safeVoidCall(
        () => rest.putVoid('/rooms/$roomId/messages/$messageId/pin'),
      );

  @override
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) =>
      safeVoidCall(() => rest.delete('/rooms/$roomId/messages/$messageId/pin'));

  @override
  Future<ChatResult<ChatPaginatedResponse<MessagePin>>> listPins(
    String roomId, {
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/pins',
      queryParams: pagination?.toQueryParams(),
    );
    final pins = (json['pins'] as List? ?? [])
        .map((e) => MessageMapper.pinFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: pins,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<void>> starMessage(String roomId, String messageId) =>
      safeVoidCall(
        () => rest.putVoid('/rooms/$roomId/messages/$messageId/star'),
      );

  @override
  Future<ChatResult<void>> unstarMessage(String roomId, String messageId) =>
      safeVoidCall(
        () => rest.delete('/rooms/$roomId/messages/$messageId/star'),
      );

  @override
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> listStarred({
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/starred',
      queryParams: pagination?.toQueryParams(),
    );
    final starred = (json['starred'] as List? ?? [])
        .map((e) => MessageMapper.starredFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: starred,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    String? roomId,
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/messages/search',
      queryParams: {
        'q': query,
        if (roomId != null) 'roomId': roomId,
        ...?pagination?.toQueryParams(),
      },
    );
    return ChatPaginatedResponse(
      items: MessageMapper.fromJsonList(json['messages'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<void>> report(
    String roomId,
    String messageId, {
    required String reason,
  }) => safeVoidCall(
    () => rest.postVoid(
      '/rooms/$roomId/messages/$messageId/report',
      data: {'reason': reason},
    ),
  );

  @override
  Future<ChatResult<ChatPaginatedResponse<MessageReport>>> listReports(
    String roomId, {
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/reports',
      queryParams: pagination?.toQueryParams(),
    );
    final reports = (json['reports'] as List? ?? [])
        .map((e) => MessageMapper.reportFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: reports,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<ScheduledMessage>> schedule(
    String roomId, {
    required DateTime sendAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) => safeApiCall(() async {
    final json = await rest.post(
      '/rooms/$roomId/scheduled-messages',
      data: {
        'sendAt': sendAt.toUtc().toIso8601String(),
        if (text != null) 'text': text,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return MessageMapper.scheduledFromJson(json);
  });

  @override
  Future<ChatResult<ChatPaginatedResponse<ScheduledMessage>>> listScheduled(
    String roomId,
  ) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/rooms/$roomId/scheduled-messages',
    );
    final items = (json['scheduledMessages'] as List? ?? [])
        .map((e) => MessageMapper.scheduledFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: items,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<void>> cancelScheduled(String roomId, String scheduledId) =>
      safeVoidCall(
        () => rest.delete('/rooms/$roomId/scheduled-messages/$scheduledId'),
      );

  /// Clears [roomId]'s message history. The REST layer has no notion of
  /// "cleared", so it maps to a server-side read reset; the cache
  /// decorator overrides this to also record the cleared-at marker
  /// locally. The [markRoomAsRead] result is returned verbatim so a
  /// failed read reset surfaces to the caller instead of being swallowed.
  @override
  Future<ChatResult<void>> clearChat(String roomId) => markRoomAsRead(roomId);

  /// Returns `null` from the REST layer — the cache decorator
  /// overrides this with the locally stored cleared-at marker.
  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      Future.value(const ChatSuccess<DateTime?>(null));
}
