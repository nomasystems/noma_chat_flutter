import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/_voice_recorder_gesture.dart'
    show VoiceRecorderGesture;
import 'package:record/record.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _FakeVoiceController extends VoiceRecordingController {
  _FakeVoiceController({
    required AudioRecorder recorder,
    required AudioPlayer player,
    required String tempDirectoryPath,
  }) : super(
         maxDuration: const Duration(minutes: 1),
         recorder: recorder,
         preListenPlayer: player,
         tempDirectoryPath: tempDirectoryPath,
       );

  VoiceRecordingState _fakeState = VoiceRecordingState.idle;
  StartRecordingResult nextStartResult = StartRecordingResult.started;
  bool cancelCalled = false;
  bool lockCalled = false;
  int stopCalls = 0;
  int confirmCalls = 0;
  VoiceMessageData? stopReturns;
  VoiceMessageData? confirmReturns;

  @override
  VoiceRecordingState get state => _fakeState;

  void setState(VoiceRecordingState next) {
    _fakeState = next;
    notifyListeners();
  }

  @override
  Future<StartRecordingResult> startRecording() async {
    if (nextStartResult == StartRecordingResult.started) {
      _fakeState = VoiceRecordingState.recording;
      notifyListeners();
    }
    return nextStartResult;
  }

  @override
  Future<void> cancelRecording() async {
    cancelCalled = true;
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
  }

  @override
  void lockRecording() {
    lockCalled = true;
    _fakeState = VoiceRecordingState.locked;
    notifyListeners();
  }

  @override
  Future<VoiceMessageData?> stopRecording() async {
    stopCalls++;
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
    return stopReturns;
  }

  @override
  Future<VoiceMessageData?> confirmSend() async {
    confirmCalls++;
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
    return confirmReturns;
  }

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Future<void> startPreListen() async {}

  @override
  Future<void> stopPreListen() async {}

  @override
  void dispose() {
    // Skip super.dispose() to avoid touching the real recorder/player
    // platform channels; mocks are configured to no-op anyway.
    super.dispose();
  }
}

_FakeVoiceController _buildFake() {
  final recorder = _MockAudioRecorder();
  final player = _MockAudioPlayer();
  when(() => recorder.dispose()).thenAnswer((_) async {});
  when(() => recorder.isRecording()).thenAnswer((_) async => false);
  when(() => recorder.isPaused()).thenAnswer((_) async => false);
  when(() => recorder.stop()).thenAnswer((_) async => null);
  when(() => player.dispose()).thenAnswer((_) async {});
  when(() => player.stop()).thenAnswer((_) async {});
  when(
    () => player.onPositionChanged,
  ).thenAnswer((_) => const Stream<Duration>.empty());
  when(
    () => player.onDurationChanged,
  ).thenAnswer((_) => const Stream<Duration>.empty());
  when(
    () => player.onPlayerStateChanged,
  ).thenAnswer((_) => const Stream<PlayerState>.empty());
  return _FakeVoiceController(
    recorder: recorder,
    player: player,
    tempDirectoryPath: '/tmp/noma_chat_voice_test',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVoiceController fake;
  late MessageInputVoiceController controller;

  setUp(() {
    fake = _buildFake();
    controller = MessageInputVoiceController(
      maxRecordingDuration: const Duration(minutes: 1),
      recordingControllerFactory: (_) => fake,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('MessageInputVoiceController', () {
    test('initial state', () {
      expect(controller.dragOffsetX, 0);
      expect(controller.dragOffsetY, 0);
      expect(controller.isRecording, isFalse);
      expect(controller.isLocked, isFalse);
      expect(controller.isAnyRecordingState, isFalse);
      expect(controller.recording, isNull);
    });

    test('onLongPressStart transitions to recording on success', () async {
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final result = await controller.onLongPressStart();

      expect(result, StartRecordingResult.started);
      expect(controller.isRecording, isTrue);
      expect(controller.isAnyRecordingState, isTrue);
      expect(controller.recording, isNotNull);
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('onLongPressStart surfaces permissionDenied', () async {
      fake.nextStartResult = StartRecordingResult.permissionDenied;

      final result = await controller.onLongPressStart();

      expect(result, StartRecordingResult.permissionDenied);
      expect(controller.isRecording, isFalse);
    });

    test('onLongPressMoveUpdate tracks drag while recording', () async {
      await controller.onLongPressStart();

      controller.onLongPressMoveUpdate(const Offset(-10, -20), 360);

      expect(controller.dragOffsetX, -10);
      expect(controller.dragOffsetY, -20);
      expect(controller.isRecording, isTrue);
    });

    test('onLongPressMoveUpdate ignores drag when not recording', () {
      controller.onLongPressMoveUpdate(const Offset(-50, -50), 360);

      expect(controller.dragOffsetX, 0);
      expect(controller.dragOffsetY, 0);
    });

    test('drag past cancel threshold cancels recording', () async {
      await controller.onLongPressStart();
      // cancelThresholdRatio defaults to 1/3 of screenWidth (here 360 -> -120)
      controller.onLongPressMoveUpdate(const Offset(-200, 0), 360);

      expect(fake.cancelCalled, isTrue);
      expect(controller.isRecording, isFalse);
      expect(controller.dragOffsetX, 0);
      expect(controller.dragOffsetY, 0);
    });

    test('drag past lock threshold locks recording', () async {
      await controller.onLongPressStart();
      // lockThreshold default is -100.
      controller.onLongPressMoveUpdate(const Offset(0, -150), 360);

      expect(fake.lockCalled, isTrue);
      expect(controller.isLocked, isTrue);
      expect(controller.dragOffsetX, 0);
      expect(controller.dragOffsetY, 0);
    });

    test('custom thresholds honored', () async {
      controller.dispose();
      fake = _buildFake();
      controller = MessageInputVoiceController(
        maxRecordingDuration: const Duration(minutes: 1),
        thresholds: const VoiceGestureThresholds(
          lockThreshold: -50,
          cancelThresholdRatio: 0.5,
        ),
        recordingControllerFactory: (_) => fake,
      );

      await controller.onLongPressStart();

      // 200 wide screen, ratio 0.5 -> cancel at -100
      controller.onLongPressMoveUpdate(const Offset(-120, 0), 200);
      expect(fake.cancelCalled, isTrue);
    });

    test('onLongPressEnd while recording stops and returns data', () async {
      fake.stopReturns = VoiceMessageData(
        audioBytes: Uint8List(0),
        duration: const Duration(seconds: 2),
        waveform: const [1, 2, 3],
      );
      await controller.onLongPressStart();

      final data = await controller.onLongPressEnd();

      expect(fake.stopCalls, 1);
      expect(data, isNotNull);
      expect(controller.dragOffsetX, 0);
      expect(controller.dragOffsetY, 0);
    });

    test('onLongPressEnd while locked does not stop the recording', () async {
      await controller.onLongPressStart();
      fake.setState(VoiceRecordingState.locked);

      final data = await controller.onLongPressEnd();

      expect(data, isNull);
      expect(fake.stopCalls, 0);
      // The recording stays alive — the composer drives confirm from the
      // recording row, not the long-press release.
      expect(controller.isLocked, isTrue);
    });

    test('confirmSend stops + returns data when recording', () async {
      fake.stopReturns = VoiceMessageData(
        audioBytes: Uint8List(0),
        duration: const Duration(seconds: 3),
        waveform: const [],
      );
      await controller.onLongPressStart();

      final data = await controller.confirmSend();

      expect(fake.stopCalls, 1);
      expect(data, isNotNull);
    });

    test('confirmSend calls confirmSend when locked', () async {
      fake.confirmReturns = VoiceMessageData(
        audioBytes: Uint8List(0),
        duration: const Duration(seconds: 3),
        waveform: const [],
      );
      await controller.onLongPressStart();
      fake.setState(VoiceRecordingState.locked);

      final data = await controller.confirmSend();

      expect(fake.confirmCalls, 1);
      expect(data, isNotNull);
    });

    test('cancel cancels the underlying recording', () async {
      await controller.onLongPressStart();

      await controller.cancel();

      expect(fake.cancelCalled, isTrue);
      expect(controller.isAnyRecordingState, isFalse);
    });

    test('notifies listeners on drag update', () async {
      await controller.onLongPressStart();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.onLongPressMoveUpdate(const Offset(-5, -5), 360);

      expect(notifyCount, 1);
    });
  });

  group('VoiceRecorderGesture widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders child unchanged when idle', (tester) async {
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: const Text('child'),
          ),
        ),
      );

      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('disposing the host widget does not leak listeners', (
      tester,
    ) async {
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: const SizedBox(),
          ),
        ),
      );

      await tester.pumpWidget(wrap(const SizedBox()));
      // The host is gone; controller mutations must not throw.
      await controller.onLongPressStart();
    });
  });
}
