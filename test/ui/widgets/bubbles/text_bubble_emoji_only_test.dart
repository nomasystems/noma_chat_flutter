import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// A message that is nothing but emoji is painted the way WhatsApp paints
/// it: large, and with no bubble behind it.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage message(
    String text, {
    Map<String, dynamic>? metadata,
    MessageType type = MessageType.regular,
    String? attachmentUrl,
    bool isForwarded = false,
  }) => ChatMessage(
    id: 'm1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 20, 30),
    text: text,
    metadata: metadata,
    messageType: type,
    attachmentUrl: attachmentUrl,
    isForwarded: isForwarded,
  );

  /// Font size the body text ended up painted at.
  double bodyFontSize(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.fontSize!;

  /// The bubble's own background box, or `null` when it has none.
  BoxDecoration? bubbleDecoration(WidgetTester tester) {
    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.color != null && d.borderRadius != null);
    return boxes.isEmpty ? null : boxes.first;
  }

  testWidgets('a lone emoji is enlarged and loses the bubble', (tester) async {
    await tester.pumpWidget(
      wrap(MessageBubble(message: message('🍺'), isOutgoing: true)),
    );

    expect(bodyFontSize(tester, '🍺'), kChatEmojiOnlyFontSize);
    expect(bubbleDecoration(tester), isNull);
  });

  testWidgets('three emoji too', (tester) async {
    await tester.pumpWidget(
      wrap(MessageBubble(message: message('😀😀😀'), isOutgoing: true)),
    );

    expect(bodyFontSize(tester, '😀😀😀'), kChatEmojiOnlyFontSize);
    expect(bubbleDecoration(tester), isNull);
  });

  testWidgets('four do not', (tester) async {
    await tester.pumpWidget(
      wrap(MessageBubble(message: message('😀😀😀😀'), isOutgoing: true)),
    );

    expect(bubbleDecoration(tester), isNotNull);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('an ordinary message keeps its bubble and its size', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(MessageBubble(message: message('vale 🍺'), isOutgoing: true)),
    );

    expect(bubbleDecoration(tester), isNotNull);
  });

  testWidgets('the time and the ticks move below the glyph, not on top', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: message('🍺'),
          isOutgoing: true,
          status: ReceiptStatus.read,
        ),
      ),
    );

    final emojiBottom = tester.getBottomLeft(find.text('🍺')).dy;
    final timeTop = tester.getTopLeft(find.text('20:30')).dy;
    expect(timeTop, greaterThanOrEqualTo(emojiBottom));
  });

  testWidgets('an emoji caption under a photo is not this case', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: message(
            '🍺',
            type: MessageType.attachment,
            attachmentUrl: 'https://example.com/a.png',
            metadata: const {'mimeType': 'image/png'},
          ),
          isOutgoing: true,
        ),
      ),
    );

    expect(bubbleDecoration(tester), isNotNull);
  });

  testWidgets('a forwarded emoji keeps its bubble, it has a header to hold', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: message('🍺', isForwarded: true),
          isOutgoing: true,
        ),
      ),
    );

    expect(bubbleDecoration(tester), isNotNull);
  });

  testWidgets('an emoji with a link preview card keeps its bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: message(
            '🍺 https://example.com',
            metadata: const {
              'linkUrl': 'https://example.com',
              'linkTitle': 'Example',
            },
          ),
          isOutgoing: true,
        ),
      ),
    );

    expect(bubbleDecoration(tester), isNotNull);
  });

  testWidgets(
    'a highlighted emoji keeps its background, that IS the highlight',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message('🍺'),
            isOutgoing: true,
            isHighlighted: true,
          ),
        ),
      );

      expect(bubbleDecoration(tester), isNotNull);
    },
  );
}
