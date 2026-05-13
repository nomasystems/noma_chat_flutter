import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// A single row in the room list showing avatar, name, last message preview,
/// timestamp, unread badge, and muted/pinned indicators.
class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.lastMessageSenderName,
    this.currentUserId,
    this.theme = ChatTheme.defaults,
    this.leadingBuilder,
    this.trailingBuilder,
    this.subtitleBuilder,
    this.lastMessagePreviewBuilder,
    this.typingUserNameResolver,
    this.onAcceptInvitation,
    this.onRejectInvitation,
  });

  final RoomListItem room;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? lastMessageSenderName;
  final String? currentUserId;
  final ChatTheme theme;
  final Widget Function(BuildContext, RoomListItem)? leadingBuilder;
  final Widget Function(BuildContext, RoomListItem)? trailingBuilder;
  final Widget Function(BuildContext, RoomListItem)? subtitleBuilder;

  /// Optional override for the last-message preview text. When this builder
  /// returns a non-null string, it is used verbatim as the subtitle (with the
  /// usual sender prefix and receipt icon applied). When it returns `null`,
  /// the default WhatsApp-style preview kicks in.
  ///
  /// Useful for consumers that want to render domain-specific previews for
  /// system/event messages while keeping the default render for regular chat.
  final String? Function(BuildContext, RoomListItem)? lastMessagePreviewBuilder;

  /// Resolves the display name of a user actively typing in [room]. When `null`
  /// or the resolver returns `null`/empty, the tile falls back to a generic
  /// "typing" label without a name.
  final String? Function(String userId)? typingUserNameResolver;

  final VoidCallback? onAcceptInvitation;
  final VoidCallback? onRejectInvitation;

  String _formatTimestamp(DateTime time) {
    return DateFormatter.formatRelative(time, l10n: theme.l10n);
  }

  @override
  Widget build(BuildContext context) {
    final leading =
        leadingBuilder?.call(context, room) ??
        UserAvatar(
          imageUrl: room.avatarUrl,
          displayName: room.name,
          size: 48,
          isOnline: room.isGroup ? null : room.isOnline,
          presenceStatus: room.isGroup ? null : room.presenceStatus,
          theme: theme,
          excludeSemantics: true,
        );

    final trailing =
        trailingBuilder?.call(context, room) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (room.lastMessageTime != null)
              Text(
                _formatTimestamp(room.lastMessageTime!),
                style: room.unreadCount > 0
                    ? (theme.roomTimestampUnreadTextStyle ??
                          theme.roomTimestampTextStyle ??
                          TextStyle(
                            fontSize: 12,
                            color: theme.unreadBadgeColor ?? Colors.red,
                          ))
                    : (theme.roomTimestampTextStyle ??
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (room.muted)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: theme.mutedIconColor ?? Colors.grey,
                    ),
                  ),
                if (room.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.push_pin_outlined,
                      size: 16,
                      color: theme.pinnedIconColor ?? Colors.grey,
                    ),
                  ),
                if (room.unreadCount > 0)
                  UnreadBadge(count: room.unreadCount, theme: theme),
              ],
            ),
          ],
        );

    final subtitle =
        subtitleBuilder?.call(context, room) ?? _buildDefaultSubtitle(context);

    return Semantics(
      label: room.displayName,
      container: true,
      child: Material(
        color: isSelected
            ? (theme.roomTileSelectedColor ?? Colors.blue.shade50)
            : (theme.roomTileBackgroundColor ?? Colors.transparent),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 28,
              right: 16,
              top: 12,
              bottom: 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        room.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (theme.roomNameTextStyle ??
                                    const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ))
                                .copyWith(
                                  fontWeight: room.unreadCount > 0
                                      ? FontWeight.w700
                                      : null,
                                ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        subtitle,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isOwnLastMessage =>
      currentUserId != null && room.lastMessageUserId == currentUserId;

  Widget? _buildDefaultSubtitle(BuildContext context) {
    if (room.isInvitation) {
      return Row(
        children: [
          _InvitationButton(
            label: theme.l10n.accept,
            color: theme.sendButtonColor ?? Colors.blue,
            onTap: onAcceptInvitation,
          ),
          const SizedBox(width: 8),
          _InvitationButton(
            label: theme.l10n.reject,
            color: theme.contextMenuDestructiveColor ?? Colors.red,
            onTap: onRejectInvitation,
          ),
        ],
      );
    }

    if (room.typingUserIds.isNotEmpty) {
      return _buildTypingSubtitle();
    }

    final overrideText = lastMessagePreviewBuilder?.call(context, room);
    final body =
        overrideText ??
        buildLastMessagePreview(room, theme.l10n, currentUserId: currentUserId);

    if (body == null) return null;

    final hasUnread = room.unreadCount > 0;
    final defaultStyle =
        theme.roomPreviewTextStyle ??
        TextStyle(fontSize: 14, color: Colors.grey.shade600);
    final style = hasUnread
        ? (theme.roomPreviewUnreadTextStyle ??
              defaultStyle.copyWith(fontWeight: FontWeight.w600))
        : defaultStyle;

    final showReceipt = _isOwnLastMessage && room.lastMessageReceipt != null;
    final prefix = _resolvePrefix();
    final fullText = '$prefix$body';

    if (showReceipt) {
      return Row(
        children: [
          MessageStatusIcon(
            status: room.lastMessageReceipt!,
            theme: theme,
            size: 12,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              fullText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }

    return Text(
      fullText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _buildTypingSubtitle() {
    final ids = room.typingUserIds.toList();
    final resolver = typingUserNameResolver;
    final names = <String>[];
    if (resolver != null) {
      for (final id in ids) {
        final n = resolver(id);
        if (n != null && n.isNotEmpty) names.add(n);
      }
    }

    String text;
    if (room.isGroup) {
      if (names.length == 1) {
        text = theme.l10n.typingOne(names.first);
      } else if (names.length == 2) {
        text = theme.l10n.typingTwo(names[0], names[1]);
      } else if (names.length > 2) {
        text = theme.l10n.typingMany(names.length);
      } else if (ids.length > 1) {
        text = theme.l10n.typingMany(ids.length);
      } else {
        text = theme.l10n.typing;
      }
    } else {
      text = theme.l10n.typing;
    }

    final color = theme.sendButtonColor ?? Colors.blue;
    final base = theme.roomPreviewTextStyle ?? const TextStyle(fontSize: 14);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Returns the sender prefix to prepend to the preview body.
  ///
  /// Mirrors WhatsApp behaviour: "Tú: " only in groups when the last message
  /// is mine; sender name in groups when the last message is from someone
  /// else; no prefix in 1-to-1 chats. When the message is deleted, no prefix
  /// is added because the localized text already implies authorship.
  String _resolvePrefix() {
    if (room.lastMessageIsDeleted) return '';
    if (_isOwnLastMessage) {
      return room.isGroup ? '${theme.l10n.previewYouPrefix}: ' : '';
    }
    return lastMessageSenderName != null ? '$lastMessageSenderName: ' : '';
  }
}

class _InvitationButton extends StatelessWidget {
  const _InvitationButton({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
