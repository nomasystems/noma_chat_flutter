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

  goldenBubbleTest(
    'TextBubble outgoing — light',
    'bubble_text_outgoing_light',
    TextBubble(
      text: 'Hello world! This is a sample outgoing message.',
      isOutgoing: true,
      timestamp: ts,
      theme: goldenLightTheme,
    ),
  );

  goldenBubbleTest(
    'TextBubble incoming — light',
    'bubble_text_incoming_light',
    TextBubble(
      text: 'Incoming reply with some longer text to wrap into two lines.',
      isOutgoing: false,
      timestamp: ts,
      theme: goldenLightTheme,
    ),
  );

  // ImageBubble is gated on CachedNetworkImage → flutter_cache_manager
  // → sqflite. sqflite_common requires `databaseFactory` (FFI) to be
  // wired before any DB op; method-channel stubs are insufficient
  // because the package short-circuits inside `databaseFactory`. Pulling
  // `sqflite_common_ffi` in just to render a placeholder isn't worth
  // it — see ISSUES.md ("Golden tests for ImageBubble"). VideoBubble
  // exercises the same image pipeline with a nullable thumbnail, so
  // visual coverage isn't lost.
  goldenBubbleTest(
    'ImageBubble outgoing — light (skipped)',
    'bubble_image_outgoing_light',
    const SizedBox.shrink(),
    skip: true,
  );

  goldenBubbleTest(
    'VideoBubble outgoing — light',
    'bubble_video_outgoing_light',
    VideoBubble(
      videoUrl: 'https://example.com/missing.mp4',
      caption: 'Highlights',
      timestamp: ts,
      isOutgoing: true,
      theme: goldenLightTheme,
    ),
    size: const Size(360, 320),
  );

  goldenBubbleTest(
    'AudioBubble outgoing — light',
    'bubble_audio_outgoing_light',
    AudioBubble(
      audioUrl: 'https://example.com/missing.m4a',
      timestamp: ts,
      isOutgoing: true,
      theme: goldenLightTheme,
      waveform: const [3, 8, 14, 20, 26, 22, 16, 10, 6, 4, 8, 16, 22, 18, 12],
    ),
    size: const Size(360, 120),
  );

  goldenBubbleTest(
    'FileBubble incoming — light',
    'bubble_file_incoming_light',
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

  goldenBubbleTest(
    'LocationBubble incoming — light',
    'bubble_location_incoming_light',
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

  // LinkPreviewBubble with `imageUrl: null`: skips the CachedNetworkImage
  // branch entirely so the OG card renders without needing sqflite. The
  // title/description/domain text layout is the regression target.
  goldenBubbleTest(
    'LinkPreviewBubble outgoing (no OG image) — light',
    'bubble_link_preview_outgoing_light',
    const LinkPreviewBubble(
      url: 'https://example.com/article',
      title: 'A meaningful headline',
      description: 'A short OpenGraph description used as preview text.',
      isOutgoing: true,
      theme: goldenLightTheme,
    ),
    size: const Size(360, 120),
  );

  goldenBubbleTest(
    'ForwardedBubble (text inside) — light',
    'bubble_forwarded_outgoing_light',
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
}
