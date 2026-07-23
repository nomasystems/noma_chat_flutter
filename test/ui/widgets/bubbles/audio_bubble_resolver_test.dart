import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

// Note: this harness has no real `audioplayers` platform channel, but
// unlike a typical "unregistered channel" plugin, `AudioPlayer.setSource`
// does not throw here (desktop/test-mode audioplayers accepts any source
// string without validating it) — so the "retry once via urlResolver
// after a load error" branch in `AudioBubble._ensureInitialized` cannot be
// driven end-to-end through a real failure in this suite. It is covered
// instead by `SignedAttachmentUrlResolver.refresh` (see
// attachment_url_resolver_test.dart), which is exactly what a retry calls
// under the hood, plus manual verification during implementation.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AudioBubble + urlResolver', () {
    testWidgets('resolves the URL via the resolver before attempting '
        'playback, keyed by attachmentId', (tester) async {
      final calls = <String>[];
      Future<String> resolver(AttachmentRef ref) async {
        calls.add(ref.attachmentId ?? ref.fallbackUrl);
        return 'https://signed.example/resolved';
      }

      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://stale.example/audio.m4a',
            attachmentRef: const AttachmentRef(
              roomId: 'r1',
              attachmentId: 'att-1',
              fallbackUrl: 'https://stale.example/audio.m4a',
            ),
            urlResolver: resolver,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(calls, ['att-1']);
    });

    testWidgets('plays fine with no resolver wired at all (default, no '
        'behaviour change)', (tester) async {
      await tester.pumpWidget(
        wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(find.byType(AudioBubble), findsOneWidget);
    });

    testWidgets('never calls the resolver when attachmentRef is null even '
        'if urlResolver is set', (tester) async {
      var resolverCalls = 0;
      await tester.pumpWidget(
        wrap(
          AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            urlResolver: (ref) async {
              resolverCalls++;
              return ref.fallbackUrl;
            },
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(resolverCalls, 0);
    });
  });
}
