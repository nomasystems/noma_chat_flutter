import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ReadReceiptAvatars', () {
    testWidgets('renders avatars for each receipt', (tester) async {
      await tester.pumpWidget(wrap(
        ReadReceiptAvatars(
          receipts: const [
            ReadReceipt(userId: 'u1'),
            ReadReceipt(userId: 'u2'),
          ],
          users: const [
            ChatUser(id: 'u1', displayName: 'Alice'),
            ChatUser(id: 'u2', displayName: 'Bob'),
          ],
        ),
      ));

      expect(find.byType(CircleAvatar), findsNWidgets(2));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('shows overflow when more than maxAvatars', (tester) async {
      await tester.pumpWidget(wrap(
        ReadReceiptAvatars(
          receipts: const [
            ReadReceipt(userId: 'u1'),
            ReadReceipt(userId: 'u2'),
            ReadReceipt(userId: 'u3'),
            ReadReceipt(userId: 'u4'),
            ReadReceipt(userId: 'u5'),
          ],
          users: const [
            ChatUser(id: 'u1', displayName: 'Alice'),
            ChatUser(id: 'u2', displayName: 'Bob'),
            ChatUser(id: 'u3', displayName: 'Charlie'),
            ChatUser(id: 'u4', displayName: 'Diana'),
            ChatUser(id: 'u5', displayName: 'Eve'),
          ],
          maxAvatars: 3,
        ),
      ));

      expect(find.byType(CircleAvatar), findsNWidgets(3));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('renders nothing when receipts is empty', (tester) async {
      await tester.pumpWidget(wrap(
        const ReadReceiptAvatars(receipts: []),
      ));

      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('shows question mark for unknown user', (tester) async {
      await tester.pumpWidget(wrap(
        const ReadReceiptAvatars(
          receipts: [ReadReceipt(userId: 'unknown')],
          users: [],
        ),
      ));

      expect(find.text('?'), findsOneWidget);
    });
  });
}
