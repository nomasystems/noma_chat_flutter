import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

/// The E2E vocabulary of the chat room. Every name below is published twice
/// with the exact same string: as a `ValueKey` (reachable from a widget test
/// or an `integration_test` run) and as `Semantics(identifier:)` (reachable
/// from outside the process — `resource-id` on Android,
/// `accessibilityIdentifier` on iOS). These tests drive the real semantics
/// tree, because a widget sitting in the widget tree proves nothing about it
/// being addressable by a native driver.
void main() {
  SemanticsFinder identifier(String name) => find.semantics.byPredicate(
    (node) => node.identifier == name,
    describeMatch: (_) => 'semantics node with identifier "$name"',
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  group('composer identifiers', () {
    late ChatController controller;
    late SemanticsHandle handle;

    setUp(() {
      handle = WidgetsBinding.instance.ensureSemantics();
      controller = ChatController(
        initialMessages: const [],
        currentUser: fixtureUserMe,
      );
    });

    tearDown(() {
      controller.dispose();
      handle.dispose();
    });

    Future<void> pumpInput(WidgetTester tester) => tester.pumpWidget(
      wrap(MessageInput(controller: controller, onSendMessageRequest: (_) {})),
    );

    testWidgets('chat_message_input is exposed on the semantics tree', (
      tester,
    ) async {
      await pumpInput(tester);

      expect(identifier('chat_message_input'), findsOne);
    });

    testWidgets('chat_message_input is also addressable by ValueKey, and both '
        'halves land on the composer TextField', (tester) async {
      await pumpInput(tester);

      final byKey = find.byKey(const ValueKey('chat_message_input'));
      expect(byKey, findsOneWidget);
      expect(tester.widget(byKey), isA<TextField>());
    });

    testWidgets('the composer identifier rides on the text field node itself, '
        'without a stray extra node', (tester) async {
      await pumpInput(tester);

      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(identifier: 'chat_message_input', isTextField: true),
      );
    });

    testWidgets('chat_attach_button is exposed and keeps its Gallery label', (
      tester,
    ) async {
      await pumpInput(tester);

      expect(identifier('chat_attach_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_attach_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_attach_button'))),
        isSemantics(
          identifier: 'chat_attach_button',
          label: 'Gallery',
          isButton: true,
        ),
      );
    });

    testWidgets('chat_send_button is exposed and keeps its Send label', (
      tester,
    ) async {
      await pumpInput(tester);
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      expect(identifier('chat_send_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_send_button'))),
        isSemantics(
          identifier: 'chat_send_button',
          label: 'Send',
          isButton: true,
        ),
      );
    });
  });

  group('message bubble identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('a bubble publishes chat_message_<id>', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
          ),
        ),
      );

      expect(identifier('chat_message_m42'), findsOne);
    });

    testWidgets('the bubble identifier does not replace its semantic label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(
              id: 'm42',
              text: 'hola',
              from: fixtureUserOther.id,
            ),
            isOutgoing: false,
            senderName: 'Bob',
          ),
        ),
      );

      expect(
        identifier('chat_message_m42').evaluate().single.label,
        contains('hola'),
      );
    });

    testWidgets(
      'inside a MessageList the ValueKey and the identifier are the same name',
      (tester) async {
        final controller = ChatController(
          initialMessages: [
            fixtureMessage(id: 'm7', text: 'uno'),
            fixtureMessage(id: 'm8', text: 'dos', from: fixtureUserOther.id),
          ],
          currentUser: fixtureUserMe,
          otherUsers: const [fixtureUserOther],
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(wrap(MessageList(controller: controller)));

        for (final id in ['m7', 'm8']) {
          expect(
            find.byKey(ValueKey('chat_message_$id')),
            findsOneWidget,
            reason: 'ValueKey half missing for $id',
          );
          expect(
            identifier('chat_message_$id'),
            findsOne,
            reason: 'Semantics half missing for $id',
          );
        }
      },
    );

    testWidgets('the prefixed key still resolves the child index so the list '
        'keeps reconciling rows by message id', (tester) async {
      final controller = ChatController(
        initialMessages: [
          fixtureMessage(id: 'm1', text: 'uno'),
          fixtureMessage(id: 'm2', text: 'dos'),
        ],
        currentUser: fixtureUserMe,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));

      final delegate =
          tester.widget<SliverList>(find.byType(SliverList).first).delegate
              as SliverChildBuilderDelegate;

      expect(delegate.findChildIndexCallback, isNotNull);
      expect(
        delegate.findChildIndexCallback!(const ValueKey('chat_message_m2')),
        0,
      );
      expect(
        delegate.findChildIndexCallback!(const ValueKey('chat_message_m1')),
        1,
      );
      expect(
        delegate.findChildIndexCallback!(const ValueKey('chat_message_nope')),
        isNull,
      );
    });
  });

  group('reaction identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('each reaction pill publishes chat_reaction_<emoji>', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ReactionBar(reactions: {'👍': 2, '❤️': 1})),
      );

      expect(identifier('chat_reaction_👍'), findsOne);
      expect(identifier('chat_reaction_❤️'), findsOne);
      expect(find.byKey(const ValueKey('chat_reaction_👍')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_reaction_❤️')), findsOneWidget);
    });

    testWidgets(
      'the reaction identifier does not replace its emoji+count label',
      (tester) async {
        await tester.pumpWidget(wrap(const ReactionBar(reactions: {'👍': 2})));

        expect(
          tester.getSemantics(find.byKey(const ValueKey('chat_reaction_👍'))),
          isSemantics(
            identifier: 'chat_reaction_👍',
            label: '👍 2',
            isButton: true,
          ),
        );
      },
    );

    testWidgets('the reaction picker publishes chat_reaction_picker_<emoji> '
        'and chat_reaction_picker_more', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍', '😂'],
            showExpandButton: true,
            onReactionSelected: (_) {},
            onExpandTap: () {},
          ),
        ),
      );

      expect(identifier('chat_reaction_picker_👍'), findsOne);
      expect(identifier('chat_reaction_picker_😂'), findsOne);
      expect(identifier('chat_reaction_picker_more'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_reaction_picker_👍')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_reaction_picker_more')),
        findsOneWidget,
      );
    });
  });
}
