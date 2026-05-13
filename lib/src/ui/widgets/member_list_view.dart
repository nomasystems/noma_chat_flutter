import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// A user paired with their per-room [RoomRole], shown in [MemberListView].
class MemberEntry {
  const MemberEntry({required this.user, this.role = RoomRole.member});
  final ChatUser user;
  final RoomRole role;
}

/// Sorted list of members for a room; offers role badges and admin actions
/// (kick/promote) gated on the caller's [currentUserRole].
class MemberListView extends StatelessWidget {
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

  bool _canManage(MemberEntry entry) {
    if (currentUserRole == null) return false;
    if (currentUserRole == RoomRole.member) return false;
    if (entry.role == RoomRole.owner) return false;
    if (currentUserRole == RoomRole.admin && entry.role == RoomRole.admin) {
      return false;
    }
    return true;
  }

  String _roleLabel(RoomRole role) {
    return switch (role) {
      RoomRole.owner => theme.l10n.owner,
      RoomRole.admin => theme.l10n.admin,
      RoomRole.member => theme.l10n.member,
    };
  }

  Color _roleColor(RoomRole role) {
    return switch (role) {
      RoomRole.owner => Colors.orange,
      RoomRole.admin => Colors.blue,
      RoomRole.member => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: members.length,
      itemBuilder: (context, index) {
        final entry = members[index];
        final canManage = _canManage(entry);

        return ListTile(
          onTap: onTapMember != null ? () => onTapMember!(entry.user) : null,
          leading: UserAvatar(
            imageUrl: entry.user.avatarUrl,
            displayName: entry.user.displayName,
            size: 40,
            theme: theme,
          ),
          title: Text(
            entry.user.displayName ?? entry.user.id,
            style:
                theme.roomNameTextStyle ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Container(
            margin: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _roleColor(entry.role).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _roleLabel(entry.role),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _roleColor(entry.role),
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
                        onRemoveMember?.call(entry.user);
                      case 'change_role':
                        final newRole = entry.role == RoomRole.admin
                            ? RoomRole.member
                            : RoomRole.admin;
                        onChangeRole?.call(entry.user, newRole);
                      case 'ban':
                        onBanMember?.call(entry.user);
                    }
                  },
                  itemBuilder: (_) => [
                    if (onRemoveMember != null)
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(theme.l10n.removeMember),
                      ),
                    if (onChangeRole != null)
                      PopupMenuItem(
                        value: 'change_role',
                        child: Text(theme.l10n.changeRole),
                      ),
                    if (onBanMember != null)
                      PopupMenuItem(value: 'ban', child: Text(theme.l10n.ban)),
                  ],
                )
              : null,
        );
      },
    );
  }
}
