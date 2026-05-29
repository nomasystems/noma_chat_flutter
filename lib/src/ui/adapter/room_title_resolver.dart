import '../../models/room.dart';
import '../../models/user.dart';
import '../models/room_list_item.dart';

/// Snapshot of the data the SDK has about a room when it needs to
/// pick a title. Passed to [RoomTitleResolver] so consumers can build
/// app-specific naming.
///
/// [currentItem] is the row currently being titled (may already carry
/// a `name`/`subject` from the backend, or be a freshly-created blank).
/// [currentUser] is the logged-in user.
/// [detail] is the most recent [RoomDetail] when one has been fetched
/// (always present after the bulk-enrich pass, may be null for rows
/// hydrated only from `UnreadRoom`).
/// [otherMembers] is the list of room members minus the current user
/// when available — populated for DMs and for groups whose member list
/// has been resolved.
/// [isDm] is the adapter's best current guess of whether this room is
/// a direct message. The adapter precomputes it via the
/// [IsDmRoomPredicate] when [detail] is available, or carries it
/// forward from prior enrichment state when only [otherMembers] is
/// available. A custom resolver can ignore it; the SDK's built-in
/// default only fires when [isDm] is true.
class RoomTitleContext {
  const RoomTitleContext({
    required this.currentItem,
    required this.currentUser,
    this.detail,
    this.otherMembers = const [],
    this.isDm = false,
  });

  final RoomListItem currentItem;
  final ChatUser currentUser;
  final RoomDetail? detail;
  final List<ChatUser> otherMembers;
  final bool isDm;
}

/// Resolves the title shown for a room across the SDK (surfaced via
/// [RoomListItem.displayName] and any consumer reading it). Returning
/// `null` opts out and lets the SDK apply its default: for DMs the
/// other member's `displayName` (falling back to their id); for
/// groups the server-provided `room.name`. Use this hook to inject
/// app-specific naming (e.g. nickname books, role-based titles)
/// without forking the SDK or mutating room state.
typedef RoomTitleResolver = String? Function(RoomTitleContext context);
