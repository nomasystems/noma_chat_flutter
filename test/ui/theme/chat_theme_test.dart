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
