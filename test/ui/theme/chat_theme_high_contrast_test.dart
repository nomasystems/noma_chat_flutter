import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatTheme.highContrast', () {
    test('has distinct outgoing/incoming colors', () {
      final hc = ChatTheme.highContrast;
      expect(hc.outgoingBubbleColor, isNotNull);
      expect(hc.incomingBubbleColor, isNotNull);
      expect(hc.outgoingBubbleColor, isNot(equals(hc.incomingBubbleColor)));
    });

    test('text styles have explicit colors and minimum 16px size', () {
      final hc = ChatTheme.highContrast;
      expect(hc.outgoingTextStyle!.fontSize, greaterThanOrEqualTo(16));
      expect(hc.incomingTextStyle!.fontSize, greaterThanOrEqualTo(16));
      expect(hc.inputTextStyle!.fontSize, greaterThanOrEqualTo(16));
      expect(hc.outgoingTextStyle!.color, isNotNull);
      expect(hc.incomingTextStyle!.color, isNotNull);
    });

    test('is a valid ChatTheme usable with widgets', () {
      final hc = ChatTheme.highContrast;
      expect(hc.l10n, isNotNull);
      expect(hc.backgroundColor, isNotNull);
    });
  });

  group('MessageBubble accessibility', () {
    testWidgets('has semantic label with sender and content', (tester) async {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'alice',
        timestamp: DateTime.utc(2026, 1, 1),
        text: 'Hello world',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: msg,
              isOutgoing: false,
              senderName: 'Alice',
            ),
          ),
        ),
      );

      final semanticsWidget = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label?.contains('Alice') ?? false),
        ),
      );
      expect(semanticsWidget.properties.label, contains('Hello world'));
    });

    testWidgets('outgoing message uses You as sender in semantics', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'msg-2',
        from: 'me',
        timestamp: DateTime.utc(2026, 1, 1),
        text: 'My message',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: msg, isOutgoing: true)),
        ),
      );

      final semanticsWidget = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && (w.properties.label?.contains('You') ?? false),
        ),
      );
      expect(semanticsWidget.properties.label, contains('My message'));
    });
  });
}
