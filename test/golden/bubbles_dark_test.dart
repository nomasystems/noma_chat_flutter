import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:noma_chat/noma_chat.dart';

import 'helpers/golden_helpers.dart';

void main() {
  setUpAll(() async {
    configureGoldenTests();
    await loadAppFonts();
  });

  final ts = DateTime(2026, 5, 12, 10, 30);
  final theme = goldenDarkTheme;

  testGoldens('TextBubble outgoing — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      TextBubble(
        text: 'Hello world! This is a sample outgoing message.',
        isOutgoing: true,
        timestamp: ts,
        theme: theme,
      ),
      darkBackground: true,
    );
    await screenMatchesGolden(tester, 'bubble_text_outgoing_dark');
  });

  testGoldens('TextBubble incoming — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      TextBubble(
        text: 'Incoming reply with some longer text to wrap into two lines.',
        isOutgoing: false,
        timestamp: ts,
        theme: theme,
      ),
      darkBackground: true,
    );
    await screenMatchesGolden(tester, 'bubble_text_incoming_dark');
  });

  // See note in bubbles_light_test.dart: skipped due to CachedNetworkImage
  // sqflite/path_provider chain in widget tests.
  testGoldens(
    'ImageBubble outgoing — dark (skipped)',
    (tester) async {},
    skip: true,
  );

  testGoldens('VideoBubble outgoing — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      VideoBubble(
        videoUrl: 'https://example.com/missing.mp4',
        caption: 'Highlights',
        timestamp: ts,
        isOutgoing: true,
        theme: theme,
      ),
      darkBackground: true,
      size: const Size(360, 320),
    );
    await screenMatchesGolden(tester, 'bubble_video_outgoing_dark');
  });

  testGoldens('AudioBubble outgoing — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      AudioBubble(
        audioUrl: 'https://example.com/missing.m4a',
        timestamp: ts,
        isOutgoing: true,
        theme: theme,
        waveform: const [3, 8, 14, 20, 26, 22, 16, 10, 6, 4, 8, 16, 22, 18, 12],
      ),
      darkBackground: true,
      size: const Size(360, 120),
    );
    await screenMatchesGolden(tester, 'bubble_audio_outgoing_dark');
  });

  testGoldens('FileBubble incoming — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      FileBubble(
        fileName: 'meeting-notes.pdf',
        fileSize: '243 KB',
        mimeType: 'application/pdf',
        timestamp: ts,
        isOutgoing: false,
        theme: theme,
      ),
      darkBackground: true,
      size: const Size(360, 140),
    );
    await screenMatchesGolden(tester, 'bubble_file_incoming_dark');
  });

  testGoldens('LocationBubble incoming — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      LocationBubble(
        latitude: 43.3623,
        longitude: -8.4115,
        label: 'A Coruña, Spain',
        timestamp: ts,
        isOutgoing: false,
        theme: theme,
      ),
      darkBackground: true,
      size: const Size(360, 280),
    );
    await screenMatchesGolden(tester, 'bubble_location_incoming_dark');
  });

  // See note in bubbles_light_test.dart: skipped due to CachedNetworkImage.
  testGoldens(
    'LinkPreviewBubble outgoing — dark (skipped)',
    (tester) async {},
    skip: true,
  );

  testGoldens('ForwardedBubble (text inside) — dark', (tester) async {
    await pumpGoldenSurface(
      tester,
      ForwardedBubble(
        sourceLabel: 'Equipo cervecero',
        theme: theme,
        child: TextBubble(
          text: 'Forwarded payload preserved.',
          isOutgoing: true,
          timestamp: ts,
          theme: theme,
        ),
      ),
      darkBackground: true,
      size: const Size(360, 180),
    );
    await screenMatchesGolden(tester, 'bubble_forwarded_outgoing_dark');
  });
}
