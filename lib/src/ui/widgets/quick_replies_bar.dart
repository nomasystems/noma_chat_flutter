import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

/// Horizontal row of one-tap reply chips above the composer.
///
/// The SDK ships the *layout* (scrollable row, theming, semantics);
/// the *content* is fully consumer-driven via [replies]. Apps that
/// need plan-specific or context-aware quick replies build their own
/// list and hand it over — for example, a meeting room could surface
/// "On my way", "Running late", "Confirm".
///
/// Tap dispatches `onReply(reply)`. The bar is purely a chrome widget
/// — it doesn't talk to the adapter directly so the consumer keeps
/// full control over how the reply gets sent (text vs. structured
/// payload, metadata, …).
class QuickRepliesBar extends StatelessWidget {
  const QuickRepliesBar({
    super.key,
    required this.replies,
    required this.onReply,
    this.theme = ChatTheme.defaults,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.chipSpacing = 8,
  });

  /// Plain-text labels rendered as tap chips. Empty list collapses the
  /// bar to zero-height.
  final List<String> replies;

  /// Invoked with the tapped label.
  final ValueChanged<String> onReply;

  final ChatTheme theme;
  final EdgeInsetsGeometry padding;
  final double chipSpacing;

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < replies.length; i++) ...[
              if (i > 0) SizedBox(width: chipSpacing),
              _QuickReplyChip(
                label: replies[i],
                onTap: () => onReply(replies[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickReplyChip extends StatelessWidget {
  const _QuickReplyChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ActionChip(label: Text(label), onPressed: onTap),
    );
  }
}
