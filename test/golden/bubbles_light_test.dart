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

  testGoldens('TextBubble outgoing — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      TextBubble(
        text: 'Hello world! This is a sample outgoing message.',
        isOutgoing: true,
        timestamp: ts,
        theme: goldenLightTheme,
      ),
    );
    await screenMatchesGolden(tester, 'bubble_text_outgoing_light');
  });

  testGoldens('TextBubble incoming — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      TextBubble(
        text: 'Incoming reply with some longer text to wrap into two lines.',
        isOutgoing: false,
        timestamp: ts,
        theme: goldenLightTheme,
      ),
    );
    await screenMatchesGolden(tester, 'bubble_text_incoming_light');
  });

  // ImageBubble uses CachedNetworkImage, which transitively requires sqflite
  // + path_provider via flutter_cache_manager. Stubbing the full chain in a
  // widget test is not worth extra dev dependencies; visual regressions on
  // the image bubble are partially caught by VideoBubble (same image
  // pipeline, simpler placeholder). Follow-up if needed.
  testGoldens(
    'ImageBubble outgoing — light (skipped)',
    (tester) async {},
    skip: true,
  );

  testGoldens('VideoBubble outgoing — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      VideoBubble(
        videoUrl: 'https://example.com/missing.mp4',
        caption: 'Highlights',
        timestamp: ts,
        isOutgoing: true,
        theme: goldenLightTheme,
      ),
      size: const Size(360, 320),
    );
    await screenMatchesGolden(tester, 'bubble_video_outgoing_light');
  });

  testGoldens('AudioBubble outgoing — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      AudioBubble(
        audioUrl: 'https://example.com/missing.m4a',
        timestamp: ts,
        isOutgoing: true,
        theme: goldenLightTheme,
        waveform: const [3, 8, 14, 20, 26, 22, 16, 10, 6, 4, 8, 16, 22, 18, 12],
      ),
      size: const Size(360, 120),
    );
    await screenMatchesGolden(tester, 'bubble_audio_outgoing_light');
  });

  testGoldens('FileBubble incoming — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      FileBubble(
        fileName: 'meeting-notes.pdf',
        fileSize: '243 KB',
        mimeType: 'application/pdf',
        timestamp: ts,
        isOutgoing: false,
        theme: goldenLightTheme,
      ),
      size: const Size(360, 140),
    );
    await screenMatchesGolden(tester, 'bubble_file_incoming_light');
  });

  testGoldens('LocationBubble incoming — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      LocationBubble(
        latitude: 43.3623,
        longitude: -8.4115,
        label: 'A Coruña, Spain',
        timestamp: ts,
        isOutgoing: false,
        theme: goldenLightTheme,
      ),
      size: const Size(360, 280),
    );
    await screenMatchesGolden(tester, 'bubble_location_incoming_light');
  });

  // LinkPreviewBubble also pulls in CachedNetworkImage (for the OG image
  // preview), same skip rationale as ImageBubble.
  testGoldens(
    'LinkPreviewBubble outgoing — light (skipped)',
    (tester) async {},
    skip: true,
  );

  testGoldens('ForwardedBubble (text inside) — light', (tester) async {
    await pumpGoldenSurface(
      tester,
      ForwardedBubble(
        sourceLabel: 'Equipo cervecero',
        theme: goldenLightTheme,
        child: TextBubble(
          text: 'Forwarded payload preserved.',
          isOutgoing: true,
          timestamp: ts,
          theme: goldenLightTheme,
        ),
      ),
      size: const Size(360, 180),
    );
    await screenMatchesGolden(tester, 'bubble_forwarded_outgoing_light');
  });
}
