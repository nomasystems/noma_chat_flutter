import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The affordances an in-room search screen is expected to open with: a
/// focused field, copy explaining what it searches, self-attributed rows, a
/// result count and arrows to walk the matches.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage msg(String id, String from) => ChatMessage(
    id: id,
    from: from,
    timestamp: DateTime(2026, 1, 1),
    text: 'hello from $id',
  );

  MessageSearchController controllerWith(List<ChatMessage> items) =>
      MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            ChatSuccess(ChatPaginatedResponse(items: items, hasMore: false)),
      );

  testWidgets('opens focused, so the keyboard is already up', (tester) async {
    final controller = controllerWith(const []);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(MessageSearchView(controller: controller, roomId: 'room1')),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat_search_input')),
    );
    expect(field.autofocus, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('autofocus: false leaves the field unfocused', (tester) async {
    final controller = controllerWith(const []);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          autofocus: false,
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat_search_input')),
    );
    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets('an untouched screen explains what it searches', (tester) async {
    final controller = controllerWith(const []);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(MessageSearchView(controller: controller, roomId: 'room1')),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_search_prompt')), findsOneWidget);
    expect(
      find.text('Search for text inside this conversation'),
      findsOneWidget,
    );
  });

  testWidgets('a query with no matches still says "no results", not the '
      'opening prompt', (tester) async {
    final controller = controllerWith(const []);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(MessageSearchView(controller: controller, roomId: 'room1')),
    );
    await controller.search('nothing', 'room1');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_search_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_search_prompt')), findsNothing);
  });

  testWidgets('own results are labelled "You", other people by name', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1', 'me'), msg('m2', 'u1')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          currentUserId: 'me',
          senderNameResolver: (id) => id == 'u1' ? 'Alice' : id,
        ),
      ),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('without currentUserId nothing is self-attributed', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1', 'me'), msg('m2', 'u1')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          senderNameResolver: (id) => id == 'u1' ? 'Alice' : id,
        ),
      ),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    expect(find.text('You'), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('the header counts the matches', (tester) async {
    final controller = controllerWith([msg('m1', 'u1'), msg('m2', 'u1')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(MessageSearchView(controller: controller, roomId: 'room1')),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    expect(find.text('2 results'), findsOneWidget);
  });

  testWidgets('the arrows walk the results and report each step', (
    tester,
  ) async {
    final tapped = <String>[];
    final controller = controllerWith([
      msg('m1', 'u1'),
      msg('m2', 'u1'),
      msg('m3', 'u1'),
    ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          onMessageTap: (_, id) => tapped.add(id),
        ),
      ),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    // Parked on the first match: there is nothing before it.
    final prev = find.byKey(const ValueKey('chat_search_prev'));
    final next = find.byKey(const ValueKey('chat_search_next'));
    expect(tester.widget<IconButton>(prev).onPressed, isNull);

    await tester.tap(next);
    await tester.pump();
    await tester.tap(next);
    await tester.pump();

    expect(tapped, ['m2', 'm3']);
    // At the last match "next" is spent and "previous" is live again.
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(tester.widget<IconButton>(prev).onPressed, isNotNull);

    await tester.tap(prev);
    await tester.pump();
    expect(tapped, ['m2', 'm3', 'm2']);
  });

  testWidgets('showResultNavigation: false keeps the count without arrows', (
    tester,
  ) async {
    final controller = controllerWith([msg('m1', 'u1'), msg('m2', 'u1')]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        MessageSearchView(
          controller: controller,
          roomId: 'room1',
          showResultNavigation: false,
        ),
      ),
    );
    await controller.search('hello', 'room1');
    await tester.pump();

    expect(find.text('2 results'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_search_next')), findsNothing);
  });
}
