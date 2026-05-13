import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  late AudioPlaybackCoordinator coordinator;
  late MockAudioPlayer player1;
  late MockAudioPlayer player2;

  setUp(() {
    coordinator = AudioPlaybackCoordinator();
    player1 = MockAudioPlayer();
    player2 = MockAudioPlayer();

    when(() => player1.play()).thenAnswer((_) async {});
    when(() => player1.pause()).thenAnswer((_) async {});
    when(() => player1.seek(any())).thenAnswer((_) async {});
    when(() => player1.setSpeed(any())).thenAnswer((_) async {});
    when(() => player1.dispose()).thenAnswer((_) async {});
    when(() => player2.play()).thenAnswer((_) async {});
    when(() => player2.pause()).thenAnswer((_) async {});
    when(() => player2.seek(any())).thenAnswer((_) async {});
    when(() => player2.setSpeed(any())).thenAnswer((_) async {});
    when(() => player2.dispose()).thenAnswer((_) async {});
  });

  tearDown(() => coordinator.dispose());

  test('initial state is idle', () {
    expect(coordinator.currentlyPlayingId, isNull);
    expect(coordinator.speed, 1.0);
    expect(coordinator.speedLabel, '1x');
  });

  test('play sets currentlyPlayingId', () async {
    coordinator.registerPlayer('msg1', player1);
    await coordinator.play('msg1');

    expect(coordinator.currentlyPlayingId, 'msg1');
    // Speed is owned by each AudioBubble; the coordinator no longer touches
    // it during play() so each audio keeps its own 1x/1.5x/2x.
    verifyNever(() => player1.setSpeed(any()));
    verify(() => player1.play()).called(1);
  });

  test('playing a second audio pauses the first', () async {
    coordinator.registerPlayer('msg1', player1);
    coordinator.registerPlayer('msg2', player2);

    await coordinator.play('msg1');
    await coordinator.play('msg2');

    expect(coordinator.currentlyPlayingId, 'msg2');
    verify(() => player1.pause()).called(1);
    verify(() => player2.play()).called(1);
  });

  test('pause clears currentlyPlayingId', () async {
    coordinator.registerPlayer('msg1', player1);
    await coordinator.play('msg1');
    await coordinator.pause('msg1');

    expect(coordinator.currentlyPlayingId, isNull);
    verify(() => player1.pause()).called(1);
  });

  test('cycleSpeed cycles 1x -> 1.5x -> 2x -> 1x', () {
    expect(coordinator.speed, 1.0);
    expect(coordinator.speedLabel, '1x');

    coordinator.cycleSpeed();
    expect(coordinator.speed, 1.5);
    expect(coordinator.speedLabel, '1.5x');

    coordinator.cycleSpeed();
    expect(coordinator.speed, 2.0);
    expect(coordinator.speedLabel, '2x');

    coordinator.cycleSpeed();
    expect(coordinator.speed, 1.0);
    expect(coordinator.speedLabel, '1x');
  });

  test('cycleSpeed sets speed on currently playing player', () async {
    coordinator.registerPlayer('msg1', player1);
    await coordinator.play('msg1');

    coordinator.cycleSpeed();
    verify(() => player1.setSpeed(1.5)).called(1);
  });

  test('stopAll pauses all and resets', () async {
    coordinator.registerPlayer('msg1', player1);
    coordinator.registerPlayer('msg2', player2);
    await coordinator.play('msg1');

    await coordinator.stopAll();

    expect(coordinator.currentlyPlayingId, isNull);
    verify(() => player1.pause()).called(1);
    verify(() => player1.seek(Duration.zero)).called(1);
    verify(() => player2.pause()).called(1);
    verify(() => player2.seek(Duration.zero)).called(1);
  });

  test('unregisterPlayer clears currentlyPlayingId if active', () async {
    coordinator.registerPlayer('msg1', player1);
    await coordinator.play('msg1');

    coordinator.unregisterPlayer('msg1');
    expect(coordinator.currentlyPlayingId, isNull);
  });

  test('notifies listeners on play', () async {
    coordinator.registerPlayer('msg1', player1);
    var notified = false;
    coordinator.addListener(() => notified = true);

    await coordinator.play('msg1');
    expect(notified, isTrue);
  });

  group('auto-play next unlistened', () {
    test(
      'plays the next incoming unlistened audio when one completes',
      () async {
        coordinator.registerPlayer(
          'msg1',
          player1,
          isOutgoing: false,
          isListened: false,
        );
        coordinator.registerPlayer(
          'msg2',
          player2,
          isOutgoing: false,
          isListened: false,
        );

        await coordinator.play('msg1');
        coordinator.markListened('msg1');
        await coordinator.notifyCompleted('msg1');

        expect(coordinator.currentlyPlayingId, 'msg2');
        verify(() => player2.play()).called(1);
      },
    );

    test('skips outgoing audios as auto-play target', () async {
      final player3 = MockAudioPlayer();
      when(() => player3.play()).thenAnswer((_) async {});
      when(() => player3.pause()).thenAnswer((_) async {});
      when(() => player3.seek(any())).thenAnswer((_) async {});
      when(() => player3.setSpeed(any())).thenAnswer((_) async {});
      when(() => player3.dispose()).thenAnswer((_) async {});

      coordinator.registerPlayer('msg1', player1, isOutgoing: false);
      coordinator.registerPlayer('msg2', player2, isOutgoing: true);
      coordinator.registerPlayer('msg3', player3, isOutgoing: false);

      await coordinator.play('msg1');
      coordinator.markListened('msg1');
      await coordinator.notifyCompleted('msg1');

      expect(coordinator.currentlyPlayingId, 'msg3');
      verifyNever(() => player2.play());
      verify(() => player3.play()).called(1);
    });

    test('skips already listened audios', () async {
      final player3 = MockAudioPlayer();
      when(() => player3.play()).thenAnswer((_) async {});
      when(() => player3.pause()).thenAnswer((_) async {});
      when(() => player3.seek(any())).thenAnswer((_) async {});
      when(() => player3.setSpeed(any())).thenAnswer((_) async {});
      when(() => player3.dispose()).thenAnswer((_) async {});

      coordinator.registerPlayer('msg1', player1, isOutgoing: false);
      coordinator.registerPlayer(
        'msg2',
        player2,
        isOutgoing: false,
        isListened: true,
      );
      coordinator.registerPlayer('msg3', player3, isOutgoing: false);

      await coordinator.play('msg1');
      coordinator.markListened('msg1');
      await coordinator.notifyCompleted('msg1');

      expect(coordinator.currentlyPlayingId, 'msg3');
      verifyNever(() => player2.play());
      verify(() => player3.play()).called(1);
    });

    test('stops auto-play when no next unlistened exists', () async {
      coordinator.registerPlayer('msg1', player1, isOutgoing: false);

      await coordinator.play('msg1');
      coordinator.markListened('msg1');
      await coordinator.notifyCompleted('msg1');

      expect(coordinator.currentlyPlayingId, isNull);
      verifyNever(() => player2.play());
    });

    test('markListened on already listened entry is a no-op', () {
      coordinator.registerPlayer(
        'msg1',
        player1,
        isOutgoing: false,
        isListened: true,
      );
      coordinator.markListened('msg1');
      coordinator.markListened('msg1');
      // No assertion target other than not throwing — sanity check.
      expect(coordinator.currentlyPlayingId, isNull);
    });

    test('re-registering preserves listened flag once set', () async {
      coordinator.registerPlayer(
        'msg1',
        player1,
        isOutgoing: false,
        isListened: false,
      );
      coordinator.markListened('msg1');
      coordinator.registerPlayer(
        'msg1',
        player1,
        isOutgoing: false,
        isListened: false,
      );
      coordinator.registerPlayer('msg2', player2, isOutgoing: false);
      await coordinator.notifyCompleted('msg1');

      expect(coordinator.currentlyPlayingId, 'msg2');
    });
  });
}
