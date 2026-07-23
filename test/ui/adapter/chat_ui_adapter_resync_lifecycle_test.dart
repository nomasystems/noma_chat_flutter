import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Cluster ➋ (WS reliability + app lifecycle) coverage for
/// `ChatUiAdapter.resync`, its debounce, the automatic reconnect trigger and
/// the `manageAppLifecycle`/`lifecyclePolicy` constructor wiring.
void main() {
  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
  });

  tearDown(() async {
    await client.dispose();
  });

  group('resync()', () {
    test('is a no-op before the first loadRooms ever completed — nothing '
        'to resync yet, and it must not race the host\'s own initial load',
        () async {
      var loadedCount = 0;
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
        onRoomsLoaded: (_) => loadedCount++,
      );
      client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));

      await adapter.resync();

      expect(loadedCount, 0);
      expect(adapter.roomListController.rooms, isEmpty);

      await adapter.dispose();
    });

    test('once initialized, loads rooms from the network', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );
      await adapter.rooms.load();
      expect(adapter.roomListController.rooms, isEmpty);

      // A room that appeared server-side after the initial load — resync
      // must pick it up.
      client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
      await adapter.resync();

      expect(adapter.roomListController.rooms.any((r) => r.id == 'r1'), isTrue);

      await adapter.dispose();
    });

    test('once initialized, reloads the active room, backfilling messages '
        'that arrived while disconnected', () async {
      client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );
      await adapter.rooms.load();
      adapter.getChatController('r1');
      adapter.setActiveRoom('r1');

      // Simulate a message that landed on the server during a disconnected
      // window — the client never saw it as a live event.
      client.addMessage(
        'r1',
        ChatMessage(
          id: 'm1',
          from: 'bob',
          timestamp: DateTime(2026, 1, 1),
          text: 'missed while offline',
        ),
      );

      await adapter.resync();

      final controller = adapter.getChatController('r1');
      expect(controller.messages.any((m) => m.id == 'm1'), isTrue);

      await adapter.dispose();
    });

    test('is a no-op when disposed', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );
      await adapter.dispose();

      await expectLater(adapter.resync(), completes);
    });

    test('is debounced to at most once every 5 seconds', () async {
      var loadedCount = 0;
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
        onRoomsLoaded: (_) => loadedCount++,
      );
      await adapter.rooms.load();
      expect(loadedCount, 1);

      client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
      await adapter.resync();
      expect(loadedCount, 2);

      // A second call within the 5s debounce window must not re-trigger
      // the network round-trip.
      await adapter.resync();
      expect(loadedCount, 2);

      await adapter.dispose();
    });

    test(
      'does not consume the debounce window when the network fetch fails, '
      'so the very next call retries instead of waiting out the window',
      () async {
        var loadedCount = 0;
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: const ChatUser(id: 'me', displayName: 'Me'),
          manageAppLifecycle: false,
          onRoomsLoaded: (_) => loadedCount++,
        );
        await adapter.rooms.load();
        expect(loadedCount, 1);

        // Fail only the forced network pass (not the cache-only pass
        // `loadAll` always tries first) so `resync`'s `loadRooms` call
        // surfaces a failed `ChatResult` — `onRoomsLoaded` is only invoked
        // on a successful network pass, so `loadedCount` staying put is
        // the observable signature of that failure.
        client.rooms.failNextGetUserRooms = true;
        await adapter.resync();
        expect(
          loadedCount,
          1,
          reason: 'the network pass failed, so no fresh snapshot was applied',
        );

        // Immediately retrying (still well within the nominal 5s debounce
        // window) must succeed instead of being swallowed by the debounce
        // that a naive "stamp before await" would have left in place.
        await adapter.resync();
        expect(
          loadedCount,
          2,
          reason:
              'a failed resync must not consume the debounce window — the '
              'very next call should go to the network, not be skipped',
        );

        await adapter.dispose();
      },
    );

    test(
      'a trigger that lands while a resync is in flight is coalesced into a '
      'follow-up pass, not swallowed by the debounce (R2-11)',
      () async {
        var loadedCount = 0;
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: const ChatUser(id: 'me', displayName: 'Me'),
          manageAppLifecycle: false,
          onRoomsLoaded: (_) => loadedCount++,
        );
        await adapter.rooms.load();
        expect(loadedCount, 1);

        client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));

        // Two reconnects <5s apart: the first starts a resync that suspends
        // on its first network await; the second lands mid-flight. The old
        // "stamp-then-debounce" path dropped the second (2 total loads);
        // coalescing runs a follow-up pass instead (3 total).
        final f1 = adapter.resync();
        final f2 = adapter.resync();
        await Future.wait([f1, f2]);

        expect(
          loadedCount,
          3,
          reason:
              'the mid-flight trigger must run a follow-up resync — a live '
              'reconnection carries its own backlog and must not be dropped',
        );

        await adapter.dispose();
      },
    );

    test(
      'a resync that THROWS (not just returns a failure) reverts its debounce '
      'seal, so the very next call retries instead of being swallowed (R2-3)',
      () async {
        var loadedCount = 0;
        client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: const ChatUser(id: 'me', displayName: 'Me'),
          manageAppLifecycle: false,
          onRoomsLoaded: (_) => loadedCount++,
        );
        await adapter.rooms.load();
        expect(loadedCount, 1);
        adapter.getChatController('r1');
        adapter.setActiveRoom('r1');

        // The active-room message reload throws (a raw exception, not a
        // failed ChatResult) during this resync's second leg.
        client.messages.throwNextList = true;
        await adapter.resync();
        expect(
          loadedCount,
          2,
          reason:
              'loadRooms succeeded (bumping the counter) before loadMessages '
              'threw — the attempt as a whole still failed',
        );

        // Retry within the nominal 5s window must go to the network: a
        // thrown attempt must revert the seal exactly like an isFailure one.
        await adapter.resync();
        expect(
          loadedCount,
          3,
          reason:
              'an exception in the resync must revert the debounce seal — the '
              'next call must not be swallowed by a stale seal',
        );

        await adapter.dispose();
      },
    );

    test(
      'a trigger dropped by the time debounce is not lost — it runs '
      'deferred once the window clears (BLOCKER/MAJOR-3)',
      () async {
        var loadedCount = 0;
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: const ChatUser(id: 'me', displayName: 'Me'),
          manageAppLifecycle: false,
          onRoomsLoaded: (_) => loadedCount++,
          resyncDebounce: const Duration(milliseconds: 50),
        );
        await adapter.rooms.load();
        expect(loadedCount, 1);

        client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
        await adapter.resync();
        expect(loadedCount, 2);

        // Lands inside the debounce window: must not be dropped outright —
        // it should arm a single deferred pass for the remainder of it.
        await adapter.resync();
        expect(
          loadedCount,
          2,
          reason: 'still inside the window — no immediate network round-trip',
        );

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          loadedCount,
          3,
          reason:
              'the debounce-dropped trigger must still run once the window '
              'clears, catching up on whatever prompted it instead of being '
              'silently lost',
        );

        await adapter.dispose();
      },
    );

    test(
      'a burst of triggers inside the same debounce window coalesces into '
      'a single deferred pass, not one per trigger',
      () async {
        var loadedCount = 0;
        final adapter = ChatUiAdapter(
          client: client,
          currentUser: const ChatUser(id: 'me', displayName: 'Me'),
          manageAppLifecycle: false,
          onRoomsLoaded: (_) => loadedCount++,
          resyncDebounce: const Duration(milliseconds: 50),
        );
        await adapter.rooms.load();
        expect(loadedCount, 1);

        client.seedRoom(const ChatRoom(id: 'r1', members: ['me', 'bob']));
        await adapter.resync();
        expect(loadedCount, 2);

        await adapter.resync();
        await adapter.resync();
        await adapter.resync();

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          loadedCount,
          3,
          reason:
              'three debounced triggers in the same window must coalesce '
              'into exactly one deferred pass, not three',
        );

        await adapter.dispose();
      },
    );
  });

  group('connect()/start() subscription wiring', () {
    test('client.stateChanges keeps delivering after connect() — a fresh '
        'connect must not leave the state subscription cancelled by a '
        'stale _cancelSubscriptions() call racing start()\'s reassignment',
        () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );

      await adapter.connect();
      client.emitConnectionState(ChatConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(
        adapter.connectionStateNotifier.value,
        ChatConnectionState.reconnecting,
        reason:
            'an intermediate state with no accompanying ChatEvent (as WS '
            'connecting/authenticating/reconnecting all are) only ever '
            'reaches connectionStateNotifier via the stateChanges '
            'subscription — if that subscription was silently cancelled '
            'right after being created, this value would still read '
            'connected from the earlier ConnectedEvent.',
      );

      await adapter.dispose();
    });

    test('a second connect() does not leak the previous event subscription '
        '— each event is delivered exactly once, not once per past connect',
        () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );

      var reconnectedCount = 0;
      adapter.onReconnected = () => reconnectedCount++;

      await adapter.connect();
      await adapter.disconnect();
      await adapter.connect();
      await adapter.disconnect();
      await adapter.connect();
      await Future<void>.delayed(Duration.zero);

      expect(
        reconnectedCount,
        3,
        reason:
            'three connects must fire onReconnected exactly three times — '
            'a stale, never-actually-cancelled event subscription from an '
            'earlier connect() would double- or triple-count the same '
            'ConnectedEvent once enough reconnect cycles piled up.',
      );

      await adapter.dispose();
    });
  });

  group('automatic reconnect-triggered resync', () {
    test('enableReconnectResync (default true): a reconnect after rooms '
        'have already loaded once triggers resync via the reconnect hook',
        () async {
      var loadedCount = 0;
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
        onRoomsLoaded: (_) => loadedCount++,
      );

      // First connect: nothing to resync yet (rooms never loaded).
      await adapter.connect();
      await adapter.rooms.load();
      expect(loadedCount, 1);

      // A drop + reconnect now has something to catch up on.
      await adapter.disconnect();
      await adapter.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        loadedCount,
        greaterThanOrEqualTo(2),
        reason:
            'the reconnect must trigger an automatic resync now that rooms '
            'have been loaded once',
      );

      await adapter.dispose();
    });

    test('enableReconnectResync: false disables the automatic trigger',
        () async {
      var loadedCount = 0;
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
        enableReconnectResync: false,
        onRoomsLoaded: (_) => loadedCount++,
      );

      await adapter.connect();
      await adapter.rooms.load();
      expect(loadedCount, 1);

      await adapter.disconnect();
      await adapter.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        loadedCount,
        1,
        reason: 'no automatic resync must fire beyond the explicit load',
      );

      await adapter.dispose();
    });
  });

  group('manageAppLifecycle / lifecyclePolicy constructor wiring', () {
    test('manageAppLifecycle defaults to true and lifecyclePolicy to '
        '.standard()', () async {
      // Constructing with the default (manageAppLifecycle: true) must not
      // throw even without a Flutter binding (plain unit test) — attach()
      // is a best-effort no-op in that case.
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      );

      expect(adapter.manageAppLifecycle, isTrue);
      expect(adapter.lifecyclePolicy.onPause, ChatPauseAction.keepAlive);

      await adapter.dispose();
    });

    test('manageAppLifecycle: false skips registering the observer '
        '(dispose is still safe)', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
      );

      expect(adapter.manageAppLifecycle, isFalse);
      await adapter.dispose();
    });

    test('lifecyclePolicy is overridable to pushOptimized()', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
        manageAppLifecycle: false,
        lifecyclePolicy: const ChatLifecyclePolicy.pushOptimized(),
      );

      expect(adapter.lifecyclePolicy.onPause, ChatPauseAction.disconnect);

      await adapter.dispose();
    });
  });
}
