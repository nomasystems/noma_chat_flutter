import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/local_datasource.dart';
import '../../../core/result.dart';
import '../../controller/room_list_controller.dart';
import '../../models/room_list_item.dart';
import '../deleted_room_policy.dart';

/// Signature of the adapter's tagged cache-error swallower, so this helper
/// can be handed the caller's own instead of inventing a second one.
typedef CacheThrowHandlerFactory =
    ChatResult<void> Function(Object error) Function({
      String? op,
      String? roomId,
    });

/// Fallback for callers with no tagged swallower wired (standalone
/// handlers built directly in tests). Same fire-and-forget contract, just
/// without the log line.
ChatResult<void> Function(Object) _silentCacheThrow({
  String? op,
  String? roomId,
}) =>
    (Object _) =>
        const ChatFailureResult<void>(UnexpectedFailure('cache mutator threw'));

/// Removes every local trace of [roomId]: the chat-list row, the open chat
/// controller, and the cached room, detail, messages, unread snapshot and
/// kicked marker.
///
/// This is what [DeletedRoomPolicy.purge] performs, and it is also the body
/// of the user-driven "delete this chat" option
/// (`ChatRoomOption.deleteKickedChat`) — the two must stay literally the
/// same operation, so they share this function.
///
/// The kicked marker is cleared FIRST in intent (all five writes are fired
/// together and not awaited, matching every other cache write in the
/// adapter): without that, the next room-list enrichment pass would rebuild
/// the row from whatever the cache still held and the room would come back.
///
/// Attachment blobs the deleted messages referenced are not touched here.
/// They become orphans and the datasource's own reaper collects them on its
/// usual schedule (`orphanGracePeriod`), which is the same contract every
/// other message-deleting path in the SDK relies on.
@internal
void purgeDeletedRoom({
  required String roomId,
  required RoomListController roomList,
  required ChatLocalDatasource? cache,
  required void Function(String roomId) removeChatController,
  CacheThrowHandlerFactory? swallowCacheThrow,
  String op = 'purgeDeletedRoom',
}) {
  roomList.removeRoom(roomId);
  removeChatController(roomId);
  final c = cache;
  if (c == null) return;
  final report = swallowCacheThrow ?? _silentCacheThrow;
  Future<ChatResult<void>> guard(
    Future<ChatResult<void>> future,
    String step,
  ) => future.catchError(report(op: '$op.$step', roomId: roomId));

  unawaited(guard(c.unmarkKicked(roomId), 'unmarkKicked'));
  unawaited(guard(c.deleteRoom(roomId), 'deleteRoom'));
  unawaited(guard(c.deleteRoomDetail(roomId), 'deleteRoomDetail'));
  unawaited(guard(c.clearMessages(roomId), 'clearMessages'));
  unawaited(guard(c.deleteUnread(roomId), 'deleteUnread'));
}

/// Applies [resolver] to [room], defaulting to
/// [DeletedRoomPolicy.keepReadOnly] when no resolver is wired or when the
/// host's resolver throws.
///
/// Swallowing the throw is deliberate: the fallback is the non-destructive
/// branch, so a broken host predicate degrades to the SDK's historical
/// behaviour instead of wiping a conversation.
@internal
DeletedRoomPolicy resolveDeletedRoomPolicy(
  DeletedRoomPolicyResolver? resolver,
  RoomListItem? room,
) {
  if (resolver == null || room == null) return DeletedRoomPolicy.keepReadOnly;
  try {
    return resolver(room);
  } catch (_) {
    return DeletedRoomPolicy.keepReadOnly;
  }
}
