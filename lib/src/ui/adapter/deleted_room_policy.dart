import '../models/room_list_item.dart';

/// What the SDK does with a room the backend says the local user no longer
/// belongs to — a `room_deleted` event over WS/SSE, the equivalent event the
/// polling transport synthesizes when a room drops out of the listing, and
/// the cached "kicked" marker replayed on a cold start.
///
/// Chosen per room by a [DeletedRoomPolicyResolver]; when no resolver is
/// wired every room gets [keepReadOnly], which is what the SDK has always
/// done.
enum DeletedRoomPolicy {
  /// Keep the row in the chat list, read-only, with its full history —
  /// WhatsApp parity. The row flips to `isParticipating == false` (the
  /// composer is replaced by the "no longer a participant" banner) and the
  /// id is persisted as kicked so the room survives cold starts even though
  /// the backend stops returning it. The user removes it by hand through
  /// `ChatRoomOption.deleteKickedChat`, and an admin re-add brings it back
  /// to life.
  ///
  /// The default, and the only behaviour available before this policy
  /// existed.
  keepReadOnly,

  /// Drop the room from the app entirely, with no row left behind: it leaves
  /// the chat list, its open controller is disposed, and every cached trace
  /// (room, detail, messages, unread snapshot, kicked marker) is deleted.
  /// Orphaned attachment blobs are collected by the datasource's own reaper
  /// on its usual schedule.
  ///
  /// For rooms whose lifetime the backend owns and whose history means
  /// nothing to the user once it ends — a support conversation closed by
  /// the operator, a transient broadcast room. A user sitting inside such a
  /// room when it is purged is taken out of it: the SDK fires
  /// `ChatUiAdapter.onRoomRemoved` (and `NomaChatView` pops itself) exactly
  /// as it already does for any other membership revocation.
  purge,
}

/// Host hook that picks the [DeletedRoomPolicy] for one room.
///
/// Called with the room as the SDK last knew it — on the live paths that is
/// the row currently in the chat list, and on a cold start the row rebuilt
/// from cache — so `custom`, `isGroup`, `name` and the rest are all
/// available to decide with:
///
/// ```dart
/// deletedRoomPolicy: (room) => room.custom?['support'] == true
///     ? DeletedRoomPolicy.purge
///     : DeletedRoomPolicy.keepReadOnly,
/// ```
///
/// Must be pure and fast: it runs inside event dispatch and inside every
/// room-list enrichment pass. A resolver that throws is treated as
/// [DeletedRoomPolicy.keepReadOnly] so a host bug can never destroy a
/// user's history.
typedef DeletedRoomPolicyResolver =
    DeletedRoomPolicy Function(RoomListItem room);
