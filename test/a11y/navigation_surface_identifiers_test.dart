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

/// The controls a driver has to press to move between screens: the room
/// header's back arrow and title, the row that opens a chat, the new-chat
/// button, the thread panel's close button and the pre-listen play button.
///
/// Each publishes the same literal twice — as a `ValueKey` and as
/// `Semantics(identifier:)` — so the same name works from a widget test and
/// from a native driver (`resource-id` on Android, `accessibilityIdentifier`
/// on iOS).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SemanticsHandle handle;

  setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
  tearDown(() => handle.dispose());

  SemanticsFinder identifier(String name) => find.semantics.byPredicate(
    (node) => node.identifier == name,
    describeMatch: (_) => 'semantics node with identifier "$name"',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  void expectBothHalves(WidgetTester tester, String name) {
    expect(find.byKey(ValueKey(name)), findsOneWidget);
    expect(identifier(name), findsOne);
  }

  group('the room header', () {
    ChatController makeController() => ChatController(
      initialMessages: const [],
      currentUser: const ChatUser(id: 'me', displayName: 'Me'),
    );

    Future<void> pumpBar(
      WidgetTester tester, {
      VoidCallback? onBack,
      VoidCallback? onTap,
    }) async {
      final controller = makeController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: ChatRoomAppBar(
              controller: controller,
              room: const RoomListItem(id: 'r1', name: 'Alice'),
              onBack: onBack,
              onTap: onTap,
            ),
            body: const SizedBox(),
          ),
        ),
      );
    }

    testWidgets('names the back arrow and the title row', (tester) async {
      await pumpBar(tester, onBack: () {}, onTap: () {});

      expectBothHalves(tester, 'chat_room_back_button');
      expectBothHalves(tester, 'chat_room_title');
    });

    testWidgets('the back arrow is gone when the host owns the leading slot', (
      tester,
    ) async {
      await pumpBar(tester, onTap: () {});

      expect(identifier('chat_room_back_button'), findsNothing);
      expectBothHalves(tester, 'chat_room_title');
    });
  });

  group('the room list', () {
    testWidgets('names each row after the room it opens', (tester) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              RoomTile(
                room: const RoomListItem(id: 'r1', name: 'Alice'),
                onTap: () {},
              ),
              RoomTile(
                room: const RoomListItem(id: 'r2', name: 'Alice'),
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expectBothHalves(tester, roomTileSemanticsId('r1'));
      expectBothHalves(tester, roomTileSemanticsId('r2'));
    });

    testWidgets('names the new-chat button', (tester) async {
      await tester.pumpWidget(wrap(RoomListHeader(onNewChat: () {})));

      expectBothHalves(tester, 'chat_room_list_new_chat_button');
    });
  });

  group('the thread panel', () {
    testWidgets('names the close button', (tester) async {
      final controller = ChatController(
        initialMessages: const [],
        currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: ChatMessage(
              id: 'parent1',
              from: 'u2',
              timestamp: DateTime(2026, 1, 1),
              text: 'Parent',
            ),
            controller: controller,
            currentUserId: 'u1',
            onClose: () {},
          ),
        ),
      );

      expectBothHalves(tester, 'chat_thread_close_button');
    });
  });

  group('the voice recorder', () {
    late _MockAudioRecorder recorder;
    late _MockAudioPlayer player;
    late Directory tempDir;

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

      tempDir = await Directory.systemTemp.createTemp('voice_overlay_ids_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('names the pre-listen play button', (tester) async {
      final controller = VoiceRecordingController(
        recorder: recorder,
        preListenPlayer: player,
        tempDirectoryPath: tempDir.path,
      );

      await controller.startRecording();
      controller.lockRecording();
      await controller.startPreListen();
      await tester.pumpWidget(
        wrap(VoiceRecorderOverlay(controller: controller, onSend: () {})),
      );

      expectBothHalves(tester, 'chat_voice_overlay_prelisten_play_button');

      await controller.cancelRecording();
      controller.dispose();
    });
  });
}
