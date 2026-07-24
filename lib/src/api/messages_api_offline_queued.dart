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
/// provably never reached the server ([TimeoutKind.connection] or
/// [TimeoutKind.send]). [TimeoutKind.unknown] is NOT pre-response: it
/// is the defensive "phase not available" default, so a non-idempotent
/// operation treats it the same as a `receive` timeout and is not
/// enqueued — the body may have reached the backend, so a blind resend
/// risks a duplicate; the optimistic UI layer keeps it as a failed
/// bubble the user can retry manually instead.
bool _shouldEnqueueAfter(ChatFailure? failure, {required bool idempotent}) {
  if (failure is NetworkFailure) return true;
  if (failure is TimeoutFailure) {
    return idempotent || failure.kind.isPreResponse;
  }
  return false;
}

/// Offline-queue decorator on top of [CachedMessagesApi].
///
/// Wraps the network mutations that are safe to retry asynchronously —
/// `send`, `delete`, `addReaction`, `deleteReaction`, `pinMessage`,
/// `unpinMessage`, `starMessage`, `unstarMessage` — so a [NetworkFailure] (or a
/// pre-response [TimeoutFailure]) result enqueues a matching
/// [PendingOperation] for the next reconnect drain. `send` is the only
/// non-idempotent op among these, so it alone requires the request to
/// have provably never reached the server (see [_shouldEnqueueAfter]);
/// the rest are safe to retry even after a `receive` timeout.
///
/// Other mutations (`update`, `markRoomAsRead`, `report`) are still
/// surfaced as failures to the caller without enqueueing — the
/// optimistic UI layer handles their rollback. Adding more ops to the
/// queue is a one-method override away.
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
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,

    /// Set to `false` when replaying this op from [OfflineQueue.drain] —
    /// the drain loop already owns retry/backoff for the instance it is
    /// replaying (see [OfflineQueue._drainWith]), so enqueueing here too
    /// would leave two copies of the same send in the queue. Defaults to
    /// `true` for every normal (non-replay) caller.
    bool enqueueOnFailure = true,
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
    if (enqueueOnFailure &&
        result.isFailure &&
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
          attachmentId: attachmentId,
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
  Future<ChatResult<void>> delete(
    String roomId,
    String messageId, {
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.delete(roomId, messageId);
    if (enqueueOnFailure &&
        result.isFailure &&
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

  @override
  Future<ChatResult<void>> addReaction(
    String roomId,
    String messageId, {
    required String emoji,
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.addReaction(roomId, messageId, emoji: emoji);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      _offlineQueue.enqueue(
        PendingAddReaction(
          id:
              'pending-${DateTime.now().microsecondsSinceEpoch}'
              '-${RestMessagesApi.pendingSeq++}',
          roomId: roomId,
          messageId: messageId,
          emoji: emoji,
        ),
      );
    }
    return result;
  }

  @override
  Future<ChatResult<void>> deleteReaction(
    String roomId,
    String messageId, {
    String? emoji,
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.deleteReaction(roomId, messageId, emoji: emoji);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      // The drain executor replays this without an emoji (clears the user's
      // reaction wholesale), so the queued op does not carry one — matching
      // the single-reaction-per-user semantics of the omit-emoji path.
      _offlineQueue.enqueue(
        PendingDeleteReaction(
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

  @override
  Future<ChatResult<void>> pinMessage(
    String roomId,
    String messageId, {
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.pinMessage(roomId, messageId);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      _offlineQueue.enqueue(
        PendingPinMessage(
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

  @override
  Future<ChatResult<void>> unpinMessage(
    String roomId,
    String messageId, {
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.unpinMessage(roomId, messageId);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      _offlineQueue.enqueue(
        PendingUnpinMessage(
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

  @override
  Future<ChatResult<void>> starMessage(
    String roomId,
    String messageId, {
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.starMessage(roomId, messageId);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      _offlineQueue.enqueue(
        PendingStarMessage(
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

  @override
  Future<ChatResult<void>> unstarMessage(
    String roomId,
    String messageId, {
    bool enqueueOnFailure = true,
  }) async {
    final result = await super.unstarMessage(roomId, messageId);
    if (enqueueOnFailure &&
        result.isFailure &&
        _shouldEnqueueAfter(result.failureOrNull, idempotent: true)) {
      _offlineQueue.enqueue(
        PendingUnstarMessage(
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
