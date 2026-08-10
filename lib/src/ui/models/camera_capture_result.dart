import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';

export 'package:camera/camera.dart' show XFile;

/// What `CameraCapturePage` hands back: the shot the user just took plus
/// whether it is a clip, so callers pick a mime type without sniffing the
/// extension.
///
/// Unlike [AttachmentPickResult] this keeps the capture on disk as an
/// [XFile] instead of reading it into memory — a hold-to-record clip is
/// routinely tens of megabytes.
@immutable
class CameraCaptureResult {
  const CameraCaptureResult({required this.file, required this.isVideo});

  final XFile file;

  /// `true` for a hold-to-record clip, `false` for a still.
  final bool isVideo;

  /// Mime type to upload with. The native camera plugins leave
  /// [XFile.mimeType] null (only `camera_web` fills it), so each branch
  /// falls back to the container they actually write.
  String get mimeType =>
      file.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg');

  String get fileName => file.name;
}
