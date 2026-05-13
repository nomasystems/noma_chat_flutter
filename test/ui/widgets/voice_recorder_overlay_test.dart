import 'dart:io';

import 'package:flutter/material.dart';
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
  late Directory tempDir;

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUpAll(() {
    registerFallbackValue(FakeRecordConfig());
    registerFallbackValue(Duration.zero);
  });

  setUp(() async {
    mockRecorder = MockAudioRecorder();
    mockPlayer = MockAudioPlayer();
    when(() => mockRecorder.dispose()).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => mockRecorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => mockRecorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => false);
    when(() => mockRecorder.isPaused()).thenAnswer((_) async => false);
    when(() => mockRecorder.pause()).thenAnswer((_) async {});
    when(() => mockRecorder.resume()).thenAnswer((_) async {});
    when(() => mockRecorder.stop()).thenAnswer((_) async => '');
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockPlayer.pause()).thenAnswer((_) async {});
    when(() => mockPlayer.playing).thenReturn(false);
    when(() => mockPlayer.position).thenReturn(Duration.zero);
    when(() => mockPlayer.duration).thenReturn(null);
    when(() => mockPlayer.setFilePath(any())).thenAnswer((_) async => null);
    when(() => mockPlayer.play()).thenAnswer((_) async {});
    when(
      () => mockPlayer.positionStream,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.durationStream,
    ).thenAnswer((_) => const Stream<Duration?>.empty());
    when(
      () => mockPlayer.playerStateStream,
    ).thenAnswer((_) => const Stream<PlayerState>.empty());

    tempDir = await Directory.systemTemp.createTemp('overlay_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  VoiceRecordingController createController() => VoiceRecordingController(
    recorder: mockRecorder,
    preListenPlayer: mockPlayer,
    tempDirectoryPath: tempDir.path,
  );

  test('formatDuration formats correctly', () {
    expect(VoiceRecorderOverlay.formatDuration(Duration.zero), '00:00');
    expect(
      VoiceRecorderOverlay.formatDuration(const Duration(seconds: 5)),
      '00:05',
    );
    expect(
      VoiceRecorderOverlay.formatDuration(
        const Duration(minutes: 1, seconds: 30),
      ),
      '01:30',
    );
  });

  testWidgets('renders nothing in idle state', (tester) async {
    final controller = createController();
    addTearDown(() => controller.dispose());

    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(find.byType(WaveformDisplay), findsNothing);
  });

  testWidgets('renders recording UI after startRecording', (tester) async {
    final controller = createController();

    await controller.startRecording();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(find.byType(WaveformDisplay), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Slide up to lock'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.text('Slide to cancel'), findsOneWidget);

    await controller.cancelRecording();
    controller.dispose();
  });

  testWidgets('shows pause/delete/send buttons in locked state', (
    tester,
  ) async {
    final controller = createController();

    await controller.startRecording();
    controller.lockRecording();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.text('Recording...'), findsOneWidget);

    await controller.cancelRecording();
    controller.dispose();
  });

  testWidgets('shows resume button when locked recording is paused', (
    tester,
  ) async {
    final controller = createController();
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);

    await controller.startRecording();
    controller.lockRecording();
    await controller.pauseRecording();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(controller.isPaused, isTrue);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);

    await controller.cancelRecording();
    controller.dispose();
  });

  testWidgets('delete in locked cancels recording', (tester) async {
    final controller = createController();
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);

    await controller.startRecording();
    controller.lockRecording();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(controller.state, VoiceRecordingState.idle);
    controller.dispose();
  });

  testWidgets('send button calls onSend', (tester) async {
    final controller = createController();
    var sendCalled = false;

    await controller.startRecording();
    controller.lockRecording();
    await tester.pumpWidget(
      wrap(
        VoiceRecorderOverlay(
          controller: controller,
          onSend: () => sendCalled = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sendCalled, isTrue);

    await controller.cancelRecording();
    controller.dispose();
  });

  testWidgets('locked state shows play button that triggers preListen', (
    tester,
  ) async {
    final controller = createController();
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);

    await controller.startRecording();
    controller.lockRecording();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(controller.state, VoiceRecordingState.preListen);
    verify(() => mockPlayer.setFilePath(any())).called(1);
    verify(() => mockPlayer.play()).called(1);

    await controller.cancelRecording();
    controller.dispose();
  });

  testWidgets('preListen shows play/pause and send', (tester) async {
    final controller = createController();
    when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);

    await controller.startRecording();
    controller.lockRecording();
    await controller.startPreListen();
    await tester.pumpWidget(wrap(VoiceRecorderOverlay(controller: controller)));

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);

    await controller.cancelRecording();
    controller.dispose();
  });
}
