import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat_example/chat_session.dart';
import 'package:noma_chat_example/settings/example_settings.dart';

void main() {
  group('ExampleSettings', () {
    test('default values are sensible', () {
      const s = ExampleSettings();
      expect(s.username, '');
      expect(s.mode, ChatMode.mock);
      expect(s.baseUrl, 'http://localhost:8077/v1');
      expect(s.realtimeUrl, 'http://localhost:8077');
      expect(s.realtimeMode, RealtimeMode.auto);
      expect(s.pollingIntervalSeconds, 15);
      expect(s.requestTimeoutSeconds, 30);
      expect(s.wsReconnectDelaySeconds, 2);
      expect(s.sseUrl, isNull);
      expect(s.wsPath, '/v1/ws');
      expect(s.ssePath, '/eventsource');
      expect(s.maxReconnectAttempts, isNull);
      expect(s.eventBufferSize, 20);
    });

    test('toJson + fromJson is a round trip', () {
      const original = ExampleSettings(
        username: 'alice',
        mode: ChatMode.cht,
        baseUrl: 'https://example.com/v2',
        realtimeUrl: 'wss://example.com',
        realtimeMode: RealtimeMode.serverSentEventsOnly,
        pollingIntervalSeconds: 30,
        requestTimeoutSeconds: 15,
        wsReconnectDelaySeconds: 5,
        sseUrl: 'https://events.example.com',
        wsPath: '/realtime/ws',
        ssePath: '/realtime/sse',
        maxReconnectAttempts: 10,
        eventBufferSize: 100,
      );
      final restored = ExampleSettings.fromJson(original.toJson());
      expect(restored, original);
    });

    test('fromJson uses defaults for missing keys', () {
      final restored = ExampleSettings.fromJson({'username': 'bob'});
      expect(restored.username, 'bob');
      expect(restored.mode, ChatMode.mock);
      expect(restored.baseUrl, 'http://localhost:8077/v1');
    });

    test('copyWith clearSseUrl actually clears it', () {
      const initial = ExampleSettings(sseUrl: 'https://sse.example.com');
      final cleared = initial.copyWith(clearSseUrl: true);
      expect(cleared.sseUrl, isNull);
    });

    test('fromJson migrates legacy enableWebSocket=true → auto', () {
      final restored = ExampleSettings.fromJson({
        'username': 'alice',
        'enableWebSocket': true,
      });
      expect(restored.realtimeMode, RealtimeMode.auto);
    });

    test('fromJson migrates legacy enableWebSocket=false → sseOnly', () {
      final restored = ExampleSettings.fromJson({
        'username': 'alice',
        'enableWebSocket': false,
      });
      expect(restored.realtimeMode, RealtimeMode.serverSentEventsOnly);
    });

    test('fromJson explicit realtimeMode wins over legacy bool', () {
      final restored = ExampleSettings.fromJson({
        'username': 'alice',
        'realtimeMode': 'polling',
        'enableWebSocket': true, // would otherwise migrate to auto
      });
      expect(restored.realtimeMode, RealtimeMode.polling);
    });
  });

  group('demoContactsFromEnv', () {
    test('returns empty when no dart-define is set', () {
      expect(demoContactsFromEnv(), isEmpty);
    });
  });
}
