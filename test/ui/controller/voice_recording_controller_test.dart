import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:noma_chat/noma_chat.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

class MockAudioPlayer extends Mock implements AudioPlayer {}

class FakeRecordConfig extends Fake implements RecordConfig {}

/// Long enough for a capture to clear
/// [VoiceRecordingController.minCaptureDuration] on wall-clock time, with
/// room for a slow machine.
final _pastCaptureFloor =
    VoiceRecordingController.minCaptureDuration +
    const Duration(milliseconds: 80);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioRecorder mockRecorder;
  late MockAudioPlayer mockPlayer;
  late VoiceRecordingController controller;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FakeRecordConfig());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(UrlSource('_'));
  });

  setUp(() async {
    mockRecorder = MockAudioRecorder();
    mockPlayer = MockAudioPlayer();

    when(() => mockRecorder.dispose()).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => false);
    when(() => mockRecorder.isPaused()).thenAnswer((_) async => false);
    when(() => mockRecorder.pause()).thenAnswer((_) async {});
    when(() => mockRecorder.resume()).thenAnswer((_) async {});
    when(() => mockRecorder.stop()).thenAnswer((_) async => null);
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(
      () => mockPlayer.onPositionChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.onDurationChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.onPlayerStateChanged,
    ).thenAnswer((_) => const Stream<PlayerState>.empty());

    tempDir = await Directory.systemTemp.createTemp('voice_test_');

    controller = VoiceRecordingController(
      maxDuration: const Duration(minutes: 1),
      recorder: mockRecorder,
      preListenPlayer: mockPlayer,
      tempDirectoryPath: tempDir.path,
    );
  });

  tearDown(() {
    controller.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('initial state is idle', () {
    expect(controller.state, VoiceRecordingState.idle);
    expect(controller.currentDuration, Duration.zero);
    expect(controller.liveWaveform, isEmpty);
  });

  test('startRecording returns permissionDenied without permission', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => false);

    final result = await controller.startRecording();

    expect(result, StartRecordingResult.permissionDenied);
    expect(controller.state, VoiceRecordingState.idle);
  });

  test('startRecording transitions to recording state', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    final result = await controller.startRecording();

    expect(result, StartRecordingResult.started);
    expect(controller.state, VoiceRecordingState.recording);
  });

  test('cancelRecording transitions back to idle', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    await controller.cancelRecording();

    expect(controller.state, VoiceRecordingState.idle);
    expect(controller.currentDuration, Duration.zero);
    expect(controller.liveWaveform, isEmpty);
  });

  test('lockRecording transitions from recording to locked', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    await controller.startRecording();
    controller.lockRecording();

    expect(controller.state, VoiceRecordingState.locked);
  });

  test('lockRecording does nothing when not recording', () {
    controller.lockRecording();
    expect(controller.state, VoiceRecordingState.idle);
  });

  test('stopRecording returns null when too short', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    final data = await controller.stopRecording();

    expect(data, isNull);
    expect(controller.state, VoiceRecordingState.idle);
  });

  test('residual cleanup is not on the arming path', () async {
    final residual = File('${tempDir.path}/voice_stale.m4a')
      ..writeAsStringSync('stale');
    var residualStillThereWhenArmed = false;

    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      _,
    ) async {
      residualStillThereWhenArmed = residual.existsSync();
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    final result = await controller.startRecording();

    expect(result, StartRecordingResult.started);
    expect(residualStillThereWhenArmed, isTrue);
  });

  test('residual cleanup purges leftovers and spares the live file', () async {
    final residual = File('${tempDir.path}/voice_stale.m4a')
      ..writeAsStringSync('stale');
    final unrelated = File('${tempDir.path}/notes.txt')
      ..writeAsStringSync('keep me');
    late File live;

    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      live = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('live');
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(residual.existsSync(), isFalse);
    expect(live.existsSync(), isTrue);
    expect(unrelated.existsSync(), isTrue);
  });

  test('residual cleanup spares a capture staged moments ago', () async {
    // Not the file this arming passes as `except`: it stands for the
    // capture a LATER touch stages while this scan is still draining. Only
    // its age keeps it alive.
    final stamp = DateTime.now().millisecondsSinceEpoch - 1000;
    final fresh = File('${tempDir.path}/voice_$stamp.m4a')
      ..writeAsStringSync('another live capture');
    final stale = File('${tempDir.path}/voice_stale.m4a')
      ..writeAsStringSync('stale');

    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(fresh.existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
  });

  test('startRecording reports failed when the platform throws', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenThrow(StateError('audio session unavailable'));

    final result = await controller.startRecording();

    expect(result, StartRecordingResult.failed);
    expect(controller.state, VoiceRecordingState.idle);
  });

  test('a touch held past the minimum sends before the first tick', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      File(
        invocation.namedArguments[#path] as String,
      ).writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    // The duration counter is still zero — it only advances on whole
    // seconds, and the recorder came up after the touch. What the gate
    // must honour is how long the user held the button.
    expect(controller.currentDuration, Duration.zero);
    await Future<void>.delayed(_pastCaptureFloor);
    final data = await controller.stopRecording(
      heldFor: const Duration(milliseconds: 1200),
    );

    expect(data, isNotNull);
  });

  test('a touch under the minimum is still discarded', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      File(
        invocation.namedArguments[#path] as String,
      ).writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    await Future<void>.delayed(_pastCaptureFloor);
    final data = await controller.stopRecording(
      heldFor: const Duration(milliseconds: 300),
    );

    expect(data, isNull);
    expect(controller.state, VoiceRecordingState.idle);
    // Short touch, live capture: the finger is what was missing, so the
    // composer must be free to say exactly that and nothing else.
    expect(controller.lastCaptureFailed, isFalse);
  });

  test('a hold with no capture behind it is dropped, not blamed', () async {
    late File staged;
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      staged = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    // Released the instant the recorder came up: the finger was down well
    // past the minimum, the microphone was not.
    final data = await controller.stopRecording(
      heldFor: const Duration(milliseconds: 1200),
    );

    expect(data, isNull);
    expect(controller.lastCaptureFailed, isTrue);
    expect(controller.state, VoiceRecordingState.idle);
    expect(staged.existsSync(), isFalse);
  });

  test('a capture that came back as a bare header is not sent', () async {
    late File staged;
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      staged = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('ftyp');
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    await controller.startRecording();
    await Future<void>.delayed(_pastCaptureFloor);
    final data = await controller.stopRecording(
      heldFor: const Duration(seconds: 2),
    );

    expect(data, isNull);
    expect(controller.lastCaptureFailed, isTrue);
    expect(staged.existsSync(), isFalse);
  });

  test('a stop that blows up leaves the controller idle', () async {
    late File staged;
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      staged = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenThrow(StateError('recorder disposed'));

    await controller.startRecording();
    await Future<void>.delayed(_pastCaptureFloor);
    final data = await controller.stopRecording(
      heldFor: const Duration(seconds: 2),
    );

    // Stuck in `recording` here would mean a composer frozen on its
    // recording row with a dead microphone until the user leaves the room.
    expect(data, isNull);
    expect(controller.state, VoiceRecordingState.idle);
    expect(controller.lastCaptureFailed, isTrue);
    expect(staged.existsSync(), isFalse);
  });

  test('a cancel that blows up still resets and cleans up', () async {
    late File staged;
    var notifications = 0;
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      staged = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenThrow(StateError('gone'));

    await controller.startRecording();
    await Future<void>.delayed(_pastCaptureFloor);
    controller.addListener(() => notifications++);
    // The incoming-call path: the system tore the recorder down under us.
    await controller.cancelRecording();

    expect(controller.state, VoiceRecordingState.idle);
    expect(controller.currentDuration, Duration.zero);
    expect(staged.existsSync(), isFalse);
    expect(notifications, greaterThan(0));
  });

  test('a cancel is decided before the platform is asked', () async {
    late File staged;
    final drain = Completer<String?>();
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(() => mockRecorder.start(any(), path: any(named: 'path'))).thenAnswer((
      invocation,
    ) async {
      staged = File(invocation.namedArguments[#path] as String)
        ..writeAsStringSync('audio' * 500);
    });
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) => drain.future);

    await controller.startRecording();
    await Future<void>.delayed(_pastCaptureFloor);
    final cancelling = controller.cancelRecording();

    expect(controller.state, VoiceRecordingState.idle);

    final data = await controller.stopRecording(
      heldFor: const Duration(seconds: 2),
    );

    expect(data, isNull);
    expect(controller.lastCaptureFailed, isFalse);

    drain.complete(null);
    await cancelling;

    expect(controller.state, VoiceRecordingState.idle);
    expect(staged.existsSync(), isFalse);
    verify(() => mockRecorder.stop()).called(1);
  });

  test('stopRecording does nothing when not recording', () async {
    final data = await controller.stopRecording();
    expect(data, isNull);
  });

  test('confirmSend does nothing when idle', () async {
    final data = await controller.confirmSend();
    expect(data, isNull);
  });

  test('liveWaveform is unmodifiable', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    await controller.startRecording();
    expect(
      () => controller.liveWaveform.add(1.0),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('dispose cleans up recorder and player', () async {
    final rec = MockAudioRecorder();
    final pl = MockAudioPlayer();
    when(() => rec.dispose()).thenAnswer((_) async {});
    when(() => pl.dispose()).thenAnswer((_) async {});

    final ctrl = VoiceRecordingController(
      recorder: rec,
      preListenPlayer: pl,
      tempDirectoryPath: tempDir.path,
    );
    ctrl.dispose();

    verify(() => rec.dispose()).called(1);
    verify(() => pl.dispose()).called(1);
  });

  test('notifies listeners on state changes', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(notifyCount, greaterThan(0));
  });

  test('cancelRecording when idle is no-op', () async {
    await controller.cancelRecording();
    expect(controller.state, VoiceRecordingState.idle);
  });

  test(
    'startRecording when already recording returns alreadyRunning',
    () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(
        () => mockRecorder.getAmplitude(),
      ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

      await controller.startRecording();
      final result = await controller.startRecording();

      expect(result, StartRecordingResult.alreadyRunning);
      expect(controller.state, VoiceRecordingState.recording);
    },
  );

  test(
    'startRecording records on the very first grant, however slow',
    () async {
      // A slow `hasPermission` is the signature of the OS dialog being shown.
      // The first grant must still record instead of asking for a second touch.
      var firstCall = true;
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async {
        if (firstCall) {
          firstCall = false;
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        return true;
      });
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(
        () => mockRecorder.getAmplitude(),
      ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

      final first = await controller.startRecording(isStillWanted: () => true);

      expect(first, StartRecordingResult.started);
      expect(controller.state, VoiceRecordingState.recording);
      verify(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).called(1);
    },
  );

  test(
    'a touch released before the recorder is armed never opens the recorder',
    () async {
      var fingerDown = true;
      // The finger lifts while the permission check is still in flight, so
      // the recorder must never be armed: on iOS arming it opens the shared
      // audio session and stops whatever the user was listening to.
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        fingerDown = false;
        return true;
      });
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});

      final result = await controller.startRecording(
        isStillWanted: () => fingerDown,
      );

      expect(result, StartRecordingResult.aborted);
      expect(controller.state, VoiceRecordingState.idle);
      verifyNever(() => mockRecorder.start(any(), path: any(named: 'path')));
    },
  );

  test(
    'a fresh recording is not announced until it outlives the tap',
    () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(
        () => mockRecorder.getAmplitude(),
      ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));

      final seen = <VoiceRecordingState>[];
      controller.addListener(() => seen.add(controller.state));

      await controller.startRecording();

      expect(controller.state, VoiceRecordingState.recording);
      expect(seen, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(seen, contains(VoiceRecordingState.recording));
    },
  );

  test('a tap too short to be a recording never reaches listeners', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');

    final seen = <VoiceRecordingState>[];
    controller.addListener(() => seen.add(controller.state));

    await controller.startRecording();
    await controller.stopRecording();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(seen, isNot(contains(VoiceRecordingState.recording)));
    expect(controller.state, VoiceRecordingState.idle);
  });

  test(
    'preListen forwards player position events as listener notifications',
    () async {
      final positionController = StreamController<Duration>.broadcast();
      final durationController = StreamController<Duration>.broadcast();
      final stateController = StreamController<PlayerState>.broadcast();

      when(
        () => mockPlayer.onPositionChanged,
      ).thenAnswer((_) => positionController.stream);
      when(
        () => mockPlayer.onDurationChanged,
      ).thenAnswer((_) => durationController.stream);
      when(
        () => mockPlayer.onPlayerStateChanged,
      ).thenAnswer((_) => stateController.stream);
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(
        () => mockRecorder.getAmplitude(),
      ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
      when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
      when(() => mockRecorder.stop()).thenAnswer((_) async => '');
      when(() => mockPlayer.play(any())).thenAnswer((_) async {});
      when(() => mockPlayer.pause()).thenAnswer((_) async {});
      when(() => mockPlayer.seek(any())).thenAnswer((_) async {});

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.startRecording();
      controller.lockRecording();
      await controller.startPreListen();

      final baseline = notifications;
      positionController.add(const Duration(milliseconds: 500));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, greaterThan(baseline));

      await positionController.close();
      await durationController.close();
      await stateController.close();
    },
  );

  test('cancelRecording in preListen stops player and resets', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');
    when(() => mockPlayer.play(any())).thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});

    await controller.startRecording();
    controller.lockRecording();
    await controller.startPreListen();
    expect(controller.state, VoiceRecordingState.preListen);

    when(() => mockRecorder.isRecording()).thenAnswer((_) async => false);
    await controller.cancelRecording();

    expect(controller.state, VoiceRecordingState.idle);
    verify(() => mockPlayer.stop()).called(1);
  });
}
