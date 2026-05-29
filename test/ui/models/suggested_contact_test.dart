import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('SuggestedContact', () {
    test('stores all provided fields', () {
      const contact = SuggestedContact(
        id: 'u1',
        displayName: 'Alice',
        avatarUrl: 'https://cdn.test/a.png',
        isOnline: true,
        presenceStatus: PresenceStatus.available,
      );

      expect(contact.id, 'u1');
      expect(contact.displayName, 'Alice');
      expect(contact.avatarUrl, 'https://cdn.test/a.png');
      expect(contact.isOnline, true);
      expect(contact.presenceStatus, PresenceStatus.available);
    });

    test('optional fields default to null', () {
      const contact = SuggestedContact(id: 'u2', displayName: 'Bob');

      expect(contact.avatarUrl, isNull);
      expect(contact.isOnline, isNull);
      expect(contact.presenceStatus, isNull);
    });
  });
}
