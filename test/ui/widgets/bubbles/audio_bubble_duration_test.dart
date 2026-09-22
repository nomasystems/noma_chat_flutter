import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The composer downsamples every waveform to at most 200 buckets before
/// sending it, so every note longer than 20 s ships exactly this many. A
/// duration derived from the bucket count therefore announces the cap —
/// 200 × 100 ms — instead of the recording, which is the flat "00:20"
/// every long voice note used to claim.
final _cappedWaveform = List<int>.filled(200, 50);

/// A phone-width surface, and the two text scales the app runs at: its own
/// global boost over the system default, and the system's large setting
/// with the boost composed on top.
const _phoneWidth = 375.0;
const _boostedScale = 1.18;
const _largeSystemScale = 1.18 * 1.7;

void main() {
  Widget wrap(Widget child, {required double textScale}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SizedBox(width: _phoneWidth, child: child),
      ),
    ),
  );

  ChatMessage voiceNote({Map<String, dynamic>? metadata}) => ChatMessage(
    id: 'msg-voice',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1, 10, 30),
    messageType: MessageType.audio,
    attachmentUrl: 'https://example.com/audio.m4a',
    metadata: metadata,
  );

  group('AudioBubble announced duration', () {
    for (final scale in const [_boostedScale, _largeSystemScale]) {
      testWidgets('at rest it shows the recorded length, not the capped '
          'waveform estimate (text scale $scale)', (tester) async {
        await tester.pumpWidget(
          wrap(
            AudioBubble(
              audioUrl: 'https://example.com/audio.m4a',
              waveform: _cappedWaveform,
              duration: const Duration(minutes: 1, seconds: 5),
            ),
            textScale: scale,
          ),
        );

        expect(find.text('01:05'), findsOneWidget);
        expect(find.text('00:20'), findsNothing);
      });
    }

    testWidgets('without a recorded length it still falls back to the '
        'waveform estimate', (tester) async {
      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            waveform: _cappedWaveform,
          ),
          textScale: _boostedScale,
        ),
      );

      expect(find.text('00:20'), findsOneWidget);
    });

    testWidgets('a zero length counts as no length at all', (tester) async {
      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            waveform: _cappedWaveform,
            duration: Duration.zero,
          ),
          textScale: _boostedScale,
        ),
      );

      expect(find.text('00:20'), findsOneWidget);
    });

    testWidgets('the seek bar is scaled against the recorded length', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            duration: Duration(minutes: 1, seconds: 5),
          ),
          textScale: _boostedScale,
        ),
      );

      expect(tester.widget<Slider>(find.byType(Slider)).max, 65000);
    });
  });

  group('audioBubbleTimeLabel', () {
    test('at rest it reads the total', () {
      expect(
        audioBubbleTimeLabel(
          Duration.zero,
          const Duration(minutes: 1, seconds: 5),
        ),
        '01:05',
      );
    });

    test('while playing it reads the position', () {
      expect(
        audioBubbleTimeLabel(
          const Duration(seconds: 12),
          const Duration(minutes: 1, seconds: 5),
        ),
        '00:12',
      );
    });

    test('a position past the total is held at the total, the way the seek '
        'bar already is', () {
      expect(
        audioBubbleTimeLabel(
          const Duration(minutes: 1, seconds: 6),
          const Duration(minutes: 1, seconds: 5),
        ),
        '01:05',
      );
    });

    test('with no total known there is nothing to hold the position to', () {
      expect(
        audioBubbleTimeLabel(const Duration(seconds: 7), Duration.zero),
        '00:07',
      );
    });
  });

  group('bubble controls', () {
    for (final scale in const [_boostedScale, _largeSystemScale]) {
      testWidgets('play button and speed pill answer touches on at least '
          '44pt (text scale $scale)', (tester) async {
        await tester.pumpWidget(
          wrap(
            const AudioBubble(
              audioUrl: 'https://example.com/audio.m4a',
              messageId: 'm1',
              duration: Duration(minutes: 1, seconds: 5),
            ),
            textScale: scale,
          ),
        );

        final play = tester.getSize(
          find.byKey(ValueKey(audioPlaySemanticsId('m1'))),
        );
        expect(play.width, greaterThanOrEqualTo(44));
        expect(play.height, greaterThanOrEqualTo(44));

        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pumpAndSettle();

        final speed = tester.getSize(
          find.byKey(ValueKey(audioSpeedSemanticsId('m1'))),
        );
        expect(speed.width, greaterThanOrEqualTo(44));
        expect(speed.height, greaterThanOrEqualTo(44));
      });
    }
  });

  group('MessageBubble wiring', () {
    for (final scale in const [_boostedScale, _largeSystemScale]) {
      testWidgets('a voice note announces metadata["duration"], the same '
          'source the chat list row reads (text scale $scale)', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: voiceNote(
                metadata: {'duration': 65000, 'waveform': _cappedWaveform},
              ),
              isOutgoing: true,
            ),
            textScale: scale,
          ),
        );

        expect(find.text('01:05'), findsOneWidget);
        expect(find.text('00:20'), findsNothing);
        expect(formatVoiceDuration(65000), '1:05');
      });
    }

    testWidgets('a note sent before the metadata existed leaves the bubble '
        'without a recorded length', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: voiceNote(metadata: {'waveform': _cappedWaveform}),
            isOutgoing: true,
          ),
          textScale: _boostedScale,
        ),
      );

      expect(
        tester.widget<AudioBubble>(find.byType(AudioBubble)).duration,
        isNull,
      );
    });

    testWidgets('a duration written as a double is read back all the same', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: voiceNote(metadata: {'duration': 65000.0}),
            isOutgoing: true,
          ),
          textScale: _boostedScale,
        ),
      );

      expect(
        tester.widget<AudioBubble>(find.byType(AudioBubble)).duration,
        const Duration(minutes: 1, seconds: 5),
      );
    });
  });
}
