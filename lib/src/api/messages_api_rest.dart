import 'package:flutter/foundation.dart';

import '../cache/cache_policy.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../_internal/transport/transport_manager.dart';
import '../client/chat_client.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../events/chat_event.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/report.dart';
import '../models/scheduled_message.dart';

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

  @override
  Future<ChatResult<ChatMessage>> get(String roomId, String messageId) =>
      safeApiCall(() async {
        final json = await rest.get('/rooms/$roomId/messages/$messageId');
        return MessageMapper.fromJson(json);
      });

  /// Lists messages in the room identified by [roomId].
  ///
  /// [pagination] — cursor-based paging params. Pass the cursor from
  /// [ChatPaginatedResponse.nextCursor] to fetch the next page. When `null`
  /// the server returns the most recent page (newest messages).
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
  }) => safeApiCall(() async {
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
  Future<ChatResult<void>> deleteReaction(String roomId, String messageId) =>
      safeVoidCall(
        () => rest.delete('/rooms/$roomId/messages/$messageId/reactions'),
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
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query, {
    required String roomId,
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await rest.getWithTotalCount(
      '/messages/search',
      queryParams: {
        'q': query,
        'roomId': roomId,
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

  /// Best-effort clear of [roomId]'s message history. The REST layer
  /// has no notion of "cleared" — the cache decorator overrides this
  /// to also record the cleared-at marker locally.
  @override
  Future<ChatResult<void>> clearChat(String roomId) =>
      safeVoidCall(() => markRoomAsRead(roomId).then((_) {}));

  /// Returns `null` from the REST layer — the cache decorator
  /// overrides this with the locally stored cleared-at marker.
  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) =>
      Future.value(const ChatSuccess<DateTime?>(null));
}
