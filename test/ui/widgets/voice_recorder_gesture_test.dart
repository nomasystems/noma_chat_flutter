import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/_recording_indicators.dart'
    show HoldToRecordHintPill;
import 'package:noma_chat/src/ui/widgets/_voice_recorder_gesture.dart'
    show VoiceRecorderGesture;
import 'package:record/record.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _FakeRecordConfig extends Fake implements RecordConfig {}

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
  Completer<void>? startGate;

  /// Mirrors the real controller, which lets the caller veto the start
  /// right before the platform recorder would be armed. Set to false to
  /// model a release that lands once the recorder is already armed.
  bool honoursAbort = true;
  bool armed = false;
  bool cancelCalled = false;
  bool lockCalled = false;
  int stopCalls = 0;
  int confirmCalls = 0;
  VoiceMessageData? stopReturns;
  VoiceMessageData? confirmReturns;

  /// Models a platform recorder that throws instead of resolving — an iOS
  /// audio session that cannot be activated, a missing plugin.
  bool throwsOnStart = false;

  /// Models a stop that produced no usable audio: the capture never
  /// outlived the audio floor, or the file came back empty.
  bool stopFailedToCapture = false;

  /// The span the composer measured for the touch and handed to the send
  /// gate. Null until a release actually stops a capture.
  Duration? lastHeldFor;

  @override
  VoiceRecordingState get state => _fakeState;

  @override
  bool get lastCaptureFailed => stopFailedToCapture;

  void setState(VoiceRecordingState next) {
    _fakeState = next;
    notifyListeners();
  }

  @override
  Future<StartRecordingResult> startRecording({
    bool Function()? isStillWanted,
  }) async {
    if (startGate != null) await startGate!.future;
    if (throwsOnStart) throw StateError('platform recorder unavailable');
    if (honoursAbort && isStillWanted != null && !isStillWanted()) {
      return StartRecordingResult.aborted;
    }
    if (nextStartResult == StartRecordingResult.started) {
      armed = true;
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
  Future<VoiceMessageData?> stopRecording({Duration? heldFor}) async {
    stopCalls++;
    lastHeldFor = heldFor;
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

  setUpAll(() {
    registerFallbackValue(_FakeRecordConfig());
  });

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

    test('isPreparing covers the whole arming window', () async {
      fake.startGate = Completer<void>();
      final announced = <bool>[];
      controller.addListener(() => announced.add(controller.isPreparing));

      final pending = controller.onLongPressStart();

      expect(controller.isPreparing, isTrue);
      expect(controller.isRecording, isFalse);
      expect(controller.recording, isNotNull);
      expect(announced, contains(true));

      fake.startGate!.complete();
      await pending;

      expect(controller.isPreparing, isFalse);
      expect(controller.isRecording, isTrue);
    });

    test('isPreparing drops back when the start is refused', () async {
      fake.nextStartResult = StartRecordingResult.permissionDenied;

      await controller.onLongPressStart();

      expect(controller.isPreparing, isFalse);
      expect(controller.isRecording, isFalse);
    });

    test('a recorder that throws never strands isPreparing', () async {
      fake.throwsOnStart = true;

      final result = await controller.onLongPressStart();

      // The composer paints its recording row on isPreparing: leaving it
      // raised would strand recording chrome on screen with no capture
      // behind it and no text field to go back to.
      expect(result, StartRecordingResult.failed);
      expect(controller.isPreparing, isFalse);
      expect(controller.isRecording, isFalse);
      expect(controller.isAnyRecordingState, isFalse);
    });

    test('the send gate is told how long the touch lasted', () async {
      fake.stopReturns = VoiceMessageData(
        audioBytes: Uint8List(0),
        duration: const Duration(seconds: 2),
        waveform: const [],
      );
      await controller.onLongPressStart();

      await controller.onLongPressEnd(
        heldFor: const Duration(milliseconds: 1200),
      );

      expect(fake.lastHeldFor, const Duration(milliseconds: 1200));
      expect(controller.lastReleaseWasTooShort, isFalse);
    });

    test('a release under the minimum is flagged as too short', () async {
      await controller.onLongPressStart();

      await controller.onLongPressEnd(
        heldFor: const Duration(milliseconds: 300),
      );

      expect(controller.lastReleaseWasTooShort, isTrue);
    });

    test('releasing a locked recording is not flagged as too short', () async {
      await controller.onLongPressStart();
      fake.setState(VoiceRecordingState.locked);

      await controller.onLongPressEnd(heldFor: Duration.zero);

      expect(controller.lastReleaseWasTooShort, isFalse);
    });
  });

  group('VoiceRecorderGesture widget', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Material(child: Center(child: child)),
    );

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

    testWidgets('unsupported result falls back to onPermissionDenied', (
      tester,
    ) async {
      fake.nextStartResult = StartRecordingResult.unsupported;
      var permissionDeniedCalls = 0;
      final link = LayerLink();

      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: () => permissionDeniedCalls++,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      await tester.tap(find.byType(Container));
      await tester.pumpAndSettle();

      expect(permissionDeniedCalls, 1);
    });

    testWidgets('unsupported result calls onUnsupported when provided', (
      tester,
    ) async {
      fake.nextStartResult = StartRecordingResult.unsupported;
      var unsupportedCalls = 0;
      var permissionDeniedCalls = 0;
      final link = LayerLink();

      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: () => permissionDeniedCalls++,
            onUnsupported: () => unsupportedCalls++,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      await tester.tap(find.byType(Container));
      await tester.pumpAndSettle();

      expect(unsupportedCalls, 1);
      expect(permissionDeniedCalls, 0);
    });

    testWidgets('permissionDenied result does not call onUnsupported', (
      tester,
    ) async {
      fake.nextStartResult = StartRecordingResult.permissionDenied;
      var unsupportedCalls = 0;
      var permissionDeniedCalls = 0;
      final link = LayerLink();

      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: () => permissionDeniedCalls++,
            onUnsupported: () => unsupportedCalls++,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      await tester.tap(find.byType(Container));
      await tester.pumpAndSettle();

      expect(permissionDeniedCalls, 1);
      expect(unsupportedCalls, 0);
    });

    testWidgets('a denied microphone with no callback still says something', (
      tester,
    ) async {
      fake.nextStartResult = StartRecordingResult.permissionDenied;
      final link = LayerLink();

      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      await tester.tap(find.byType(Container));
      await tester.pumpAndSettle();

      expect(
        find.text(ChatUiLocalizations.en.microphonePermissionDenied),
        findsOneWidget,
      );
    });

    testWidgets('recording starts on touch down, without a long press', (
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
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();

      expect(controller.isRecording, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('touch down outside the mic button does not record', (
      tester,
    ) async {
      final micKey = GlobalKey();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            voiceButtonKey: micKey,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(key: ValueKey('field'), width: 100, height: 40),
                SizedBox(key: micKey, width: 40, height: 40),
              ],
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('field'))),
      );
      await tester.pump();

      expect(controller.isRecording, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();

      final onMic = await tester.startGesture(
        tester.getCenter(find.byKey(micKey)),
      );
      await tester.pump();

      expect(controller.isRecording, isTrue);

      await onMic.up();
      await tester.pumpAndSettle();
    });

    testWidgets('sliding up past the lock threshold locks the recording', (
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
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();

      expect(fake.lockCalled, isTrue);
      expect(controller.isLocked, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('sliding left past the cancel threshold cancels', (
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
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();

      expect(fake.cancelCalled, isTrue);
      expect(controller.isRecording, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a release while the recorder is still starting never arms it',
      (tester) async {
        fake.startGate = Completer<void>();
        final link = LayerLink();
        await tester.pumpWidget(
          wrap(
            VoiceRecorderGesture(
              controller: controller,
              layerLink: link,
              theme: ChatTheme.defaults,
              onPermissionDenied: null,
              onVoiceMessageReady: (_) {},
              child: Container(color: Colors.blue, width: 40, height: 40),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Container)),
        );
        await tester.pump();
        await gesture.up();
        await tester.pump();

        fake.startGate!.complete();
        await tester.pumpAndSettle();

        expect(fake.armed, isFalse);
        expect(fake.cancelCalled, isFalse);
        expect(controller.isAnyRecordingState, isFalse);
      },
    );

    testWidgets('a release once the recorder is already armed drops it', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      fake.honoursAbort = false;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(fake.armed, isTrue);
      expect(fake.cancelCalled, isTrue);
      expect(controller.isAnyRecordingState, isFalse);
    });

    testWidgets('a cancelled pointer discards the recording', (tester) async {
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      expect(controller.isRecording, isTrue);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(fake.cancelCalled, isTrue);
      expect(fake.stopCalls, 0);
      expect(controller.isAnyRecordingState, isFalse);
    });

    testWidgets('a cancelled pointer leaves a locked recording alone', (
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
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(controller.isLocked, isTrue);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(fake.cancelCalled, isFalse);
      expect(controller.isLocked, isTrue);

      await controller.cancel();
    });

    testWidgets('a pointer cancelled while the recorder is starting drops it', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      fake.honoursAbort = false;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.cancelCalled, isTrue);
      expect(controller.isAnyRecordingState, isFalse);
    });

    testWidgets('a hold over the mic button still delivers its own tap', (
      tester,
    ) async {
      final micKey = GlobalKey();
      final link = LayerLink();
      var micTaps = 0;
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            voiceButtonKey: micKey,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 100, height: 40),
                GestureDetector(
                  key: micKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => micTaps++,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ],
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(micKey)),
      );
      // Well past kLongPressTimeout: a gesture recognizer here would have
      // claimed the arena by now and the child would never see its tap.
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(micTaps, 1);
      expect(fake.stopCalls, 1);
    });

    testWidgets('the recording row is on screen before the recorder arms', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => VoiceRecorderGesture(
              controller: controller,
              layerLink: link,
              theme: ChatTheme.defaults,
              onPermissionDenied: null,
              onVoiceMessageReady: (_) {},
              child: controller.isRecording || controller.isPreparing
                  ? const Text('recording-row')
                  : Container(color: Colors.blue, width: 40, height: 40),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();

      expect(controller.isRecording, isFalse);
      expect(find.text('recording-row'), findsOneWidget);

      fake.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(controller.isRecording, isTrue);
      expect(find.text('recording-row'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a touch too brief to be a recording prompts the user', (
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
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.stopCalls, 1);
      expect(find.byType(HoldToRecordHintPill), findsOneWidget);

      await tester.pump(const VoiceGestureThresholds().holdHintDuration);
      await tester.pump();

      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a release before the recorder arms prompts the user', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.armed, isFalse);
      expect(find.byType(HoldToRecordHintPill), findsOneWidget);
    });

    testWidgets('a recording armed after the release prompts the user', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      fake.honoursAbort = false;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.cancelCalled, isTrue);
      expect(find.byType(HoldToRecordHintPill), findsOneWidget);
    });

    testWidgets('a pointer cancelled while arming prompts nothing', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.armed, isFalse);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a deliberate slide-to-cancel prompts nothing', (tester) async {
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.cancelCalled, isTrue);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a slide-to-cancel still draining prompts nothing', (
      tester,
    ) async {
      final recorder = _MockAudioRecorder();
      final player = _MockAudioPlayer();
      final drain = Completer<String?>();
      when(() => recorder.dispose()).thenAnswer((_) async {});
      when(() => recorder.hasPermission()).thenAnswer((_) async => true);
      when(
        () => recorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(
        () => recorder.getAmplitude(),
      ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
      when(() => recorder.isRecording()).thenAnswer((_) async => true);
      when(() => recorder.isPaused()).thenAnswer((_) async => false);
      when(() => recorder.stop()).thenAnswer((_) => drain.future);
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

      controller.dispose();
      controller = MessageInputVoiceController(
        maxRecordingDuration: const Duration(minutes: 1),
        recordingControllerFactory: (max) => VoiceRecordingController(
          maxDuration: max,
          revealDelay: Duration.zero,
          recorder: recorder,
          preListenPlayer: player,
          tempDirectoryPath: '/tmp/noma_chat_voice_gesture_test',
        ),
      );

      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(Container)));
      await tester.pump();
      await tester.pump();

      expect(controller.isRecording, isTrue);

      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();

      expect(controller.isAnyRecordingState, isFalse);

      await gesture.up(timeStamp: const Duration(milliseconds: 1500));
      await tester.pump();

      expect(find.text(ChatUiLocalizations.en.recordingFailed), findsNothing);
      expect(find.text(ChatUiLocalizations.en.holdToRecord), findsNothing);

      drain.complete(null);
      await tester.pumpAndSettle();

      expect(find.text(ChatUiLocalizations.en.recordingFailed), findsNothing);
      expect(find.text(ChatUiLocalizations.en.holdToRecord), findsNothing);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
      verify(() => recorder.stop()).called(1);
    });

    testWidgets('an empty holdToRecord string suppresses the prompt', (
      tester,
    ) async {
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults.copyWith(
              l10n: ChatUiLocalizations.en.copyWith(holdToRecord: ''),
            ),
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.stopCalls, 1);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('an upward flick thrown while arming still locks', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();

      expect(fake.lockCalled, isFalse);

      fake.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(fake.lockCalled, isTrue);
      expect(controller.isLocked, isTrue);

      await gesture.up();
      await tester.pump();

      expect(fake.stopCalls, 0);

      await controller.cancel();
    });

    testWidgets('the hold is measured from the touch, not from the arming', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      fake.stopReturns = VoiceMessageData(
        audioBytes: Uint8List(0),
        duration: const Duration(seconds: 1),
        waveform: const [],
      );
      var delivered = 0;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) => delivered++,
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(Container)));
      await tester.pump();
      fake.startGate!.complete();
      await tester.pump();
      await gesture.up(timeStamp: const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      expect(fake.lastHeldFor, const Duration(milliseconds: 1200));
      expect(delivered, 1);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a capture that comes back empty is not blamed on the user', (
      tester,
    ) async {
      fake.stopReturns = null;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(Container)));
      await tester.pump();
      await gesture.up(timeStamp: const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(fake.stopCalls, 1);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a hold the recorder never answered is told apart', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(Container)));
      await tester.pump();
      // Held well past the minimum — the permission dialog case, where the
      // arming resolves long after the finger is gone.
      await gesture.up(timeStamp: const Duration(milliseconds: 1500));
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.armed, isFalse);
      expect(find.text(ChatUiLocalizations.en.recordingFailed), findsOneWidget);
      expect(find.text(ChatUiLocalizations.en.holdToRecord), findsNothing);
    });

    testWidgets('a recorder that refuses to arm says so', (tester) async {
      fake.nextStartResult = StartRecordingResult.failed;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(controller.isAnyRecordingState, isFalse);
      expect(find.text(ChatUiLocalizations.en.recordingFailed), findsOneWidget);
    });

    testWidgets('a capture the recorder failed to deliver says so', (
      tester,
    ) async {
      fake.stopReturns = null;
      fake.stopFailedToCapture = true;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(Container)));
      await tester.pump();
      await gesture.up(timeStamp: const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(fake.stopCalls, 1);
      expect(find.text(ChatUiLocalizations.en.recordingFailed), findsOneWidget);
      expect(find.text(ChatUiLocalizations.en.holdToRecord), findsNothing);
    });

    testWidgets('a recorder that throws leaves the mic usable', (tester) async {
      fake.throwsOnStart = true;
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final failed = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await failed.up();
      await tester.pumpAndSettle();

      expect(controller.isPreparing, isFalse);
      expect(controller.isAnyRecordingState, isFalse);

      fake.throwsOnStart = false;
      final second = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();

      expect(controller.isRecording, isTrue);

      await second.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a sideways drag while arming prompts nothing', (tester) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (data) => fail('nothing may be sent: $data'),
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      fake.startGate!.complete();
      await tester.pumpAndSettle();

      expect(fake.armed, isFalse);
      expect(find.byType(HoldToRecordHintPill), findsNothing);
    });

    testWidgets('a downward drag thrown while arming stays inert', (
      tester,
    ) async {
      fake.startGate = Completer<void>();
      final link = LayerLink();
      await tester.pumpWidget(
        wrap(
          VoiceRecorderGesture(
            controller: controller,
            layerLink: link,
            theme: ChatTheme.defaults,
            onPermissionDenied: null,
            onVoiceMessageReady: (_) {},
            child: Container(color: Colors.blue, width: 40, height: 40),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Container)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      fake.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(fake.lockCalled, isFalse);
      expect(fake.cancelCalled, isFalse);
      expect(controller.isRecording, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
