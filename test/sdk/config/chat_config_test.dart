import 'package:flutter_test/flutter_test.dart';

import 'package:noma_chat/src/_internal/http/bearer_auth_interceptor.dart';
import 'package:noma_chat/src/config/chat_config.dart';

void main() {
  group('ChatConfig.validateUrls', () {
    group('debug mode', () {
      const isReleaseMode = false;

      test('accepts https on every URL field', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1',
            realtimeUrl: 'https://api.example.com',
            sseUrl: 'https://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          returnsNormally,
        );
      });

      test('accepts http for local development', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'http://localhost:8077/v1',
            realtimeUrl: 'http://localhost:8077',
            isReleaseMode: isReleaseMode,
          ),
          returnsNormally,
        );
      });
    });

    group('release mode', () {
      const isReleaseMode = true;

      test('accepts https on every URL field', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1',
            realtimeUrl: 'https://api.example.com',
            sseUrl: 'https://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          returnsNormally,
        );
      });

      test('rejects http baseUrl', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'http://api.example.com/v1',
            realtimeUrl: 'https://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('http:// is not allowed in release builds'),
            ),
          ),
        );
      });

      test('rejects http realtimeUrl', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1',
            realtimeUrl: 'http://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('http:// is not allowed in release builds'),
            ),
          ),
        );
      });

      test('rejects http sseUrl', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1',
            realtimeUrl: 'https://api.example.com',
            sseUrl: 'http://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('allows http:// to loopback hosts (secure context)', () {
        for (final url in [
          'http://localhost:8077',
          'http://127.0.0.1:8077',
          'http://[::1]:8077',
        ]) {
          expect(
            () => ChatConfig.validateUrls(
              baseUrl: '$url/v1',
              realtimeUrl: url,
              isReleaseMode: isReleaseMode,
            ),
            returnsNormally,
            reason: '$url is loopback and never leaves the device',
          );
        }
      });
    });

    group('common rules (mode-independent)', () {
      test('rejects URL ending with slash', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1/',
            realtimeUrl: 'https://api.example.com',
            isReleaseMode: false,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must not end with /'),
            ),
          ),
        );
      });

      test('rejects ws:// scheme', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'https://api.example.com/v1',
            realtimeUrl: 'ws://api.example.com',
            isReleaseMode: false,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('transports convert automatically'),
            ),
          ),
        );
      });

      test('rejects unknown scheme like ftp://', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'ftp://api.example.com/v1',
            realtimeUrl: 'https://api.example.com',
            isReleaseMode: false,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must use http or https scheme'),
            ),
          ),
        );
      });
    });
  });

  group('WS reliability tunables defaults', () {
    ChatConfig build() => ChatConfig(
      baseUrl: 'https://api.example.com/v1',
      realtimeUrl: 'https://api.example.com',
      tokenProvider: () async => 'token',
    );

    test('wsPingInterval defaults to 30s', () {
      expect(build().wsPingInterval, const Duration(seconds: 30));
    });

    test('wsPongTimeout defaults to 10s', () {
      expect(build().wsPongTimeout, const Duration(seconds: 10));
    });

    test('wsPongWatchdogEnabled defaults to true', () {
      expect(build().wsPongWatchdogEnabled, isTrue);
    });

    test('wsMaxReconnectDelay defaults to 60s', () {
      expect(build().wsMaxReconnectDelay, const Duration(seconds: 60));
    });

    test('wsReconnectJitterMs defaults to 1000', () {
      expect(build().wsReconnectJitterMs, 1000);
    });

    test('every tunable is overridable', () {
      final config = ChatConfig(
        baseUrl: 'https://api.example.com/v1',
        realtimeUrl: 'https://api.example.com',
        tokenProvider: () async => 'token',
        wsPingInterval: const Duration(seconds: 15),
        wsPongTimeout: const Duration(seconds: 5),
        wsPongWatchdogEnabled: false,
        wsMaxReconnectDelay: const Duration(seconds: 30),
        wsReconnectJitterMs: 250,
      );

      expect(config.wsPingInterval, const Duration(seconds: 15));
      expect(config.wsPongTimeout, const Duration(seconds: 5));
      expect(config.wsPongWatchdogEnabled, isFalse);
      expect(config.wsMaxReconnectDelay, const Duration(seconds: 30));
      expect(config.wsReconnectJitterMs, 250);
    });

    test('withAuthInterceptor and withBasicAuth carry the same defaults', () {
      final withInterceptor = ChatConfig.withAuthInterceptor(
        baseUrl: 'https://api.example.com/v1',
        realtimeUrl: 'https://api.example.com',
        authInterceptor: BearerAuthInterceptor(
          tokenProvider: () async => 'token',
        ),
      );
      final withBasic = ChatConfig.withBasicAuth(
        baseUrl: 'https://api.example.com/v1',
        realtimeUrl: 'https://api.example.com',
        username: 'u',
        password: 'p',
      );

      for (final config in [withInterceptor, withBasic]) {
        expect(config.wsPingInterval, const Duration(seconds: 30));
        expect(config.wsPongTimeout, const Duration(seconds: 10));
        expect(config.wsPongWatchdogEnabled, isTrue);
        expect(config.wsMaxReconnectDelay, const Duration(seconds: 60));
        expect(config.wsReconnectJitterMs, 1000);
      }
    });
  });
}
