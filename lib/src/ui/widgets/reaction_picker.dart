import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Row of selectable emoji used to add a reaction to a message.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.reactions,
    required this.onReactionSelected,
    this.showExpandButton = false,
    this.onExpandTap,
    this.theme = ChatTheme.defaults,
  });

  final List<String> reactions;
  final ValueChanged<String> onReactionSelected;
  final bool showExpandButton;
  final VoidCallback? onExpandTap;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: theme.reactionPickerElevation ?? 4,
      borderRadius:
          theme.reactionPickerBorderRadius ?? BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...reactions.map((emoji) {
              return Semantics(
                label: emoji,
                button: true,
                child: GestureDetector(
                  onTap: () => onReactionSelected(emoji),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(
                        emoji,
                        style: TextStyle(
                          fontSize: theme.reactionPickerEmojiSize ?? 24,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (showExpandButton)
              Semantics(
                label: theme.l10n.moreEmojis,
                button: true,
                child: GestureDetector(
                  onTap: onExpandTap,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        Icons.add,
                        size: (theme.reactionPickerEmojiSize ?? 24) - 2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
