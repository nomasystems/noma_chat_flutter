import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Receipts and rows the server never accepted.
///
/// A pending or failed row exists on this device only. Nobody received
/// it, so nothing may report it as delivered or read — and nothing may
/// queue it for the cache's message history, which is permanent
/// (`messageToMap` merges receipts upward and never lowers one).
///
/// The danger is not a receipt addressed to such a row — no peer knows
/// its temporary id — but the fan-outs that reach rows they got no event
/// for: the high-water-mark walk in [ChatController.updateReceipt], the
/// wholesale variant behind a `null` `fromUserId`, and the delivered
/// cursor. All three sweep the list by timestamp or index, which an
/// optimistic row sits in like any other.
///
/// The last group covers `confirmSent`, the fourth writer of the message
/// list: a REST send echo knows only that the message was accepted, so
/// applying it verbatim walks a row the event stream had already
/// advanced back down to one tick.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const peer = ChatUser(id: 'peer', displayName: 'Peer');
  final t0 = DateTime.utc(2026, 1, 1, 10);

  ChatMessage own(
    String id, {
    Duration offset = Duration.zero,
    String? clientMessageId,
    ReceiptStatus? receipt,
  }) => ChatMessage(
    id: id,
    from: 'me',
    timestamp: t0.add(offset),
    text: id,
    clientMessageId: clientMessageId,
    receipt: receipt,
  );

  ChatController controllerWith(List<ChatMessage> messages) {
    final c = ChatController(
      initialMessages: messages,
      currentUser: me,
      otherUsers: const [peer],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('unsent rows carry no receipt', () {
    test('the high-water-mark fan-out skips a failed row', () {
      // The ghost of a send the user watched fail, an hour before a
      // message that really was read. The fan-out walks every own message
      // at-or-before the reference and would stamp it too.
      final c = controllerWith([
        own('temp-abc'),
        own('srv-1', offset: const Duration(hours: 1)),
      ]);
      c.markFailed('temp-abc');

      c.updateReceipt('srv-1', ReceiptStatus.read, fromUserId: 'peer');

      expect(c.receiptStatuses['srv-1'], ReceiptStatus.read);
      expect(c.receiptStatuses['temp-abc'], isNull);
      expect(c.getMessageById('temp-abc')?.receipt, isNull);
    });

    test('a failed row is never queued for persistence', () {
      final c = controllerWith([
        own('temp-abc'),
        own('srv-1', offset: const Duration(hours: 1)),
      ]);
      c.markFailed('temp-abc');

      c.updateReceipt('srv-1', ReceiptStatus.read, fromUserId: 'peer');

      expect(c.drainReceiptUpdates().map((m) => m.id), ['srv-1']);
    });

    test('the wholesale fan-out (no fromUserId) skips a failed row', () {
      final c = controllerWith([
        own('temp-abc'),
        own('srv-1', offset: const Duration(hours: 1)),
      ]);
      c.markFailed('temp-abc');

      c.updateReceipt('srv-1', ReceiptStatus.read);

      expect(c.receiptStatuses['srv-1'], ReceiptStatus.read);
      expect(c.receiptStatuses['temp-abc'], isNull);
      expect(c.getMessageById('temp-abc')?.receipt, isNull);
      expect(c.drainReceiptUpdates().map((m) => m.id), ['srv-1']);
    });

    test('a delivered cursor does not cover a pending row', () {
      // Cursor coverage falls back to list position when no seq is known,
      // and the optimistic row is at index 0.
      final c = controllerWith([
        own('temp-abc'),
        own('srv-1', offset: const Duration(hours: 1)),
      ]);
      c.markPending('temp-abc');

      c.applyDeliveryCursor(userId: 'peer', messageId: 'srv-1');

      expect(c.receiptStatuses['srv-1'], ReceiptStatus.delivered);
      expect(c.receiptStatuses['temp-abc'], isNull);
      expect(c.getMessageById('temp-abc')?.receipt, isNull);
      expect(c.drainReceiptUpdates().map((m) => m.id), ['srv-1']);
    });

    test('declaring a row unsent revokes a receipt it already carried', () {
      // The room-open rehydration adds a pending row to the list first and
      // marks it failed a step later, so a stamp can land in between.
      final c = controllerWith([own('temp-abc')]);
      c.updateReceipt('temp-abc', ReceiptStatus.read, fromUserId: 'peer');
      expect(c.receiptStatuses['temp-abc'], ReceiptStatus.read);
      expect(c.getMessageById('temp-abc')?.receipt, ReceiptStatus.read);

      c.markFailed('temp-abc');

      expect(c.receiptStatuses['temp-abc'], isNull);
      expect(c.getMessageById('temp-abc')?.receipt, isNull);
      expect(c.drainReceiptUpdates(), isEmpty);
    });

    test('an ack absorbed under a temp id does not resurface once the '
        'authoritative row takes its slot', () {
      // Reconciliation drops the pending mark, so a per-user ack recorded
      // against the temporary id would become derivable again on the next
      // re-aggregation.
      final c = controllerWith([
        own('temp-abc', clientMessageId: 'cmid-1'),
        own('srv-1', offset: const Duration(hours: 1)),
      ]);
      c.markFailed('temp-abc');
      c.updateReceipt('srv-1', ReceiptStatus.read, fromUserId: 'peer');

      c.addMessage(
        own(
          'srv-2',
          clientMessageId: 'cmid-1',
          offset: const Duration(days: 1),
        ),
      );
      c.setIsGroup(false);

      expect(c.receiptStatuses['temp-abc'], isNull);
      expect(c.drainReceiptUpdates().map((m) => m.id), ['srv-1']);
    });
  });

  group('confirmSent defers to the receipt comparison', () {
    test('does not lower a receipt already known for the confirmed id', () {
      // ack_mode=async: the peer's read landed against the real id while
      // the bubble was still pending, ahead of the REST echo.
      final c = controllerWith([]);
      c.addMessage(own('temp-1'));
      c.markPending('temp-1');
      c.updateReceipt('srv-1', ReceiptStatus.read, fromUserId: 'peer');

      c.confirmSent('temp-1', own('srv-1', receipt: ReceiptStatus.sent));

      expect(c.getMessageById('srv-1')?.receipt, ReceiptStatus.read);
      expect(c.receiptStatuses['srv-1'], ReceiptStatus.read);
    });

    test('keeps the receipt carried by the row it replaces', () {
      // The row's own baseline, with nothing recorded in the aggregate map
      // — the shape a cached row reloaded on a cold start comes back in.
      final c = controllerWith([]);
      c.addMessage(own('srv-1', receipt: ReceiptStatus.read));
      expect(c.receiptStatuses['srv-1'], isNull);

      c.confirmSent('temp-1', own('srv-1', receipt: ReceiptStatus.sent));

      expect(c.getMessageById('srv-1')?.receipt, ReceiptStatus.read);
    });

    test('still applies the echo receipt when nothing better is known', () {
      final c = controllerWith([]);
      c.addMessage(own('temp-1'));
      c.markPending('temp-1');

      c.confirmSent('temp-1', own('srv-1', receipt: ReceiptStatus.sent));

      expect(c.messages.map((m) => m.id), ['srv-1']);
      expect(c.getMessageById('srv-1')?.receipt, ReceiptStatus.sent);
      expect(c.isPending('temp-1'), isFalse);
      expect(c.serverIdForTemp('temp-1'), 'srv-1');
    });
  });
}
