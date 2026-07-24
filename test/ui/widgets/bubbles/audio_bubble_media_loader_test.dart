import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

// Same test-harness caveat as audio_bubble_resolver_test.dart: there is no
// real `audioplayers` platform channel here, so `setSource` never throws
// regardless of what `Source` it receives — the "retry once on failure"
// branch cannot be driven end-to-end through a real player error in this
// suite. What IS covered here: mediaLoader.loadToTempFile is called
// (instead of urlResolver) with the right AttachmentRef, and mediaLoader
// takes priority when both are wired.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AudioBubble + mediaLoader', () {
    testWidgets('downloads via mediaLoader.loadToTempFile before attempting '
        'playback, keyed by attachmentId', (tester) async {
      final calls = <String>[];
      final loader = _FakeMediaLoader(
        onLoadToTempFile: (ref, suffix) async {
          calls.add('${ref.attachmentId}$suffix');
          return '/tmp/fake-audio$suffix';
        },
      );

      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://signed.example/audio.bin',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/audio.bin',
            ),
            mediaLoader: loader,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(calls, ['att-1.m4a']);
    });

    testWidgets('ignores urlResolver when mediaLoader is wired', (
      tester,
    ) async {
      var urlResolverCalls = 0;
      final loader = _FakeMediaLoader(
        onLoadToTempFile: (ref, suffix) async => '/tmp/fake-audio$suffix',
      );

      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://signed.example/audio.bin',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://signed.example/audio.bin',
            ),
            urlResolver: (ref) async {
              urlResolverCalls++;
              return ref.fallbackUrl;
            },
            mediaLoader: loader,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(urlResolverCalls, 0);
    });

    testWidgets('never calls mediaLoader when attachmentRef is null even if '
        'it is set', (tester) async {
      var calls = 0;
      final loader = _FakeMediaLoader(
        onLoadToTempFile: (ref, suffix) async {
          calls++;
          return '/tmp/fake-audio$suffix';
        },
      );

      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            mediaLoader: loader,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('plays fine with no mediaLoader wired at all (default, no '
        'behaviour change)', (tester) async {
      await tester.pumpWidget(
        wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(find.byType(AudioBubble), findsOneWidget);
    });
  });
}

class _FakeMediaLoader implements AttachmentMediaLoader {
  _FakeMediaLoader({required this.onLoadToTempFile});

  final Future<String> Function(AttachmentRef ref, String suffix)
  onLoadToTempFile;

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      onLoadToTempFile(ref, suffix);

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) => throw UnimplementedError();

  @override
  void clear() {}
}
