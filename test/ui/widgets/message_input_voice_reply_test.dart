import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:record/record.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

/// Stands in for the platform recorder: the capture locks on demand and
/// confirms with a clip, so the composer's send path runs on the frames the
/// test asks for and no platform channel is ever touched.
class _FakeRecordingController extends VoiceRecordingController {
  _FakeRecordingController({
    required AudioRecorder recorder,
    required AudioPlayer player,
  }) : super(
         maxDuration: const Duration(minutes: 1),
         recorder: recorder,
         preListenPlayer: player,
         tempDirectoryPath: '/tmp/noma_chat_voice_reply_test',
       );

  VoiceRecordingState _fakeState = VoiceRecordingState.idle;

  @override
  VoiceRecordingState get state => _fakeState;

  void lock() {
    _fakeState = VoiceRecordingState.locked;
    notifyListeners();
  }

  @override
  Future<StartRecordingResult> startRecording({
    bool Function()? isStillWanted,
  }) async {
    _fakeState = VoiceRecordingState.recording;
    notifyListeners();
    return StartRecordingResult.started;
  }

  @override
  Future<VoiceMessageData?> confirmSend() async {
    _fakeState = VoiceRecordingState.idle;
    notifyListeners();
    return VoiceMessageData(
      audioBytes: Uint8List.fromList(const [1, 2, 3]),
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3],
    );
  }

  @override
  Future<VoiceMessageData?> stopRecording({Duration? heldFor}) async {
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
    () => player.onPlayerComplete,
  ).thenAnswer((_) => const Stream<void>.empty());
  return _FakeRecordingController(recorder: recorder, player: player);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = ChatUser(id: 'u1', displayName: 'Alice');
  final quoted = ChatMessage(
    id: 'm1',
    from: 'u2',
    timestamp: DateTime(2026),
    text: 'the message being answered',
  );

  late ChatController chat;
  late _FakeRecordingController fake;
  late List<VoiceMessageData> sent;

  setUp(() {
    chat = ChatController(initialMessages: [quoted], currentUser: user);
    fake = _buildFake();
    sent = [];
  });

  tearDown(() => chat.dispose());

  Future<void> pumpAndSendLockedNote(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              controller: chat,
              onSendMessageRequest: (_) => true,
              onVoiceMessageReady: sent.add,
              voiceRecordingControllerFactory: (_) => fake,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecorderButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    fake.lock();
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  testWidgets('a note recorded with the reply preview open is sent as the '
      'answer, and the preview closes with it', (tester) async {
    chat.setReplyTo(quoted);

    await pumpAndSendLockedNote(tester);

    expect(sent, hasLength(1));
    expect(sent.single.referencedMessageId, 'm1');
    expect(chat.replyingTo, isNull);
  });

  testWidgets('a note recorded with no reply pending quotes nothing', (
    tester,
  ) async {
    await pumpAndSendLockedNote(tester);

    expect(sent, hasLength(1));
    expect(sent.single.referencedMessageId, isNull);
    expect(chat.replyingTo, isNull);
  });
}
