import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PinnedMessagesBanner', () {
    testWidgets('renders pinned message text', (tester) async {
      await tester.pumpWidget(wrap(
        PinnedMessagesBanner(
          pinnedMessage: MessagePin(
            roomId: 'r1',
            messageId: 'msg1',
            pinnedBy: 'u1',
            pinnedAt: DateTime(2026, 1, 1),
          ),
          pinnedMessageText: 'Check out this important info',
        ),
      ));

      expect(find.text('Pinned message'), findsOneWidget);
      expect(find.text('Check out this important info'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('renders nothing when pinnedMessage is null', (tester) async {
      await tester.pumpWidget(wrap(
        const PinnedMessagesBanner(),
      ));

      expect(find.byIcon(Icons.push_pin), findsNothing);
      expect(find.text('Pinned message'), findsNothing);
    });

    testWidgets('tap triggers onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        PinnedMessagesBanner(
          pinnedMessage: MessagePin(
            roomId: 'r1',
            messageId: 'msg1',
            pinnedBy: 'u1',
            pinnedAt: DateTime(2026, 1, 1),
          ),
          pinnedMessageText: 'Pinned text',
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.text('Pinned text'));
      expect(tapped, true);
    });

    testWidgets('close button triggers onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(wrap(
        PinnedMessagesBanner(
          pinnedMessage: MessagePin(
            roomId: 'r1',
            messageId: 'msg1',
            pinnedBy: 'u1',
            pinnedAt: DateTime(2026, 1, 1),
          ),
          onClose: () => closed = true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, true);
    });
  });
}
