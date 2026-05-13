import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Title bar at the top of [RoomListView] with optional selection mode UI
/// and trailing action slot.
class RoomListHeader extends StatelessWidget {
  const RoomListHeader({
    super.key,
    this.title = 'Chats',
    this.isSelecting = false,
    this.selectedCount = 0,
    this.onNewChat,
    this.onCancelSelection,
    this.trailing,
    this.theme = ChatTheme.defaults,
  });

  final String title;
  final bool isSelecting;
  final int selectedCount;
  final VoidCallback? onNewChat;
  final VoidCallback? onCancelSelection;
  final Widget? trailing;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (isSelecting) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCancelSelection,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: Icon(Icons.close)),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$selectedCount',
              style: theme.roomListHeaderSelectedStyle ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ] else ...[
            Expanded(
              child: Text(
                title,
                style:
                    theme.roomListHeaderTextStyle ??
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null)
            trailing!
          else if (!isSelecting && onNewChat != null)
            IconButton(
              icon: const Icon(Icons.edit_square),
              onPressed: onNewChat,
            ),
        ],
      ),
    );
  }
}
