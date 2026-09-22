import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Width [text] lays out to, so the fitted-label tests can pick slots
/// relative to the real metrics of the font the test paints with instead of
/// hardcoding numbers that only hold for one font.
double _measure(String text, TextStyle style, double textScale) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(textScale),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('mid-playback the total stays in sight next to the position', () {
      expect(
        audioBubbleTimeLabel(
          const Duration(seconds: 9),
          const Duration(minutes: 1, seconds: 11),
          withTotal: true,
        ),
        '00:09 / 01:11',
      );
    });

    test('at rest the pair collapses to the total alone', () {
      expect(
        audioBubbleTimeLabel(
          Duration.zero,
          const Duration(minutes: 1, seconds: 11),
          withTotal: true,
        ),
        '01:11',
      );
    });

    test(
      'the last figure of a finished note is its exact total, not a pair',
      () {
        expect(
          audioBubbleTimeLabel(
            const Duration(minutes: 1, seconds: 12),
            const Duration(minutes: 1, seconds: 11),
            withTotal: true,
          ),
          '01:11',
        );
      },
    );

    test('with no total known there is no second half to print', () {
      expect(
        audioBubbleTimeLabel(
          const Duration(seconds: 7),
          Duration.zero,
          withTotal: true,
        ),
        '00:07',
      );
    });
  });

  group('audioBubbleFittedTimeLabel', () {
    const style = TextStyle(fontSize: 11);

    String fitted(double maxWidth, {bool isPlaying = true}) =>
        audioBubbleFittedTimeLabel(
          position: const Duration(seconds: 9),
          total: const Duration(minutes: 1, seconds: 11),
          isPlaying: isPlaying,
          style: style,
          textScaler: const TextScaler.linear(_boostedScale),
          maxWidth: maxWidth,
        );

    test('a bubble with room for it prints the spaced pair', () {
      expect(fitted(200), '00:09 / 01:11');
    });

    test('a bubble that is a few points short squeezes the spaces out '
        'rather than dropping a figure', () {
      final spaced = _measure('00:09 / 01:11', style, _boostedScale);
      final compact = _measure('00:09/01:11', style, _boostedScale);
      expect(compact, lessThan(spaced));

      expect(fitted(spaced - 1), '00:09/01:11');
      expect(fitted(compact), '00:09/01:11');
    });

    test('a bubble too narrow for either pair keeps the moving half while '
        'the note plays', () {
      expect(fitted(24), '00:09');
    });

    test('a bubble too narrow for either pair falls back to the total, not '
        'the position, once the note stops', () {
      expect(fitted(24, isPlaying: false), '01:11');
    });

    test('at rest the pair never comes up, however wide the bubble', () {
      expect(
        audioBubbleFittedTimeLabel(
          position: Duration.zero,
          total: const Duration(minutes: 1, seconds: 11),
          isPlaying: false,
          style: style,
          textScaler: const TextScaler.linear(_boostedScale),
          maxWidth: 1000,
        ),
        '01:11',
      );
    });

    test('a finished note reads its exact total, not a pair', () {
      expect(
        audioBubbleFittedTimeLabel(
          position: const Duration(minutes: 1, seconds: 12),
          total: const Duration(minutes: 1, seconds: 11),
          isPlaying: false,
          style: style,
          textScaler: const TextScaler.linear(_boostedScale),
          maxWidth: 1000,
        ),
        '01:11',
      );
    });

    test('an unbounded slot never has to drop anything', () {
      expect(fitted(double.infinity), '00:09 / 01:11');
    });
  });

  group('AudioTimeLabel in the slots a real bubble grants it', () {
    /// Widths a `MessageBubble` leaves the time label on a 375pt phone,
    /// measured by pumping one: the bubble caps itself at 75 % of the
    /// screen, an incoming note carries more horizontal padding than an
    /// outgoing one, and a seek bar is inset 12pt against the waveform's 4.
    const slots = <String, double>{
      'waveform, outgoing': 141.25,
      'waveform, incoming': 121.25,
      'seek bar, outgoing': 125.25,
      'seek bar, incoming': 105.25,
    };

    /// The label is 11pt in the SDK's own theme, but the font a widget test
    /// paints with is not the one a device uses, so a fixed size would
    /// measure the test font rather than the ladder. These two bracket it:
    /// one small enough that the pair fits every slot, one large enough
    /// that neither pair does.
    const roomyStyle = TextStyle(fontSize: 4);
    const crampedStyle = TextStyle(fontSize: 20);

    Widget pumpLabel({
      required double width,
      required TextStyle style,
      required bool isPlaying,
      TextDirection textDirection = TextDirection.ltr,
    }) => MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Center(
          child: SizedBox(
            width: width,
            child: AudioTimeLabel(
              position: const Duration(seconds: 9),
              total: const Duration(minutes: 1, seconds: 11),
              isPlaying: isPlaying,
              style: style,
            ),
          ),
        ),
      ),
    );

    slots.forEach((slot, width) {
      testWidgets('$slot prints the pair when it fits, and never overflows', (
        tester,
      ) async {
        await tester.pumpWidget(
          pumpLabel(width: width, style: roomyStyle, isPlaying: true),
        );

        expect(find.text('00:09 / 01:11'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$slot still shows the total when the note is paused and '
          'no pair fits', (tester) async {
        await tester.pumpWidget(
          pumpLabel(width: width, style: crampedStyle, isPlaying: false),
        );

        expect(find.text('01:11'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$slot keeps the position while playing and no pair fits', (
        tester,
      ) async {
        await tester.pumpWidget(
          pumpLabel(width: width, style: crampedStyle, isPlaying: true),
        );

        expect(find.text('00:09'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    for (final waveform in const [true, false]) {
      for (final outgoing in const [true, false]) {
        testWidgets('the slot a real bubble grants is the one these tests '
            'pump (waveform=$waveform, outgoing=$outgoing)', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: Size(_phoneWidth, 812)),
                child: Scaffold(
                  body: MessageBubble(
                    message: voiceNote(
                      metadata: {
                        'duration': 71000,
                        if (waveform) 'waveform': _cappedWaveform,
                      },
                    ),
                    isOutgoing: outgoing,
                  ),
                ),
              ),
            ),
          );

          final box = tester.renderObject<RenderBox>(
            find.descendant(
              of: find.byType(AudioTimeLabel),
              matching: find.byType(LayoutBuilder),
            ),
          );
          final slot =
              slots['${waveform ? 'waveform' : 'seek bar'}, '
                  '${outgoing ? 'outgoing' : 'incoming'}']!;
          expect(box.constraints.maxWidth, closeTo(slot, 0.01));
        });
      }
    }

    testWidgets('under an RTL host the pair keeps elapsed-then-total order', (
      tester,
    ) async {
      await tester.pumpWidget(
        pumpLabel(
          width: slots['waveform, outgoing']!,
          style: roomyStyle,
          isPlaying: true,
          textDirection: TextDirection.rtl,
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('00:09 / 01:11'),
      );
      double runLeft(int start, int end) => paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
          )
          .first
          .left;

      expect(runLeft(0, 5), lessThan(runLeft(8, 13)));
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
