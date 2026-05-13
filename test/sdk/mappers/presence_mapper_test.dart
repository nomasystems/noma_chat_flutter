import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/presence_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresenceMapper', () {
    test('fromJson maps all fields', () {
      final presence = PresenceMapper.fromJson({
        'userId': 'u-1',
        'status': 'available',
        'online': true,
        'statusText': 'Working',
        'lastSeen': '2024-12-25T20:00:00Z',
      });
      expect(presence.userId, 'u-1');
      expect(presence.status, PresenceStatus.available);
      expect(presence.online, isTrue);
      expect(presence.statusText, 'Working');
      expect(presence.lastSeen, isNotNull);
    });

    test('maps all status types', () {
      for (final s in ['available', 'away', 'busy', 'dnd', 'offline']) {
        final presence = PresenceMapper.fromJson({
          'userId': 'u-1',
          'status': s,
          'online': s == 'available',
        });
        expect(presence.status.name, s);
      }
    });

    test('unknown status defaults to offline', () {
      final presence = PresenceMapper.fromJson({
        'userId': 'u-1',
        'status': 'unknown',
        'online': false,
      });
      expect(presence.status, PresenceStatus.offline);
    });

    test('handles missing optional fields', () {
      final presence = PresenceMapper.fromJson({
        'userId': 'u-1',
        'status': 'away',
        'online': false,
      });
      expect(presence.statusText, isNull);
      expect(presence.lastSeen, isNull);
    });

    test('bulkFromJson parses own and contacts', () {
      final bulk = PresenceMapper.bulkFromJson({
        'own': {'userId': 'me', 'status': 'available', 'online': true},
        'contacts': [
          {'userId': 'c1', 'status': 'away', 'online': false},
          {'userId': 'c2', 'status': 'busy', 'online': true},
        ],
      });
      expect(bulk.own.userId, 'me');
      expect(bulk.own.status, PresenceStatus.available);
      expect(bulk.contacts.length, 2);
      expect(bulk.contacts[0].userId, 'c1');
      expect(bulk.contacts[1].status, PresenceStatus.busy);
    });

    test('bulkFromJson with no contacts returns empty list', () {
      final bulk = PresenceMapper.bulkFromJson({
        'own': {'userId': 'me', 'status': 'offline', 'online': false},
      });
      expect(bulk.own.userId, 'me');
      expect(bulk.contacts, isEmpty);
    });

    test('bulkFromJson falls back to flat json when no own key', () {
      final bulk = PresenceMapper.bulkFromJson({
        'userId': 'me',
        'status': 'available',
        'online': true,
      });
      expect(bulk.own.userId, 'me');
      expect(bulk.contacts, isEmpty);
    });
  });
}
