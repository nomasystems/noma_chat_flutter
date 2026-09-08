import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Full emoji picker shown as a bottom sheet.
///
/// Wraps [emoji_picker_flutter] to isolate the third-party dependency.
/// Returns the selected emoji string, or `null` if dismissed.
class FullEmojiPicker {
  FullEmojiPicker._();

  static Future<String?> show(
    BuildContext context, {
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return theme.showSheet<String>(
      context,
      backgroundColor: theme.fullEmojiPickerBackgroundColor,
      useRootNavigator: false,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        final background =
            theme.fullEmojiPickerBackgroundColor ??
            theme.sheetBackgroundColor(sheetContext);
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.45,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              Navigator.of(sheetContext).pop(emoji.emoji);
            },
            config: Config(
              height: MediaQuery.sizeOf(context).height * 0.45,
              checkPlatformCompatibility: true,
              bottomActionBarConfig: const BottomActionBarConfig(
                enabled: false,
              ),
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: background,
                noRecents: Text(
                  theme.l10nOf(sheetContext).noRecentEmoji,
                  style: TextStyle(
                    fontSize: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: background,
                iconColor: colors.onSurfaceVariant,
                iconColorSelected: colors.primary,
                indicatorColor: colors.primary,
                backspaceColor: colors.primary,
              ),
              skinToneConfig: SkinToneConfig(
                dialogBackgroundColor: background,
                indicatorColor: colors.onSurfaceVariant,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: background,
                buttonIconColor: colors.onSurfaceVariant,
                hintText: theme.l10nOf(sheetContext).searchEmoji,
              ),
            ),
          ),
        );
      },
    );
  }
}
