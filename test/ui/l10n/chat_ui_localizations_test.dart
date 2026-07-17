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

  group('ChatUiLocalizations.plural', () {
    test('static const instances expose their localeCode', () {
      expect(ChatUiLocalizations.en.localeCode, 'en');
      expect(ChatUiLocalizations.es.localeCode, 'es');
      expect(ChatUiLocalizations.fr.localeCode, 'fr');
      expect(ChatUiLocalizations.de.localeCode, 'de');
      expect(ChatUiLocalizations.it.localeCode, 'it');
      expect(ChatUiLocalizations.pt.localeCode, 'pt');
      expect(ChatUiLocalizations.ca.localeCode, 'ca');
    });

    test('custom instance defaults to en', () {
      const l10n = ChatUiLocalizations();
      expect(l10n.localeCode, 'en');
    });

    test('one form returned when count == 1 (en)', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(1, one: 'singular', other: 'plural'), 'singular');
    });

    test('other form returned when count > 1 (en)', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(5, one: 'singular', other: 'plural'), 'plural');
    });

    test('en uses other for count == 0 when zero not provided', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(0, one: 'one', other: 'many'), 'many');
    });

    test('en uses provided zero when supplied', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(0, zero: 'none', one: 'one', other: 'many'), 'none');
    });

    test('fr uses one for count == 0 (CLDR rule)', () {
      const l10n = ChatUiLocalizations.fr;
      expect(l10n.plural(0, one: 'singulier', other: 'pluriel'), 'singulier');
    });

    test('fr uses one for count == 1', () {
      const l10n = ChatUiLocalizations.fr;
      expect(l10n.plural(1, one: 'singulier', other: 'pluriel'), 'singulier');
    });

    test('fr uses other for count >= 2', () {
      const l10n = ChatUiLocalizations.fr;
      expect(l10n.plural(2, one: 'singulier', other: 'pluriel'), 'pluriel');
    });

    test('zero falls back to other when not provided', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(0, other: 'fallback'), 'fallback');
    });

    test('one falls back to other when not provided', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(1, other: 'fallback'), 'fallback');
    });

    test('two falls back through few to other', () {
      const l10n = ChatUiLocalizations.en;
      expect(
        l10n.plural(5, few: 'few-form', other: 'other-form'),
        'other-form',
      );
    });

    test('unknown locale falls through to English rule', () {
      const l10n = ChatUiLocalizations(localeCode: 'xx');
      expect(l10n.plural(1, one: 'one', other: 'many'), 'one');
      expect(l10n.plural(2, one: 'one', other: 'many'), 'many');
    });

    test('IETF tag with region matches by primary subtag', () {
      const l10n = ChatUiLocalizations(localeCode: 'fr_CA');
      expect(l10n.plural(0, one: 'singulier', other: 'pluriel'), 'singulier');
    });

    test('IETF tag with hyphen region matches by primary subtag', () {
      const l10n = ChatUiLocalizations(localeCode: 'pt-BR');
      expect(l10n.plural(0, one: 'um', other: 'muitos'), 'muitos');
    });

    test('negative counts use absolute value for category', () {
      const l10n = ChatUiLocalizations.en;
      expect(l10n.plural(-1, one: 'one', other: 'many'), 'one');
    });

    test('replies uses helper — en singular', () {
      expect(ChatUiLocalizations.en.replies(1), '1 reply');
    });

    test('replies uses helper — en plural', () {
      expect(ChatUiLocalizations.en.replies(3), '3 replies');
    });

    test('newMessages uses helper — en singular', () {
      expect(ChatUiLocalizations.en.newMessages(1), '1 new message');
    });

    test('newMessages uses helper — en plural', () {
      expect(ChatUiLocalizations.en.newMessages(7), '7 new messages');
    });

    test('newMessages — fr 0 uses singular template', () {
      expect(
        ChatUiLocalizations.fr.newMessages(0),
        ChatUiLocalizations.fr.newMessageSingularTemplate.replaceAll(
          '{count}',
          '0',
        ),
      );
    });

    test('relativeMonth — en singular', () {
      expect(ChatUiLocalizations.en.relativeMonth(1), '1 mo');
    });

    test('relativeMonth — es plural', () {
      expect(ChatUiLocalizations.es.relativeMonth(3), '3 meses');
    });

    test('relativeYear — it singular', () {
      expect(ChatUiLocalizations.it.relativeYear(1), '1 anno');
    });

    test('relativeYear — it plural', () {
      expect(ChatUiLocalizations.it.relativeYear(4), '4 anni');
    });

    test('copyWith carries localeCode through', () {
      const l10n = ChatUiLocalizations.fr;
      final copy = l10n.copyWith(today: 'OVR');
      expect(copy.localeCode, 'fr');
      expect(copy.today, 'OVR');
    });

    test('copyWith can override localeCode', () {
      const l10n = ChatUiLocalizations.en;
      final copy = l10n.copyWith(localeCode: 'fr');
      expect(copy.localeCode, 'fr');
    });
  });

  group('ChatUiLocalizations — Nordic + Eastern-EU locales', () {
    test('sv has Swedish translations for the core set', () {
      const l10n = ChatUiLocalizations.sv;
      expect(l10n.localeCode, 'sv');
      expect(l10n.today, 'Idag');
      expect(l10n.writeMessage, 'Skriv ett meddelande');
      expect(l10n.send, 'Skicka');
      expect(l10n.delete, 'Ta bort');
      expect(l10n.loadMore, 'Ladda fler');
    });

    test('no has Norwegian translations for the core set', () {
      const l10n = ChatUiLocalizations.no;
      expect(l10n.localeCode, 'no');
      expect(l10n.today, 'I dag');
      expect(l10n.writeMessage, 'Skriv en melding');
      expect(l10n.send, 'Send');
      expect(l10n.loadMore, 'Last inn flere');
    });

    test('da has Danish translations for the core set', () {
      const l10n = ChatUiLocalizations.da;
      expect(l10n.localeCode, 'da');
      expect(l10n.today, 'I dag');
      expect(l10n.writeMessage, 'Skriv en besked');
      expect(l10n.send, 'Send');
      expect(l10n.loadMore, 'Indlæs flere');
    });

    test('pl has Polish translations for the core set', () {
      const l10n = ChatUiLocalizations.pl;
      expect(l10n.localeCode, 'pl');
      expect(l10n.today, 'Dzisiaj');
      expect(l10n.writeMessage, 'Napisz wiadomość');
      expect(l10n.send, 'Wyślij');
      expect(l10n.loadMore, 'Wczytaj więcej');
    });

    test('cs has Czech translations for the core set', () {
      const l10n = ChatUiLocalizations.cs;
      expect(l10n.localeCode, 'cs');
      expect(l10n.today, 'Dnes');
      expect(l10n.writeMessage, 'Napište zprávu');
      expect(l10n.send, 'Odeslat');
      expect(l10n.loadMore, 'Načíst další');
    });

    test('fields outside the core set fall back to the English default', () {
      expect(ChatUiLocalizations.sv.unblockFailed, 'Unblock failed');
      expect(ChatUiLocalizations.no.unblockFailed, 'Unblock failed');
      expect(ChatUiLocalizations.da.unblockFailed, 'Unblock failed');
      expect(ChatUiLocalizations.pl.unblockFailed, 'Unblock failed');
      expect(ChatUiLocalizations.cs.unblockFailed, 'Unblock failed');
    });

    test('loadMore defaults to English on the base constructor', () {
      const l10n = ChatUiLocalizations();
      expect(l10n.loadMore, 'Load more');
    });
  });

  group('ChatUiLocalizations — locale registry', () {
    test('supportedLanguageCodes includes all twelve locales', () {
      expect(ChatUiLocalizations.supportedLanguageCodes, [
        'en',
        'es',
        'fr',
        'de',
        'it',
        'pt',
        'ca',
        'sv',
        'no',
        'da',
        'pl',
        'cs',
      ]);
    });

    test('supportedLocales mirrors supportedLanguageCodes', () {
      expect(
        ChatUiLocalizations.supportedLocales.map((l) => l.languageCode),
        ChatUiLocalizations.supportedLanguageCodes,
      );
    });

    test('forLanguageCode resolves each new locale by exact code', () {
      expect(ChatUiLocalizations.forLanguageCode('sv'), ChatUiLocalizations.sv);
      expect(ChatUiLocalizations.forLanguageCode('no'), ChatUiLocalizations.no);
      expect(ChatUiLocalizations.forLanguageCode('da'), ChatUiLocalizations.da);
      expect(ChatUiLocalizations.forLanguageCode('pl'), ChatUiLocalizations.pl);
      expect(ChatUiLocalizations.forLanguageCode('cs'), ChatUiLocalizations.cs);
    });

    test('forLanguageCode maps nb/nn Norwegian variants to no', () {
      expect(ChatUiLocalizations.forLanguageCode('nb'), ChatUiLocalizations.no);
      expect(ChatUiLocalizations.forLanguageCode('nn'), ChatUiLocalizations.no);
    });

    test('forLanguageCode matches IETF tags with region by primary subtag', () {
      expect(
        ChatUiLocalizations.forLanguageCode('pl-PL'),
        ChatUiLocalizations.pl,
      );
      expect(
        ChatUiLocalizations.forLanguageCode('cs_CZ'),
        ChatUiLocalizations.cs,
      );
    });

    test('forLanguageCode falls back to en for an unsupported code', () {
      expect(ChatUiLocalizations.forLanguageCode('xx'), ChatUiLocalizations.en);
    });
  });
}
