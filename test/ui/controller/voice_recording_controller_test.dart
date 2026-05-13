import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:noma_chat/noma_chat.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

class MockAudioPlayer extends Mock implements AudioPlayer {}

class FakeRecordConfig extends Fake implements RecordConfig {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioRecorder mockRecorder;
  late MockAudioPlayer mockPlayer;
  late VoiceRecordingController controller;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FakeRecordConfig());
    registerFallbackValue(Duration.zero);
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
      () => mockPlayer.positionStream,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.durationStream,
    ).thenAnswer((_) => const Stream<Duration?>.empty());
    when(
      () => mockPlayer.playerStateStream,
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
    'startRecording returns permissionJustGranted on first slow grant',
    () async {
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

      final first = await controller.startRecording();
      expect(first, StartRecordingResult.permissionJustGranted);
      expect(controller.state, VoiceRecordingState.idle);

      final second = await controller.startRecording();
      expect(second, StartRecordingResult.started);
      expect(controller.state, VoiceRecordingState.recording);
    },
  );

  test(
    'preListen forwards player position events as listener notifications',
    () async {
      final positionController = StreamController<Duration>.broadcast();
      final durationController = StreamController<Duration?>.broadcast();
      final stateController = StreamController<PlayerState>.broadcast();

      when(
        () => mockPlayer.positionStream,
      ).thenAnswer((_) => positionController.stream);
      when(
        () => mockPlayer.durationStream,
      ).thenAnswer((_) => durationController.stream);
      when(
        () => mockPlayer.playerStateStream,
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
      when(() => mockPlayer.setFilePath(any())).thenAnswer((_) async => null);
      when(() => mockPlayer.play()).thenAnswer((_) async {});
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
    when(() => mockPlayer.setFilePath(any())).thenAnswer((_) async => null);
    when(() => mockPlayer.play()).thenAnswer((_) async {});
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
