import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/voice_upload_registry.dart';

void main() {
  group('VoiceUploadRegistry', () {
    late VoiceUploadRegistry registry;

    setUp(() => registry = VoiceUploadRegistry());

    tearDown(() => registry.disposeAll());

    test('starts empty', () {
      expect(registry.activeCount, 0);
      expect(registry.detachedCount, 0);
      expect(registry.isActive('t1'), isFalse);
      expect(registry.listenableFor('t1'), isNull);
    });

    test('register creates a notifier at 0.0 and marks active', () {
      final n = registry.register('t1');
      expect(n.value, 0.0);
      expect(registry.activeCount, 1);
      expect(registry.isActive('t1'), isTrue);
      expect(registry.listenableFor('t1'), same(n));
    });

    test('register replaces previous notifier for same id', () {
      final n1 = registry.register('t1');
      final n2 = registry.register('t1');
      expect(n2, isNot(same(n1)));
      expect(registry.listenableFor('t1'), same(n2));
      expect(registry.activeCount, 1);
    });

    test('complete moves notifier to detached and forces value to 1.0', () {
      final n = registry.register('t1');
      n.value = 0.42;
      registry.complete('t1');
      expect(registry.activeCount, 0);
      expect(registry.detachedCount, 1);
      expect(registry.isActive('t1'), isFalse);
      expect(n.value, 1.0);
      // Notifier is NOT disposed — bubble can still listen.
      expect(() => n.value, returnsNormally);
    });

    test('complete on unknown id is a no-op', () {
      expect(() => registry.complete('nope'), returnsNormally);
      expect(registry.detachedCount, 0);
    });

    test('drop removes from active without retaining', () {
      registry.register('t1');
      registry.drop('t1');
      expect(registry.activeCount, 0);
      expect(registry.detachedCount, 0);
      expect(registry.isActive('t1'), isFalse);
    });

    test('drop on unknown id is a no-op', () {
      expect(() => registry.drop('nope'), returnsNormally);
    });

    test('rawNotifier returns the underlying ValueNotifier identity', () {
      final n = registry.register('t1');
      expect(registry.rawNotifier('t1'), same(n));
      expect(registry.rawNotifier('other'), isNull);
    });

    test('disposeAll releases active + detached notifiers', () {
      final n1 = registry.register('t1');
      registry.register('t2');
      registry.complete('t2'); // t2 detached
      expect(registry.activeCount, 1);
      expect(registry.detachedCount, 1);

      registry.disposeAll();
      expect(registry.activeCount, 0);
      expect(registry.detachedCount, 0);

      // Calling value on a disposed ChangeNotifier doesn't throw on read,
      // but addListener does. Verify dispose actually ran.
      expect(() => n1.addListener(() {}), throwsA(isA<FlutterError>()));
    });

    test('progress changes propagate via the returned ValueListenable', () {
      final n = registry.register('t1');
      final observed = <double>[];
      n.addListener(() => observed.add(n.value));

      n.value = 0.1;
      n.value = 0.5;
      n.value = 0.9;
      expect(observed, [0.1, 0.5, 0.9]);
    });
  });
}
