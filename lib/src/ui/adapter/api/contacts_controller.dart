part of '../chat_ui_adapter.dart';

/// Contact / blocked-users operations exposed by
/// [ChatUiAdapter.contacts].
///
/// Holds the [blockedUserIds] snapshot (replaceable wholesale, e.g.
/// from a fresh `/users/me` payload) and the one-shot bootstrap
/// ([loadBlocked]) plus mutations (`block` / `unblock`). The
/// idempotent [pruneBlockedRooms] helper re-runs the DM-prune pass
/// without changing the set itself — useful right after [load].
final class ChatContactsController {
  ChatContactsController(this._a);

  final ChatUiAdapter _a;

  /// Snapshot of users blocked by the current user. Used by the
  /// adapter to drop DM rooms whose `otherUserId` falls inside the
  /// set, both at resolution time and when the set itself changes.
  Set<String> get blockedUserIds => _a._blockedUsers.all;

  /// Replaces the blocked-users set wholesale and prunes DM rooms
  /// whose `otherUserId` is now blocked. Fires
  /// [ChatUiAdapter.onBlockedUsersChanged]. Idempotent — same set
  /// twice is a no-op.
  set blockedUserIds(Set<String> ids) {
    _a._blockedUsers.replaceAll(ids);
  }

  /// Re-runs the blocked-rooms prune. Idempotent — useful after a
  /// [ChatUiAdapter.rooms.load] when the consumer wants to drop any
  /// rows that materialised for already-blocked contacts.
  void pruneBlockedRooms() => _a._roomListMutator.removeBlockedRooms();

  /// One-shot bootstrap of [blockedUserIds] from
  /// `client.contacts.listBlocked()`. Replaces the set and fires
  /// the change callback. Not polled — subsequent mutations come
  /// from [block] / [unblock] (local sources of truth).
  Future<ChatResult<void>> loadBlocked() async {
    final result = await _a.client.contacts.listBlocked();
    if (_a._disposed) return const ChatSuccess(null);
    if (result.isFailure) {
      return _a._emitFailure(
        result.castFailure<void>(),
        OperationKind.loadBlockedUsers,
      );
    }
    blockedUserIds = result.dataOrThrow.items.toSet();
    return const ChatSuccess(null);
  }

  /// Blocks [userId]. If [roomId] is provided (typical for the
  /// "block + delete DM" path), the DM row is removed locally too.
  Future<ChatResult<void>> block(String userId, {String? roomId}) async {
    final result = await _a.client.contacts.block(userId);
    if (result.isSuccess) {
      // Registry fires onChanged → adapter prunes + forwards to
      // `onBlockedUsersChanged`. No need to duplicate the callback here.
      _a._blockedUsers.block(userId);
    }
    return _a._emitFailure(
      result,
      OperationKind.blockContact,
      roomId: roomId,
      userId: userId,
    );
  }

  /// Unblocks [userId]. The user re-enters the visible contact set;
  /// any previously hidden DM room remains hidden until the next
  /// message lands or the consumer re-fetches.
  Future<ChatResult<void>> unblock(String userId) async {
    final result = await _a.client.contacts.unblock(userId);
    if (result.isSuccess) {
      // Registry fires onChanged on real removals → forwards to
      // `onBlockedUsersChanged` for us.
      _a._blockedUsers.unblock(userId);
    }
    return _a._emitFailure(
      result,
      OperationKind.unblockContact,
      userId: userId,
    );
  }
}
