import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/material_localizations_for_any_locale.dart';

void main() {
  Future<ChatUiLocalizations> resolve(
    WidgetTester tester, {
    required LocalizationsDelegate<ChatUiLocalizations> delegate,
    required Locale locale,
  }) async {
    late ChatUiLocalizations resolved;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: [locale],
        localizationsDelegates: [delegate, ...anyLocaleMaterialDelegates],
        home: Builder(
          builder: (context) {
            resolved = ChatUiLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return resolved;
  }

  testWidgets('overrides survive a locale the SDK does not translate', (
    tester,
  ) async {
    final resolved = await resolve(
      tester,
      delegate: ChatUiLocalizations.override(send: 'Submit'),
      locale: const Locale('ja'),
    );

    expect(resolved.send, 'Submit');
    expect(resolved.retry, ChatUiLocalizations.en.retry);
  });

  testWidgets('overrides scoped to one locale still fall through', (
    tester,
  ) async {
    final delegate = ChatUiLocalizations.override(
      locale: const Locale('es'),
      send: 'Enviar ya',
    );

    expect(delegate.isSupported(const Locale('es')), isTrue);
    expect(delegate.isSupported(const Locale('ja')), isFalse);
  });

  testWidgets('the plain delegate serves English for an untranslated locale', (
    tester,
  ) async {
    final resolved = await resolve(
      tester,
      delegate: ChatUiLocalizations.delegate,
      locale: const Locale('ja'),
    );

    expect(resolved.send, ChatUiLocalizations.en.send);
  });
}
