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
}
