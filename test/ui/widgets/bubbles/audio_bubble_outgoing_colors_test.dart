import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

const _waveform = [10, 40, 80, 40, 10, 60, 90, 30];

const _sharedActive = Color(0xFF34C759);
const _sharedInactive = Color(0xFFD2D2D2);
const _sharedIcon = Color(0xFF1D1D1B);
const _sharedDuration = TextStyle(fontSize: 13, color: Color(0xFF767675));
const _sharedSpeedText = TextStyle(fontSize: 12, color: Color(0xFF101010));

const _outActive = Color(0xFF233941);
const _outInactive = Color(0xFF6F6F6E);
const _outIcon = Color(0xFFFAFAFA);
const _outPlayButton = Color(0xFF3A3A39);
const _outDuration = TextStyle(fontSize: 13, color: Color(0xFF3A3A39));
const _outSeekActive = Color(0xFF112233);
const _outSeekInactive = Color(0xFF445566);

const _outgoingText = Color(0xFF1D1D1B);

const _sharedTheme = ChatTheme(
  bubble: ChatBubbleTheme(outgoingTextStyle: TextStyle(color: _outgoingText)),
  waveformActiveColor: _sharedActive,
  waveformInactiveColor: _sharedInactive,
  audioSeekBarActiveColor: _sharedActive,
  audioSeekBarColor: _sharedInactive,
  audioPlayIconColor: _sharedIcon,
  audioDurationTextStyle: _sharedDuration,
  audioSpeedTextStyle: _sharedSpeedText,
);

final _splitTheme = _sharedTheme.copyWith(
  outgoingWaveformActiveColor: _outActive,
  outgoingWaveformInactiveColor: _outInactive,
  outgoingAudioSeekBarActiveColor: _outSeekActive,
  outgoingAudioSeekBarColor: _outSeekInactive,
  outgoingAudioPlayIconColor: _outIcon,
  outgoingAudioPlayButtonColor: _outPlayButton,
  outgoingAudioDurationTextStyle: _outDuration,
);

Future<void> _pump(
  WidgetTester tester, {
  required ChatTheme theme,
  required bool isOutgoing,
  bool withWaveform = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 375,
          child: AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            isOutgoing: isOutgoing,
            theme: theme,
            waveform: withWaveform ? _waveform : null,
            duration: const Duration(seconds: 12),
            showSenderPortrait: false,
          ),
        ),
      ),
    ),
  );
}

WaveformDisplay _waveformOf(WidgetTester tester) =>
    tester.widget<WaveformDisplay>(find.byType(WaveformDisplay));

Color? _playIconColor(WidgetTester tester) =>
    tester.widget<Icon>(find.byIcon(Icons.play_arrow)).color;

Color? _playButtonFill(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .ancestor(
          of: find.byIcon(Icons.play_arrow),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

TextStyle _durationStyle(WidgetTester tester) =>
    tester.widget<AudioTimeLabel>(find.byType(AudioTimeLabel)).style;

SliderThemeData _seekTheme(WidgetTester tester) => tester
    .widget<SliderTheme>(
      find.ancestor(
        of: find.byType(Slider),
        matching: find.byType(SliderTheme),
      ),
    )
    .data;

void main() {
  group('outgoing audio slots', () {
    testWidgets('paint the outgoing waveform, glyph, fill and time', (
      tester,
    ) async {
      await _pump(tester, theme: _splitTheme, isOutgoing: true);

      final waveform = _waveformOf(tester);
      expect(waveform.activeColor, _outActive);
      expect(waveform.inactiveColor, _outInactive);
      expect(_playIconColor(tester), _outIcon);
      expect(_playButtonFill(tester), _outPlayButton);
      expect(_durationStyle(tester), _outDuration);
    });

    testWidgets('paint the outgoing seek bar when there is no waveform', (
      tester,
    ) async {
      await _pump(
        tester,
        theme: _splitTheme,
        isOutgoing: true,
        withWaveform: false,
      );

      final seek = _seekTheme(tester);
      expect(seek.activeTrackColor, _outSeekActive);
      expect(seek.inactiveTrackColor, _outSeekInactive);
    });

    testWidgets('leave an incoming voice note on the shared slots', (
      tester,
    ) async {
      await _pump(tester, theme: _splitTheme, isOutgoing: false);

      final waveform = _waveformOf(tester);
      expect(waveform.activeColor, _sharedActive);
      expect(waveform.inactiveColor, _sharedInactive);
      expect(_playIconColor(tester), _sharedIcon);
      expect(_durationStyle(tester), _sharedDuration);
    });

    testWidgets('unset, an outgoing note keeps what it painted before', (
      tester,
    ) async {
      await _pump(tester, theme: _sharedTheme, isOutgoing: true);

      final waveform = _waveformOf(tester);
      expect(waveform.activeColor, _sharedActive);
      expect(waveform.inactiveColor, _sharedInactive);
      expect(_playIconColor(tester), _sharedIcon);
      expect(_playButtonFill(tester), _outgoingText.withValues(alpha: 0.3));
      expect(_durationStyle(tester), _sharedDuration);
    });

    testWidgets('unset with no shared slots either, the defaults derive from '
        'the outgoing text colour', (tester) async {
      await _pump(
        tester,
        theme: const ChatTheme(
          bubble: ChatBubbleTheme(
            outgoingTextStyle: TextStyle(color: _outgoingText),
          ),
        ),
        isOutgoing: true,
      );

      final waveform = _waveformOf(tester);
      expect(waveform.activeColor, _outgoingText);
      expect(waveform.inactiveColor, _outgoingText.withValues(alpha: 0.4));
      expect(_playIconColor(tester), Colors.white);
      expect(
        _durationStyle(tester).color,
        _outgoingText.withValues(alpha: 0.7),
      );
    });
  });
}
