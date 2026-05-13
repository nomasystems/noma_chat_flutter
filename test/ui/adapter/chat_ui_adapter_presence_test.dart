import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Tests for the presence cache and public APIs added in DEC-036.
/// The bootstrap path itself (loadRooms -> presence.getAll()) is covered by
/// the manual smoke E2E; here we focus on the cache-driven APIs that any
/// consumer (e.g. WB/mobile Sugerencias) relies on.
void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('presence cache', () {
    test('presenceFor returns null when no info has been received', () {
      expect(adapter.presenceFor('u2'), isNull);
    });

    test('PresenceChangedEvent populates the cache', () async {
      await adapter.connect();
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future.delayed(Duration.zero);
      final p = adapter.presenceFor('u2');
      expect(p, isNotNull);
      expect(p!.online, isTrue);
      expect(p.status, PresenceStatus.available);
    });

    test('PresenceChangedEvent overrides previous cached value', () async {
      await adapter.connect();
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await Future.delayed(Duration.zero);
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.offline,
          online: false,
        ),
      );
      await Future.delayed(Duration.zero);
      final p = adapter.presenceFor('u2');
      expect(p!.online, isFalse);
      expect(p.status, PresenceStatus.offline);
    });

    test('different users are tracked independently', () async {
      await adapter.connect();
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u3',
          status: PresenceStatus.offline,
          online: false,
        ),
      );
      await Future.delayed(Duration.zero);
      expect(adapter.presenceFor('u2')!.online, isTrue);
      expect(adapter.presenceFor('u3')!.online, isFalse);
      expect(adapter.presenceFor('u4'), isNull);
    });
  });

  group('presenceStreamFor', () {
    test('emits only events for the requested user', () async {
      await adapter.connect();
      final received = <bool>[];
      final sub = adapter.presenceStreamFor('u2').listen((p) {
        received.add(p.online);
      });
      addTearDown(sub.cancel);

      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u3',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      mockClient.emitEvent(
        const ChatEvent.presenceChanged(
          userId: 'u2',
          status: PresenceStatus.offline,
          online: false,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(received, [true, false]);
    });
  });

  group('reconnect refresh', () {
    test('ConnectedEvent after a disconnect re-runs presence.getAll', () async {
      // Seed the mock so getAll returns a known contact.
      mockClient.presence.injectContact(
        const ChatPresence(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );

      await adapter.connect();
      // First connect already triggered a load via the constructor's mock,
      // but here we explicitly drive a transition disconnected→connected.
      await Future.delayed(Duration.zero);
      mockClient.presence.resetCallCount();

      // Simulate WS drop + reconnect.
      mockClient.emitEvent(const ChatEvent.disconnected());
      await Future.delayed(Duration.zero);
      mockClient.emitEvent(const ChatEvent.connected());
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        mockClient.presence.getAllCallCount,
        greaterThanOrEqualTo(1),
        reason:
            'ConnectedEvent after a disconnect should refresh the presence cache',
      );
    });

    test('two ConnectedEvents in a row only refresh once', () async {
      mockClient.presence.injectContact(
        const ChatPresence(
          userId: 'u2',
          status: PresenceStatus.available,
          online: true,
        ),
      );
      await adapter.connect();
      await Future.delayed(Duration.zero);
      mockClient.presence.resetCallCount();

      // Two connected events without a disconnect in between (idempotent).
      mockClient.emitEvent(const ChatEvent.connected());
      mockClient.emitEvent(const ChatEvent.connected());
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        mockClient.presence.getAllCallCount,
        0,
        reason:
            'No state transition: getAll should not be called when already connected',
      );
    });
  });
}
