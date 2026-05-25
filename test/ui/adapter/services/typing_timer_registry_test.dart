import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/adapter/services/typing_timer_registry.dart';

void main() {
  group('TypingTimerRegistry', () {
    test('first recordStartTyping returns true and counts a timer', () {
      final autoStops = <String>[];
      final reg = TypingTimerRegistry(onAutoStopTriggered: autoStops.add);
      expect(reg.recordStartTyping('r1'), isTrue);
      expect(reg.activeTimerCount, 1);
      reg.clearAll();
    });

    test('second recordStartTyping inside throttle window returns false', () {
      fakeAsync((async) {
        DateTime clockNow = DateTime(2026);
        final reg = TypingTimerRegistry(
          onAutoStopTriggered: (_) {},
          throttle: const Duration(seconds: 3),
          stopDelay: const Duration(seconds: 1),
        )..clockOverride = () => clockNow;

        expect(reg.recordStartTyping('r1'), isTrue);
        clockNow = clockNow.add(const Duration(seconds: 1));
        expect(reg.recordStartTyping('r1'), isFalse, reason: 'throttled');
        clockNow = clockNow.add(const Duration(seconds: 3));
        // Cancel the pending auto-stop so fakeAsync can shut down.
        reg.recordStopTyping('r1');
        async.flushTimers();
      });
    });

    test('recordStartTyping after throttle elapsed returns true', () {
      var clockNow = DateTime(2026);
      final reg = TypingTimerRegistry(onAutoStopTriggered: (_) {})
        ..clockOverride = () => clockNow;

      expect(reg.recordStartTyping('r1'), isTrue);
      clockNow = clockNow.add(const Duration(seconds: 4));
      expect(reg.recordStartTyping('r1'), isTrue);
      reg.clearAll();
    });

    test('auto-stop fires after stopDelay of silence', () {
      fakeAsync((async) {
        final fires = <String>[];
        final reg = TypingTimerRegistry(
          onAutoStopTriggered: fires.add,
          stopDelay: const Duration(seconds: 1),
        );

        reg.recordStartTyping('r1');
        async.elapse(const Duration(milliseconds: 999));
        expect(fires, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(fires, ['r1']);
        expect(reg.activeTimerCount, 0);
      });
    });

    test('repeated start within stopDelay resets the timer', () {
      fakeAsync((async) {
        final fires = <String>[];
        final reg = TypingTimerRegistry(
          onAutoStopTriggered: fires.add,
          throttle: Duration.zero, // disable throttle for this test
          stopDelay: const Duration(seconds: 1),
        );

        reg.recordStartTyping('r1');
        async.elapse(const Duration(milliseconds: 700));
        reg.recordStartTyping('r1');
        async.elapse(const Duration(milliseconds: 700));
        expect(fires, isEmpty, reason: 'timer was reset, not expired');
        async.elapse(const Duration(milliseconds: 400));
        expect(fires, ['r1']);
      });
    });

    test('recordStopTyping cancels pending auto-stop and clears throttle', () {
      fakeAsync((async) {
        final clockNow = DateTime(2026);
        final fires = <String>[];
        final reg = TypingTimerRegistry(
          onAutoStopTriggered: fires.add,
          throttle: const Duration(seconds: 3),
        )..clockOverride = () => clockNow;

        reg.recordStartTyping('r1');
        reg.recordStopTyping('r1');
        async.elapse(const Duration(seconds: 2));
        expect(fires, isEmpty);
        expect(reg.activeTimerCount, 0);
        // Throttle was cleared — next start immediately returns true.
        expect(reg.recordStartTyping('r1'), isTrue);
        reg.recordStopTyping('r1');
      });
    });

    test('two rooms have independent timers', () {
      fakeAsync((async) {
        final fires = <String>[];
        final reg = TypingTimerRegistry(
          onAutoStopTriggered: fires.add,
          stopDelay: const Duration(seconds: 1),
        );

        reg.recordStartTyping('r1');
        async.elapse(const Duration(milliseconds: 500));
        reg.recordStartTyping('r2');
        async.elapse(const Duration(milliseconds: 600));
        // r1 had 1100ms total, fired. r2 only 600ms.
        expect(fires, ['r1']);
        async.elapse(const Duration(milliseconds: 500));
        expect(fires, ['r1', 'r2']);
      });
    });

    test('clearAll cancels every timer without firing onAutoStop', () {
      fakeAsync((async) {
        final fires = <String>[];
        final reg = TypingTimerRegistry(onAutoStopTriggered: fires.add);

        reg.recordStartTyping('r1');
        reg.recordStartTyping('r2');
        expect(reg.activeTimerCount, 2);
        reg.clearAll();
        expect(reg.activeTimerCount, 0);
        async.elapse(const Duration(seconds: 5));
        expect(fires, isEmpty);
      });
    });
  });
}
