import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/temp_id_minter.dart';

void main() {
  group('TempIdMinter', () {
    test('never repeats an id, however tight the burst', () {
      final minter = TempIdMinter();

      // Minted in one synchronous run, which is how sends mint them: every
      // send stamps its id before its first suspension point. The wall
      // clock is free to read the same microsecond for all of these.
      final ids = [for (var i = 0; i < 5000; i++) minter.next()];

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('keeps the shape callers match on and sorts by mint order', () {
      final minter = TempIdMinter();

      final ids = [for (var i = 0; i < 3; i++) minter.next()];

      expect(ids.every((id) => id.startsWith('_pending_')), isTrue);
      // Trailing segment is the counter, not a clock reading — that is what
      // makes two ids minted in the same microsecond distinguishable.
      expect([for (final id in ids) int.parse(id.split('_').last)], [0, 1, 2]);
      expect(minter.mintedCount, 3);
    });

    test('two minters are two independent sequences — which is why the '
        'adapter keeps exactly one', () {
      final a = TempIdMinter();
      final b = TempIdMinter();

      // Both start over at 0, so two of these in one adapter would hand the
      // same counter to two different sends.
      expect(a.next().split('_').last, '0');
      expect(b.next().split('_').last, '0');
    });
  });
}
