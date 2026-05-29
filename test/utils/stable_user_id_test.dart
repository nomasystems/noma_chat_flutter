import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('StableUserId.forDisplayName', () {
    test('mints and persists a uuid for a new name', () async {
      final id = await StableUserId.forDisplayName('alice', prefs: prefs);

      expect(id, isNotEmpty);
      expect(prefs.getString('${StableUserId.defaultKeyPrefix}alice'), id);
    });

    test('returns the same id on subsequent calls', () async {
      final first = await StableUserId.forDisplayName('alice', prefs: prefs);
      final second = await StableUserId.forDisplayName('alice', prefs: prefs);

      expect(first, second);
    });

    test('trims surrounding whitespace before keying', () async {
      final padded = await StableUserId.forDisplayName(
        '  alice  ',
        prefs: prefs,
      );
      final plain = await StableUserId.forDisplayName('alice', prefs: prefs);

      expect(padded, plain);
    });

    test('throws when the display name is blank', () async {
      await expectLater(
        StableUserId.forDisplayName('   ', prefs: prefs),
        throwsArgumentError,
      );
    });

    test('honours a custom key prefix', () async {
      final id = await StableUserId.forDisplayName(
        'alice',
        prefs: prefs,
        keyPrefix: 'demo:',
      );

      expect(prefs.getString('demo:alice'), id);
    });

    test('different names get different ids', () async {
      final alice = await StableUserId.forDisplayName('alice', prefs: prefs);
      final bob = await StableUserId.forDisplayName('bob', prefs: prefs);

      expect(alice, isNot(bob));
    });
  });

  group('StableUserId.forget', () {
    test('removes the stored id so the next call mints a fresh one', () async {
      final before = await StableUserId.forDisplayName('alice', prefs: prefs);
      await StableUserId.forget('alice', prefs: prefs);
      final after = await StableUserId.forDisplayName('alice', prefs: prefs);

      expect(before, isNot(after));
    });
  });
}
