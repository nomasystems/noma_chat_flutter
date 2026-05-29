import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:flutter_test/flutter_test.dart';

ChatConfig _config({required RealtimeMode mode}) => ChatConfig(
  baseUrl: 'http://localhost:8077/v1',
  realtimeUrl: 'http://localhost:8077',
  tokenProvider: () async => 'test-token',
  realtimeMode: mode,
  // Tight timeouts so the smoke tests resolve quickly when the
  // factory wires a transport against the (non-existent) localhost
  // backend.
  authTimeout: const Duration(milliseconds: 100),
  wsReconnectDelay: const Duration(milliseconds: 10),
  maxReconnectAttempts: 1,
);

void main() {
  group('TransportManager.fromConfig', () {
    test('auto: factory returns a manager (failover composite)', () async {
      final manager = TransportManager.fromConfig(
        _config(mode: RealtimeMode.auto),
      );
      // Pre-connect: isWsConnected gates on `state == connected`.
      expect(manager.state, ChatConnectionState.disconnected);
      expect(manager.isWsConnected, isFalse);
      final eventSub = manager.events.listen((_) {});
      final stateSub = manager.stateChanges.listen((_) {});
      await eventSub.cancel();
      await stateSub.cancel();
    });

    test('webSocketOnly: factory returns a working manager', () async {
      final manager = TransportManager.fromConfig(
        _config(mode: RealtimeMode.webSocketOnly),
      );
      // Pre-connect smoke: state is disconnected, isWsConnected is
      // false (the underlying WS transport supports outbound frames
      // but state == connected is required to gate to true).
      expect(manager.state, ChatConnectionState.disconnected);
      expect(manager.isWsConnected, isFalse);
      // Wiring sanity: the manager exposes the broadcast streams that
      // sub-APIs depend on, so listening doesn't throw even before
      // connect.
      final eventSub = manager.events.listen((_) {});
      final stateSub = manager.stateChanges.listen((_) {});
      await eventSub.cancel();
      await stateSub.cancel();
    });

    test('serverSentEventsOnly: factory returns a working manager', () async {
      final manager = TransportManager.fromConfig(
        _config(mode: RealtimeMode.serverSentEventsOnly),
      );
      // SSE does not carry outbound frames, so isWsConnected stays
      // false in any state.
      expect(manager.state, ChatConnectionState.disconnected);
      expect(manager.isWsConnected, isFalse);
      final eventSub = manager.events.listen((_) {});
      final stateSub = manager.stateChanges.listen((_) {});
      await eventSub.cancel();
      await stateSub.cancel();
    });

    test('polling: factory returns a working manager (REST polling)', () async {
      final manager = TransportManager.fromConfig(
        _config(mode: RealtimeMode.polling),
      );
      // Polling has no outbound real-time channel — sendViaWs/typing/
      // receipts fall back to REST.
      expect(manager.state, ChatConnectionState.disconnected);
      expect(manager.isWsConnected, isFalse);
      final eventSub = manager.events.listen((_) {});
      final stateSub = manager.stateChanges.listen((_) {});
      await eventSub.cancel();
      await stateSub.cancel();
    });

    test('polling: clamps interval below 5 s to 5 s without throwing', () {
      final cfg = ChatConfig(
        baseUrl: 'http://localhost:8077/v1',
        realtimeUrl: 'http://localhost:8077',
        tokenProvider: () async => 'test-token',
        realtimeMode: RealtimeMode.polling,
        pollingConfig: const PollingConfig(interval: Duration(seconds: 1)),
      );
      // Previously threw ArgumentError; SDK now clamps to the 5 s minimum
      // and logs a warning so consumers do not crash on misconfiguration.
      expect(() => TransportManager.fromConfig(cfg), returnsNormally);
    });

    test('manual: factory returns a working manager (refresh-only)', () async {
      final manager = TransportManager.fromConfig(
        _config(mode: RealtimeMode.manual),
      );
      // Manual is the strictest mode — no streams, no outbound
      // frames. `refresh()` is the only way to receive updates.
      expect(manager.state, ChatConnectionState.disconnected);
      expect(manager.isWsConnected, isFalse);
      final eventSub = manager.events.listen((_) {});
      final stateSub = manager.stateChanges.listen((_) {});
      await eventSub.cancel();
      await stateSub.cancel();
    });
  });
}
