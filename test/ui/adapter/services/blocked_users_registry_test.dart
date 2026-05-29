import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';

void main() {
  group('BlockedUsersRegistry', () {
    test('starts empty', () {
      final r = BlockedUsersRegistry();
      expect(r.isEmpty, isTrue);
      expect(r.length, 0);
      expect(r.all, isEmpty);
      expect(r.isBlocked('u1'), isFalse);
    });

    test('block returns true on first add and fires onChanged', () {
      Set<String>? lastSnapshot;
      final r = BlockedUsersRegistry(onChanged: (ids) => lastSnapshot = ids);

      expect(r.block('u1'), isTrue);
      expect(r.isBlocked('u1'), isTrue);
      expect(r.length, 1);
      expect(lastSnapshot, {'u1'});
    });

    test('block is idempotent — second call returns false, no callback', () {
      var callbacks = 0;
      final r = BlockedUsersRegistry(onChanged: (_) => callbacks++);

      r.block('u1');
      expect(callbacks, 1);
      expect(r.block('u1'), isFalse);
      expect(callbacks, 1); // no extra fire
      expect(r.length, 1);
    });

    test('unblock returns true on real removal and fires onChanged', () {
      var callbacks = 0;
      final r = BlockedUsersRegistry(onChanged: (_) => callbacks++);

      r.block('u1');
      callbacks = 0; // reset after the block
      expect(r.unblock('u1'), isTrue);
      expect(r.isBlocked('u1'), isFalse);
      expect(callbacks, 1);
    });

    test('unblock on missing user is a no-op with no callback', () {
      var callbacks = 0;
      final r = BlockedUsersRegistry(onChanged: (_) => callbacks++);

      expect(r.unblock('never-blocked'), isFalse);
      expect(callbacks, 0);
    });

    test('replaceAll fires onChanged unconditionally with new snapshot', () {
      final fires = <Set<String>>[];
      final r = BlockedUsersRegistry(onChanged: fires.add);

      r.replaceAll({'u1', 'u2', 'u3'});
      expect(r.length, 3);
      expect(fires.last, {'u1', 'u2', 'u3'});

      // Same content — still fires (replaceAll is "I want the full reset").
      r.replaceAll({'u1', 'u2', 'u3'});
      expect(fires.length, 2);
    });

    test('clear drops set silently — no onChanged', () {
      var callbacks = 0;
      final r = BlockedUsersRegistry(onChanged: (_) => callbacks++);

      r.block('u1');
      callbacks = 0;
      r.clear();
      expect(r.isEmpty, isTrue);
      expect(callbacks, 0);
    });

    test('all returns an unmodifiable snapshot', () {
      final r = BlockedUsersRegistry();
      r.block('u1');
      final snap = r.all;
      expect(() => snap.add('u2'), throwsUnsupportedError);
      // Original is unaffected.
      expect(r.isBlocked('u2'), isFalse);
    });

    test('no onChanged callback configured — mutations still work', () {
      final r = BlockedUsersRegistry(); // no onChanged
      expect(() => r.block('u1'), returnsNormally);
      expect(() => r.unblock('u1'), returnsNormally);
      expect(() => r.replaceAll({'u2'}), returnsNormally);
      expect(r.isBlocked('u2'), isTrue);
    });
  });
}
