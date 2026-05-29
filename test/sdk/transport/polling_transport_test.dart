import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/polling_transport.dart';
import 'package:flutter_test/flutter_test.dart';

ChatConfig _config({Duration interval = const Duration(hours: 1)}) =>
    ChatConfig(
      baseUrl: 'http://localhost:8077/v1',
      realtimeUrl: 'http://localhost:8077',
      tokenProvider: () async => 'test-token',
      realtimeMode: RealtimeMode.polling,
      pollingConfig: PollingConfig(interval: interval),
    );

void main() {
  group('PollingTransport', () {
    test('supportsOutboundFrames is false', () {
      final t = PollingTransport(config: _config());
      expect(t.supportsOutboundFrames, isFalse);
    });

    test('starts disconnected', () {
      final t = PollingTransport(config: _config());
      expect(t.state, ChatConnectionState.disconnected);
    });

    test('connect emits ConnectedEvent and flips state', () async {
      final t = PollingTransport(config: _config());
      final events = <ChatEvent>[];
      final stateChanges = <ChatConnectionState>[];
      t.events.listen(events.add);
      t.stateChanges.listen(stateChanges.add);

      await t.connect();
      // Allow the controllers to fan out.
      await Future<void>.delayed(Duration.zero);

      expect(t.state, ChatConnectionState.connected);
      expect(stateChanges, contains(ChatConnectionState.connected));
      expect(events.whereType<ConnectedEvent>(), isNotEmpty);

      await t.dispose();
    });

    test('sendXxx are silent no-ops', () async {
      final t = PollingTransport(config: _config());
      // Don't connect: outbound APIs must work in any state without
      // throwing.
      expect(() => t.sendTyping('r1'), returnsNormally);
      expect(() => t.sendDmTyping('contact-1'), returnsNormally);
      expect(() => t.sendReceipt('r1', 'm1'), returnsNormally);
      expect(() => t.sendMessage('r1', text: 'hi'), returnsNormally);
      await t.dispose();
    });

    test(
      'notifyTokenRotated is a no-op (next tick uses fresh token)',
      () async {
        final t = PollingTransport(config: _config());
        await expectLater(t.notifyTokenRotated(), completes);
        await t.dispose();
      },
    );

    test('disconnect flips state and cancels the timer', () async {
      final t = PollingTransport(config: _config());
      await t.connect();
      expect(t.state, ChatConnectionState.connected);

      await t.disconnect();

      expect(t.state, ChatConnectionState.disconnected);
      await t.dispose();
    });

    test('dispose leaves the transport in disconnected state', () async {
      final t = PollingTransport(config: _config());
      await t.connect();
      await t.dispose();
      expect(t.state, ChatConnectionState.disconnected);
    });
  });
}
