import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Small numeric badge clamped to [maxCount] (shown as `99+` past the cap).
/// Used in room tiles and the scroll-to-bottom button.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({
    super.key,
    required this.count,
    this.maxCount = 99,
    this.theme = ChatTheme.defaults,
  });

  final int count;
  final int maxCount;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final label = count > maxCount ? '$maxCount+' : '$count';

    return Semantics(
      label: '$count ${theme.l10n.unreadMessages}',
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: theme.unreadBadgeColor ?? Colors.red,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            label,
            style:
                theme.unreadBadgeTextStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}
