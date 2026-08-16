import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/pages/camera_recording_gate.dart';

void main() {
  group('CameraRecordingGate', () {
    test('happy path: start then stop', () {
      final gate = CameraRecordingGate();

      final attempt = gate.beginStart();
      expect(attempt, isNotNull);
      expect(gate.isStarting, isTrue);
      expect(gate.isRecording, isFalse);

      expect(gate.completeStart(attempt), CameraStartOutcome.recording);
      expect(gate.isStarting, isFalse);
      expect(gate.isRecording, isTrue);

      expect(gate.requestStop(), isTrue);
      expect(gate.isRecording, isFalse);
    });

    test('beginStart refuses re-entry while starting or recording', () {
      final gate = CameraRecordingGate();
      final attempt = gate.beginStart();
      expect(attempt, isNotNull);
      expect(gate.beginStart(), isNull, reason: 'already starting');

      gate.completeStart(attempt);
      expect(gate.beginStart(), isNull, reason: 'already recording');
    });

    test('release during the async start is absorbed and stops immediately '
        'once the start resolves', () {
      final gate = CameraRecordingGate();

      final attempt = gate.beginStart();
      expect(attempt, isNotNull);
      // Finger lifts before `startVideoRecording()` resolves.
      expect(
        gate.requestStop(),
        isFalse,
        reason: 'nothing to stop yet, the request is absorbed',
      );
      expect(gate.isRecording, isFalse);
      expect(gate.isStarting, isTrue);

      // The async start call resolves: the pending stop must replay.
      expect(
        gate.completeStart(attempt),
        CameraStartOutcome.stopImmediately,
        reason: 'a stop was requested mid-flight',
      );
      expect(gate.isStarting, isFalse);
      // The gate is left "recording" so the follow-up requestStop() call
      // actually issues the native stop instead of silently no-op-ing.
      expect(gate.isRecording, isTrue);

      expect(gate.requestStop(), isTrue);
      expect(gate.isRecording, isFalse);
    });

    test('requestStop before any start is a no-op', () {
      final gate = CameraRecordingGate();
      expect(gate.requestStop(), isFalse);
    });

    test('a stop still in flight keeps the gate armed, so a teardown that '
        'lands inside it is reported as a lost clip', () {
      final gate = CameraRecordingGate();
      gate.completeStart(gate.beginStart());

      expect(gate.requestStop(), isTrue);
      expect(gate.isRecording, isFalse, reason: 'the clip has stopped growing');
      expect(
        gate.isStopping,
        isTrue,
        reason: 'the platform has not handed the file back yet',
      );
      expect(
        gate.beginStart(),
        isNull,
        reason: 'the camera is not free for a second recording',
      );

      // The incoming call arrives while `stopVideoRecording()` is in flight.
      expect(
        gate.interruptIfActive(),
        isTrue,
        reason: 'a clip lost inside the stop is still a clip lost',
      );
      expect(gate.isStopping, isFalse);
    });

    test(
      'completeStop frees the gate once the platform hands the clip back',
      () {
        final gate = CameraRecordingGate();
        gate.completeStart(gate.beginStart());
        gate.requestStop();

        gate.completeStop();

        expect(gate.isStopping, isFalse);
        expect(
          gate.interruptIfActive(),
          isFalse,
          reason: 'nothing is in flight any more',
        );
        expect(gate.beginStart(), isNotNull);
      },
    );

    test('a delivered clip leaves the gate ready for the retake that may '
        'follow, since the capture is now reviewed before it is sent', () {
      final gate = CameraRecordingGate();
      gate.completeStart(gate.beginStart());
      gate.requestStop();
      gate.completeStop();

      // The user looked at the take, did not like it, and holds the shutter
      // again — no teardown and no rebind in between.
      final retake = gate.beginStart();
      expect(retake, isNotNull);
      expect(gate.completeStart(retake), CameraStartOutcome.recording);
      expect(gate.isRecording, isTrue);
      expect(gate.requestStop(), isTrue);
    });

    test(
      'the session token a stop captured goes stale when it is interrupted',
      () {
        final gate = CameraRecordingGate();
        gate.completeStart(gate.beginStart());
        final session = gate.currentSession;
        gate.requestStop();

        expect(
          gate.isStale(session),
          isFalse,
          reason: 'the stop belongs to the session the gate is tracking',
        );

        gate.interruptIfActive();

        expect(
          gate.isStale(session),
          isTrue,
          reason:
              'the resolving stop is reporting about a session that is gone',
        );
      },
    );

    test('requestStop after a stop already ran is a no-op', () {
      final gate = CameraRecordingGate();
      gate.completeStart(gate.beginStart());
      gate.requestStop();
      expect(gate.requestStop(), isFalse);
    });

    test(
      'reset clears an in-flight start after a failed startVideoRecording',
      () {
        final gate = CameraRecordingGate();
        gate.beginStart();
        gate.reset();
        expect(gate.isStarting, isFalse);
        expect(gate.isRecording, isFalse);
        expect(
          gate.beginStart(),
          isNotNull,
          reason: 'gate is fully clear again',
        );
      },
    );

    test('reset after a stop-request mid-start drops the pending stop too', () {
      final gate = CameraRecordingGate();
      final attempt = gate.beginStart();
      gate.requestStop();
      gate.reset();
      expect(gate.completeStart(attempt), CameraStartOutcome.stale);
    });

    test(
      'interruptIfActive reports true and clears an in-progress recording',
      () {
        final gate = CameraRecordingGate();
        gate.completeStart(gate.beginStart());
        expect(gate.isRecording, isTrue);

        expect(gate.interruptIfActive(), isTrue);
        expect(gate.isRecording, isFalse);
        expect(gate.isStarting, isFalse);
        expect(
          gate.beginStart(),
          isNotNull,
          reason: 'gate is fully clear again',
        );
      },
    );

    test(
      'interruptIfActive reports true and clears a start still in flight',
      () {
        final gate = CameraRecordingGate();
        gate.beginStart();

        expect(gate.interruptIfActive(), isTrue);
        expect(gate.isStarting, isFalse);
        expect(gate.isRecording, isFalse);
      },
    );

    test('interruptIfActive is a no-op false when nothing was active', () {
      final gate = CameraRecordingGate();
      expect(gate.interruptIfActive(), isFalse);
    });

    test(
      'a start interrupted mid-flight cannot re-arm the gate when it resolves',
      () {
        final gate = CameraRecordingGate();
        final attempt = gate.beginStart();

        // The controller is torn down while `startVideoRecording()` is still
        // in flight; the call resolves against a session that is already gone.
        expect(gate.interruptIfActive(), isTrue);

        expect(gate.completeStart(attempt), CameraStartOutcome.stale);
        expect(
          gate.isRecording,
          isFalse,
          reason: 'a dead session must not leave the recording UI armed',
        );
        expect(gate.isStarting, isFalse);
        expect(
          gate.requestStop(),
          isFalse,
          reason: 'there is nothing left to stop natively',
        );
      },
    );

    test('a stale start cannot hijack the attempt the user began after it', () {
      final gate = CameraRecordingGate();
      final interrupted = gate.beginStart();
      gate.interruptIfActive();

      // The user holds the shutter again once the preview is back.
      final fresh = gate.beginStart();
      expect(fresh, isNotNull);

      expect(gate.completeStart(interrupted), CameraStartOutcome.stale);
      expect(
        gate.isStarting,
        isTrue,
        reason: 'the fresh attempt is untouched by the stale one resolving',
      );
      expect(gate.completeStart(fresh), CameraStartOutcome.recording);
      expect(gate.isRecording, isTrue);
    });

    test(
      'completeStart is stale when replayed for an attempt already resolved',
      () {
        final gate = CameraRecordingGate();
        final attempt = gate.beginStart();
        expect(gate.completeStart(attempt), CameraStartOutcome.recording);
        expect(gate.completeStart(attempt), CameraStartOutcome.stale);
        expect(
          gate.isRecording,
          isTrue,
          reason: 'the live recording is intact',
        );
      },
    );
  });
}
