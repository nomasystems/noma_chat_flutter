import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';
import 'unread_badge.dart';

/// Floating action button that appears when the user scrolls up in the
/// message list, optionally showing an unread badge.
class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.unreadCount = 0,
    this.theme = ChatTheme.defaults,
    this.semanticLabel,
  });

  final bool visible;
  final VoidCallback onPressed;
  final int unreadCount;
  final ChatTheme theme;
  /// Optional Semantics label. When omitted, falls back to the localised
  /// `theme.l10n.scrollToBottom` (shipped in 7 locales).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: UnreadBadge(count: unreadCount, theme: theme),
          ),
        Semantics(
          label: semanticLabel ?? theme.l10n.scrollToBottom,
          button: true,
          child: FloatingActionButton.small(
            onPressed: onPressed,
            backgroundColor:
                theme.scrollToBottomButtonColor ??
                theme.sendButtonColor ??
                Colors.blue,
            child: Icon(
              Icons.keyboard_arrow_down,
              color: theme.scrollToBottomIconColor ?? Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
