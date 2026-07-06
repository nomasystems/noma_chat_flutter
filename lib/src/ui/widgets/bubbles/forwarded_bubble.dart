import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

/// Decorates [child] with a "Forwarded" header and optional source room
/// label, used when the underlying message was forwarded from another room.
class ForwardedBubble extends StatelessWidget {
  const ForwardedBubble({
    super.key,
    required this.child,
    this.sourceLabel,
    this.sourceTimestamp,
    this.theme = ChatTheme.defaults,
  });

  final Widget child;
  final String? sourceLabel;

  /// When the source message's original timestamp is known, it's rendered
  /// next to [sourceLabel] (e.g. "Forwarded from Alpha Team · 12/03") — the
  /// same "when it was originally sent" context WhatsApp shows on forwarded
  /// messages. `null` (default, and the common case today: the SDK doesn't
  /// yet persist the original timestamp server-side) renders just the label,
  /// same as before this field existed.
  final DateTime? sourceTimestamp;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final timestamp = sourceTimestamp;
    final label = sourceLabel ?? theme.l10n.forwarded;
    final headerText = timestamp == null
        ? label
        : '$label · ${DateFormatter.formatSeparator(timestamp)}';
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
              color: theme.bubble.forwardedLabelColor ?? Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              headerText,
              style:
                  theme.bubble.forwardedLabelStyle ??
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
