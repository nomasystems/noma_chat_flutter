import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../_helpers/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform player;

  setUp(() {
    player = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = player;
  });

  Future<void> pumpPreview(
    WidgetTester tester, {
    ChatTheme? theme,
    String path = '/tmp/clip.mp4',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraVideoPreview(
            file: XFile(path),
            theme: theme ?? ChatTheme.defaults,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    // `VideoPlayerController` pauses itself once as it settles the freshly
    // initialised player; every assertion below is about what the *user*
    // asked for, so the baseline starts empty.
    player.played.clear();
    player.paused.clear();
    player.seeks.clear();
  }

  /// Tears the preview down and lets its player release, so the position
  /// poll `play()` starts cannot outlive the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('the clip on disk is what gets opened, and it starts paused so '
      'nothing plays behind the user\'s back', (tester) async {
    await pumpPreview(tester);

    expect(player.created, hasLength(1));
    expect(player.created.single.uri, contains('/tmp/clip.mp4'));
    expect(
      player.played,
      isEmpty,
      reason: 'a review step that autoplays talks over whoever is nearby',
    );
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('tapping the frame plays, and tapping it again pauses', (
    tester,
  ) async {
    await pumpPreview(tester);

    await tester.tap(find.byType(CameraVideoPreview), warnIfMissed: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(player.played, hasLength(1));
    expect(
      find.byIcon(Icons.play_circle_fill),
      findsNothing,
      reason: 'the play badge has to get out of the way of the picture',
    );

    await tester.tap(find.byType(CameraVideoPreview), warnIfMissed: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(player.paused, hasLength(1));
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
    'a clip that ran to the end restarts from the first frame instead of '
    'reporting playback nobody can see',
    (tester) async {
      await pumpPreview(tester);

      await tester.tap(find.byType(CameraVideoPreview), warnIfMissed: false);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      player.complete(1);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      player.seeks.clear();

      await tester.tap(find.byType(CameraVideoPreview), warnIfMissed: false);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(
        player.seeks,
        contains(Duration.zero),
        reason: 'the playhead is sitting on the last frame',
      );
      expect(player.played, hasLength(2));

      await unmount(tester);
    },
  );

  testWidgets(
    'a clip the platform cannot open falls back to a placeholder, so the '
    'capture can still be sent or thrown away',
    (tester) async {
      player.failCreate = true;

      await pumpPreview(tester);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'handed a different take, it opens that one instead of playing the clip '
    'that was thrown away',
    (tester) async {
      await pumpPreview(tester);
      expect(player.created.single.uri, contains('/tmp/clip.mp4'));

      await pumpPreview(tester, path: '/tmp/second-take.mp4');
      // The old player's teardown is a chain of real futures inside
      // `video_player`; the fake clock alone never gets to the end of it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(player.created, hasLength(2));
      expect(player.created.last.uri, contains('/tmp/second-take.mp4'));
      expect(
        player.disposed,
        contains(1),
        reason: 'the first player has to go, not linger behind the new one',
      );

      await unmount(tester);
    },
  );

  testWidgets(
    'a take superseded while it was still opening releases its player '
    'instead of leaving a decoder session behind',
    (tester) async {
      // Nothing resolves until the gate opens, so all three opens are in
      // flight at once — the shape a user retaking twice in a row produces.
      final gate = Completer<void>();
      player.beforeCreate = gate.future;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CameraVideoPreview(file: XFile('/tmp/a.mp4'))),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CameraVideoPreview(file: XFile('/tmp/b.mp4'))),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CameraVideoPreview(file: XFile('/tmp/c.mp4'))),
        ),
      );
      await tester.pump();

      gate.complete();
      // `VideoPlayerController`'s teardown is a chain of real futures; the
      // fake clock alone never reaches the end of it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(player.created, hasLength(3));
      expect(player.created.last.uri, contains('/tmp/c.mp4'));
      expect(
        player.disposed..sort(),
        <int>[1, 2],
        reason:
            'every superseded take has to release its own player, and '
            'only the take on screen survives',
      );

      await unmount(tester);
    },
  );

  testWidgets('the placeholder honours the capture screen\'s foreground '
      'colour instead of hardcoding white', (tester) async {
    const brand = Color(0xFFAA00AA);
    player.failCreate = true;

    await pumpPreview(
      tester,
      theme: const ChatTheme(cameraCaptureForegroundColor: brand),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.videocam_off));
    expect(
      icon.color!.toARGB32() & 0x00FFFFFF,
      brand.toARGB32() & 0x00FFFFFF,
      reason: 'only the alpha is the widget\'s own; the hue is the theme\'s',
    );
  });
}
