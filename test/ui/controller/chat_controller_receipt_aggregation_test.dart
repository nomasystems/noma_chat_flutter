import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// per-user receipt aggregation in [ChatController].
///
/// Asserts the WhatsApp-style semantics the controller is supposed to
/// enforce:
///
/// * 1:1 DM: any peer ack flips the aggregated status. One `read` from
///   the only other member is enough to render ✓✓-blue.
/// * Group: the bubble only flips to ✓✓-blue once *every* non-sender
///   member has acked `read`. Partial reads stay at `delivered` (or
///   `sent` if no one even delivered yet).
/// * High-water-mark propagation: when a recipient reads message N,
///   every older message from the same sender is implicitly read too —
///   but only by that recipient, and only for the same sender. Older
///   messages by a different sender stay untouched.
/// * Monotonicity: the aggregate only ever moves forward along
///   `sent → delivered → read`. No event, roster change or group/1:1
///   reclassification may walk a rendered ✓✓ back to a ✓.
/// * [ChatController.clearMessages] resets both the per-user tracking
///   and the aggregated cache so a re-loaded room doesn't carry over
///   stale acks.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final t0 = DateTime.utc(2026, 1, 1, 10, 0, 0);

  ChatMessage own(String id, {Duration offset = Duration.zero}) =>
      ChatMessage(id: id, from: 'me', timestamp: t0.add(offset), text: id);

  group('DM aggregation (single other user)', () {
    test('any delivered → aggregated = delivered', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('any read → aggregated = read', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('no receipts → aggregated absent (falls back to sent)', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      expect(c.receiptStatuses['m1'], isNull);
    });
  });

  group('Group aggregation (multiple other users)', () {
    ChatController buildGroup() => ChatController(
      initialMessages: [own('m1')],
      currentUser: me,
      otherUsers: const [
        ChatUser(id: 'u1', displayName: 'Alice'),
        ChatUser(id: 'u2', displayName: 'Bob'),
        ChatUser(id: 'u3', displayName: 'Charlie'),
      ],
    );

    test('only one read → aggregated stays at sent (no blue)', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      // Two members still haven't ack'd → not delivered-by-all either.
      expect(c.receiptStatuses['m1'], ReceiptStatus.sent);
    });

    test('all delivered, none read → aggregated = delivered', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u3');
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('two read + one delivered → aggregated = delivered', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.delivered, fromUserId: 'u3');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
      // u3 only acknowledged delivery, not read → bubble must NOT flip
      // to blue yet.
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
    });

    test('all read → aggregated = read (blue)', () {
      final c = buildGroup();
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u3');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });
  });

  group('High-water-mark propagation', () {
    test('reading the latest msg from a sender flips all older ones for '
        'that sender, but never crosses to a different sender', () {
      final c = ChatController(
        initialMessages: [
          own('m1', offset: const Duration(seconds: 1)),
          own('m2', offset: const Duration(seconds: 2)),
          // A foreign message in the middle — should NOT inherit u1's read.
          ChatMessage(
            id: 'm-foreign',
            from: 'u3',
            timestamp: t0.add(const Duration(seconds: 3)),
            text: 'foreign',
          ),
          own('m3', offset: const Duration(seconds: 4)),
        ],
        currentUser: me,
        otherUsers: const [
          ChatUser(id: 'u1', displayName: 'Alice'),
          ChatUser(id: 'u2', displayName: 'Bob'),
        ],
      );
      addTearDown(c.dispose);

      // u1 reads the latest own message. u2 hasn't acked yet → still
      // "sent" in a 2-other-user group.
      c.updateReceipt('m3', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m3'], ReceiptStatus.sent);

      // Now u2 reads m3 → all otherUsers have read → m3 flips to read.
      c.updateReceipt('m3', ReceiptStatus.read, fromUserId: 'u2');
      expect(c.receiptStatuses['m3'], ReceiptStatus.read);
      // Propagation: m1 and m2 (older, same sender) inherit "read by
      // u1 and u2" too → also flip to read.
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
      expect(c.receiptStatuses['m2'], ReceiptStatus.read);
      // The foreign message has a different sender → untouched.
      expect(c.receiptStatuses['m-foreign'], isNull);
    });
  });

  group('Delivered cursors (applyDeliveryCursor / recordMessageSeq)', () {
    test('cursor covers every message at-or-before, cross-sender', () {
      final c = ChatController(
        initialMessages: [
          own('m1', offset: const Duration(seconds: 1)),
          ChatMessage(
            id: 'm-foreign',
            from: 'u2',
            timestamp: t0.add(const Duration(seconds: 2)),
            text: 'foreign',
          ),
          own('m3', offset: const Duration(seconds: 3)),
          own('m4', offset: const Duration(seconds: 4)),
        ],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      // u1's cursor lands on the FOREIGN message m-foreign: unlike the
      // same-sender propagation of updateReceipt, the cursor must still
      // cover m1 (own, older) even though the cursor message's author
      // is someone else.
      c.applyDeliveryCursor(userId: 'u1', messageId: 'm-foreign', seq: 2);
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
      // Messages after the cursor stay untouched.
      expect(c.receiptStatuses['m3'], isNull);
      expect(c.receiptStatuses['m4'], isNull);
    });

    test('stale cursor (lower seq) is an idempotent no-op', () {
      final c = ChatController(
        initialMessages: [
          own('m1', offset: const Duration(seconds: 1)),
          own('m2', offset: const Duration(seconds: 2)),
          own('m3', offset: const Duration(seconds: 3)),
        ],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.applyDeliveryCursor(userId: 'u1', messageId: 'm3', seq: 3);
      expect(c.receiptStatuses['m3'], ReceiptStatus.delivered);

      // u1 then reads everything; a late/stale delivered cursor must
      // not regress any status (max-register semantics).
      c.updateReceipt('m3', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m3'], ReceiptStatus.read);
      c.applyDeliveryCursor(userId: 'u1', messageId: 'm1', seq: 1);
      expect(c.receiptStatuses['m3'], ReceiptStatus.read);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('numeric coverage by seq wins over list order', () {
      // m-late sorts AFTER the cursor message by timestamp, but its
      // acked seq (5) is <= the cursor seq (9): the live path must
      // cover it numerically.
      final c = ChatController(
        initialMessages: [
          own('m-late', offset: const Duration(seconds: 9)),
          own('m-cursor', offset: const Duration(seconds: 1)),
        ],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.recordMessageSeq('m-late', 5);
      c.recordMessageSeq('m-cursor', 4);
      c.applyDeliveryCursor(userId: 'u1', messageId: 'm-cursor', seq: 9);
      expect(c.receiptStatuses['m-late'], ReceiptStatus.delivered);
      expect(c.receiptStatuses['m-cursor'], ReceiptStatus.delivered);
    });

    test('cursor on a not-yet-loaded message is stashed and re-applied '
        'by setMessages', () {
      final c = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      // Cursor arrives before the history page (no seqs known either).
      c.applyDeliveryCursor(userId: 'u1', messageId: 'm2');
      expect(c.receiptStatuses, isEmpty);

      c.setMessages([
        own('m1', offset: const Duration(seconds: 1)),
        own('m2', offset: const Duration(seconds: 2)),
        own('m3', offset: const Duration(seconds: 3)),
      ]);
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
      expect(c.receiptStatuses['m2'], ReceiptStatus.delivered);
      expect(c.receiptStatuses['m3'], isNull);
    });
  });

  group('clearMessages resets all per-user tracking', () {
    test('aggregated and per-user maps are wiped after clearMessages', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.clearMessages();
      expect(c.receiptStatuses, isEmpty);
      // After re-seeding the same id, status starts from scratch.
      c.addMessage(own('m1'));
      expect(c.receiptStatuses['m1'], isNull);
    });
  });

  group('Group flag while members hydrate (regression)', () {
    test('a group with no members hydrated yet does NOT flip to read on one '
        'peer read when setIsGroup(true) is set', () {
      // Reproduces the bug: the controller opens before its member list
      // loads, so `_otherUsers` is empty and the count heuristic would treat
      // it as a 1:1, marking the message read-by-all on the first peer read.
      // setIsGroup pins the group decision so that can't happen.
      final c = ChatController(initialMessages: [own('m1')], currentUser: me);
      addTearDown(c.dispose);
      c.setIsGroup(true);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      // Members unknown → can't be "read by all" → the aggregate is unknown
      // and nothing is recorded. Absent and `sent` render identically (one
      // check); what matters is that it did NOT flip to read.
      expect(c.receiptStatuses['m1'], isNull);
    });

    test('without the group flag, an unhydrated chat falls back to the 1:1 '
        'heuristic (single peer read => read)', () {
      final c = ChatController(initialMessages: [own('m1')], currentUser: me);
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      // No flag, no members → treated as 1:1 (legacy behaviour preserved).
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('setOtherUsers recomputes receipts: a group stuck at a wrong status '
        'corrects once the member list arrives', () {
      final c = ChatController(initialMessages: [own('m1')], currentUser: me);
      addTearDown(c.dispose);
      c.setIsGroup(true);

      // Two of three peers read while the roster is still empty: no divisor
      // for "read by all" yet, so nothing is recorded (renders as one check).
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u2');
      expect(c.receiptStatuses['m1'], isNull);

      // Member list arrives with three members — still not read-by-all.
      c.setOtherUsers(const [
        ChatUser(id: 'u1', displayName: 'Alice'),
        ChatUser(id: 'u2', displayName: 'Bob'),
        ChatUser(id: 'u3', displayName: 'Charlie'),
      ]);
      expect(c.receiptStatuses['m1'], ReceiptStatus.sent);

      // The third peer reads → now genuinely read-by-all.
      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u3');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('setIsGroup(false) forces the 1:1 rule even with several members', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [
          ChatUser(id: 'u1', displayName: 'Alice'),
          ChatUser(id: 'u2', displayName: 'Bob'),
        ],
      );
      addTearDown(c.dispose);
      c.setIsGroup(false);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test(
      'isGroup getter reflects the explicit flag, then the member count',
      () {
        final c = ChatController(initialMessages: const [], currentUser: me);
        addTearDown(c.dispose);
        expect(c.isGroup, isFalse); // no flag, no members
        c.setOtherUsers(const [
          ChatUser(id: 'u1', displayName: 'Alice'),
          ChatUser(id: 'u2', displayName: 'Bob'),
        ]);
        expect(c.isGroup, isTrue); // inferred from count
        c.setIsGroup(false);
        expect(c.isGroup, isFalse); // explicit wins
      },
    );
  });

  group('wholesale receipt (fromUserId == null) rank-guard (R2-12)', () {
    test('an out-of-order delivered never regresses a read bubble', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      // Backlog `delivered` for the same message arrives late — must be
      // ignored, not flip the bubble back to a single gray double-check.
      c.updateReceipt('m1', ReceiptStatus.delivered);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('the guard honours the message\'s own baseline receipt', () {
      // The message already loaded as `read` from the server; no aggregated
      // entry recorded yet. A stale wholesale `delivered` must not downgrade.
      final c = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'me',
            timestamp: t0,
            text: 'm1',
            receipt: ReceiptStatus.read,
          ),
        ],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered);
      expect(c.receiptStatuses['m1'], isNot(ReceiptStatus.delivered));
    });

    test('still advances forward (sent → delivered → read)', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.delivered);
      expect(c.receiptStatuses['m1'], ReceiptStatus.delivered);
      c.updateReceipt('m1', ReceiptStatus.read);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });
  });

  group('Monotonicity: a check never walks back', () {
    const peers = [
      ChatUser(id: 'u1', displayName: 'Alice'),
      ChatUser(id: 'u2', displayName: 'Bob'),
      ChatUser(id: 'u3', displayName: 'Charlie'),
    ];

    test('rank never decreases across an arbitrary sequence of events', () {
      const ids = ['m1', 'm2', 'm3'];

      for (var seed = 0; seed < 30; seed++) {
        final rnd = Random(seed);
        final c = ChatController(
          initialMessages: [
            own('m1', offset: const Duration(seconds: 1)),
            own('m2', offset: const Duration(seconds: 2)),
            own('m3', offset: const Duration(seconds: 3)),
          ],
          currentUser: me,
          otherUsers: peers,
        );
        addTearDown(c.dispose);
        final highWater = {for (final id in ids) id: 0};

        for (var step = 0; step < 80; step++) {
          final id = ids[rnd.nextInt(ids.length)];
          final peer = peers[rnd.nextInt(peers.length)].id;
          final status =
              ReceiptStatus.values[rnd.nextInt(ReceiptStatus.values.length)];
          final event = rnd.nextInt(6);
          if (event == 0) {
            c.updateReceipt(id, status);
          } else if (event == 1) {
            c.updateReceipt(id, status, fromUserId: peer);
          } else if (event == 2) {
            c.applyDeliveryCursor(
              userId: peer,
              messageId: id,
              seq: rnd.nextInt(5),
            );
          } else if (event == 3) {
            c.setOtherUsers(peers.take(rnd.nextInt(peers.length + 1)).toList());
          } else if (event == 4) {
            c.setIsGroup(rnd.nextBool());
          } else {
            c.recordMessageSeq(id, rnd.nextInt(5));
          }

          for (final tracked in ids) {
            final rank = c.receiptStatuses[tracked]?.rank ?? 0;
            expect(
              rank,
              greaterThanOrEqualTo(highWater[tracked]!),
              reason:
                  'seed $seed, step $step (event $event): $tracked regressed '
                  'from ${highWater[tracked]} to $rank',
            );
            highWater[tracked] = rank;
          }
        }
      }
    });

    test('re-entering the app with an unhydrated roster keeps read', () {
      // The closed reproduction: the room is known to be a group, every peer
      // had read, and the controller is rebuilt (app resumed) before member
      // hydration lands — the roster momentarily goes empty.
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: peers,
      );
      addTearDown(c.dispose);
      c.setIsGroup(true);
      for (final p in peers) {
        c.updateReceipt('m1', ReceiptStatus.read, fromUserId: p.id);
      }
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.setOtherUsers(const []);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('an emptied roster keeps read in a DM too', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.setOtherUsers(const []);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('setIsGroup does not downgrade an already-read message', () {
      // Receipts can land before the adapter pins the room type: the peer
      // read while the chat still looked like a 1:1.
      final c = ChatController(initialMessages: [own('m1')], currentUser: me);
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.setIsGroup(true);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('a growing member count does not downgrade', () {
      // The group opened with a partial roster (one member), the only known
      // peer read, and the remaining members arrive afterwards.
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);
      c.setIsGroup(true);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);

      c.setOtherUsers(peers);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });

    test('a delivered cursor does not downgrade the server baseline', () {
      // After a resume the aggregate cache is empty and the only receipt
      // knowledge is the message's own field, rehydrated from cache. The
      // peer acking a NEWER message drags a delivered cursor over this one.
      final c = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'm1',
            from: 'me',
            timestamp: t0,
            text: 'm1',
            receipt: ReceiptStatus.read,
          ),
          own('m2', offset: const Duration(seconds: 1)),
        ],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.applyDeliveryCursor(userId: 'u1', messageId: 'm2');
      expect(c.receiptStatuses['m1'], isNot(ReceiptStatus.delivered));
      expect(c.receiptStatuses['m2'], ReceiptStatus.delivered);
    });

    test('clearMessages resets the monotonic floor', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      c.clearMessages();
      expect(c.receiptStatuses, isEmpty);

      // The reset must be real, not merely a cleared map shadowed by the old
      // floor: the same id can go back to `sent` in the reloaded room.
      c.addMessage(own('m1'));
      c.updateReceipt('m1', ReceiptStatus.sent, fromUserId: 'u1');
      expect(c.receiptStatuses['m1'], ReceiptStatus.sent);
    });
  });

  group('Write-back queue (drainReceiptUpdates)', () {
    test('a receipt that landed before its row is queued once the row '
        'arrives', () {
      // The ack beat the send confirmation: nothing carries the value but
      // the aggregate map, and the row that finally shows up came off the
      // wire without a receipt. What the drain returns here is the only
      // thing standing between that value and a cold start without it.
      final c = ChatController(
        initialMessages: const [],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt('m1', ReceiptStatus.read, fromUserId: 'u1');
      expect(c.drainReceiptUpdates(), isEmpty);

      c.addMessage(own('m1'));

      final drained = c.drainReceiptUpdates();
      expect(drained.map((m) => m.id), ['m1']);
      expect(drained.single.receipt, ReceiptStatus.read);
    });

    test('a mark applied as not persistable never leaves through the '
        'drain', () {
      final c = ChatController(
        initialMessages: [own('m1')],
        currentUser: me,
        otherUsers: const [ChatUser(id: 'u1', displayName: 'Alice')],
      );
      addTearDown(c.dispose);

      c.updateReceipt(
        'm1',
        ReceiptStatus.read,
        fromUserId: 'u1',
        persistable: false,
      );
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
      expect(c.drainReceiptUpdates(), isEmpty);

      // Nor through the row landing again and picking the value back up.
      c.addMessage(own('m1'));
      expect(c.drainReceiptUpdates(), isEmpty);
      expect(c.receiptStatuses['m1'], ReceiptStatus.read);
    });
  });
}
