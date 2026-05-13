import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Confirms that every system-message string is filled in for every locale
/// shipped with the SDK. The list of locales below is the contract; if a
/// new locale is added without backfilling these strings, this test fails.
void main() {
  final locales = <String, ChatUiLocalizations>{
    'en': ChatUiLocalizations.en,
    'es': ChatUiLocalizations.es,
    'fr': ChatUiLocalizations.fr,
    'de': ChatUiLocalizations.de,
    'it': ChatUiLocalizations.it,
    'pt': ChatUiLocalizations.pt,
    'ca': ChatUiLocalizations.ca,
  };

  group('System message templates are filled in every locale', () {
    for (final entry in locales.entries) {
      final code = entry.key;
      final l = entry.value;

      test('[$code] userJoinedTemplate is non-empty and contains {user}', () {
        expect(l.userJoinedTemplate.trim(), isNotEmpty);
        expect(l.userJoinedTemplate, contains('{user}'));
      });

      test('[$code] userLeftTemplate is non-empty and contains {user}', () {
        expect(l.userLeftTemplate.trim(), isNotEmpty);
        expect(l.userLeftTemplate, contains('{user}'));
      });

      test('[$code] core status strings are filled', () {
        expect(l.statusSent.trim(), isNotEmpty);
        expect(l.statusDelivered.trim(), isNotEmpty);
        expect(l.statusRead.trim(), isNotEmpty);
      });

      test('[$code] empty-state strings are filled', () {
        expect(l.noMessages.trim(), isNotEmpty);
        expect(l.noResults.trim(), isNotEmpty);
      });

      test('[$code] composer + search strings are filled', () {
        expect(l.writeMessage.trim(), isNotEmpty);
        expect(l.searchMessages.trim(), isNotEmpty);
      });
    }

    test('userJoined("alice") expands the placeholder', () {
      final out = ChatUiLocalizations.es.userJoined('alice');
      expect(out.contains('alice'), true);
      expect(out.contains('{user}'), false);
    });

    test('userLeft("bob") expands the placeholder', () {
      final out = ChatUiLocalizations.de.userLeft('bob');
      expect(out.contains('bob'), true);
      expect(out.contains('{user}'), false);
    });
  });
}
