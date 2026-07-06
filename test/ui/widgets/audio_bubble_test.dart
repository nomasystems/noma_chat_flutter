import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 300, child: child)),
  );

  testWidgets('shows mic icon grey for incoming unlistened message', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          isOutgoing: false,
          isListened: false,
        ),
      ),
    );

    final micIcon = tester.widget<Icon>(find.byIcon(Icons.mic).first);
    expect(micIcon.color, Colors.grey.shade500);
  });

  testWidgets('shows mic icon blue for incoming listened message', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          isOutgoing: false,
          isListened: true,
        ),
      ),
    );

    final micIcon = tester.widget<Icon>(find.byIcon(Icons.mic).first);
    expect(micIcon.color, Colors.blue);
  });

  testWidgets('does not show mic icon for outgoing message', (tester) async {
    await tester.pumpWidget(
      wrap(
        const AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          isOutgoing: true,
        ),
      ),
    );

    // Mic icon should not appear (only play_arrow from play button)
    // The mic listened indicator is only for incoming
    final micIcons = tester.widgetList<Icon>(find.byIcon(Icons.mic));
    expect(micIcons, isEmpty);
  });

  testWidgets('shows WaveformDisplay when waveform data provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          waveform: [50, 80, 30, 90, 10, 60],
        ),
      ),
    );

    expect(find.byType(WaveformDisplay), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('shows Slider when no waveform data', (tester) async {
    await tester.pumpWidget(
      wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
    );

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(WaveformDisplay), findsNothing);
  });

  testWidgets(
    'speed pill is absent before first interaction (avatar slot design)',
    (tester) async {
      final coordinator = AudioPlaybackCoordinator();
      addTearDown(() => coordinator.dispose());

      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            coordinator: coordinator,
            messageId: 'msg1',
          ),
        ),
      );

      // Speed pill replaces the sender avatar only after the user has started
      // playback; it must not be present on first render.
      expect(find.text('1x'), findsNothing);
    },
  );

  testWidgets('speed pill is absent in idle state even without coordinator', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
    );

    expect(find.text('1x'), findsNothing);
  });

  testWidgets('shows timestamp when provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          timestamp: DateTime(2026, 4, 16, 14, 30),
        ),
      ),
    );

    expect(find.textContaining('14:30'), findsOneWidget);
  });

  testWidgets('shows upload progress overlay when uploadProgress is set', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0.0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      wrap(
        AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          isOutgoing: true,
          uploadProgress: progress,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // While uploading, the regular play arrow icon is hidden.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    // The bubble shows the upward arrow as the progress placeholder.
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    progress.value = 0.5;
    await tester.pump();
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, closeTo(0.5, 0.001));
  });

  testWidgets('falls back to regular play button when uploadProgress is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AudioBubble(
          audioUrl: 'https://example.com/audio.m4a',
          isOutgoing: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  group('playback speed persistence', () {
    testWidgets('starts the speed pill at initialPlaybackSpeed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            initialPlaybackSpeed: 1.5,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.text('1.5x'), findsOneWidget);
    });

    testWidgets('onPlaybackSpeedChanged fires with the next cycled speed', (
      tester,
    ) async {
      final reported = <double>[];
      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            onPlaybackSpeedChanged: reported.add,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.text('1x'));
      await tester.pump();

      expect(reported, [1.5]);
      expect(find.text('1.5x'), findsOneWidget);

      await tester.tap(find.text('1.5x'));
      await tester.pump();
      expect(reported, [1.5, 2.0]);

      await tester.tap(find.text('2x'));
      await tester.pump();
      expect(reported, [1.5, 2.0, 1.0]);
    });

    testWidgets('onPlaybackSpeedChanged is not required', (tester) async {
      await tester.pumpWidget(
        wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.tap(find.text('1x'));
      await tester.pump();

      expect(find.text('1.5x'), findsOneWidget);
    });
  });
}
