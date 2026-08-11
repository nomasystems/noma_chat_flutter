import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Wiring tests for the adapter-owned collaborators whose behaviour is
/// opt-in by construction:
///
/// - `PresenceRegistry` and `DeliveredConfirmationCoordinator` both take an
///   optional connection-state listenable. It defaults to `null` (gate off)
///   so a host can build either standalone, which means the adapter is the
///   only place that can arm them. These tests fail if that argument is
///   dropped from the construction sites.
/// - `RoomEnricher.hydrationNotifier` is only reachable through the
///   adapter's `roomHydrationNotifier`, and only released if the adapter
///   disposes the enricher.
void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  ChatMessage incoming(String id) => ChatMessage(
    id: id,
    from: 'u2',
    text: 'hi',
    timestamp: DateTime.utc(2026),
  );

  group('presence bootstrap network gate', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'u1');
      adapter = ChatUiAdapter(client: client, currentUser: currentUser);
      client.presence.injectContact(
        const ChatPresence(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    test('offline loadRooms does not fire GET /presence', () async {
      expect(
        adapter.connectionStateNotifier.value.isConnected,
        isFalse,
        reason: 'precondition: the adapter has never connected',
      );

      await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        client.presence.getAllCallCount,
        0,
        reason:
            '`GET /presence` has no cache tier, so an offline bootstrap is a '
            'doomed round-trip on the cold-start path. Arming the registry '
            'is the adapter constructor\'s job.',
      );
    });

    test('the gate reopens once the transport is connected', () async {
      await adapter.connect();
      await Future.delayed(Duration.zero);
      client.presence.resetCallCount();

      await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        client.presence.getAllCallCount,
        greaterThanOrEqualTo(1),
        reason: 'the gate must skip the fetch, never disable it',
      );
    });
  });

  group('delivered confirmation network gate', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'u1');
      client.seedUser(const ChatUser(id: 'u2', displayName: 'Peer'));
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Room', members: ['u1']));
      client.addMessage('r1', incoming('m1'));
      adapter = ChatUiAdapter(
        client: client,
        currentUser: currentUser,
        // A read receipt implies delivery server-side, so the delivered
        // confirmation only runs when the read flush does not.
        autoMarkAsRead: false,
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    test(
      'offline message load does not confirm the delivered cursor',
      () async {
        expect(adapter.connectionStateNotifier.value.isConnected, isFalse);

        await adapter.messages.load('r1');
        await Future.delayed(const Duration(milliseconds: 20));

        expect(
          client.messages.markRoomAsDeliveredCalls,
          isEmpty,
          reason:
              'the room sync fires one of these per unread room on its cache '
              'pass; offline that is N doomed requests racing the first paint',
        );
      },
    );

    test('confirms once connected, and re-confirms after signOut', () async {
      await adapter.connect();
      await Future.delayed(Duration.zero);
      client.messages.resetMarkRoomAsDeliveredCalls();

      await adapter.messages.load('r1');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(client.messages.markRoomAsDeliveredCalls, hasLength(1));

      // Same cursor, same room: suppressed by the coordinator's own repeat
      // gate. This is the state that must not survive the session.
      await adapter.messages.load('r1');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(client.messages.markRoomAsDeliveredCalls, hasLength(1));

      await adapter.signOut();
      // `MockChatClient.logout` wipes its own store, which `signOut` routes
      // through. Re-seed so the next load has the same room at the same
      // cursor — the whole point is that the coordinator no longer
      // remembers having confirmed it.
      client.seedUser(const ChatUser(id: 'u2', displayName: 'Peer'));
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Room', members: ['u1']));
      client.addMessage('r1', incoming('m1'));
      await adapter.connect();
      await Future.delayed(Duration.zero);

      await adapter.messages.load('r1');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        client.messages.markRoomAsDeliveredCalls,
        hasLength(2),
        reason:
            'the suppression map is keyed by room id alone, so a cursor '
            'confirmed by the outgoing identity would silently swallow the '
            'incoming one\'s first confirmation for the same room',
      );
    });
  });

  group('roomHydrationNotifier', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'u1');
      adapter = ChatUiAdapter(client: client, currentUser: currentUser);
    });

    test('is reachable from the public barrel and starts pending', () {
      final ValueListenable<RoomHydrationStatus> notifier =
          adapter.roomHydrationNotifier;

      expect(notifier.value.outcome, RoomHydrationOutcome.pending);
      expect(notifier.value.hasRun, isFalse);
      expect(notifier.value.roomCount, 0);

      addTearDown(() async {
        await adapter.dispose();
        await client.dispose();
      });
    });

    test('publishes the cache-phase outcome after a load', () async {
      await adapter.loadRooms();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        adapter.roomHydrationNotifier.value.hasRun,
        isTrue,
        reason:
            'the getter must delegate to the live enricher notifier, '
            'not to a detached copy',
      );

      addTearDown(() async {
        await adapter.dispose();
        await client.dispose();
      });
    });

    test('is released by dispose()', () async {
      final notifier = adapter.roomHydrationNotifier;
      await adapter.dispose();
      await client.dispose();

      expect(
        () => notifier.addListener(() {}),
        throwsFlutterError,
        reason: 'the adapter owns the enricher, so it owns its notifier',
      );
    });
  });
}
