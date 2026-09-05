import 'package:flutter/foundation.dart';

import '../core/pagination.dart';
import '../core/result.dart';
import '../models/contact.dart';
import '../models/host_user.dart';
import '../models/invited_room.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/room.dart';
import '../models/room_user.dart';
import '../models/unread_room.dart';
import '../models/user.dart';

/// A [HostUser] as the cache keeps it: the answer plus the moment it was
/// given, which is the only thing that can tell a fresh name from one the
/// host resolved months ago.
///
/// Stored rather than recomputed because the host's directory is often the
/// slow, expensive side of the app — a contacts sync, a permissioned user
/// service — and a cold start that had to ask it again before painting a
/// single row would show a list of blank titles for as long as that call
/// takes.
@immutable
class CachedHostUser {
  const CachedHostUser({required this.user, required this.updatedAt});

  /// What the host answered.
  final HostUser user;

  /// When the host answered it. Compared against a time-to-live to decide
  /// whether the entry may be painted as-is or has to be asked about again.
  final DateTime updatedAt;

  /// Whether this entry is still within [ttl] as of [now].
  bool isFresh(Duration ttl, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(updatedAt) < ttl;

  Map<String, dynamic> toMap() => {
    'id': user.id,
    'displayName': user.displayName,
    'avatarUrl': user.avatarUrl,
    'gone': user.gone,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Rebuilds an entry from its stored shape, or returns `null` when the
  /// record is unusable (no id, unparseable timestamp). A single corrupt
  /// row costs one name, never the whole box.
  static CachedHostUser? fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    if (id is! String || id.isEmpty) return null;
    final raw = map['updatedAt'];
    final updatedAt = raw is String ? DateTime.tryParse(raw) : null;
    if (updatedAt == null) return null;
    final displayName = map['displayName'];
    final avatarUrl = map['avatarUrl'];
    return CachedHostUser(
      user: HostUser(
        id: id,
        displayName: displayName is String ? displayName : null,
        avatarUrl: avatarUrl is String ? avatarUrl : null,
        gone: map['gone'] == true,
      ),
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedHostUser &&
          other.user == user &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(user, updatedAt);

  @override
  String toString() => 'CachedHostUser($user, updatedAt: $updatedAt)';
}

/// Durable storage for host directory answers, kept as a contract of its
/// own rather than as part of [ChatLocalDatasource].
///
/// The split is deliberate. Everything a [ChatLocalDatasource] holds came
/// from chat; this came from the host application, and a store is free to
/// implement one without the other. Making it a separate interface also
/// means a datasource written against an earlier version of the SDK keeps
/// satisfying [ChatLocalDatasource] unchanged — it simply persists no host
/// names, exactly as it did before this existed.
///
/// A store that also implements this is picked up automatically: the SDK
/// tests the datasource it was given and persists only when it answers to
/// this contract.
///
/// Entries are keyed by the same id chat uses for the person, so a room's
/// member list can be titled straight from the store on the first frame.
/// They are kept apart from [ChatLocalDatasource.saveUsers] on purpose:
/// those are chat's own profiles, these are the host's, and the two
/// disagree often (a contact renamed in the phone book, a colleague
/// titled by role).
abstract class HostUserStore {
  Future<ChatResult<void>> saveHostUsers(List<CachedHostUser> users);
  Future<ChatResult<List<CachedHostUser>>> getHostUsers();
  Future<ChatResult<CachedHostUser?>> getHostUser(String userId);

  /// Forgets every stored answer. For sign-out, and for a host whose
  /// directory changed underneath the SDK — a contacts re-sync, a
  /// permission granted — and wants the next paint to ask again. Does not
  /// touch [ChatLocalDatasource.saveUsers] data.
  Future<ChatResult<void>> clearHostUsers();
}

/// Contract for local data persistence in the chat SDK.
///
/// Every read/write method returns `Future<ChatResult<T>>` so cache I/O
/// failures (Hive disk full, decrypt mismatch, lock contention) surface
/// explicitly instead of being silently absorbed by the caller's
/// try/catch — or worse, conflated with "no data" (`null`). Callers
/// that want the legacy "best-effort" behaviour can `.dataOrNull` the
/// result; callers that want to react to failures can pattern-match.
///
/// Implementations may enforce a max messages per room limit via
/// eviction. [deleteRoom] must cascade to room details, messages,
/// unreads, invited rooms, and the member roster. [dispose] is
/// intentionally NOT wrapped
/// in [ChatResult] — it is a lifecycle hook called once at shutdown and
/// errors there are non-actionable.
abstract class ChatLocalDatasource {
  // Messages
  Future<ChatResult<void>> saveMessages(
    String roomId,
    List<ChatMessage> messages,
  );
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
  });
  Future<ChatResult<void>> updateMessage(String roomId, ChatMessage message);
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId);
  Future<ChatResult<void>> clearMessages(String roomId);
  Future<ChatResult<void>> setClearedAt(String roomId, DateTime timestamp);
  Future<ChatResult<DateTime?>> getClearedAt(String roomId);

  /// "Delete for me" persistence: a per-room set of message IDs the
  /// user explicitly hid via `messages.deleteLocally`. The network
  /// list endpoint has no concept of per-user hiding, so without
  /// this set the tombstone (or the deleted message) re-appears
  /// every time the chat is re-opened. Default implementations are
  /// no-ops so non-persistent datasources (memory) keep working,
  /// at the cost of losing the hidden set on app restart.
  Future<ChatResult<void>> hideMessageLocally(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
  Future<ChatResult<Set<String>>> getHiddenMessageIds(String roomId) async =>
      const ChatSuccess(<String>{});
  Future<ChatResult<void>> clearHiddenMessages(String roomId) async =>
      const ChatSuccess(null);

  // Pending/failed outgoing messages (best-effort persistence).
  // Default implementations are no-ops so alternate datasources stay compatible.
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async => const ChatSuccess(null);
  Future<ChatResult<List<PendingChatMessage>>> getPendingMessages(
    String roomId,
  ) async => const ChatSuccess(<PendingChatMessage>[]);
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
  Future<ChatResult<void>> clearPendingMessages(String roomId) async =>
      const ChatSuccess(null);

  // Rooms
  Future<ChatResult<void>> saveRooms(List<ChatRoom> rooms);
  Future<ChatResult<List<ChatRoom>>> getRooms();
  Future<ChatResult<ChatRoom?>> getRoom(String roomId);
  Future<ChatResult<void>> deleteRoom(String roomId);

  // Room details
  Future<ChatResult<void>> saveRoomDetail(RoomDetail detail);
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId);
  Future<ChatResult<void>> deleteRoomDetail(String roomId);

  // Users
  Future<ChatResult<void>> saveUsers(List<ChatUser> users);
  Future<ChatResult<List<ChatUser>>> getUsers();
  Future<ChatResult<ChatUser?>> getUser(String userId);
  Future<ChatResult<void>> deleteUser(String userId);

  // Contacts
  Future<ChatResult<void>> saveContacts(List<ChatContact> contacts);
  Future<ChatResult<List<ChatContact>>> getContacts();

  // Unreads & invitations
  Future<ChatResult<void>> saveUnreads(List<UnreadRoom> unreads);
  Future<ChatResult<List<UnreadRoom>>> getUnreads();
  Future<ChatResult<void>> saveInvitedRooms(List<InvitedRoom> invitedRooms);
  Future<ChatResult<List<InvitedRoom>>> getInvitedRooms();

  /// Replaces the cached unread set with exactly [unreads], removing any
  /// previously cached room absent from the new list. Use this for an
  /// authoritative `type='all'` room listing so rooms deleted or left on
  /// the server stop reappearing from cache (plain [saveUnreads] merges
  /// and never evicts). The default implementation diffs against
  /// [getUnreads] and [deleteUnread]; datasources with a native
  /// "replace box" primitive should override it for atomicity.
  ///
  /// Kicked rooms are preserved: the backend stops listing a room the
  /// moment the user leaves or is removed, but its unread snapshot is the
  /// last-message preview the read-only chat renders, so evicting it would
  /// blank the row and risk the room vanishing on cold start.
  Future<ChatResult<void>> reconcileUnreads(List<UnreadRoom> unreads) async {
    final current = (await getUnreads()).dataOrNull ?? const <UnreadRoom>[];
    final keep = unreads.map((u) => u.roomId).toSet()
      ..addAll((await getKickedRoomIds()).dataOrNull ?? const <String>{});
    for (final c in current) {
      if (!keep.contains(c.roomId)) {
        await deleteUnread(c.roomId);
      }
    }
    return saveUnreads(unreads);
  }

  // Unreads (individual)
  Future<ChatResult<void>> deleteUnread(String roomId);

  // Reactions
  Future<ChatResult<void>> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  );
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  );
  Future<ChatResult<void>> deleteReactions(String roomId, String messageId);

  // Pins
  Future<ChatResult<void>> savePins(String roomId, List<MessagePin> pins);
  Future<ChatResult<List<MessagePin>>> getPins(String roomId);
  Future<ChatResult<void>> deletePin(String roomId, String messageId);

  // Read receipts
  Future<ChatResult<void>> saveReceipts(
    String roomId,
    List<ReadReceipt> receipts,
  );
  Future<ChatResult<List<ReadReceipt>>> getReceipts(String roomId);

  /// Room member roster, as returned by an UNPAGINATED, UNEXPANDED
  /// `members.list` — the only shape `MembersApi` caches, so one record
  /// per room can never be served to a caller that asked for a different
  /// one. `hasMore` and `totalCount` travel with the items because a hit
  /// that invented them would break the paginator of a large group.
  ///
  /// [getRoomMembers] distinguishes the two "no items" cases the way
  /// [getRoom] / [getRoomDetail] do: `ChatSuccess(null)` means "nothing
  /// stored for this room" and [ChatFailureResult] means "the store could
  /// not be read". Collapsing them would let a `cacheOnly` read answer
  /// "this room has no members" off a box that failed to open.
  ///
  /// Default implementations are no-ops so non-persistent datasources keep
  /// working, at the cost of a roster that does not survive a restart.
  Future<ChatResult<void>> saveRoomMembers(
    String roomId,
    ChatPaginatedResponse<RoomUser> members,
  ) async => const ChatSuccess(null);
  Future<ChatResult<ChatPaginatedResponse<RoomUser>?>> getRoomMembers(
    String roomId,
  ) async => const ChatSuccess(null);
  Future<ChatResult<void>> deleteRoomMembers(String roomId) async =>
      const ChatSuccess(null);

  // Offline queue
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  );
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue();
  Future<ChatResult<void>> clearOfflineQueue();

  // Cache manager TTL timestamps. Persisted so `cacheFirst` survives
  // cold starts: without this, an empty in-memory `_timestamps` map
  // forces every `cacheFirst` resolve to fall through to network even
  // when the Hive box still holds fresh data. Stored in a single
  // meta entry (ISO-millis values) so reads are O(1) at boot.
  // Default impls are no-ops so alternate datasources stay compatible.
  Future<Map<String, DateTime>> loadCacheTimestamps() async =>
      const <String, DateTime>{};
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {}

  // Kicked-rooms registry — WhatsApp-parity. Local-only flag set
  // when the user receives a `user_left` event with themselves as
  // target and an `actorUserId` distinct from themselves. The room
  // gets retained on cold start even though the backend stops
  // returning it via `bulk_conversations` (they're no longer a
  // member). `unmarkKicked` runs on admin re-add (`user_joined`
  // with target = me) or when the user manually deletes the chat
  // via `ChatRoomOption.deleteKickedChat`. Default impls are
  // no-ops so alternate datasources stay compatible.
  Future<ChatResult<void>> markKicked(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<void>> unmarkKicked(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<Set<String>>> getKickedRoomIds() async =>
      const ChatSuccess(<String>{});

  // Deleted-rooms registry — WhatsApp "Delete chat" parity. Local-only
  // per-user marker set when the user taps "Delete chat" (distinct from
  // the `hidden` flag used for "Archive"). A deleted room disappears
  // from BOTH the main list and the Archived section; it reappears
  // empty only when a peer writes again, at which point the resurrection
  // path calls `clearDeletedRoom`. The marker is NEVER evicted (it
  // outlives room/message eviction so a deleted chat does not silently
  // return). Default impls are no-ops so alternate datasources stay
  // compatible (losing the set on restart is acceptable for memory mode).
  Future<ChatResult<void>> addDeletedRoom(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<void>> clearDeletedRoom(String roomId) async =>
      const ChatSuccess(null);
  Future<ChatResult<Set<String>>> getDeletedRoomIds() async =>
      const ChatSuccess(<String>{});

  // Lifecycle
  Future<ChatResult<void>> clear();

  /// Releases resources. Not wrapped in [ChatResult] — lifecycle errors at
  /// shutdown are non-actionable.
  Future<void> dispose();
}
