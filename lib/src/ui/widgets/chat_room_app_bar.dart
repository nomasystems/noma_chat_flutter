import 'package:flutter/material.dart';

import '../controller/chat_controller.dart';
import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// Drop-in AppBar for a chat room.
///
/// Renders a WhatsApp-style header: small avatar, room title and a
/// dynamic subtitle (typing… → online → last seen → member count) — all
/// driven by the bound [ChatController] and the optional [room].
///
/// Defaults are sensible: 1:1 chats show "online / last seen" derived
/// from [room]; groups show member count and the comma-separated
/// names of typers when applicable. Override any slot via the
/// `*Builder` props to keep the visual language consistent with the
/// rest of the app (custom avatars, plan-specific subtitle, …).
class ChatRoomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatRoomAppBar({
    super.key,
    required this.controller,
    this.room,
    this.title,
    this.theme = ChatTheme.defaults,
    this.onTap,
    this.onBack,
    this.actions = const [],
    this.avatarBuilder,
    this.subtitleBuilder,
    this.avatarSize = 36,
  });

  /// Live controller for the room — provides typing indicators, draft
  /// state, etc. Listened to via [AnimatedBuilder] so the subtitle stays
  /// in sync without a manual rebuild.
  final ChatController controller;

  /// Live [RoomListItem] for the room. Optional — when present, the
  /// AppBar uses `displayName`, `isOnline`, `presenceStatus` and
  /// `memberCount` to drive the visuals. When null the AppBar still
  /// renders but falls back to the `controller`-only data.
  final RoomListItem? room;

  /// Explicit title override. When non-null, takes precedence over
  /// `room?.displayName` — useful for draft DMs whose name isn't on
  /// the room list yet, or for tests.
  final String? title;

  final ChatTheme theme;

  /// Invoked when the user taps the title row. Typically opens a
  /// "room info" screen.
  final VoidCallback? onTap;

  /// Invoked when the user taps the leading back button. When null the
  /// AppBar's default `Navigator.maybePop` runs.
  final VoidCallback? onBack;

  /// Extra actions rendered on the right side (search, options, …).
  final List<Widget> actions;

  /// Optional avatar override. Receives the room's display name as a
  /// hint; the SDK default builds a [UserAvatar] from
  /// `room.avatarUrl` / initials.
  final Widget Function(BuildContext context)? avatarBuilder;

  /// Optional subtitle override. Receives the resolved subtitle string
  /// (e.g. "typing…", "online", "5 members") and the theme so consumers
  /// can wrap it in their own Text widget; return `null` to suppress
  /// the subtitle entirely.
  final Widget? Function(BuildContext context, String? subtitle)?
  subtitleBuilder;

  final double avatarSize;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _resolveTitle() {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fromRoom = room?.displayName.trim();
    if (fromRoom != null && fromRoom.isNotEmpty) return fromRoom;
    // Never expose the UUID as a title.
    return '';
  }

  String? _resolveSubtitle() {
    // Priority: typers → presence → member count.
    final typers = controller.typingUserIds.toList();
    if (typers.isNotEmpty) {
      final names = typers
          .map((id) {
            final u = controller.otherUsers
                .where((u) => u.id == id)
                .firstOrNull;
            return u?.displayName?.trim().isNotEmpty == true
                ? u!.displayName!.trim()
                : null;
          })
          .whereType<String>()
          .toList();
      if (names.isEmpty) return theme.l10n.typing;
      if (names.length == 1) {
        return theme.l10n.typingOneTemplate.replaceAll('{name}', names[0]);
      }
      if (names.length == 2) {
        return theme.l10n.typingTwoTemplate
            .replaceAll('{name1}', names[0])
            .replaceAll('{name2}', names[1]);
      }
      return theme.l10n.typingManyTemplate.replaceAll(
        '{count}',
        names.length.toString(),
      );
    }

    final r = room;
    if (r != null) {
      if (r.isGroup) {
        final count = r.memberCount;
        if (count != null && count > 0) {
          return '$count ${theme.l10n.members}';
        }
      } else if (r.isOnline == true) {
        return theme.l10n.online;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final resolvedTitle = _resolveTitle();
        final subtitle = _resolveSubtitle();
        final avatar =
            avatarBuilder?.call(context) ??
            UserAvatar(
              imageUrl: room?.avatarUrl,
              displayName: resolvedTitle.isNotEmpty ? resolvedTitle : null,
              size: avatarSize,
              isOnline: room?.isOnline,
              presenceStatus: room?.presenceStatus,
              theme: theme,
            );
        final defaultSubtitle = subtitle == null
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              );
        final subtitleWidget = subtitleBuilder != null
            ? subtitleBuilder!(context, subtitle)
            : defaultSubtitle;

        return AppBar(
          leading: onBack == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: theme.l10n.back,
                  onPressed: onBack,
                ),
          titleSpacing: 0,
          title: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        resolvedTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitleWidget != null) subtitleWidget,
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: actions,
        );
      },
    );
  }
}
