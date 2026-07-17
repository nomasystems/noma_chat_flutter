import 'package:flutter/foundation.dart';

/// Capability gates for features whose underlying plugins do not cover every
/// target platform. Derived from [kIsWeb] + [defaultTargetPlatform] (never
/// `dart:io`) so it resolves correctly on every platform the SDK builds for,
/// web included. The UI uses these to hide options the platform cannot honour
/// instead of surfacing a control that silently fails.
class PlatformSupport {
  PlatformSupport._();

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// `image_picker` implements camera capture on mobile (and on web via
  /// `<input capture>`). Its desktop federated plugins delegate gallery picks
  /// to a file dialog and throw `StateError` on `ImageSource.camera`, so
  /// camera capture is unavailable on macOS / Windows / Linux.
  static bool get supportsCameraCapture => _isMobile || kIsWeb;

  /// Crop is offered on mobile only. There is no native cropper for
  /// macOS / Windows / Linux, and the SDK's crop path stages the image through
  /// a `dart:io` temp file, which is unavailable on web — so on every
  /// non-mobile target the crop step is skipped and the picked image is used
  /// as-is. (`image_cropper`'s web delegate could be wired later for web crop.)
  static bool get supportsImageCrop => _isMobile;

  /// `open_filex` ships android / ios only. On desktop the SDK opens the
  /// downloaded file through `url_launcher` (a `file://` URI handed to the OS
  /// default handler) instead.
  static bool get opensFilesNatively => _isMobile;

  /// `record` ships a federated implementation for every target the SDK
  /// builds for (android / ios / macos / windows / linux via native
  /// platform channels, web via `record_web`'s `MediaRecorder` wrapper).
  /// Voice recording in this SDK release, however, is gated off on web
  /// regardless of `record`'s own support: [VoiceRecordingController]
  /// stages the finished recording through a `dart:io` temp file before
  /// reading it back as bytes, and that staging path has no web
  /// implementation yet. `startRecording` consults this getter and returns
  /// `StartRecordingResult.unsupported` on web instead of attempting (and
  /// failing) a permission check.
  static bool get supportsVoiceRecording => !kIsWeb;

  /// `file_picker` and `shared_preferences` both ship first-party
  /// implementations for every target the SDK builds for (android / ios /
  /// macos / windows / linux / web), so file picking and local key-value
  /// storage are supported everywhere. Exposed as explicit gates (rather
  /// than leaving callers to assume support) so a future plugin swap that
  /// narrows platform coverage only requires a change here.
  static bool get supportsFilePicker => true;

  static bool get supportsLocalStorage => true;
}
