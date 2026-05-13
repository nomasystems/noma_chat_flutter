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
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.fullEmojiPickerBackgroundColor ??
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.45,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              Navigator.of(sheetContext).pop(emoji.emoji);
            },
            config: Config(
              height: MediaQuery.sizeOf(context).height * 0.45,
              checkPlatformCompatibility: true,
              bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
              searchViewConfig: const SearchViewConfig(
                hintText: 'Search emoji...',
              ),
            ),
          ),
        );
      },
    );
  }
}
