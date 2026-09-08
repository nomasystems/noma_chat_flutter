import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The full emoji picker is a third-party grid inside an SDK sheet: it paints
/// its own background over the sheet's, so every sub-view of its `Config` has
/// to be told the sheet's colour or the sheet shows through as the package's
/// `0xFFEBEFF2`.
void main() {
  const packageDefault = Color(0xFFEBEFF2);
  const lightSheet = Color(0xFFFFFFFF);
  const darkSheet = Color(0xFF1B2E34);

  Widget host(ThemeData themeData, ChatTheme theme) => MaterialApp(
    theme: themeData,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => FullEmojiPicker.show(context, theme: theme),
          child: const Text('open'),
        ),
      ),
    ),
  );

  ThemeData themed(Brightness brightness, Color sheet) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFC9A00),
      brightness: brightness,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: sheet),
  );

  Future<Config> openAndReadConfig(
    WidgetTester tester,
    ThemeData themeData, {
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    await tester.pumpWidget(host(themeData, theme));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.widget<EmojiPicker>(find.byType(EmojiPicker)).config;
  }

  testWidgets('every sub-view takes the sheet colour in light theme', (
    tester,
  ) async {
    final config = await openAndReadConfig(
      tester,
      themed(Brightness.light, lightSheet),
    );

    expect(config.emojiViewConfig.backgroundColor, lightSheet);
    expect(config.categoryViewConfig.backgroundColor, lightSheet);
    expect(config.searchViewConfig.backgroundColor, lightSheet);
    expect(config.skinToneConfig.dialogBackgroundColor, lightSheet);
    expect(config.emojiViewConfig.backgroundColor, isNot(packageDefault));
  });

  testWidgets('and in dark theme, where the package default would glare', (
    tester,
  ) async {
    final themeData = themed(Brightness.dark, darkSheet);
    final config = await openAndReadConfig(tester, themeData);

    expect(config.emojiViewConfig.backgroundColor, darkSheet);
    expect(config.categoryViewConfig.backgroundColor, darkSheet);
    expect(config.searchViewConfig.backgroundColor, darkSheet);
    expect(config.skinToneConfig.dialogBackgroundColor, darkSheet);
  });

  testWidgets('the chrome over that background comes from the colour scheme', (
    tester,
  ) async {
    final themeData = themed(Brightness.dark, darkSheet);
    final colors = themeData.colorScheme;
    final config = await openAndReadConfig(tester, themeData);

    expect(config.categoryViewConfig.iconColor, colors.onSurfaceVariant);
    expect(config.categoryViewConfig.iconColorSelected, colors.primary);
    expect(config.categoryViewConfig.indicatorColor, colors.primary);
    expect(config.categoryViewConfig.backspaceColor, colors.primary);
    expect(config.searchViewConfig.buttonIconColor, colors.onSurfaceVariant);
    expect(config.categoryViewConfig.iconColor, isNot(Colors.grey));
    expect(config.searchViewConfig.buttonIconColor, isNot(Colors.black26));
  });

  testWidgets('the host override still wins over the ambient sheet colour', (
    tester,
  ) async {
    const override = Color(0xFF102030);
    final config = await openAndReadConfig(
      tester,
      themed(Brightness.light, lightSheet),
      theme: ChatTheme.defaults.copyWith(
        fullEmojiPickerBackgroundColor: override,
      ),
    );

    expect(config.emojiViewConfig.backgroundColor, override);
    expect(config.categoryViewConfig.backgroundColor, override);
    expect(config.searchViewConfig.backgroundColor, override);
    expect(config.skinToneConfig.dialogBackgroundColor, override);
  });

  testWidgets('the empty recents line is localized, not the package literal', (
    tester,
  ) async {
    final config = await openAndReadConfig(
      tester,
      themed(Brightness.dark, darkSheet),
      theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.it),
    );

    final noRecents = config.emojiViewConfig.noRecents as Text;
    expect(noRecents.data, ChatUiLocalizations.it.noRecentEmoji);
    expect(noRecents.data, isNot('No Recents'));
    expect(noRecents.style?.color, isNot(Colors.black26));
  });
}
