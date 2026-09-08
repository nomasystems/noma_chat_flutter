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
/// [rawPeerId] is the id of the other side of a one-to-one room, when
/// there is one. It exists so a host that genuinely wants the identifier
/// — a debug build, a directory lookup of its own — can reach it, because
/// the SDK's own default no longer paints it.
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
    this.rawPeerId,
  });

  final RoomListItem currentItem;
  final ChatUser currentUser;
  final RoomDetail? detail;
  final List<ChatUser> otherMembers;
  final bool isDm;
  final String? rawPeerId;
}

/// Resolves the title shown for a room across the SDK (surfaced via
/// [RoomListItem.displayName] and any consumer reading it). Returning
/// `null` opts out and lets the SDK apply its default: for DMs the name
/// the host directory gives for the other member, then that member's own
/// chat `displayName`; for groups the server-provided `room.name`.
///
/// When none of those produces anything the default is nothing — an empty
/// title, never the peer's id. An opaque identifier on screen reads as a
/// bug to the person reading it, and a host that wants a placeholder can
/// paint a better one than the SDK could guess. The id is still reachable
/// through [RoomTitleContext.rawPeerId].
///
/// Use this hook to inject app-specific naming (e.g. nickname books,
/// role-based titles) without forking the SDK or mutating room state.
typedef RoomTitleResolver = String? Function(RoomTitleContext context);
