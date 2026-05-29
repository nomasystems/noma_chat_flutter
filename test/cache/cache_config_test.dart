import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart' show CachePolicy;
import 'package:noma_chat/noma_chat_advanced.dart';

void main() {
  group('CacheConfig', () {
    test('uses sane defaults', () {
      const config = CacheConfig();

      expect(config.maxMessagesPerRoom, 500);
      expect(config.maxRooms, 100);
      expect(config.ttlMessages, const Duration(hours: 24));
      expect(config.ttlRooms, const Duration(hours: 12));
      expect(config.ttlUsers, const Duration(hours: 6));
      expect(config.defaultReadPolicy, CachePolicy.networkFirst);
      expect(config.offlineQueueMaxRetries, 5);
    });

    test('stores custom values', () {
      const config = CacheConfig(
        maxMessagesPerRoom: 10,
        maxRooms: 5,
        ttlMessages: Duration(minutes: 1),
        ttlRooms: Duration(minutes: 2),
        ttlUsers: Duration(minutes: 3),
        offlineQueueMaxRetries: 0,
      );

      expect(config.maxMessagesPerRoom, 10);
      expect(config.maxRooms, 5);
      expect(config.ttlMessages, const Duration(minutes: 1));
      expect(config.ttlRooms, const Duration(minutes: 2));
      expect(config.ttlUsers, const Duration(minutes: 3));
      expect(config.offlineQueueMaxRetries, 0);
    });

    test('asserts maxMessagesPerRoom > 0', () {
      expect(
        () => CacheConfig(maxMessagesPerRoom: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts maxRooms > 0', () {
      expect(() => CacheConfig(maxRooms: 0), throwsA(isA<AssertionError>()));
    });

    test('asserts offlineQueueMaxRetries >= 0', () {
      expect(
        () => CacheConfig(offlineQueueMaxRetries: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
