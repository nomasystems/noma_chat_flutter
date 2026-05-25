import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

/// Helpers shared by every bubble that renders the timestamp + receipt
/// status pair at the corner of the bubble (text / image / video /
/// audio / file / forwarded). Each bubble owns its outer layout
/// (Stack, Align, Row...) but the chunk that paints the time and the
/// ticks is identical.
///
/// Keeping this in `bubbles/_bubble_metadata.dart` (private prefix)
/// avoids re-exporting it from the library barrel — host apps customise
/// the visuals through `ChatTheme`, not by composing this widget.
@immutable
class BubbleMetadataRow extends StatelessWidget {
  const BubbleMetadataRow({
    super.key,
    required this.theme,
    required this.isOutgoing,
    this.timestamp,
    this.statusWidget,
    this.gap = 3,
  });

  final ChatTheme theme;
  final bool isOutgoing;
  final DateTime? timestamp;
  final Widget? statusWidget;

  /// Horizontal gap between the timestamp and the status widget. Each
  /// bubble already has subtle differences here (text/image use 3,
  /// file uses 4) so it's a parameter rather than a theme field.
  final double gap;

  /// Resolved text style for the timestamp. Cascades:
  /// `outgoing/incomingTimestampTextStyle` → `timestampTextStyle` → a
  /// neutral fallback. Exposed as a `static` helper so bubbles that
  /// build a richer meta row (e.g. file size · time) can reuse the
  /// same style without instantiating this widget.
  static TextStyle resolveTimestampStyle(ChatTheme theme, bool isOutgoing) =>
      (isOutgoing
          ? theme.bubble.outgoingTimestampStyle
          : theme.bubble.incomingTimestampStyle) ??
      theme.bubble.timestampStyle ??
      TextStyle(fontSize: 11, color: Colors.grey.shade600);

  @override
  Widget build(BuildContext context) {
    if (timestamp == null && statusWidget == null) {
      return const SizedBox.shrink();
    }
    final style = resolveTimestampStyle(theme, isOutgoing);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (timestamp != null)
          Text(DateFormatter.formatTime(timestamp!), style: style),
        if (statusWidget != null) ...[SizedBox(width: gap), statusWidget!],
      ],
    );
  }
}
