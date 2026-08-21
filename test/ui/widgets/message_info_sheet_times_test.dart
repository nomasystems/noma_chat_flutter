import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The sheet may print an hour only for the rows whose cursor lands on the
/// message being inspected. Every other row is covered by a cursor that
/// moved past it, so its time is an upper bound, never "when they read
/// this".
void main() {
  final today = DateTime.now();
  final at1005 = DateTime(today.year, today.month, today.day, 10, 5);
  final at1042 = DateTime(today.year, today.month, today.day, 10, 42);

  ChatMessage msg() => ChatMessage(
    id: 'm1',
    from: 'me',
    timestamp: DateTime(today.year, today.month, today.day, 10, 0),
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('an exact hour only where the cursor points at this message', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(
        userId: 'alice',
        lastReadMessageId: 'm1',
        lastReadAt: at1005,
        lastDeliveredMessageId: 'm1',
        lastDeliveredAt: at1005,
      ),
      ReadReceipt(
        userId: 'bob',
        lastReadMessageId: 'm9',
        lastReadAt: at1042,
        lastDeliveredMessageId: 'm9',
        lastDeliveredAt: at1042,
      ),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
        ),
      ),
    );

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    // Alice's read cursor IS this message: her hour is hers.
    expect(
      find.byKey(const ValueKey('chat_message_info_time_read_alice')),
      findsOneWidget,
    );
    expect(find.text('10:05'), findsOneWidget);
    // Bob's cursor is a later message: the sheet refuses to date this one.
    expect(find.text('No exact time'), findsOneWidget);
    expect(find.textContaining('10:42'), findsNothing);
  });

  testWidgets('a member with no cursor time is still listed, with no hour', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(userId: 'alice', lastReadAt: at1005, lastDeliveredAt: at1005),
      ReadReceipt(userId: 'bob', lastDeliveredAt: at1005),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
        ),
      ),
    );

    // The lists themselves are untouched by the hours work.
    expect(find.text('Read by'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Delivered to'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    // Neither row's cursor names a message, so neither can be dated.
    expect(find.text('No exact time'), findsNWidgets(2));
    expect(find.textContaining('10:05'), findsNothing);
  });

  testWidgets('the delivered list dates its own cursor, not the read one', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(
        userId: 'bob',
        lastDeliveredMessageId: 'm1',
        lastDeliveredAt: at1042,
      ),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
        ),
      ),
    );

    expect(find.text('Delivered to'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat_message_info_time_delivered_bob')),
      findsOneWidget,
    );
    expect(find.text('10:42'), findsOneWidget);
  });

  testWidgets('showApproximateReceiptTimes states the bound as a bound', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(userId: 'bob', lastReadMessageId: 'm9', lastReadAt: at1042),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
          showApproximateReceiptTimes: true,
        ),
      ),
    );

    expect(find.text('By 10:42 at the latest'), findsOneWidget);
    expect(find.text('10:42'), findsNothing);
    expect(find.text('No exact time'), findsNothing);
  });

  testWidgets('receiptTimeFormatter and receiptSubtitleBuilder take over', (
    tester,
  ) async {
    final receipts = [
      ReadReceipt(userId: 'alice', lastReadMessageId: 'm1', lastReadAt: at1005),
      ReadReceipt(
        userId: 'bob',
        lastDeliveredMessageId: 'm1',
        lastDeliveredAt: at1042,
      ),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
          receiptTimeFormatter: (context, at) => 'at ${at.hour}h',
          receiptSubtitleBuilder: (context, detail) =>
              detail.kind == MessageReceiptKind.delivered
              ? const Text('handled by the host')
              : null,
        ),
      ),
    );

    expect(find.text('at 10h'), findsOneWidget);
    expect(find.text('handled by the host'), findsOneWidget);
  });

  testWidgets('the sheet still reports the ambient locale', (tester) async {
    final receipts = [
      ReadReceipt(userId: 'bob', lastReadMessageId: 'm9', lastReadAt: at1042),
    ];

    await tester.pumpWidget(
      wrap(
        MessageInfoSheet(
          message: msg(),
          receipts: receipts,
          currentUserId: 'me',
          displayNameFor: (id) => id,
          theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
        ),
      ),
    );

    expect(find.text('Sin hora exacta'), findsOneWidget);
  });
}
