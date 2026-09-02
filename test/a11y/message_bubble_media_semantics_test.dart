import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

/// A bubble that carries no text used to reach a screen reader with an
/// empty body: a photo, a shared location and a failed upload all read as
/// "You: , Sent" or plain "You: ". The chat list had always been able to
/// describe those same rows, so the words existed — they just never made it
/// into the conversation.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('non-text bubbles announce what they are', () {
    testWidgets('a sent photo reads "You: Photo, Sent"', (tester) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'image/jpeg',
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: Photo, 12:00, Sent'), findsOneWidget);
      expect(semanticsWithLabel('You: , Sent'), findsNothing);
    });

    testWidgets('a video reads its own label rather than a blank body', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'video/mp4',
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: Video, 12:00, Sent'), findsOneWidget);
    });

    testWidgets('a shared location reads "You: Location, Sent"', (
      tester,
    ) async {
      final message =
          fixtureMessage(
            text: null,
            from: fixtureUserMe.id,
            messageType: MessageType.location,
          ).copyWith(
            receipt: ReceiptStatus.sent,
            metadata: const {'lat': 40.4, 'lng': -3.7},
          );

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: Location, 12:00, Sent'), findsOneWidget);
    });

    testWidgets('a named document reads its file name', (tester) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'application/pdf',
        fileName: 'contract.pdf',
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: contract.pdf, 12:00, Sent'), findsOneWidget);
    });

    testWidgets('a captioned photo announces the photo before the caption', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: 'en la playa',
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'image/jpeg',
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(
        semanticsWithLabel('You: Photo, en la playa, 12:00, Sent'),
        findsOneWidget,
        reason:
            'reading the caption alone left no clue there was an image '
            'above it — the caption describes the photo, it does not '
            'replace it',
      );
      expect(semanticsWithLabel('You: en la playa, Sent'), findsNothing);
    });

    testWidgets('a plain text message is still read verbatim', (tester) async {
      final message = fixtureMessage(
        text: 'hola',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: hola, 12:00, Sent'), findsOneWidget);
    });
  });

  group('a forward says it is one', () {
    testWidgets('a forwarded message with nothing but the forward reads '
        '"You: Forwarded, Sent"', (tester) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.forward,
      ).copyWith(receipt: ReceiptStatus.sent);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: Forwarded, 12:00, Sent'), findsOneWidget);
      expect(semanticsWithLabel('You: , Sent'), findsNothing);
    });

    testWidgets('a forwarded text keeps its text and gains the marker the '
        'bubble draws', (tester) async {
      final message = fixtureMessage(
        text: 'mira esto',
        from: fixtureUserMe.id,
      ).copyWith(receipt: ReceiptStatus.sent, isForwarded: true);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(
        semanticsWithLabel('You: Forwarded, mira esto, 12:00, Sent'),
        findsOneWidget,
      );
    });

    testWidgets('a forwarded photo announces both the forward and the photo', (
      tester,
    ) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'image/jpeg',
      ).copyWith(receipt: ReceiptStatus.sent, isForwarded: true);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true)),
      );

      expect(semanticsWithLabel('You: Forwarded, Photo, 12:00, Sent'), findsOneWidget);
    });
  });

  group('a failed send says so', () {
    testWidgets('a failed photo reads "You: Photo, Failed"', (tester) async {
      final message = fixtureMessage(
        text: null,
        from: fixtureUserMe.id,
        messageType: MessageType.attachment,
        mimeType: 'image/jpeg',
      );

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true, isFailed: true)),
      );

      expect(semanticsWithLabel('You: Photo, 12:00, Failed'), findsOneWidget);
    });

    testWidgets('a failed text message reads its text and the failure', (
      tester,
    ) async {
      final message = fixtureMessage(text: 'hola', from: fixtureUserMe.id);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, isOutgoing: true, isFailed: true)),
      );

      expect(semanticsWithLabel('You: hola, 12:00, Failed'), findsOneWidget);
    });

    testWidgets('a send still on its way keeps announcing Sending', (
      tester,
    ) async {
      final message = fixtureMessage(text: 'hola', from: fixtureUserMe.id);

      await tester.pumpWidget(
        wrap(
          MessageBubble(message: message, isOutgoing: true, isPending: true),
        ),
      );

      expect(semanticsWithLabel('You: hola, 12:00, Sending'), findsOneWidget);
    });
  });
}
