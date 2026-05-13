import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';

/// Decorates [child] with a "Forwarded" header and optional source room
/// label, used when the underlying message was forwarded from another room.
class ForwardedBubble extends StatelessWidget {
  const ForwardedBubble({
    super.key,
    required this.child,
    this.sourceLabel,
    this.theme = ChatTheme.defaults,
  });

  final Widget child;
  final String? sourceLabel;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forward,
              size: 14,
              color: theme.forwardedLabelColor ?? Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              sourceLabel ?? theme.l10n.forwarded,
              style:
                  theme.forwardedLabelTextStyle ??
                  TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
