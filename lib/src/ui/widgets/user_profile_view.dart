import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Profile sheet for a single user: avatar, display name, presence and
/// quick actions (DM, mute, block) supplied by the host app.
class UserProfileView extends StatelessWidget {
  const UserProfileView({
    super.key,
    required this.user,
    this.presence,
    this.theme = ChatTheme.defaults,
    this.onBlock,
    this.onMute,
    this.onStartChat,
  });

  final ChatUser user;
  final PresenceStatus? presence;
  final ChatTheme theme;
  final VoidCallback? onBlock;
  final VoidCallback? onMute;
  final VoidCallback? onStartChat;

  Color _presenceDotColor() {
    return switch (presence!) {
      PresenceStatus.available => theme.presenceAvailableColor ?? Colors.green,
      PresenceStatus.away => theme.presenceAwayColor ?? Colors.amber,
      PresenceStatus.busy => theme.presenceBusyColor ?? Colors.red,
      PresenceStatus.dnd => theme.presenceDndColor ?? Colors.red.shade900,
      PresenceStatus.offline => theme.avatarOfflineColor ?? Colors.grey,
    };
  }

  String _presenceText() {
    return switch (presence!) {
      PresenceStatus.available => 'Available',
      PresenceStatus.away => 'Away',
      PresenceStatus.busy => 'Busy',
      PresenceStatus.dnd => 'Do not disturb',
      PresenceStatus.offline => 'Offline',
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasActions = onStartChat != null || onMute != null || onBlock != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            imageUrl: user.avatarUrl,
            displayName: user.displayName,
            size: 96,
            presenceStatus: presence,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Text(
            user.displayName ?? user.id,
            style:
                theme.roomNameTextStyle ??
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              user.bio!,
              textAlign: TextAlign.center,
              style:
                  theme.roomPreviewTextStyle ??
                  TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
          if (presence != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _presenceDotColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _presenceText(),
                  style:
                      theme.timestampTextStyle ??
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
          if (hasActions) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onStartChat != null)
                  _ActionButton(
                    label: theme.l10n.startChat,
                    icon: Icons.chat_outlined,
                    onPressed: onStartChat!,
                    color: theme.sendButtonColor ?? Colors.blue,
                  ),
                if (onMute != null) ...[
                  if (onStartChat != null) const SizedBox(width: 12),
                  _ActionButton(
                    label: theme.l10n.mute,
                    icon: Icons.notifications_off_outlined,
                    onPressed: onMute!,
                    color: theme.mutedIconColor ?? Colors.grey,
                  ),
                ],
                if (onBlock != null) ...[
                  if (onStartChat != null || onMute != null)
                    const SizedBox(width: 12),
                  _ActionButton(
                    label: theme.l10n.block,
                    icon: Icons.block_outlined,
                    onPressed: onBlock!,
                    color: theme.contextMenuDestructiveColor ?? Colors.red,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
