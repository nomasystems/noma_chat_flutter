import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/manual_transport.dart';
import 'package:flutter_test/flutter_test.dart';

ChatConfig _config() => ChatConfig(
  baseUrl: 'http://localhost:8077/v1',
  realtimeUrl: 'http://localhost:8077',
  tokenProvider: () async => 'test-token',
  realtimeMode: RealtimeMode.manual,
);

void main() {
  group('ManualTransport', () {
    test('supportsOutboundFrames is false', () {
      final t = ManualTransport(config: _config());
      expect(t.supportsOutboundFrames, isFalse);
    });

    test('starts disconnected', () {
      final t = ManualTransport(config: _config());
      expect(t.state, ChatConnectionState.disconnected);
    });

    test('connect emits ConnectedEvent without setting up any timer', () async {
      final t = ManualTransport(config: _config());
      final events = <ChatEvent>[];
      t.events.listen(events.add);

      await t.connect();
      await Future<void>.delayed(Duration.zero);

      expect(t.state, ChatConnectionState.connected);
      expect(events.whereType<ConnectedEvent>(), isNotEmpty);

      // Wait a bit and confirm no additional events arrive: there is
      // no background timer in manual mode.
      events.clear();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(events, isEmpty);

      await t.dispose();
    });

    test('refresh is a no-op when not connected', () async {
      final t = ManualTransport(config: _config());
      // No connect call → refresh early-returns without touching
      // network or emitting events.
      await expectLater(t.refresh(), completes);
      await t.dispose();
    });

    test('sendXxx are silent no-ops in any state', () async {
      final t = ManualTransport(config: _config());
      expect(() => t.sendTyping('r1'), returnsNormally);
      expect(() => t.sendDmTyping('contact'), returnsNormally);
      expect(() => t.sendReceipt('r1', 'm1'), returnsNormally);
      expect(() => t.sendMessage('r1', text: 'x'), returnsNormally);
      await t.dispose();
    });

    test('notifyTokenRotated is a no-op', () async {
      final t = ManualTransport(config: _config());
      await expectLater(t.notifyTokenRotated(), completes);
      await t.dispose();
    });

    test('disconnect leaves transport in disconnected state', () async {
      final t = ManualTransport(config: _config());
      await t.connect();
      await t.disconnect();
      expect(t.state, ChatConnectionState.disconnected);
      await t.dispose();
    });
  });
}
