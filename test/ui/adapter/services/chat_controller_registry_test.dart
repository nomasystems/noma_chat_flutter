import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';

void main() {
  group('ChatControllerRegistry', () {
    late ChatControllerRegistry r;

    ChatController newController() => ChatController(
      initialMessages: const [],
      currentUser: const ChatUser(id: 'me'),
      otherUsers: const [ChatUser(id: 'other')],
    );

    setUp(() => r = ChatControllerRegistry());

    tearDown(() => r.disposeAll());

    test('starts empty', () {
      expect(r.isEmpty, isTrue);
      expect(r.length, 0);
      expect(r['r1'], isNull);
      expect(r.containsKey('r1'), isFalse);
    });

    test('operator []= + operator [] round-trip', () {
      final c = newController();
      r['r1'] = c;
      expect(r['r1'], same(c));
      expect(r.containsKey('r1'), isTrue);
      expect(r.length, 1);
    });

    test('remove returns the controller without disposing it', () {
      final c = newController();
      r['r1'] = c;
      final removed = r.remove('r1');
      expect(removed, same(c));
      expect(r['r1'], isNull);
      // Controller is still usable (caller decides dispose).
      expect(() => c.draft, returnsNormally);
      c.dispose();
    });

    test('remove on unknown id returns null', () {
      expect(r.remove('nope'), isNull);
    });

    test('clear drops entries WITHOUT disposing', () {
      final c1 = newController();
      final c2 = newController();
      r['r1'] = c1;
      r['r2'] = c2;
      r.clear();
      expect(r.length, 0);
      // Both controllers are still usable.
      expect(() => c1.draft, returnsNormally);
      expect(() => c2.draft, returnsNormally);
      c1.dispose();
      c2.dispose();
    });

    test('disposeAll disposes every controller and empties the map', () {
      final c1 = newController();
      final c2 = newController();
      r['r1'] = c1;
      r['r2'] = c2;

      r.disposeAll();

      expect(r.length, 0);
      // ChatController extends ChangeNotifier — addListener throws
      // after dispose. Use that as the dispose-witness.
      expect(() => c1.addListener(() {}), throwsA(anything));
    });

    test('values and entries reflect current state', () {
      final c1 = newController();
      final c2 = newController();
      r['r1'] = c1;
      r['r2'] = c2;
      expect(r.values.toSet(), {c1, c2});
      expect(r.entries.map((e) => e.key).toSet(), {'r1', 'r2'});
    });
  });
}
