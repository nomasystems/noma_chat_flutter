import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The `VideoThumbnailer` seam and its built-in implementations. The
/// platform decoder itself is not exercisable from a unit test (no method
/// channel), so what is pinned here is the contract around it: the seam
/// never throws, the opt-out returns nothing, and the spooled copy carries
/// the extension the native extractors sniff the container from.
void main() {
  final videoBytes = Uint8List.fromList(List<int>.filled(32, 3));

  group('videoFileExtensionFor', () {
    test('maps the containers a camera roll or in-app capture produces', () {
      expect(videoFileExtensionFor('video/mp4'), '.mp4');
      expect(videoFileExtensionFor('video/quicktime'), '.mov');
      expect(videoFileExtensionFor('video/webm'), '.webm');
      expect(videoFileExtensionFor('video/x-matroska'), '.mkv');
      expect(videoFileExtensionFor('video/3gpp'), '.3gp');
    });

    test('is case-insensitive and ignores parameters', () {
      expect(videoFileExtensionFor('VIDEO/QuickTime'), '.mov');
      expect(videoFileExtensionFor('video/mp4; codecs="avc1"'), '.mp4');
    });

    test('falls back to .mp4 for an unknown subtype', () {
      expect(videoFileExtensionFor('video/x-unknown-container'), '.mp4');
      expect(videoFileExtensionFor(''), '.mp4');
    });
  });

  group('NoVideoThumbnailer', () {
    test('produces nothing, so videos send exactly as they did before', () {
      expect(
        const NoVideoThumbnailer().generate(videoBytes, mimeType: 'video/mp4'),
        completion(isNull),
      );
    });
  });

  group('NativeVideoThumbnailer', () {
    // Plain `test()` keeps `defaultTargetPlatform` on the host (macOS /
    // linux), where `PlatformSupport.supportsVideoThumbnails` is false —
    // the same branch a desktop consumer takes.
    test('returns null off mobile instead of reaching for the plugin', () {
      expect(
        const NativeVideoThumbnailer().generate(
          videoBytes,
          mimeType: 'video/mp4',
        ),
        completion(isNull),
      );
    });

    test('never throws on bytes that are not a video', () {
      expect(
        const NativeVideoThumbnailer().generate(
          Uint8List.fromList(const [0, 1, 2]),
          mimeType: 'video/mp4',
        ),
        completion(isNull),
      );
    });
  });
}
