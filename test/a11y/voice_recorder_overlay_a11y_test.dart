import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:record/record.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _FakeRecordConfig extends Fake implements RecordConfig {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAudioRecorder recorder;
  late _MockAudioPlayer player;
  late Directory tempDir;

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUpAll(() {
    registerFallbackValue(_FakeRecordConfig());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(UrlSource('_'));
  });

  setUp(() async {
    recorder = _MockAudioRecorder();
    player = _MockAudioPlayer();
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => recorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(
      () => recorder.getAmplitude(),
    ).thenAnswer((_) async => Amplitude(current: -30.0, max: 0.0));
    when(() => recorder.isRecording()).thenAnswer((_) async => true);
    when(() => recorder.isPaused()).thenAnswer((_) async => false);
    when(() => recorder.pause()).thenAnswer((_) async {});
    when(() => recorder.resume()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async => '');
    when(() => player.stop()).thenAnswer((_) async {});
    when(() => player.pause()).thenAnswer((_) async {});
    when(() => player.resume()).thenAnswer((_) async {});
    when(() => player.seek(any())).thenAnswer((_) async {});
    when(() => player.play(any())).thenAnswer((_) async {});
    when(
      () => player.onPositionChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => player.onDurationChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => player.onPlayerStateChanged,
    ).thenAnswer((_) => const Stream<PlayerState>.empty());

    tempDir = await Directory.systemTemp.createTemp('voice_overlay_a11y_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  VoiceRecordingController makeController() => VoiceRecordingController(
    recorder: recorder,
    preListenPlayer: player,
    tempDirectoryPath: tempDir.path,
  );

  group('VoiceRecorderOverlay a11y', () {
    testWidgets(
      'locked state surfaces Delete / Pause / Preview / Send labels',
      (tester) async {
        final controller = makeController();

        await controller.startRecording();
        controller.lockRecording();
        await tester.pumpWidget(
          wrap(VoiceRecorderOverlay(controller: controller, onSend: () {})),
        );

        expect(find.bySemanticsLabel('Delete'), findsOneWidget);
        expect(find.bySemanticsLabel('Pause recording'), findsOneWidget);
        expect(find.bySemanticsLabel('Preview'), findsOneWidget);
        expect(find.bySemanticsLabel('Send'), findsOneWidget);

        await controller.cancelRecording();
        controller.dispose();
      },
    );

    testWidgets('locked state buttons have 48dp tap targets', (tester) async {
      final controller = makeController();

      await controller.startRecording();
      controller.lockRecording();
      await tester.pumpWidget(
        wrap(VoiceRecorderOverlay(controller: controller, onSend: () {})),
      );

      for (final label in const [
        'Delete',
        'Pause recording',
        'Preview',
        'Send',
      ]) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: '$label width $size',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: '$label height $size',
        );
      }

      await controller.cancelRecording();
      controller.dispose();
    });

    testWidgets('paused locked state exposes Resume recording label', (
      tester,
    ) async {
      final controller = makeController();

      await controller.startRecording();
      controller.lockRecording();
      await controller.pauseRecording();
      await tester.pumpWidget(
        wrap(VoiceRecorderOverlay(controller: controller, onSend: () {})),
      );

      expect(find.bySemanticsLabel('Resume recording'), findsOneWidget);
      final size = tester.getSize(find.bySemanticsLabel('Resume recording'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await controller.cancelRecording();
      controller.dispose();
    });

    testWidgets('preListen state exposes Delete and Send labels at 48dp', (
      tester,
    ) async {
      final controller = makeController();

      await controller.startRecording();
      controller.lockRecording();
      await controller.startPreListen();
      await tester.pumpWidget(
        wrap(VoiceRecorderOverlay(controller: controller, onSend: () {})),
      );

      for (final label in const ['Delete', 'Send']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      }

      await controller.cancelRecording();
      controller.dispose();
    });
  });
}
