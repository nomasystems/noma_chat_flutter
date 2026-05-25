import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/room_user.dart';
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

  @override
  State<GroupMembersView> createState() => _GroupMembersViewState();
}

class _GroupMembersViewState extends State<GroupMembersView> {
  List<RoomUser>? _members;
  bool _loading = false;
  String? _error;

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
  }

  @override
  void dispose() {
    widget.adapter.userCacheListenable.removeListener(_onUserCacheChanged);
    super.dispose();
  }

  void _onUserCacheChanged() {
    if (mounted) setState(() {});
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
    final result = await widget.adapter.client.members.list(widget.roomId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.toString();
      }),
      (paginated) {
        setState(() {
          _loading = false;
          _members = _sort(paginated.items);
        });
        // For any member the host resolver can't name yet, pull the
        // profile and seed the adapter's user cache. Without this the
        // row label falls back to the raw id ("9df87f95-…") — the
        // resolver is sync and just reads cache, so we have to
        // proactively warm it. Fire-and-forget; each successful
        // `cacheUsers` triggers a `notifyMembersChanged` that the
        // host's resolver re-evaluates on the next rebuild.
        unawaited(_warmMissingUsers(paginated.items));
      },
    );
  }

  /// Fetches `users.get` for every member whose displayName isn't yet
  /// known to the host resolver. Caches the result via the adapter so
  /// the row label flips from the raw id to the friendly name on next
  /// rebuild. Also re-sorts and re-renders once at the end so the
  /// alphabetical ordering picks up the now-known names.
  Future<void> _warmMissingUsers(List<RoomUser> members) async {
    final missing = <String>[];
    for (final m in members) {
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
            result.failureOrNull?.toString() ?? 'Update role failed',
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
            result.failureOrNull?.toString() ?? 'Remove member failed',
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
    final list = ListView.separated(
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: members.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
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
