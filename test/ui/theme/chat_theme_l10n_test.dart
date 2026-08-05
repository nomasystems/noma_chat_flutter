import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/material_localizations_for_any_locale.dart';

Widget _host({
  required Locale locale,
  required Widget child,
  List<LocalizationsDelegate<dynamic>> delegates = const [],
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: [...delegates, ...anyLocaleMaterialDelegates],
    supportedLocales: ChatUiLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  group('ChatTheme.l10nOf', () {
    testWidgets('resolves from the Localizations ancestor when the theme '
        'carries the default', (tester) async {
      late ChatUiLocalizations resolved;
      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: Builder(
            builder: (context) {
              resolved = ChatTheme.defaults.l10nOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolved.localeCode, 'es');
      expect(resolved.today, 'Hoy');
    });

    testWidgets('an explicit theme instance wins over the ancestor', (
      tester,
    ) async {
      late ChatUiLocalizations resolved;
      final theme = ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.fr);
      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: Builder(
            builder: (context) {
              resolved = theme.l10nOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolved.localeCode, 'fr');
    });

    testWidgets('falls back to English when no delegate is registered', (
      tester,
    ) async {
      late ChatUiLocalizations resolved;
      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          child: Builder(
            builder: (context) {
              resolved = ChatTheme.defaults.l10nOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(identical(resolved, ChatUiLocalizations.en), isTrue);
    });

    testWidgets('a theme carrying the canonical en instance still resolves '
        'from the ancestor, while en.copyWith() pins English', (tester) async {
      late ChatUiLocalizations viaCanonicalEn;
      late ChatUiLocalizations viaCopy;
      final canonical = ChatTheme.defaults.copyWith(
        l10n: ChatUiLocalizations.forLanguageCode('en'),
      );
      final pinned = ChatTheme.defaults.copyWith(
        l10n: ChatUiLocalizations.en.copyWith(),
      );
      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: Builder(
            builder: (context) {
              viaCanonicalEn = canonical.l10nOf(context);
              viaCopy = pinned.l10nOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(viaCanonicalEn.localeCode, 'es');
      expect(viaCopy.localeCode, 'en');
    });

    testWidgets('a widget renders the ancestor locale with no theme wiring', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: const Scaffold(
            body: ConnectionBanner(state: ChatConnectionState.connecting),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Conectando...'), findsOneWidget);
    });

    testWidgets('the app locale drives the widget on a live change', (
      tester,
    ) async {
      Widget app(Locale locale) => _host(
        locale: locale,
        delegates: const [ChatUiLocalizations.delegate],
        child: const Scaffold(
          body: ConnectionBanner(state: ChatConnectionState.connecting),
        ),
      );

      await tester.pumpWidget(app(const Locale('en')));
      await tester.pump();
      expect(find.text('Connecting...'), findsOneWidget);

      await tester.pumpWidget(app(const Locale('es')));
      await tester.pump();
      expect(find.text('Conectando...'), findsOneWidget);
    });
  });

  group('ChatUiLocalizations.override', () {
    test('forwards every key, including the ones copyWith exposes', () async {
      final delegate = ChatUiLocalizations.override(
        attachmentUploadingTemplate: 'Subiendo {percent} por ciento',
        retry: 'Otra vez',
        loadMore: 'Cargar más',
        starredMessages: 'Destacados',
      );

      final resolved = await delegate.load(const Locale('es'));

      expect(resolved.attachmentUploadingLabel(40), 'Subiendo 40 por ciento');
      expect(resolved.retry, 'Otra vez');
      expect(resolved.loadMore, 'Cargar más');
      expect(resolved.starredMessages, 'Destacados');
      expect(resolved.today, 'Hoy');
    });

    test('scoped to a single locale, other languages fall through', () {
      final delegate = ChatUiLocalizations.override(
        locale: const Locale('es'),
        send: 'Enviar ya',
      );

      expect(delegate.isSupported(const Locale('es')), isTrue);
      expect(delegate.isSupported(const Locale('fr')), isFalse);
    });
  });
}
