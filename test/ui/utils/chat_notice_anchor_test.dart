import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/material_localizations_for_any_locale.dart';

/// A notice is composed before it is published: the caller reads
/// `theme.l10nOf(context)` to get the wording and only then hands the
/// string over. That first lookup sits outside anything `showChatNotice`
/// can guard, and on a context whose element has left the tree it throws
/// — which loses the notice earlier and more quietly than the two lookups
/// inside the helper ever did.
class _Anchored extends StatefulWidget {
  const _Anchored({super.key, this.theme = ChatTheme.defaults});

  final ChatTheme theme;

  @override
  State<_Anchored> createState() => _AnchoredState();
}

class _AnchoredState extends State<_Anchored> with ChatNoticeAnchor<_Anchored> {
  @override
  ChatTheme get noticeTheme => widget.theme;

  @override
  Widget build(BuildContext context) => const Text('anchored');
}

void main() {
  testWidgets('the wording of a notice survives a context that has gone', (
    tester,
  ) async {
    late BuildContext raiser;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ChatUiLocalizations.delegate,
          ...anyLocaleMaterialDelegates,
        ],
        supportedLocales: ChatUiLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              raiser = context;
              return const Text('child');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      chatNoticeL10n(raiser, ChatTheme.defaults).editWindowExpired,
      ChatUiLocalizations.es.editWindowExpired,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
    );

    expect(() => ChatUiLocalizations.of(raiser), throwsFlutterError);
    expect(
      chatNoticeL10n(raiser, ChatTheme.defaults).editWindowExpired,
      ChatUiLocalizations.en.editWindowExpired,
    );
  });

  testWidgets('an anchored State reads the ambient locale like the lookup it '
      'replaces', (tester) async {
    final key = GlobalKey<_AnchoredState>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ChatUiLocalizations.delegate,
          ...anyLocaleMaterialDelegates,
        ],
        supportedLocales: ChatUiLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(body: _Anchored(key: key)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      key.currentState!.noticeL10n.editWindowExpired,
      ChatUiLocalizations.de.editWindowExpired,
    );
  });

  testWidgets('an anchored State honours a theme that pins its own strings', (
    tester,
  ) async {
    final key = GlobalKey<_AnchoredState>();
    final pinned = ChatTheme.defaults.copyWith(
      l10n: ChatUiLocalizations.en.copyWith(editWindowExpired: 'too late'),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ChatUiLocalizations.delegate,
          ...anyLocaleMaterialDelegates,
        ],
        supportedLocales: ChatUiLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: _Anchored(key: key, theme: pinned),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.noticeL10n.editWindowExpired, 'too late');
  });

  testWidgets('showNotice still reaches the host presenter and the messenger', (
    tester,
  ) async {
    final presented = <String>[];
    final key = GlobalKey<_AnchoredState>();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatNoticeScope(
          presenter: (context, message) {
            presented.add(message);
            return true;
          },
          child: Scaffold(body: _Anchored(key: key)),
        ),
      ),
    );

    key.currentState!.showNotice('through the host');
    await tester.pump();

    expect(presented, ['through the host']);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Anchored(key: key)),
      ),
    );
    key.currentState!.showNotice('through the messenger');
    await tester.pump();
    await tester.pump();

    expect(presented, ['through the host']);
    expect(find.text('through the messenger'), findsOneWidget);
  });

  testWidgets('a presenter that throws degrades to the default bar instead of '
      'losing the notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatNoticeScope(
          presenter: (context, message) => throw StateError('host is busy'),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChatNotice(context, 'still spoken'),
                child: const Text('raise'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('raise'));
    await tester.pump();
    await tester.pump();

    expect(find.text('still spoken'), findsOneWidget);
  });
}
