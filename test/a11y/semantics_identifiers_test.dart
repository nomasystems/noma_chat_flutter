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

    testWidgets('a bubble publishes chat_message_<id>_<authorship>', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
          ),
        ),
      );

      expect(identifier('chat_message_m42_outgoing'), findsOne);
    });

    testWidgets('the helper builds the name both halves are published under', (
      tester,
    ) async {
      expect(
        messageBubbleSemanticsId('m42', isOutgoing: true),
        'chat_message_m42_outgoing',
      );
      expect(
        messageBubbleSemanticsId('m42', isOutgoing: false),
        'chat_message_m42_incoming',
      );
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
        identifier('chat_message_m42_incoming').evaluate().single.label,
        contains('hola'),
      );
    });

    testWidgets('two bubbles of the same room differ in the authorship the '
        'semantics tree dumps, without reading a single pixel', (tester) async {
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

      expect(identifier('chat_message_m7_outgoing'), findsOne);
      expect(identifier('chat_message_m8_incoming'), findsOne);
      expect(identifier('chat_message_m7_incoming'), findsNothing);
      expect(identifier('chat_message_m8_outgoing'), findsNothing);
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

        for (final name in [
          messageBubbleSemanticsId('m7', isOutgoing: true),
          messageBubbleSemanticsId('m8', isOutgoing: false),
        ]) {
          expect(
            find.byKey(ValueKey(name)),
            findsOneWidget,
            reason: 'ValueKey half missing for $name',
          );
          expect(
            identifier(name),
            findsOne,
            reason: 'Semantics half missing for $name',
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
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('m2', isOutgoing: true)),
        ),
        0,
      );
      expect(
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('m1', isOutgoing: true)),
        ),
        1,
      );
      expect(
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('nope', isOutgoing: true)),
        ),
        isNull,
      );
      expect(
        delegate.findChildIndexCallback!(const ValueKey('chat_message_input')),
        isNull,
      );
    });
  });

  group('delivery status identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('a named tick publishes chat_message_<id>_status on both '
        'halves', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageStatusIcon(
            status: ReceiptStatus.delivered,
            messageId: 'm42',
          ),
        ),
      );

      expect(messageStatusSemanticsId('m42'), 'chat_message_m42_status');
      expect(identifier('chat_message_m42_status'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsOneWidget,
      );
    });

    testWidgets('the name never displaces the screen-reader label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageStatusIcon(status: ReceiptStatus.read, messageId: 'm42'),
        ),
      );

      expect(
        identifier('chat_message_m42_status').evaluate().single.label,
        isNotEmpty,
      );
    });

    testWidgets('a bubble names the tick it paints on both halves of the '
        "framework's tree", (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
            status: ReceiptStatus.delivered,
          ),
        ),
      );

      expect(
        identifier('chat_message_m42_status'),
        findsOne,
        reason:
            'the bubble excludes its own subtree, so the name rides a sibling '
            'node. This asserts the framework tree only: whether a platform '
            'republishes that node is the engine bridge\'s call, and iOS does '
            'not — see the delivery-tick note in README.md',
      );
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsOneWidget,
        reason: 'the ValueKey half, which is what an in-process driver reads',
      );
    });

    testWidgets('naming the tick does not break the merged announcement of '
        'the bubble', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
            status: ReceiptStatus.delivered,
          ),
        ),
      );

      expect(
        identifier('chat_message_m42_status').evaluate().single.label,
        isEmpty,
        reason:
            'the node exists to carry a name, not to announce anything; a '
            'label here would read the delivery state out a second time',
      );

      final bubbleLabel = identifier(
        'chat_message_m42_outgoing',
      ).evaluate().single.label;
      expect(
        bubbleLabel,
        contains('hola'),
        reason: 'the bubble still reads as one unit, body included',
      );
      expect(
        bubbleLabel,
        contains('Delivered'),
        reason:
            'and the delivery state is still part of that one unit, not a '
            'fragment the reader has to go find on its own',
      );
    });

    testWidgets('a bubble with no tick to name publishes no status name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(
              id: 'm9',
              text: 'hola',
              from: fixtureUserOther.id,
            ),
            isOutgoing: false,
          ),
        ),
      );

      expect(identifier('chat_message_m9_status'), findsNothing);
      expect(
        find.byKey(const ValueKey('chat_message_m9_status')),
        findsNothing,
      );
    });

    testWidgets('a tick with no message behind it publishes no name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MessageStatusIcon(status: ReceiptStatus.sent)),
      );

      expect(find.byType(MessageStatusIcon), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsNothing,
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
