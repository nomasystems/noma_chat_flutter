import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatTheme', () {
    test('defaults has all new properties as null', () {
      const theme = ChatTheme();
      expect(theme.editingBackgroundColor, isNull);
      expect(theme.editingBorderColor, isNull);
      expect(theme.editingLabelStyle, isNull);
      expect(theme.editingPreviewStyle, isNull);
      expect(theme.inputFillColor, isNull);
      expect(theme.sendButtonDisabledColor, isNull);
      expect(theme.dateSeparatorBackgroundColor, isNull);
      expect(theme.replyPreviewSenderStyle, isNull);
      expect(theme.replyPreviewTextStyle, isNull);
      expect(theme.senderNameStyle, isNull);
      expect(theme.avatarOnlineBorderColor, isNull);
      expect(theme.imageCaptionStyle, isNull);
      expect(theme.imageMaxWidth, isNull);
      expect(theme.linkPreviewDomainStyle, isNull);
      expect(theme.videoHeight, isNull);
      expect(theme.videoPlaceholderColor, isNull);
      expect(theme.videoBorderRadius, isNull);
      expect(theme.contextMenuHandleColor, isNull);
    });

    test('ChatTheme.defaults is a valid const', () {
      expect(ChatTheme.defaults, isA<ChatTheme>());
      expect(ChatTheme.defaults.l10n.today, 'Today');
    });

    test('new properties can be set', () {
      const theme = ChatTheme(
        editingBackgroundColor: Colors.red,
        videoHeight: 200,
        videoBorderRadius: BorderRadius.zero,
      );
      expect(theme.editingBackgroundColor, Colors.red);
      expect(theme.videoHeight, 200);
      expect(theme.videoBorderRadius, BorderRadius.zero);
    });

    test('icon builders default to null', () {
      const theme = ChatTheme();
      expect(theme.attachIconBuilder, isNull);
      expect(theme.cameraIconBuilder, isNull);
      expect(theme.voiceIconBuilder, isNull);
    });

    test('icon builders can be set and copied', () {
      Widget builder(BuildContext context) => const SizedBox();
      const fallback = Icons.attach_file;
      final theme = const ChatTheme(attachButtonIcon: fallback).copyWith(
        attachIconBuilder: builder,
        cameraIconBuilder: builder,
        voiceIconBuilder: builder,
      );
      expect(theme.attachIconBuilder, isNotNull);
      expect(theme.cameraIconBuilder, isNotNull);
      expect(theme.voiceIconBuilder, isNotNull);
      expect(theme.attachButtonIcon, fallback);
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
