import 'package:flutter/material.dart';
import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';

/// Actions available in the long-press menu of a room tile.
enum RoomAction { mute, unmute, pin, unpin, markAsRead, delete }

/// Long-press context menu for a room: returns the selected [RoomAction]
/// (or `null` if dismissed).
class RoomContextMenu extends StatelessWidget {
  const RoomContextMenu({
    super.key,
    required this.room,
    this.enabledActions,
    this.onAction,
    this.theme = ChatTheme.defaults,
  });

  final RoomListItem room;
  final Set<RoomAction>? enabledActions;
  final ValueChanged<RoomAction>? onAction;
  final ChatTheme theme;

  static Future<RoomAction?> show(
    BuildContext context, {
    required RoomListItem room,
    Set<RoomAction>? enabledActions,
    Widget Function(BuildContext, RoomListItem)? builder,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    );

    if (builder != null) {
      return showModalBottomSheet<RoomAction>(
        context: context,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        useRootNavigator: true,
        builder: (ctx) => builder(ctx, room),
      );
    }

    return showModalBottomSheet<RoomAction>(
      context: context,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      useRootNavigator: true,
      builder: (ctx) => RoomContextMenu(
        room: room,
        enabledActions: enabledActions,
        theme: theme,
        onAction: (action) => Navigator.of(ctx).pop(action),
      ),
    );
  }

  List<_MenuEntry> _buildEntries() {
    final entries = <_MenuEntry>[];
    final allowed = enabledActions;
    final l10n = theme.l10n;

    if (room.muted) {
      if (allowed == null || allowed.contains(RoomAction.unmute)) {
        entries.add(
          _MenuEntry(
            icon: Icons.notifications_active_outlined,
            label: l10n.unmute,
            action: RoomAction.unmute,
          ),
        );
      }
    } else {
      if (allowed == null || allowed.contains(RoomAction.mute)) {
        entries.add(
          _MenuEntry(
            icon: Icons.notifications_off_outlined,
            label: l10n.mute,
            action: RoomAction.mute,
          ),
        );
      }
    }

    if (room.pinned) {
      if (allowed == null || allowed.contains(RoomAction.unpin)) {
        entries.add(
          _MenuEntry(
            icon: Icons.push_pin,
            label: l10n.unpin,
            action: RoomAction.unpin,
          ),
        );
      }
    } else {
      if (allowed == null || allowed.contains(RoomAction.pin)) {
        entries.add(
          _MenuEntry(
            icon: Icons.push_pin_outlined,
            label: l10n.pin,
            action: RoomAction.pin,
          ),
        );
      }
    }

    if (room.unreadCount > 0) {
      if (allowed == null || allowed.contains(RoomAction.markAsRead)) {
        entries.add(
          _MenuEntry(
            icon: Icons.done_all,
            label: l10n.markAsRead,
            action: RoomAction.markAsRead,
          ),
        );
      }
    }

    if (allowed == null || allowed.contains(RoomAction.delete)) {
      entries.add(
        _MenuEntry(
          icon: Icons.delete_outline,
          label: l10n.delete,
          action: RoomAction.delete,
          isDestructive: true,
        ),
      );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.contextMenuHandleColor ?? Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map(
            (entry) => ListTile(
              leading: Icon(
                entry.icon,
                color: entry.isDestructive
                    ? (theme.contextMenuDestructiveColor ?? Colors.red)
                    : null,
              ),
              title: Text(
                entry.label,
                style: entry.isDestructive
                    ? TextStyle(
                        color: theme.contextMenuDestructiveColor ?? Colors.red,
                      )
                    : null,
              ),
              onTap: () => onAction?.call(entry.action),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuEntry {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.action,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final RoomAction action;
  final bool isDestructive;
}
