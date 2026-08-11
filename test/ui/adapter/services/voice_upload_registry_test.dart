import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/voice_upload_registry.dart';

void main() {
  group('VoiceUploadRegistry', () {
    late VoiceUploadRegistry registry;

    setUp(() => registry = VoiceUploadRegistry());

    tearDown(() => registry.releaseAll());

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

    test('releaseAll lets go of active + detached notifiers, and leaves both '
        'usable for a host that kept one', () {
      final n1 = registry.register('t1');
      final n2 = registry.register('t2');
      registry.complete('t2'); // t2 detached
      expect(registry.activeCount, 1);
      expect(registry.detachedCount, 1);

      registry.releaseAll();
      expect(registry.activeCount, 0);
      expect(registry.detachedCount, 0);
      expect(registry.listenableFor('t1'), isNull);

      // Both left through `voiceUploadProgressFor` /
      // `attachmentUploadProgressFor`; a host that resolved one and
      // subscribed itself must not have its next addListener blow up on the
      // UI thread because somebody signed out.
      void listener() {}
      expect(() => n1.addListener(listener), returnsNormally);
      expect(() => n1.removeListener(listener), returnsNormally);
      expect(() => n2.addListener(listener), returnsNormally);
      expect(() => n2.removeListener(listener), returnsNormally);
      // The teardown invents no terminal value: what each one last reported
      // is what it still reports.
      expect(n1.value, 0.0);
      expect(n2.value, 1.0);
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
