import '../_internal/cache/offline_queue.dart';
import '../core/result.dart';
import '../models/message.dart';
import 'messages_api_cached.dart';
import 'messages_api_rest.dart';

/// Offline-queue decorator on top of [CachedMessagesApi].
///
/// Wraps the network mutations that are safe to retry asynchronously
/// — `send` and `delete` — so a [NetworkFailure] result enqueues a
/// matching [PendingOperation] for the next reconnect drain.
///
/// Other mutations (`update`, `markRoomAsRead`, `pinMessage`,
/// `unpinMessage`, reactions, `report`) are still surfaced as
/// failures to the caller without enqueueing — the optimistic UI
/// layer handles their rollback. Adding more ops to the queue is a
/// one-method override away.
class OfflineQueuedMessagesApi extends CachedMessagesApi {
  OfflineQueuedMessagesApi({
    required super.rest,
    super.transport,
    required super.cache,
    required super.cacheManager,
    required OfflineQueue offlineQueue,
    super.logger,
  }) : _offlineQueue = offlineQueue;

  final OfflineQueue _offlineQueue;

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
    if (result.isFailure && result.failureOrNull is NetworkFailure) {
      _offlineQueue.enqueue(
        PendingSendMessage(
          id:
              'pending-${DateTime.now().microsecondsSinceEpoch}'
              '-${RestMessagesApi.pendingSeq++}',
          roomId: roomId,
          text: text,
          messageType: messageType,
          referencedMessageId: referencedMessageId,
          reaction: reaction,
          attachmentUrl: attachmentUrl,
          sourceRoomId: sourceRoomId,
          metadata: metadata,
          tempId: tempId,
        ),
      );
    }
    return result;
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    final result = await super.delete(roomId, messageId);
    if (result.isFailure && result.failureOrNull is NetworkFailure) {
      _offlineQueue.enqueue(
        PendingDeleteMessage(
          id:
              'pending-${DateTime.now().microsecondsSinceEpoch}'
              '-${RestMessagesApi.pendingSeq++}',
          roomId: roomId,
          messageId: messageId,
        ),
      );
    }
    return result;
  }
}
