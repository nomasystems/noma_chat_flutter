import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../models/room_user.dart';
import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';
import 'chat_room_options_menu.dart';
import 'user_avatar.dart';

/// Members management view for a group room. Loads the current member
/// list via the SDK adapter, sorts owner → admin → member (alphabetical
/// inside each tier), and exposes per-row actions for admins:
///
/// - "Make admin"   (instant, no confirmation — WhatsApp-style)
/// - "Remove admin" (with confirmation)
/// - "Remove from group" (with confirmation)
///
/// The owner row is never actionable. The local user's own row is also
/// non-actionable: leaving the group is exposed via
/// `ChatRoomOption.leaveGroup` instead.
///
/// Permission gating is purely client-side UX — the backend re-checks
/// the caller's role on every mutation and rejects with 403 otherwise,
/// surfaced through the adapter's `operationErrors` stream.
class GroupMembersView extends StatefulWidget {
  const GroupMembersView({
    super.key,
    required this.adapter,
    required this.roomId,
    required this.currentUserRole,
    this.theme = ChatTheme.defaults,
    this.displayNameResolver,
    this.avatarUrlResolver,
    this.onMessageMember,
    this.onMemberRemoved,
    this.onRoleChanged,
    this.embedded = false,
    this.pageSize = 100,
  });

  /// When `true`, the inner [ListView] becomes `shrinkWrap: true` +
  /// `NeverScrollableScrollPhysics` so the widget can be nested inside
  /// an outer scrollable (e.g. the ListView in [GroupInfoPage]) without
  /// triggering Flutter's "Vertical viewport given unbounded height"
  /// assertion. The pull-to-refresh is dropped in this mode — the
  /// outer scroll already owns the gesture.
  final bool embedded;

  final ChatUiAdapter adapter;
  final String roomId;
  final RoomRole currentUserRole;
  final ChatTheme theme;

  /// Resolver from userId → display name. Return `null` to fall back to
  /// the raw userId rendering. Typically wired to
  /// `adapter.findCachedUser(id)?.displayName`.
  final String? Function(String userId)? displayNameResolver;

  /// Resolver from userId → avatar URL.
  final String? Function(String userId)? avatarUrlResolver;

  /// Optional WhatsApp-style "tap a member to message them" hook. When
  /// non-null, tapping a non-self row invokes this callback (typically
  /// the consumer opens a DM with the target via
  /// `findExistingDmRoom` + `openDirectMessageDraft`). When `null`, tap
  /// on a row does nothing for members; admin/owner viewers still get
  /// the management sheet on long-press. Tap on the local user's own
  /// row is always a no-op.
  final FutureOr<void> Function(String userId)? onMessageMember;

  /// Optional callback fired after a successful kick.
  final FutureOr<void> Function(String userId)? onMemberRemoved;

  /// Optional callback fired after a successful role change.
  final FutureOr<void> Function(String userId, RoomRole role)? onRoleChanged;

  /// Number of members fetched per page via `members.list`'s offset
  /// pagination. The initial load and every subsequent "load more" (fired
  /// when the user scrolls within [_loadMoreThreshold] of the bottom) both
  /// request this many rows. Groups with more members than fit in one
  /// response used to be silently truncated to the backend's default page
  /// size — this makes rosters of any size reachable without loading
  /// hundreds of rows upfront. Defaults to 100.
  final int pageSize;

  @override
  State<GroupMembersView> createState() => _GroupMembersViewState();
}

class _GroupMembersViewState extends State<GroupMembersView> {
  List<RoomUser>? _members;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  final _scrollController = ScrollController();

  static const double _loadMoreThresholdPx = 200;

  bool get _canManage =>
      widget.currentUserRole == RoomRole.owner ||
      widget.currentUserRole == RoomRole.admin;

  @override
  void initState() {
    super.initState();
    _load();
    // Subscribe to the adapter's user cache: when ANOTHER group member
    // changes their avatar / displayName on another device, the
    // `UserUpdatedEvent` updates the cache and emits the listenable.
    // Without this subscription, the affected member's row kept showing
    // the stale avatar until the page was closed and reopened. setState
    // is enough — the ListTile uses `widget.avatarUrlResolver(id)` which
    // already reads the fresh cache on every build.
    widget.adapter.userCacheListenable.addListener(_onUserCacheChanged);
    // Subscribe to membership changes: when a member is added / removed
    // in this room in realtime (`user_joined` / `user_left`), re-fetch
    // the roster so it stays live instead of only refreshing on mount /
    // pull-to-refresh.
    widget.adapter.roomMembersListenable.addListener(_onRoomMembersChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.adapter.userCacheListenable.removeListener(_onUserCacheChanged);
    widget.adapter.roomMembersListenable.removeListener(_onRoomMembersChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThresholdPx) {
      return;
    }
    _loadMore();
  }

  void _onUserCacheChanged() {
    if (mounted) setState(() {});
  }

  void _onRoomMembersChanged() {
    if (!mounted) return;
    // Only react to changes for the room we're showing. Guard against
    // re-entrancy with the loading flag — a reload is already in flight.
    if (widget.adapter.lastMembersChangedRoomId != widget.roomId) return;
    if (_loading) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    // Guard the leading synchronous setState: `_load` is also invoked
    // from `_updateRole` / `_removeMember` *after* awaiting the host's
    // `onRoleChanged` / `onMemberRemoved` callbacks, during which the
    // page can be popped. Without this re-check the post-await `_load`
    // calls setState on a defunct State (the crash seen in the logs).
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Request the `users` expansion so the backend embeds each member's
    // displayName + avatarUrl in the list response. This is the modern
    // default for rendering a group roster: it eliminates the per-member
    // `GET /users/{id}` N+1 that `_warmMissingUsers` would otherwise fire
    // for every unknown id. On a backend that ignores the param the rows
    // come back bare and we transparently fall back to the warm-up path.
    //
    // Always (re-)fetches page 1 only — this is also the path used to
    // refresh after a mutation or a realtime membership event, where
    // re-requesting every already-loaded page would be wasteful and could
    // reorder rows the user is mid-scroll through. Large-group pagination
    // beyond page 1 is exclusively driven by [_loadMore].
    final result = await widget.adapter.client.members.list(
      widget.roomId,
      pagination: ChatPaginationParams(limit: widget.pageSize),
      expand: const [RoomMemberExpand.users],
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.toString();
      }),
      (paginated) {
        // Seed the adapter cache from the embedded fields BEFORE the first
        // render so the sync resolvers (which read the cache) already have
        // names + avatars on this same frame.
        _seedCacheFromExpanded(paginated.items);
        setState(() {
          _loading = false;
          _hasMore = paginated.hasMore;
          _members = _sort(paginated.items);
        });
        // Only members the expansion did NOT cover still need a profile
        // fetch — typically none when the backend honours `?expand=users`.
        // Fire-and-forget; each successful `cacheUsers` triggers a
        // `notifyMembersChanged` that the host's resolver re-evaluates on
        // the next rebuild.
        unawaited(_warmMissingUsers(paginated.items));
      },
    );
  }

  /// Fetches the next page (offset = current member count) and appends it
  /// to [_members], keeping the existing sort stable for already-loaded
  /// rows. Triggered by [_onScroll] once the user nears the bottom of a
  /// group whose roster didn't fit in a single page.
  Future<void> _loadMore() async {
    if (!mounted || _loading || _loadingMore || !_hasMore) return;
    final currentCount = _members?.length ?? 0;
    setState(() => _loadingMore = true);
    final result = await widget.adapter.client.members.list(
      widget.roomId,
      pagination: ChatPaginationParams(
        limit: widget.pageSize,
        offset: currentCount,
      ),
      expand: const [RoomMemberExpand.users],
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loadingMore = false;
        // Keep whatever page is already loaded; only surface the error via
        // a snackbar since `_error` would otherwise blank the existing list.
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(failure.toString())));
      }),
      (paginated) {
        _seedCacheFromExpanded(paginated.items);
        setState(() {
          _loadingMore = false;
          _hasMore = paginated.hasMore;
          final merged = [...?_members, ...paginated.items];
          _members = _sort(merged);
        });
        unawaited(_warmMissingUsers(paginated.items));
      },
    );
  }

  /// Seeds the adapter user cache from the `displayName` / `avatarUrl`
  /// embedded by the `users` expansion, merging onto any richer cached
  /// entry so we never clobber a previously fetched bio/email/config.
  /// This is what makes the expanded list render names + avatars without
  /// a single extra request.
  void _seedCacheFromExpanded(List<RoomUser> members) {
    final seed = <ChatUser>[];
    for (final m in members) {
      if (m.displayName == null && m.avatarUrl == null) continue;
      final existing = widget.adapter.findCachedUser(m.userId);
      seed.add(
        (existing ?? ChatUser(id: m.userId)).copyWith(
          displayName: m.displayName ?? existing?.displayName,
          avatarUrl: m.avatarUrl ?? existing?.avatarUrl,
        ),
      );
    }
    if (seed.isNotEmpty) widget.adapter.cacheUsers(seed);
  }

  /// Fetches `users.get` for every member whose displayName isn't yet
  /// known to the host resolver. Caches the result via the adapter so
  /// the row label flips from the raw id to the friendly name on next
  /// rebuild. Also re-sorts and re-renders once at the end so the
  /// alphabetical ordering picks up the now-known names.
  ///
  /// With the `users` expansion in [_load] this normally finds nothing to
  /// fetch — it stays as a resilient fallback for backends that ignore the
  /// expansion or omit a particular member's profile.
  Future<void> _warmMissingUsers(List<RoomUser> members) async {
    final missing = <String>[];
    for (final m in members) {
      // The expansion already gave us this member's name — skip the fetch.
      if (m.displayName != null && m.displayName!.trim().isNotEmpty) continue;
      final name = widget.displayNameResolver?.call(m.userId)?.trim();
      if (name == null || name.isEmpty) missing.add(m.userId);
    }
    if (missing.isEmpty) return;
    final fetched = await Future.wait(
      missing.map((id) => widget.adapter.client.users.get(id)),
    );
    if (!mounted) return;
    final users = [
      for (final r in fetched)
        if (r case ChatSuccess(data: final u)) u,
    ];
    if (users.isEmpty) return;
    widget.adapter.cacheUsers(users);
    if (!mounted) return;
    setState(() {
      final current = _members;
      if (current != null) _members = _sort(current);
    });
  }

  List<RoomUser> _sort(List<RoomUser> members) {
    int rank(RoomRole r) => switch (r) {
      RoomRole.owner => 0,
      RoomRole.admin => 1,
      RoomRole.member => 2,
    };
    String label(RoomUser m) {
      final name = widget.displayNameResolver?.call(m.userId);
      return (name != null && name.trim().isNotEmpty)
          ? name.trim().toLowerCase()
          : m.userId.toLowerCase();
    }

    return [...members]..sort((a, b) {
      final byRank = rank(a.role).compareTo(rank(b.role));
      if (byRank != 0) return byRank;
      return label(a).compareTo(label(b));
    });
  }

  Future<void> _openActions(RoomUser target) async {
    final l10n = widget.theme.l10n;
    final options = <ChatRoomOption>[];
    if (target.role == RoomRole.member) {
      options.add(
        ChatRoomOption(
          icon: const Icon(Icons.shield_outlined),
          label: l10n.makeAdmin,
          onTap: () => _updateRole(target.userId, RoomRole.admin),
        ),
      );
    } else if (target.role == RoomRole.admin) {
      options.add(
        ChatRoomOption(
          icon: const Icon(Icons.shield_outlined),
          label: l10n.removeAdmin,
          onTap: () => _updateRole(target.userId, RoomRole.member),
          confirmation: ChatRoomOptionConfirmation(
            title: l10n.removeAdminConfirmTitle,
            body: l10n.removeAdminConfirmBody,
            acceptLabel: l10n.removeAdmin,
            cancelLabel: l10n.cancel,
          ),
        ),
      );
    }
    options.add(
      ChatRoomOption(
        icon: const Icon(Icons.person_remove_outlined),
        label: l10n.removeMember,
        destructive: true,
        onTap: () => _removeMember(target.userId),
        confirmation: ChatRoomOptionConfirmation(
          title: l10n.removeMemberConfirmTitle,
          body: l10n.removeMemberConfirmBody,
          acceptLabel: l10n.removeMember,
          cancelLabel: l10n.cancel,
        ),
      ),
    );
    await ChatRoomOptionsMenu.show(
      context: context,
      options: options,
      theme: widget.theme,
    );
  }

  Future<void> _updateRole(String userId, RoomRole newRole) async {
    final result = await widget.adapter.updateMemberRole(
      widget.roomId,
      userId,
      newRole,
    );
    if (!mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.toString() ??
                widget.theme.l10n.updateRoleFailed,
          ),
        ),
      );
      return;
    }
    if (widget.onRoleChanged != null) {
      await widget.onRoleChanged!(userId, newRole);
    }
    await _load();
  }

  Future<void> _removeMember(String userId) async {
    final result = await widget.adapter.rooms.removeMember(
      widget.roomId,
      userId,
    );
    if (!mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.toString() ??
                widget.theme.l10n.removeMemberFailed,
          ),
        ),
      );
      return;
    }
    if (widget.onMemberRemoved != null) {
      await widget.onMemberRemoved!(userId);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _members == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_members == null || _members!.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final members = _members ?? const <RoomUser>[];
    final currentUserId = widget.adapter.currentUser.id;
    // `embedded` mode nests this list (shrinkWrap + non-scrolling physics)
    // inside a host-owned outer scrollable — this widget can't observe that
    // outer scroll position, so `_onScroll`'s auto-load-near-bottom never
    // fires there. A tappable "load more" row is the fallback that keeps
    // pagination reachable in embedded mode instead of silently truncating
    // the roster to the first page.
    final showLoadMoreRow = widget.embedded && _hasMore && !_loadingMore;
    final showFooter = _loadingMore || showLoadMoreRow;
    final list = ListView.separated(
      controller: _scrollController,
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: members.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        if (index >= members.length) {
          if (showLoadMoreRow) {
            return ListTile(
              title: Center(
                child: Text(
                  widget.theme.l10n.loadMore,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              onTap: _loadMore,
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final m = members[index];
        final resolvedName = widget.displayNameResolver?.call(m.userId);
        final displayName =
            (resolvedName != null && resolvedName.trim().isNotEmpty)
            ? resolvedName.trim()
            : m.userId;
        final avatarUrl = widget.avatarUrlResolver?.call(m.userId);
        final badge = _badgeFor(m.role);
        final isSelf = m.userId == currentUserId;
        final canActOn = _canManage && !isSelf && m.role != RoomRole.owner;
        // Tap = WhatsApp's "message this person" (when wired). Self
        // row is always inert. Admin/owner viewers also get the
        // management sheet on long-press.
        final tap = isSelf
            ? null
            : widget.onMessageMember == null
            ? null
            : () => widget.onMessageMember!(m.userId);
        final longPress = canActOn ? () => _openActions(m) : null;
        // Surface the management menu as a visible
        // overflow button next to the role badge. Long-press was
        // discoverable only to power users; admins reported "no
        // sale el rol ni botones" — the explicit `more_vert` tap
        // makes promote/demote/remove obvious. The role badge keeps
        // its place so the trailing area shows BOTH (badge + menu).
        final trailing = badge == null && !canActOn
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (badge != null) badge,
                  if (canActOn) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      tooltip: widget.theme.l10n.manage,
                      onPressed: () => _openActions(m),
                    ),
                  ],
                ],
              );
        return ListTile(
          leading: UserAvatar(
            imageUrl: avatarUrl,
            displayName: displayName,
            size: 40,
            theme: widget.theme,
            excludeSemantics: true,
          ),
          title: Text(displayName),
          // No `@<uuid>` subtitle. The id is an internal opaque
          // value, not a mention handle — surfacing it here was
          // misleading. Mentions resolve via displayName + the
          // autocomplete overlay in the composer; the id never
          // leaves the SDK.
          subtitle: null,
          trailing: trailing,
          onTap: tap,
          onLongPress: longPress,
        );
      },
    );
    if (widget.embedded) return list;
    return RefreshIndicator(onRefresh: _load, child: list);
  }

  Widget? _badgeFor(RoomRole role) {
    final l10n = widget.theme.l10n;
    final label = switch (role) {
      RoomRole.owner => l10n.owner,
      RoomRole.admin => l10n.admin,
      RoomRole.member => null,
    };
    if (label == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
