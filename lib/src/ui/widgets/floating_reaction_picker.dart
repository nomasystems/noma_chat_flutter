import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';
import 'full_emoji_picker.dart';
import 'reaction_picker.dart';

/// Floating overlay that shows predefined reactions near a message.
///
/// Appears anchored to [anchorRect] (the message's screen position),
/// choosing above or below depending on available space.
/// Includes a "+" button to open [FullEmojiPicker].
///
/// Returns the selected emoji string, or `null` if dismissed.
class FloatingReactionPicker {
  FloatingReactionPicker._();

  static const _expandSentinel = '__expand__';

  static Future<String?> show(
    BuildContext context, {
    required Rect anchorRect,
    required List<String> reactions,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss reaction picker',
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, __) {
        return _FloatingPickerLayout(
          anchorRect: anchorRect,
          reactions: reactions,
          theme: theme,
          dialogContext: dialogContext,
        );
      },
    );

    if (result == _expandSentinel && context.mounted) {
      return FullEmojiPicker.show(context, theme: theme);
    }

    return result;
  }
}

class _FloatingPickerLayout extends StatelessWidget {
  const _FloatingPickerLayout({
    required this.anchorRect,
    required this.reactions,
    required this.theme,
    required this.dialogContext,
  });

  final Rect anchorRect;
  final List<String> reactions;
  final ChatTheme theme;
  final BuildContext dialogContext;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    const pickerHeight = 56.0;
    const margin = 8.0;

    final spaceAbove = anchorRect.top - padding.top;
    final showAbove = spaceAbove > pickerHeight + margin;

    final top = showAbove
        ? anchorRect.top - pickerHeight - margin
        : anchorRect.bottom + margin;

    final pickerWidth = (reactions.length + 1) * 48.0 + 16;
    var left = anchorRect.center.dx - pickerWidth / 2;
    left = left.clamp(margin, screenSize.width - pickerWidth - margin);

    return Stack(
      children: [
        Positioned(
          top: top,
          left: left,
          child: ReactionPicker(
            reactions: reactions,
            showExpandButton: true,
            onReactionSelected: (emoji) {
              Navigator.of(dialogContext).pop(emoji);
            },
            onExpandTap: () {
              Navigator.of(dialogContext).pop(FloatingReactionPicker._expandSentinel);
            },
            theme: theme,
          ),
        ),
      ],
    );
  }
}
