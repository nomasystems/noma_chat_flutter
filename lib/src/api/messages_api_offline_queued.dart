import '../_internal/cache/offline_queue.dart';
import '../core/result.dart';
import '../models/message.dart';
import 'messages_api_cached.dart';
import 'messages_api_rest.dart';

/// True when [failure] should land the mutation in the offline queue.
///
/// A [NetworkFailure] always qualifies. A [TimeoutFailure] qualifies
/// when the operation is [idempotent] (re-running it cannot create a
/// duplicate) or when the timeout is pre-response — i.e. the request
/// provably never reached the server. A `receive` timeout on a
/// non-idempotent send is deliberately NOT enqueued: the body may have
/// reached the backend, so a blind resend would duplicate the message;
/// the optimistic UI layer keeps it as a failed bubble the user can
/// retry manually instead.
bool _shouldEnqueueAfter(ChatFailure? failure, {required bool idempotent}) {
  if (failure is NetworkFailure) return true;
  if (failure is TimeoutFailure) {
    return idempotent || failure.kind.isPreResponse;
  }
  return false;
}

/// Offline-queue decorator on top of [CachedMessagesApi].
///
/// Wraps the network mutations that are safe to retry asynchronously
/// — `send` and `delete` — so a [NetworkFailure] (or a pre-response
/// [TimeoutFailure]) result enqueues a matching [PendingOperation] for
/// the next reconnect drain.
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
    String? clientMessageId,
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
      clientMessageId: clientMessageId,
    );
    if (result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: false)) {
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
          // Reuse the same idempotency key on every retry so the server
          // dedups a delivery that actually succeeded before the failure
          // surfaced (returns the persisted message, no duplicate).
          clientMessageId: clientMessageId,
        ),
      );
    }
    return result;
  }

  @override
  Future<ChatResult<void>> delete(String roomId, String messageId) async {
    final result = await super.delete(roomId, messageId);
    if (result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
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
