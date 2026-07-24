import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../models/attachment_policy.dart';
import '../models/attachment_rejection.dart';
import '../utils/platform_support.dart';

/// ChatResult of an attachment picker call.
///
/// Carries the raw bytes (in-memory; for very large files prefer the
/// stream-based attachment API directly), the negotiated MIME type and
/// the optional original file name. `size` mirrors `bytes.length` for
/// convenience.
@immutable
class AttachmentPickResult {
  const AttachmentPickResult({
    required this.bytes,
    required this.mimeType,
    this.fileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? fileName;

  int get size => bytes.length;
}

/// Convenience entry points for the most common attachment flows in
/// chat composers. Wraps `image_picker` and `file_picker` so consumers
/// don't have to (re)wire them.
///
/// Returns `null` when the user cancels the system picker. Throws
/// nothing — pickers swallow plugin errors and log them via [logger]
/// when supplied so the composer never crashes on a denied permission.
class AttachmentPickers {
  AttachmentPickers._();

  static final ip.ImagePicker _imagePicker = ip.ImagePicker();

  /// When [policy] rejects the pick, the result is dropped (returns
  /// null / filtered out) and a `warn` line is logged. Consumers that
  /// want to surface the violation to the user should inspect the
  /// pick themselves before calling these helpers, or validate
  /// post-hoc via [AttachmentPolicy.validate] on a separate path.
  static Future<AttachmentPickResult?> pickImageFromCamera({
    int imageQuality = 85,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
  }) async {
    if (!PlatformSupport.supportsCameraCapture) {
      logger?.call(
        'warn',
        'pickImageFromCamera unsupported on this platform; ignoring',
      );
      return null;
    }
    try {
      final file = await _imagePicker.pickImage(
        source: ip.ImageSource.camera,
        imageQuality: imageQuality,
      );
      return await _xfileToValidatedResult(file, policy, logger, onRejected);
    } on Object catch (e) {
      logger?.call('warn', 'pickImageFromCamera failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return null;
    }
  }

  static Future<AttachmentPickResult?> pickImageFromGallery({
    int imageQuality = 85,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
  }) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ip.ImageSource.gallery,
        imageQuality: imageQuality,
      );
      return await _xfileToValidatedResult(file, policy, logger, onRejected);
    } on Object catch (e) {
      logger?.call('warn', 'pickImageFromGallery failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return null;
    }
  }

  static Future<AttachmentPickResult?> pickVideoFromGallery({
    Duration? maxDuration,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
  }) async {
    try {
      final file = await _imagePicker.pickVideo(
        source: ip.ImageSource.gallery,
        maxDuration: maxDuration,
      );
      return await _xfileToValidatedResult(
        file,
        policy,
        logger,
        onRejected,
        fallbackMime: 'video/mp4',
      );
    } on Object catch (e) {
      logger?.call('warn', 'pickVideoFromGallery failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return null;
    }
  }

  /// Opens the system multi-pick photo/video chooser and returns every
  /// selected file that satisfies [policy]. A rejected pick (wrong mime,
  /// too large) is filtered out of the returned list and reported via
  /// [onRejected] — always a `warn` log line, and no longer a silent drop
  /// when [onRejected] is wired.
  ///
  /// Returns an empty list when the user cancels.
  static Future<List<AttachmentPickResult>> pickMultipleMedia({
    int imageQuality = 85,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
  }) async {
    try {
      final files = await _imagePicker.pickMultipleMedia(
        imageQuality: imageQuality,
      );
      final results = <AttachmentPickResult>[];
      for (final f in files) {
        final r = await _xfileToValidatedResult(f, policy, logger, onRejected);
        if (r != null) results.add(r);
      }
      return results;
    } on Object catch (e) {
      logger?.call('warn', 'pickMultipleMedia failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return const [];
    }
  }

  /// Opens a generic file picker. When [allowedExtensions] is non-empty
  /// (e.g. `['pdf', 'docx']`), restricts the picker to those types at
  /// the system level. The [policy] is then evaluated post-pick to
  /// catch mime-type and size violations not expressible as extension
  /// lists. Returns null on cancellation or rejection.
  static Future<AttachmentPickResult?> pickFile({
    List<String> allowedExtensions = const [],
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
  }) async {
    if (!PlatformSupport.supportsFilePicker) {
      logger?.call('warn', 'pickFile unsupported on this platform; ignoring');
      return null;
    }
    try {
      // file_picker 9+ exposes `pickFiles` as a static method on
      // `FilePicker` (previously through `FilePicker.platform`). The
      // current call surface is otherwise unchanged.
      final result = await fp.FilePicker.pickFiles(
        type: allowedExtensions.isEmpty ? fp.FileType.any : fp.FileType.custom,
        allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        onRejected?.call(AttachmentRejection.unreadable(fileName: file.name));
        return null;
      }
      final pick = AttachmentPickResult(
        bytes: bytes,
        mimeType:
            _mimeFromExtension(file.extension) ?? 'application/octet-stream',
        fileName: file.name,
      );
      final violation = policy.validate(
        mimeType: pick.mimeType,
        sizeBytes: pick.size,
      );
      if (violation != null) {
        logger?.call('warn', 'pickFile rejected: $violation');
        onRejected?.call(
          AttachmentRejection.fromPolicyViolation(
            violation,
            fileName: pick.fileName,
            sizeBytes: pick.size,
          ),
        );
        return null;
      }
      return pick;
    } on Object catch (e) {
      logger?.call('warn', 'pickFile failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return null;
    }
  }

  static Future<AttachmentPickResult?> _xfileToValidatedResult(
    ip.XFile? file,
    AttachmentPolicy policy,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected, {
    String fallbackMime = 'application/octet-stream',
  }) async {
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final pick = AttachmentPickResult(
      bytes: bytes,
      mimeType:
          file.mimeType ??
          _mimeFromExtension(_extensionOf(file.name)) ??
          fallbackMime,
      fileName: file.name,
    );
    final violation = policy.validate(
      mimeType: pick.mimeType,
      sizeBytes: pick.size,
    );
    if (violation != null) {
      logger?.call('warn', 'pick rejected: $violation');
      onRejected?.call(
        AttachmentRejection.fromPolicyViolation(
          violation,
          fileName: pick.fileName,
          sizeBytes: pick.size,
        ),
      );
      return null;
    }
    return pick;
  }

  static String? _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1) return null;
    return path.substring(dot + 1).toLowerCase();
  }

  /// Returns the mime type guessed from a file extension, or `null` when
  /// the extension isn't on the small dictionary baked into the SDK.
  /// Callers should `??`-chain to a sensible fallback (kind-specific
  /// `video/mp4`, generic `application/octet-stream`, etc.) so unknown
  /// extensions don't silently become opaque blobs.
  static String? _mimeFromExtension(String? ext) {
    if (ext == null || ext.isEmpty) return null;
    return switch (ext.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'zip' => 'application/zip',
      _ => null,
    };
  }
}
