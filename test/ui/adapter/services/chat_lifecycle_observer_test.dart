import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/config/lifecycle_policy.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_lifecycle_observer.dart';

void main() {
  group('ChatLifecycleObserver', () {
    // Deliberately plain `test()`, never `testWidgets()` — this file must
    // NOT initialize a Flutter binding, so `attach()`'s no-binding-available
    // path is genuinely exercised (mirrors a `ChatUiAdapter` built inside a
    // plain SDK unit test that never called
    // `TestWidgetsFlutterBinding.ensureInitialized()`).
    test('attach()/detach() are safe no-ops without a Flutter binding', () {
      var resumeCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy.standard(),
        onResume: () => resumeCalls++,
        onPause: () {},
      );

      expect(observer.attach, returnsNormally);
      expect(observer.attach, returnsNormally); // idempotent
      expect(observer.detach, returnsNormally);
      expect(observer.detach, returnsNormally); // idempotent, not attached
      expect(resumeCalls, 0);
    });

    test('resumed calls onResume when reconnectOnResume is true', () {
      var resumeCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy(),
        onResume: () => resumeCalls++,
        onPause: () {},
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(resumeCalls, 1);
    });

    test('resumed does nothing when reconnectOnResume is false', () {
      var resumeCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy(reconnectOnResume: false),
        onResume: () => resumeCalls++,
        onPause: () {},
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(resumeCalls, 0);
    });

    test(
      'paused never calls onPause under the standard (keepAlive) policy',
      () async {
        var pauseCalls = 0;
        final observer = ChatLifecycleObserver(
          policy: const ChatLifecyclePolicy.standard(),
          onResume: () {},
          onPause: () => pauseCalls++,
        );

        observer.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(pauseCalls, 0);
      },
    );

    test(
      'paused calls onPause after pauseGracePeriod under pushOptimized',
      () async {
        var pauseCalls = 0;
        final observer = ChatLifecycleObserver(
          policy: const ChatLifecyclePolicy(
            onPause: ChatPauseAction.disconnect,
            pauseGracePeriod: Duration(milliseconds: 20),
          ),
          onResume: () {},
          onPause: () => pauseCalls++,
        );

        observer.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(pauseCalls, 0, reason: 'must wait for the grace period');

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(pauseCalls, 1);
      },
    );

    test(
      'a resume within the grace period cancels the pending onPause',
      () async {
        var pauseCalls = 0;
        var resumeCalls = 0;
        final observer = ChatLifecycleObserver(
          policy: const ChatLifecyclePolicy(
            onPause: ChatPauseAction.disconnect,
            pauseGracePeriod: Duration(milliseconds: 30),
          ),
          onResume: () => resumeCalls++,
          onPause: () => pauseCalls++,
        );

        observer.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(
          pauseCalls,
          0,
          reason: 'the grace-period timer must be cancelled',
        );
        expect(resumeCalls, 1);
      },
    );

    test('a second paused restarts the grace-period timer', () async {
      var pauseCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy(
          onPause: ChatPauseAction.disconnect,
          pauseGracePeriod: Duration(milliseconds: 30),
        ),
        onResume: () {},
        onPause: () => pauseCalls++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pauseCalls, 0, reason: 'the timer must have restarted');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pauseCalls, 1);
    });

    test('detach() cancels a pending grace-period timer', () async {
      var pauseCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy(
          onPause: ChatPauseAction.disconnect,
          pauseGracePeriod: Duration(milliseconds: 20),
        ),
        onResume: () {},
        onPause: () => pauseCalls++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.detach();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(pauseCalls, 0);
    });

    test('inactive/hidden/detached are no-ops', () async {
      var resumeCalls = 0;
      var pauseCalls = 0;
      final observer = ChatLifecycleObserver(
        policy: const ChatLifecyclePolicy(
          onPause: ChatPauseAction.disconnect,
          pauseGracePeriod: Duration(milliseconds: 10),
        ),
        onResume: () => resumeCalls++,
        onPause: () => pauseCalls++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      observer.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(resumeCalls, 0);
      expect(pauseCalls, 0);
    });
  });
}
