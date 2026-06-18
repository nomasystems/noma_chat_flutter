import 'package:flutter/material.dart';
import '../../models/presence.dart';
import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

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
    this.rebuildSignal,
    this.userResolver,
  });

  /// Self-wiring variant: resolves [userId] against the adapter's live user
  /// cache on every rebuild and refreshes whenever that cache changes, so the
  /// sheet tracks name / bio / avatar edits (by the user themselves or by the
  /// peer) without the host having to wire [rebuildSignal] / [userResolver].
  /// The captured [user] is the fallback snapshot until the cache resolves.
  factory UserProfileView.live({
    Key? key,
    required ChatUiAdapter adapter,
    required String userId,
    required ChatUser user,
    PresenceStatus? presence,
    ChatTheme theme = ChatTheme.defaults,
    VoidCallback? onBlock,
    VoidCallback? onMute,
    VoidCallback? onStartChat,
  }) {
    return UserProfileView(
      key: key,
      user: user,
      presence: presence,
      theme: theme,
      onBlock: onBlock,
      onMute: onMute,
      onStartChat: onStartChat,
      rebuildSignal: adapter.userCacheListenable,
      userResolver: () => adapter.findCachedUser(userId) ?? user,
    );
  }

  final ChatUser user;
  final PresenceStatus? presence;
  final ChatTheme theme;
  final VoidCallback? onBlock;
  final VoidCallback? onMute;
  final VoidCallback? onStartChat;

  /// Optional live signal that rebuilds the sheet whenever the shared user
  /// cache changes — so a profile edit (name / description / avatar) made by
  /// the user themselves, or by the peer, is reflected while the sheet is
  /// open. `null` renders the captured [user] once.
  final Listenable? rebuildSignal;

  /// Optional resolver returning the freshest snapshot of the displayed user.
  /// Invoked on every rebuild; falls back to the captured [user] when it
  /// returns `null` (or is itself `null`).
  final ChatUser Function()? userResolver;

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
      PresenceStatus.available => theme.l10n.presenceAvailable,
      PresenceStatus.away => theme.l10n.presenceAway,
      PresenceStatus.busy => theme.l10n.presenceBusy,
      PresenceStatus.dnd => theme.l10n.presenceDnd,
      PresenceStatus.offline => theme.l10n.presenceOffline,
    };
  }

  @override
  Widget build(BuildContext context) {
    // `Listenable.merge(const [])` is a Listenable that never notifies — the
    // sheet stays one-shot when no live signal is supplied.
    return ListenableBuilder(
      listenable: rebuildSignal ?? Listenable.merge(const []),
      builder: (context, _) => _buildContent(),
    );
  }

  Widget _buildContent() {
    final u = userResolver?.call() ?? user;
    final hasActions = onStartChat != null || onMute != null || onBlock != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            imageUrl: u.avatarUrl,
            displayName: u.displayName,
            size: 96,
            presenceStatus: presence,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Text(
            u.displayName ?? u.id,
            style:
                theme.roomList.nameStyle ??
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          if (u.bio != null && u.bio!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              u.bio!,
              textAlign: TextAlign.center,
              style:
                  theme.roomList.previewStyle ??
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
                      theme.bubble.timestampStyle ??
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
                    color: theme.input.sendButtonColor ?? Colors.blue,
                  ),
                if (onMute != null) ...[
                  if (onStartChat != null) const SizedBox(width: 12),
                  _ActionButton(
                    label: theme.l10n.mute,
                    icon: Icons.notifications_off_outlined,
                    onPressed: onMute!,
                    color: theme.roomList.mutedIconColor ?? Colors.grey,
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
