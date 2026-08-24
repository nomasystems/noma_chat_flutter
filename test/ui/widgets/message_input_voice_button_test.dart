import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/_recording_indicators.dart'
    show HoldToRecordHintPill;
import 'package:record/record.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

/// Stands in for the platform recorder inside a real [MessageInput]: state
/// flips immediately and no platform channel is ever touched, so the
/// composer's row swaps happen on the frames the test asks for.
class _FakeRecordingController extends VoiceRecordingController {
  _FakeRecordingController({
    required AudioRecorder recorder,
    required AudioPlayer player,
  }) : super(
         maxDuration: const Duration(minutes: 1),
         recorder: recorder,
         preListenPlayer: player,
         tempDirectoryPath: '/tmp/noma_chat_voice_test',
       );

  VoiceRecordingState _fakeState = VoiceRecordingState.idle;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  VoiceRecordingState get state => _fakeState;

  @override
  Future<StartRecordingResult> startRecording({
    bool Function()? isStillWanted,
  }) async {
    startCalls++;
    if (isStillWanted != null && !isStillWanted()) {
      return StartRecordingResult.aborted;
    }
    _fakeState = VoiceRecordingState.recording;
    notifyListeners();
    return StartRecordingResult.started;
  }

  @override
  Future<VoiceMessageData?> stopRecording({Duration? heldFor}) async {
    stopCalls++;
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
    return null;
  }

  @override
  Future<void> cancelRecording() async {
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
  }

  @override
  Future<void> startPreListen() async {}

  @override
  Future<void> stopPreListen() async {}
}

_FakeRecordingController _buildFake() {
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
  return _FakeRecordingController(recorder: recorder, player: player);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = ChatUser(id: 'u1', displayName: 'Alice');
  late ChatController chat;
  late _FakeRecordingController fake;

  setUp(() {
    chat = ChatController(initialMessages: [], currentUser: user);
    fake = _buildFake();
  });

  tearDown(() => chat.dispose());

  Widget wrap({
    ChatTheme? theme,
    bool Function()? canStartRecording,
    VoidCallback? onRecordingRejected,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MessageInput(
          controller: chat,
          onSendMessageRequest: (_) {},
          onVoiceMessageReady: (_) {},
          canStartRecording: canStartRecording,
          onRecordingRejected: onRecordingRejected,
          voiceRecordingControllerFactory: (_) => fake,
          theme: theme ?? ChatTheme.defaults,
        ),
      ),
    ),
  );

  group('MessageInput voice button', () {
    testWidgets('short taps repeated inside the cross-fade keep one button', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      expect(find.byType(VoiceRecorderButton), findsOneWidget);

      for (var pass = 0; pass < 3; pass++) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(VoiceRecorderButton)),
        );
        await tester.pump();

        expect(find.byType(VoiceRecorderButton), findsOneWidget);
        expect(tester.takeException(), isNull);

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.byType(VoiceRecorderButton), findsOneWidget);
        expect(find.byType(TextField), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      }

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VoiceRecorderButton), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(fake.stopCalls, 3);
    });

    testWidgets('the button survives a full recording round trip', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(VoiceRecorderButton), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(VoiceRecorderButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a host recording composer gets no leader to follow', (
      tester,
    ) async {
      final theme = ChatTheme.defaults.copyWith(
        input: ChatTheme.defaults.input.copyWith(
          recordingComposerBuilder: (context, controller, onSend) =>
              const SizedBox(height: 56, child: Text('host composer')),
        ),
      );
      await tester.pumpWidget(wrap(theme: theme));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('host composer'), findsOneWidget);
      // No mic button means no leader, which is what keeps the floating
      // "slide up to lock" pill from anchoring itself to an empty
      // rectangle at the edge of the screen, over the host's own composer.
      expect(find.byType(VoiceRecorderButton), findsNothing);
      expect(find.byType(CompositedTransformTarget), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('once there is text, the send button cannot start a capture', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.byType(VoiceRecorderButton), findsNothing);

      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(fake.startCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('MessageInput voice gate', () {
    testWidgets('a vetoed room never arms the recorder', (tester) async {
      var rejections = 0;
      await tester.pumpWidget(
        wrap(
          canStartRecording: () => false,
          onRecordingRejected: () => rejections++,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      // startRecording is where the platform permission round trip lives,
      // so zero calls is what "the system never asked for the microphone"
      // looks like from here.
      expect(fake.startCalls, 0);
      expect(rejections, 1);
      // The composer never swaps to the recording row: no "slide to
      // cancel", no lock hint, the text field still on screen.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(ChatUiLocalizations.en.slideToCancel), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(fake.startCalls, 0);
      expect(fake.stopCalls, 0);
      expect(rejections, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a veto with no handler floats the default prompt', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(canStartRecording: () => false));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();

      expect(fake.startCalls, 0);
      expect(find.byType(HoldToRecordHintPill), findsOneWidget);
      expect(
        find.text(ChatUiLocalizations.en.recordingNotAllowed),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('the veto is re-asked on every touch, not cached', (
      tester,
    ) async {
      var open = false;
      await tester.pumpWidget(
        wrap(canStartRecording: () => open, onRecordingRejected: () {}),
      );

      final blocked = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await blocked.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fake.startCalls, 0);

      open = true;
      final allowed = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The refused touch left no gesture state behind: the very next
      // touch records normally.
      expect(fake.startCalls, 1);
      expect(find.byType(TextField), findsNothing);

      await allowed.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no veto keeps the recorder arming as before', (tester) async {
      await tester.pumpWidget(wrap());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fake.startCalls, 1);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
