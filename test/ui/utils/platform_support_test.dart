import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/platform_support.dart';

void main() {
  final originalPlatform = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  group('supportsCameraCapture', () {
    test('true on android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlatformSupport.supportsCameraCapture, isTrue);
    });

    test('true on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlatformSupport.supportsCameraCapture, isTrue);
    });

    test('false on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlatformSupport.supportsCameraCapture, isFalse);
    });

    test('false on windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlatformSupport.supportsCameraCapture, isFalse);
    });

    test('false on linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(PlatformSupport.supportsCameraCapture, isFalse);
    });
  });

  group('supportsImageCrop', () {
    test('true on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlatformSupport.supportsImageCrop, isTrue);
    });

    test('false on desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlatformSupport.supportsImageCrop, isFalse);
    });
  });

  group('opensFilesNatively', () {
    test('true on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlatformSupport.opensFilesNatively, isTrue);
    });

    test('false on desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlatformSupport.opensFilesNatively, isFalse);
    });
  });

  group('supportsVoiceRecording', () {
    test('true on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlatformSupport.supportsVoiceRecording, isTrue);
    });

    test('true on desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlatformSupport.supportsVoiceRecording, isTrue);
    });
  });

  group('supportsFilePicker and supportsLocalStorage', () {
    test('true on every platform', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(PlatformSupport.supportsFilePicker, isTrue);
        expect(PlatformSupport.supportsLocalStorage, isTrue);
      }
    });
  });
}
