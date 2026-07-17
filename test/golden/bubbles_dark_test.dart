@Tags(['golden', 'slow'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import 'helpers/golden_helpers.dart';

void main() {
  setUpAll(() async {
    configureGoldenTests();
  });

  final ts = DateTime(2026, 5, 12, 10, 30);
  final theme = goldenDarkTheme;

  goldenBubbleTest(
    'TextBubble outgoing — dark',
    'bubble_text_outgoing_dark',
    TextBubble(
      text: 'Hello world! This is a sample outgoing message.',
      isOutgoing: true,
      timestamp: ts,
      theme: theme,
    ),
    darkBackground: true,
  );

  goldenBubbleTest(
    'TextBubble incoming — dark',
    'bubble_text_incoming_dark',
    TextBubble(
      text: 'Incoming reply with some longer text to wrap into two lines.',
      isOutgoing: false,
      timestamp: ts,
      theme: theme,
    ),
    darkBackground: true,
  );

  // See note in bubbles_light_test.dart: ImageBubble requires sqflite
  // (via flutter_cache_manager). Tracked as deferred dev-dep concern
  // in ISSUES.md.
  goldenBubbleTest(
    'ImageBubble outgoing — dark (skipped)',
    'bubble_image_outgoing_dark',
    const SizedBox.shrink(),
    skip: true,
  );

  goldenBubbleTest(
    'VideoBubble outgoing — dark',
    'bubble_video_outgoing_dark',
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

  goldenBubbleTest(
    'AudioBubble outgoing — dark',
    'bubble_audio_outgoing_dark',
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

  goldenBubbleTest(
    'FileBubble incoming — dark',
    'bubble_file_incoming_dark',
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

  goldenBubbleTest(
    'LocationBubble incoming — dark',
    'bubble_location_incoming_dark',
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

  // LinkPreviewBubble with `imageUrl: null` (no OG image branch) —
  // captures the text-only card layout without needing sqflite.
  goldenBubbleTest(
    'LinkPreviewBubble outgoing (no OG image) — dark',
    'bubble_link_preview_outgoing_dark',
    LinkPreviewBubble(
      url: 'https://example.com/article',
      title: 'A meaningful headline',
      description: 'A short OpenGraph description used as preview text.',
      isOutgoing: true,
      theme: theme,
    ),
    darkBackground: true,
    size: const Size(360, 120),
  );

  goldenBubbleTest(
    'ForwardedBubble (text inside) — dark',
    'bubble_forwarded_outgoing_dark',
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
}
