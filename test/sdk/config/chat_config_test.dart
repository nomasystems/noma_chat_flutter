import 'package:flutter_test/flutter_test.dart';

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

      test('rejects http://localhost (no special-case for loopback)', () {
        expect(
          () => ChatConfig.validateUrls(
            baseUrl: 'http://localhost:8077/v1',
            realtimeUrl: 'https://api.example.com',
            isReleaseMode: isReleaseMode,
          ),
          throwsA(isA<ArgumentError>()),
        );
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
}
