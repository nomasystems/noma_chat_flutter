import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ReactionUser', () {
    test('constructs with required fields', () {
      const user = ReactionUser(id: 'u1', displayName: 'Alice');
      expect(user.id, 'u1');
      expect(user.displayName, 'Alice');
      expect(user.avatarUrl, isNull);
    });

    test('constructs with all fields', () {
      const user = ReactionUser(
        id: 'u1',
        displayName: 'Alice',
        avatarUrl: 'https://example.com/avatar.png',
      );
      expect(user.avatarUrl, 'https://example.com/avatar.png');
    });

    test('equality compares all fields', () {
      const a = ReactionUser(id: 'u1', displayName: 'Alice');
      const b = ReactionUser(id: 'u1', displayName: 'Alice');
      const c = ReactionUser(id: 'u1', displayName: 'Bob');
      const d = ReactionUser(id: 'u2', displayName: 'Alice');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('equality includes avatarUrl', () {
      const a = ReactionUser(id: 'u1', displayName: 'Alice');
      const b = ReactionUser(
        id: 'u1',
        displayName: 'Alice',
        avatarUrl: 'https://example.com/a.png',
      );
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      const a = ReactionUser(id: 'u1', displayName: 'Alice');
      const b = ReactionUser(id: 'u1', displayName: 'Alice');
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
