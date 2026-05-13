import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatUiLocalizations', () {
    test('en defaults are in English', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.today, 'Today');
      expect(l10n.yesterday, 'Yesterday');
      expect(l10n.writeMessage, 'Write a message');
      expect(l10n.reply, 'Reply');
      expect(l10n.delete, 'Delete');
    });

    test('es has Spanish translations', () {
      const l10n = ChatUiLocalizations.es;
      expect(l10n.today, 'Hoy');
      expect(l10n.yesterday, 'Ayer');
      expect(l10n.writeMessage, 'Escribe un mensaje');
      expect(l10n.reply, 'Responder');
      expect(l10n.delete, 'Eliminar');
    });

    test('custom localizations override defaults', () {
      const l10n = ChatUiLocalizations(today: 'Aujourd\'hui');
      expect(l10n.today, 'Aujourd\'hui');
      expect(l10n.yesterday, 'Yesterday');
    });

    test('theme carries l10n', () {
      const theme = ChatTheme(l10n: ChatUiLocalizations.es);
      expect(theme.l10n.today, 'Hoy');
    });

    test('default theme uses English', () {
      expect(ChatTheme.defaults.l10n.today, 'Today');
    });

    test('en has F4 strings', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.thread, 'Thread');
      expect(l10n.replyInThread, 'Reply in thread');
      expect(l10n.searchMessages, 'Search messages');
      expect(l10n.noResults, 'No results');
      expect(l10n.accept, 'Accept');
      expect(l10n.reject, 'Reject');
      expect(l10n.invitation, 'Invitation');
      expect(l10n.pinnedMessage, 'Pinned message');
    });

    test('es has F4 strings', () {
      const l10n = ChatUiLocalizations.es;
      expect(l10n.thread, 'Hilo');
      expect(l10n.replyInThread, 'Responder en hilo');
      expect(l10n.searchMessages, 'Buscar mensajes');
      expect(l10n.noResults, 'Sin resultados');
      expect(l10n.accept, 'Aceptar');
      expect(l10n.reject, 'Rechazar');
      expect(l10n.invitation, 'Invitaci\u00f3n');
      expect(l10n.pinnedMessage, 'Mensaje fijado');
    });

    test('replies formats count', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.replies(3), '3 replies');

      const esL10n = ChatUiLocalizations.es;
      expect(esL10n.replies(5), '5 respuestas');
    });

    test('copyWith preserves F4 strings', () {
      const l10n = ChatUiLocalizations.en;
      final custom = l10n.copyWith(thread: 'Custom Thread');
      expect(custom.thread, 'Custom Thread');
      expect(custom.replyInThread, 'Reply in thread');
      expect(custom.accept, 'Accept');
      expect(custom.pinnedMessage, 'Pinned message');
    });
  });
}
