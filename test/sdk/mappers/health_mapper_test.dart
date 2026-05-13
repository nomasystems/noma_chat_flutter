import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/health_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthMapper', () {
    test('maps ok status', () {
      final health = HealthMapper.fromJson({
        'status': 'ok',
        'checks': {'memtabd': 'ok', 'db': 'ok', 'ejabberd': 'ok'},
      });
      expect(health.status, ServiceStatus.ok);
      expect(health.isHealthy, isTrue);
      expect(health.checks.length, 3);
    });

    test('maps degraded status', () {
      final health = HealthMapper.fromJson({
        'status': 'degraded',
        'checks': {'db': 'error'},
      });
      expect(health.status, ServiceStatus.degraded);
      expect(health.isHealthy, isFalse);
    });

    test('handles missing checks', () {
      final health = HealthMapper.fromJson({'status': 'ok'});
      expect(health.checks, isEmpty);
    });
  });
}
