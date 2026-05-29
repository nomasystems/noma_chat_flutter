import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('PresenceStatus serialization', () {
    test('PresenceStatus.toJson() preserves dnd', () {
      expect(PresenceStatus.dnd.toJson(), 'dnd');
      expect(PresenceStatus.available.toJson(), 'available');
      expect(PresenceStatus.away.toJson(), 'away');
      expect(PresenceStatus.busy.toJson(), 'busy');
      expect(PresenceStatus.offline.toJson(), 'offline');
    });
  });
}
