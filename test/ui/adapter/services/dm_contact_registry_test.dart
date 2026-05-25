import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';

void main() {
  group('DmContactRegistry', () {
    late DmContactRegistry r;

    setUp(() => r = DmContactRegistry());

    test('starts empty', () {
      expect(r.isEmpty, isTrue);
      expect(r.length, 0);
      expect(r.roomIdFor('u1'), isNull);
      expect(r.contactIdFor('r1'), isNull);
      expect(r.hasContact('u1'), isFalse);
    });

    test('bind populates both directions', () {
      r.bind('u1', 'r1');
      expect(r.roomIdFor('u1'), 'r1');
      expect(r.contactIdFor('r1'), 'u1');
      expect(r.hasContact('u1'), isTrue);
      expect(r.length, 1);
    });

    test('bind replacing existing room cleans the reverse map', () {
      r.bind('u1', 'r1');
      r.bind('u1', 'r2'); // contact u1 now in r2 (room migrated)
      expect(r.roomIdFor('u1'), 'r2');
      expect(r.contactIdFor('r2'), 'u1');
      expect(
        r.contactIdFor('r1'),
        isNull,
        reason: 'old reverse entry should be dropped',
      );
    });

    test('unbind removes both sides', () {
      r.bind('u1', 'r1');
      r.unbind('u1');
      expect(r.roomIdFor('u1'), isNull);
      expect(r.contactIdFor('r1'), isNull);
    });

    test('unbindRoom removes both sides via reverse lookup', () {
      r.bind('u1', 'r1');
      r.unbindRoom('r1');
      expect(r.roomIdFor('u1'), isNull);
      expect(r.contactIdFor('r1'), isNull);
    });

    test('draft custom: set, get, clear', () {
      const draft = {'type': 'dm', 'extra': 'plan-1'};
      r.setDraftCustom('u1', draft);
      expect(r.draftCustomFor('u1'), draft);
      r.clearDraftCustom('u1');
      expect(r.draftCustomFor('u1'), isNull);
    });

    test('setDraftCustom defensively copies the map', () {
      final original = <String, dynamic>{'type': 'dm'};
      r.setDraftCustom('u1', original);
      original['type'] = 'mutated';
      expect(
        r.draftCustomFor('u1')!['type'],
        'dm',
        reason: 'registry should hold its own copy',
      );
    });

    test('clear drops mappings AND draft customs', () {
      r.bind('u1', 'r1');
      r.bind('u2', 'r2');
      r.setDraftCustom('u3', {'type': 'dm'});
      expect(r.isEmpty, isFalse);

      r.clear();

      expect(r.isEmpty, isTrue);
      expect(r.length, 0);
      expect(r.draftCustomFor('u3'), isNull);
      expect(r.contactIdFor('r1'), isNull);
    });
  });
}
