import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

ChatMessage _msg() => ChatMessage(
  id: 'm1',
  from: 'me',
  timestamp: DateTime.utc(2026, 6, 15, 10, 0),
);

void main() {
  testWidgets('renders Read by / Delivered to sections with member names', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(
        userId: 'alice',
        lastReadAt: DateTime.utc(2026, 6, 15, 10, 5),
        lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 5),
      ),
      ReadReceipt(
        userId: 'bob',
        lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInfoSheet(
            message: _msg(),
            receipts: receipts,
            currentUserId: 'me',
            displayNameFor: (id) => id,
          ),
        ),
      ),
    );

    expect(find.text('Message info'), findsOneWidget);
    expect(find.text('Read by'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Delivered to'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('shows empty state when no member has a covering cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInfoSheet(
            message: _msg(),
            receipts: const [],
            currentUserId: 'me',
          ),
        ),
      ),
    );

    expect(find.text('No read or delivery info yet'), findsOneWidget);
    expect(find.text('Read by'), findsNothing);
  });

  testWidgets('show() loads receipts lazily then renders the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MessageInfoSheet.show(
                context,
                message: _msg(),
                currentUserId: 'me',
                displayNameFor: (id) => id,
                loadReceipts: () async => [
                  ReadReceipt(
                    userId: 'alice',
                    lastReadAt: DateTime.utc(2026, 6, 15, 10, 5),
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Read by'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
  });
}
