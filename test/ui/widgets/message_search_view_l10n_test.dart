import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The search screen's opening prompt and result count are bundle keys, so
/// they follow the ambient locale and answer to `copyWith` like every other
/// string in the SDK.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage msg(String id) => ChatMessage(
    id: id,
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    text: 'hello from $id',
  );

  MessageSearchController controllerWith(List<ChatMessage> items) =>
      MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            ChatSuccess(ChatPaginatedResponse(items: items, hasMore: false)),
      );

  testWidgets('a bundle override reaches the prompt and the count', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1'), msg('m2')]);
    addTearDown(controller.dispose);

    final theme = ChatTheme.defaults.copyWith(
      l10n: ChatUiLocalizations.en.copyWith(
        searchPromptEmpty: 'Look inside this room',
        searchResultCountPluralTemplate: '{count} hits',
      ),
    );

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          theme: theme,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Look inside this room'), findsOneWidget);

    await controller.search('hello', 'room1');
    await tester.pump();
    expect(find.text('2 hits'), findsOneWidget);
  });

  testWidgets('a locale with no English fallback gets its own copy', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1'), msg('m2')]);
    addTearDown(controller.dispose);

    final theme = ChatTheme.defaults.copyWith(
      l10n: ChatUiLocalizations.forLanguageCode('fr'),
    );

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          theme: theme,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Rechercher du texte dans cette conversation'),
      findsOneWidget,
    );

    await controller.search('hello', 'room1');
    await tester.pump();
    expect(find.text('2 résultats'), findsOneWidget);
  });

  testWidgets('one match reads as one, in the locale plural form', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
        ),
      ),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    expect(find.text('1 resultado'), findsOneWidget);
  });

  testWidgets('the per-call overrides still win over the bundle', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1'), msg('m2')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          emptyPromptText: 'Escribe algo',
          resultCountLabelBuilder: (count) => 'salen $count',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Escribe algo'), findsOneWidget);
    expect(
      find.text('Busca por texto dentro de esta conversación'),
      findsNothing,
    );

    await controller.search('hello', 'room1');
    await tester.pump();
    expect(find.text('salen 2'), findsOneWidget);
  });
}
