import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatTheme', () {
    test('defaults has all sub-themes initialised + flat slots null', () {
      const theme = ChatTheme();
      // Sub-themes default to const empty instances, not null.
      expect(theme.bubble, isA<ChatBubbleTheme>());
      expect(theme.input, isA<ChatInputTheme>());
      expect(theme.roomList, isA<ChatRoomListTheme>());
      expect(theme.markdown, isA<ChatMarkdownTheme>());

      // Flat fields that don't belong to any sub-theme default to null.
      expect(theme.dateSeparatorBackgroundColor, isNull);
      expect(theme.videoHeight, isNull);
      expect(theme.videoPlaceholderColor, isNull);
      expect(theme.videoBorderRadius, isNull);
      expect(theme.contextMenuHandleColor, isNull);
      expect(theme.imageCaptionStyle, isNull);
      expect(theme.imageMaxWidth, isNull);
      expect(theme.linkPreviewDomainStyle, isNull);
      expect(theme.avatarOnlineBorderColor, isNull);
    });

    test('ChatTheme.defaults is a valid const', () {
      expect(ChatTheme.defaults, isA<ChatTheme>());
      expect(ChatTheme.defaults.l10n.today, 'Today');
    });

    test('sub-theme slots can be set + read back', () {
      const theme = ChatTheme(
        input: ChatInputTheme(
          editingBackgroundColor: Colors.red,
          editingBorderColor: Colors.orange,
        ),
        bubble: ChatBubbleTheme(senderNameStyle: TextStyle(fontSize: 12)),
      );
      expect(theme.input.editingBackgroundColor, Colors.red);
      expect(theme.input.editingBorderColor, Colors.orange);
      expect(theme.bubble.senderNameStyle?.fontSize, 12);
    });

    test('flat slots can be set', () {
      const theme = ChatTheme(
        videoHeight: 200,
        videoBorderRadius: BorderRadius.zero,
      );
      expect(theme.videoHeight, 200);
      expect(theme.videoBorderRadius, BorderRadius.zero);
    });

    test('icon builders default to null inside ChatInputTheme', () {
      const theme = ChatTheme();
      expect(theme.input.attachIconBuilder, isNull);
      expect(theme.input.cameraIconBuilder, isNull);
      expect(theme.input.voiceIconBuilder, isNull);
    });

    test('icon builders can be set + copied via copyWith on the sub-theme', () {
      Widget builder(BuildContext context) => const SizedBox();
      const fallback = Icons.attach_file;
      final theme =
          const ChatTheme(
            input: ChatInputTheme(attachButtonIcon: fallback),
          ).copyWith(
            input: const ChatInputTheme(attachButtonIcon: fallback).copyWith(
              attachIconBuilder: builder,
              cameraIconBuilder: builder,
              voiceIconBuilder: builder,
            ),
          );
      expect(theme.input.attachIconBuilder, isNotNull);
      expect(theme.input.cameraIconBuilder, isNotNull);
      expect(theme.input.voiceIconBuilder, isNotNull);
      expect(theme.input.attachButtonIcon, fallback);
    });
  });

  group('ChatTheme presets — message search', () {
    /// Every `messageSearch*` slot, by name, so a preset that forgets one is
    /// named in the failure instead of showing up as a bare `null`.
    Map<String, Object?> searchSlots(ChatTheme theme) => {
      'backgroundColor': theme.messageSearchBackgroundColor,
      'fieldFillColor': theme.messageSearchFieldFillColor,
      'fieldTextStyle': theme.messageSearchFieldTextStyle,
      'fieldHintStyle': theme.messageSearchFieldHintStyle,
      'fieldCursorColor': theme.messageSearchFieldCursorColor,
      'fieldBorderColor': theme.messageSearchFieldBorderColor,
      'fieldIconColor': theme.messageSearchFieldIconColor,
      'resultTitleStyle': theme.messageSearchResultTitleStyle,
      'resultSnippetStyle': theme.messageSearchResultSnippetStyle,
      'resultHighlightStyle': theme.messageSearchResultHighlightStyle,
      'resultTimestampStyle': theme.messageSearchResultTimestampStyle,
      'emptyTextStyle': theme.messageSearchEmptyTextStyle,
      'progressColor': theme.messageSearchProgressColor,
    };

    for (final entry in <String, ChatTheme Function()>{
      'lightPreset': ChatTheme.lightPreset,
      'darkPreset': ChatTheme.darkPreset,
    }.entries) {
      test('${entry.key} dresses the search screen like every other surface', () {
        final theme = entry.value();
        final unset = searchSlots(
          theme,
        ).entries.where((slot) => slot.value == null).map((s) => s.key);

        expect(
          unset,
          isEmpty,
          reason: 'a preset that skips a slot leaves the search screen half '
              'stock-Material inside a fully themed app',
        );
        expect(theme.messageSearchFieldBorderRadius, isNotNull);
        expect(
          theme.messageSearchProgressColor,
          theme.input.sendButtonColor,
          reason: 'the spinner is the preset accent, same as the fallback '
              'chain would have picked',
        );
      });
    }

    test('the light preset keeps the chat wallpaper off the search page', () {
      final light = ChatTheme.lightPreset();

      expect(
        light.messageSearchBackgroundColor,
        isNot(light.backgroundColor),
        reason: 'the beige wallpaper behind a tabbed list of results reads '
            'as a stray panel, the same reasoning the gallery slots carry',
      );
      expect(
        light.messageSearchBackgroundColor,
        light.input.backgroundColor,
        reason: 'it is the preset surface colour, not a colour of its own',
      );
    });

    test('the two presets read as light and dark, not as one palette', () {
      final light = ChatTheme.lightPreset();
      final dark = ChatTheme.darkPreset();

      expect(
        light.messageSearchBackgroundColor,
        isNot(dark.messageSearchBackgroundColor),
      );
      expect(
        light.messageSearchResultTitleStyle!.color,
        isNot(dark.messageSearchResultTitleStyle!.color),
      );
      expect(
        light.messageSearchFieldBorderColor,
        isNot(dark.messageSearchFieldBorderColor),
      );
    });

    test('the search rows borrow the room list typography of their preset', () {
      for (final theme in [ChatTheme.lightPreset(), ChatTheme.darkPreset()]) {
        expect(
          theme.messageSearchResultTitleStyle,
          theme.roomList.nameStyle,
          reason: 'a result row is a room-list row with a different subtitle',
        );
        expect(
          theme.messageSearchResultSnippetStyle,
          theme.roomList.previewStyle,
        );
        expect(
          theme.messageSearchResultTimestampStyle,
          theme.roomList.timestampStyle,
        );
      }
    });

    test('branded tints only the accent-carrying search slots', () {
      const accent = Color(0xFFE91E63);
      final theme = ChatTheme.branded(accent: accent);

      expect(theme.messageSearchFieldCursorColor, accent);
      expect(theme.messageSearchProgressColor, accent);
      expect(theme.messageSearchResultHighlightStyle?.color, accent);
      expect(
        theme.messageSearchResultHighlightStyle?.fontWeight,
        FontWeight.w700,
      );
      // A brand colour is a tint, not a palette: the surfaces and the body
      // copy stay on the fallback chain, like everywhere else in `branded`.
      expect(theme.messageSearchBackgroundColor, isNull);
      expect(theme.messageSearchFieldFillColor, isNull);
      expect(theme.messageSearchResultTitleStyle, isNull);
      expect(theme.messageSearchResultSnippetStyle, isNull);
    });
  });

  group('ChatUiLocalizations', () {
    test('en has send and recordVoice', () {
      expect(ChatUiLocalizations.en.send, 'Send');
      expect(ChatUiLocalizations.en.recordVoice, 'Record voice message');
    });

    test('es has send and recordVoice', () {
      expect(ChatUiLocalizations.es.send, 'Enviar');
      expect(ChatUiLocalizations.es.recordVoice, 'Grabar mensaje de voz');
    });
  });
}
