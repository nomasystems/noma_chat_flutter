import 'package:flutter/material.dart';
import '../../models/room_user.dart';
import '../../models/user.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// A user paired with their per-room [RoomRole], shown in [MemberListView].
class MemberEntry {
  const MemberEntry({required this.user, this.role = RoomRole.member});
  final ChatUser user;
  final RoomRole role;
}

/// Sorted list of members for a room; offers role badges and admin actions
/// (kick/promote) gated on the caller's [currentUserRole].
class MemberListView extends StatefulWidget {
  const MemberListView({
    super.key,
    required this.members,
    this.currentUserRole,
    this.theme = ChatTheme.defaults,
    this.onTapMember,
    this.onRemoveMember,
    this.onChangeRole,
    this.onBanMember,
  });

  final List<MemberEntry> members;
  final RoomRole? currentUserRole;
  final ChatTheme theme;
  final ValueChanged<ChatUser>? onTapMember;
  final ValueChanged<ChatUser>? onRemoveMember;
  final void Function(ChatUser user, RoomRole newRole)? onChangeRole;
  final ValueChanged<ChatUser>? onBanMember;

  @override
  State<MemberListView> createState() => _MemberListViewState();
}

class _MemberListViewState extends State<MemberListView> {
  /// Every member this list has rendered, each pinned to the slot it first
  /// occupied. Rows the host drops stay in place, hidden instead of
  /// unmounted, so the overflow menu is never torn down inside its own
  /// press.
  late List<MemberEntry> _rendered = widget.members;

  @override
  void didUpdateWidget(MemberListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rendered = _pinHiddenRows(widget.members);
  }

  /// Merges [live] into the rendered roster: entries the host no longer
  /// lists keep the index they had, and the live rows fill the slots that
  /// are left, in the order the host gave them.
  List<MemberEntry> _pinHiddenRows(List<MemberEntry> live) {
    final liveIds = {for (final e in live) e.user.id};
    final pinned = <int, MemberEntry>{};
    for (var i = 0; i < _rendered.length; i++) {
      final e = _rendered[i];
      if (!liveIds.contains(e.user.id)) pinned[i] = e;
    }
    if (pinned.isEmpty) return live;
    final rows = <MemberEntry>[];
    final queue = List<MemberEntry>.of(live);
    var slot = 0;
    while (queue.isNotEmpty || pinned.containsKey(slot)) {
      final hidden = pinned[slot];
      rows.add(hidden ?? queue.removeAt(0));
      slot++;
    }
    return rows;
  }

  bool _canManage(MemberEntry entry) {
    final currentUserRole = widget.currentUserRole;
    if (currentUserRole == null) return false;
    if (currentUserRole == RoomRole.member) return false;
    if (entry.role == RoomRole.owner) return false;
    if (currentUserRole == RoomRole.admin && entry.role == RoomRole.admin) {
      return false;
    }
    return true;
  }

  String _roleLabel(BuildContext context, RoomRole role) {
    return switch (role) {
      RoomRole.owner => widget.theme.l10nOf(context).owner,
      RoomRole.admin => widget.theme.l10nOf(context).admin,
      RoomRole.member => widget.theme.l10nOf(context).member,
    };
  }

  Color _roleColor(BuildContext context, RoomRole role) {
    final colors = Theme.of(context).colorScheme;
    return switch (role) {
      RoomRole.owner => colors.tertiary,
      RoomRole.admin => colors.primary,
      RoomRole.member => colors.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final liveIds = {for (final e in widget.members) e.user.id};
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _rendered.length,
      itemBuilder: (context, index) {
        final entry = _rendered[index];
        final canManage = _canManage(entry);

        return Visibility(
          // Stable identity so Flutter doesn't recycle tiles when the
          // member list reorders (e.g. role change moves a member from
          // member→admin section, owner→admin demote, kick).
          key: ValueKey(entry.user.id),
          visible: liveIds.contains(entry.user.id),
          maintainState: true,
          child: ListTile(
            onTap: widget.onTapMember != null
                ? () => widget.onTapMember!(entry.user)
                : null,
            leading: UserAvatar(
              imageUrl: entry.user.avatarUrl,
              displayName: entry.user.displayName,
              size: 40,
              theme: widget.theme,
            ),
            title: Text(
              entry.user.displayName ?? entry.user.id,
              style:
                  widget.theme.roomList.nameStyle ??
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Container(
              margin: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _roleColor(
                      context,
                      entry.role,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _roleLabel(context, entry.role),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _roleColor(context, entry.role),
                    ),
                  ),
                ),
              ),
            ),
            trailing: canManage
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'remove':
                          widget.onRemoveMember?.call(entry.user);
                        case 'change_role':
                          final newRole = entry.role == RoomRole.admin
                              ? RoomRole.member
                              : RoomRole.admin;
                          widget.onChangeRole?.call(entry.user, newRole);
                        case 'ban':
                          widget.onBanMember?.call(entry.user);
                      }
                    },
                    itemBuilder: (_) => [
                      if (widget.onRemoveMember != null)
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            widget.theme.l10nOf(context).removeMember,
                          ),
                        ),
                      if (widget.onChangeRole != null)
                        PopupMenuItem(
                          value: 'change_role',
                          child: Text(widget.theme.l10nOf(context).changeRole),
                        ),
                      if (widget.onBanMember != null)
                        PopupMenuItem(
                          value: 'ban',
                          child: Text(widget.theme.l10nOf(context).ban),
                        ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}
