import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Horizontal pill bar showing per-emoji counts under a message bubble.
class ReactionBar extends StatelessWidget {
  const ReactionBar({
    super.key,
    required this.reactions,
    this.userReactions = const {},
    this.onReactionTap,
    this.onDeleteReaction,
    this.onShowDetail,
    this.theme = ChatTheme.defaults,
  });

  final Map<String, int> reactions;
  final Set<String> userReactions;
  final ValueChanged<String>? onReactionTap;
  final ValueChanged<String>? onDeleteReaction;
  final VoidCallback? onShowDetail;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      children: reactions.entries.map((entry) {
        final isOwn = userReactions.contains(entry.key);
        return Semantics(
          label: '${entry.key} ${entry.value}',
          button: true,
          child: GestureDetector(
            onTap: () {
              if (onShowDetail != null) {
                onShowDetail!();
              } else if (isOwn) {
                onDeleteReaction?.call(entry.key);
              } else {
                onReactionTap?.call(entry.key);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isOwn
                      ? (theme.reactionSelectedColor ??
                          Colors.blue.shade100)
                      : (theme.reactionBackgroundColor ??
                          Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                  border: isOwn
                      ? Border.all(
                          color: theme.reactionSelectedBorderColor ??
                              Colors.blue.shade300,
                        )
                      : null,
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style:
                      theme.reactionTextStyle ?? const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
