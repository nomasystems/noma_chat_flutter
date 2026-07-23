import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../controller/chat_controller.dart';
import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
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
    this.userCacheListenable,
    this.peerResolver,
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

  /// Explicit title seed / fallback. Used only when neither the live
  /// `peerResolver()` nor `room?.displayName` yields a non-empty name —
  /// e.g. the first frame before the room/peer resolves, draft DMs not
  /// yet on the room list, or tests. A live peer rename takes precedence.
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

  /// Optional live signal that drives a title/subtitle rebuild whenever the
  /// shared user cache changes — e.g. a peer renaming themselves or updating
  /// their avatar. Merged with the [controller] so the header stays in sync
  /// without the host wiring a manual rebuild. `null` keeps the AppBar
  /// reactive to the controller only.
  final Listenable? userCacheListenable;

  /// Optional resolver for the live peer of a 1:1 chat. When it returns a
  /// user with a non-empty `displayName`, that name takes precedence over
  /// the (possibly stale) `room?.displayName`, so a peer renaming themselves
  /// updates the header live. `null` keeps the title/`room` logic untouched.
  final ChatUser Function()? peerResolver;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _resolveTitle() {
    final livePeerName = peerResolver?.call().displayName?.trim();
    if (livePeerName != null && livePeerName.isNotEmpty) return livePeerName;
    final fromRoom = room?.displayName.trim();
    if (fromRoom != null && fromRoom.isNotEmpty) return fromRoom;
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
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
      } else if (r.lastSeen != null) {
        return theme.l10n.lastSeen(
          DateFormatter.formatRelative(r.lastSeen!, l10n: theme.l10n),
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final animation = userCacheListenable == null
        ? controller
        : Listenable.merge([controller, userCacheListenable]);
    return AnimatedBuilder(
      animation: animation,
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              resolvedTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (room?.pinned == true) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.push_pin,
                              size: 16,
                              color:
                                  theme.roomList.pinnedIconColor ??
                                  Colors.black54,
                              semanticLabel: theme.l10n.pin,
                            ),
                          ],
                          if (room?.muted == true) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 16,
                              color:
                                  theme.roomList.mutedIconColor ??
                                  Colors.black54,
                              semanticLabel: theme.l10n.mute,
                            ),
                          ],
                        ],
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
