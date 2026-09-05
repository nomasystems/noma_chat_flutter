import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../../_internal/cache/cache_manager.dart' show MetricCallback;
import '../adapter/chat_ui_adapter.dart' show AttachmentShrinker;
import '../models/attachment_policy.dart';
import '../models/attachment_rejection.dart';
import '../utils/platform_support.dart';
import 'attachment_shrinker.dart';
import 'image_metadata_scrubber.dart';

/// Re-exported so the shrinking engine every picker below defaults to is
/// reachable from `package:noma_chat/noma_chat.dart`, next to the pickers
/// that use it.
export 'attachment_shrinker.dart';

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
///
/// Picked images are rebuilt from their pixels on every platform, so GPS
/// coordinates and capture timestamps never travel to the room members who
/// download the original file.
///
/// Two passes, because neither covers both platforms:
///
/// - `requestFullMetadata: false` on every still-image pick. On iOS this
///   skips fetching the source `PHAsset`, so the JPEG comes back re-encoded
///   without the original EXIF block. It does nothing on Android, where
///   `image_picker_android`'s resize pass (triggered by `imageQuality < 100`,
///   which every picker here sets) copies EXIF from the source file
///   unconditionally and offers no flag to suppress it.
/// - [ImageMetadataScrubber] over the picked bytes, which closes the Android
///   gap by decoding the image and encoding a fresh one, so that nothing but
///   pixel data can come out the other side.
///
/// A file the scrubber cannot decode, and a format it cannot write back, are
/// sent as they came, metadata included — wire [MetricCallback] through the
/// `onMetric` parameter of any of these methods (`NomaChatView` passes
/// `ChatUiAdapter.metricCallback` for you) to tell those outcomes apart from
/// a clean one. See `TELEMETRY.md`.
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
    MetricCallback? onMetric,
    AttachmentShrinker shrinker = const DefaultAttachmentShrinker(),
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
        requestFullMetadata: false,
      );
      return await _xfileToValidatedResult(
        file,
        policy,
        logger,
        onRejected,
        onMetric,
        shrinker,
      );
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
    MetricCallback? onMetric,
    AttachmentShrinker shrinker = const DefaultAttachmentShrinker(),
  }) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ip.ImageSource.gallery,
        imageQuality: imageQuality,
        requestFullMetadata: false,
      );
      return await _xfileToValidatedResult(
        file,
        policy,
        logger,
        onRejected,
        onMetric,
        shrinker,
      );
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
    MetricCallback? onMetric,
    AttachmentShrinker shrinker = const DefaultAttachmentShrinker(),
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
        onMetric,
        shrinker,
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
    MetricCallback? onMetric,
    AttachmentShrinker shrinker = const DefaultAttachmentShrinker(),
  }) async {
    try {
      final files = await _imagePicker.pickMultipleMedia(
        imageQuality: imageQuality,
        requestFullMetadata: false,
      );
      final results = <AttachmentPickResult>[];
      for (final f in files) {
        final r = await _xfileToValidatedResult(
          f,
          policy,
          logger,
          onRejected,
          onMetric,
          shrinker,
        );
        if (r != null) results.add(r);
      }
      return results;
    } on Object catch (e) {
      logger?.call('warn', 'pickMultipleMedia failed: $e');
      onRejected?.call(AttachmentRejection.unreadable());
      return const [];
    }
  }

  /// Opens a generic file picker. Default-allow: with [allowedExtensions]
  /// left empty (the default), the system picker offers every file type —
  /// [policy]'s [AttachmentPolicy.deniedExtensions] is what keeps an
  /// OS-executable dropper out, not an allow-list a host has to maintain.
  /// When [allowedExtensions] is non-empty (e.g. `['pdf', 'docx']`), it
  /// restricts the picker to those types at the system level instead —
  /// useful for a narrow "attach a document" flow, but opt-in, since
  /// `file_picker`'s `FileType.custom` + extension list has platform quirks
  /// of its own (e.g. failing outright on iOS for some extension/UTI
  /// mappings). Either way [policy] is evaluated post-pick to catch mime-
  /// type, size and dangerous-extension violations. Returns null on
  /// cancellation or rejection.
  ///
  /// The deny-list and the mime whitelist are weighed on the file the user
  /// picked, while the size cap is weighed on the payload that will actually
  /// be uploaded: an [AttachmentShrinker] re-encodes and renames, and neither
  /// a rename nor a re-labelled mime type may walk a rejected file past the
  /// check.
  static Future<AttachmentPickResult?> pickFile({
    List<String> allowedExtensions = const [],
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
    MetricCallback? onMetric,
    AttachmentShrinker shrinker = const DefaultAttachmentShrinker(),
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
      final original = AttachmentPickResult(
        bytes: await ImageMetadataScrubber.scrub(bytes, onMetric: onMetric),
        mimeType:
            _mimeFromExtension(file.extension) ?? 'application/octet-stream',
        fileName: file.name,
      );
      final pick = await shrinkToPolicy(
        original,
        policy: policy,
        shrinker: shrinker,
      );
      final violation = violationFor(policy, original: original, payload: pick);
      if (violation != null) {
        logger?.call('warn', 'pickFile rejected: $violation');
        onRejected?.call(
          AttachmentRejection.fromPolicyViolation(
            violation,
            fileName: original.fileName,
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

  /// Runs [shrinker] over [pick] and returns the payload that will
  /// actually be uploaded: the re-encoded one when the engine produced it,
  /// [pick] itself when it declined or when [AttachmentPolicy.shrinkEnabled]
  /// is `false` — in which case [shrinker] is never even called, so a host
  /// that opts out gets exactly the bytes it picked, untouched.
  ///
  /// [policy] is the single source of the downscale ladder: a [shrinker]
  /// that implements [PolicyConfigurableShrinker] is re-configured with
  /// [AttachmentPolicy.shrinkSteps] before it runs, so
  /// `copyWith(shrinkSteps: [...])` changes what actually happens here. A
  /// shrinker that does not implement it keeps whatever cascade its own
  /// encoder defines.
  ///
  /// Callers validate the result of this step, never [pick]: measuring the
  /// size cap on bytes the shrinker is about to replace rejects photos that
  /// would have fit once reduced.
  @internal
  static Future<AttachmentPickResult> shrinkToPolicy(
    AttachmentPickResult pick, {
    required AttachmentPolicy policy,
    required AttachmentShrinker shrinker,
  }) async {
    if (!policy.shrinkEnabled) return pick;
    final engine = shrinker is PolicyConfigurableShrinker
        ? (shrinker as PolicyConfigurableShrinker).withShrinkSteps(
            policy.shrinkSteps,
          )
        : shrinker;
    final shrunk = await engine.fit(
      pick.bytes,
      mimeType: pick.mimeType,
      maxBytes: policy.maxBytesFor(pick.mimeType),
      fileName: pick.fileName ?? '',
    );
    if (shrunk == null) return pick;
    return AttachmentPickResult(
      bytes: shrunk.bytes,
      mimeType: shrunk.mimeType,
      fileName: shrunk.fileName,
    );
  }

  static Future<AttachmentPickResult?> _xfileToValidatedResult(
    ip.XFile? file,
    AttachmentPolicy policy,
    void Function(String level, String message)? logger,
    void Function(AttachmentRejection rejection)? onRejected,
    MetricCallback? onMetric,
    AttachmentShrinker shrinker, {
    String fallbackMime = 'application/octet-stream',
  }) async {
    if (file == null) return null;
    final bytes = await ImageMetadataScrubber.scrub(
      await file.readAsBytes(),
      onMetric: onMetric,
    );
    final original = AttachmentPickResult(
      bytes: bytes,
      mimeType:
          file.mimeType ??
          _mimeFromExtension(_extensionOf(file.name)) ??
          fallbackMime,
      fileName: file.name,
    );
    final pick = await shrinkToPolicy(
      original,
      policy: policy,
      shrinker: shrinker,
    );
    final violation = violationFor(policy, original: original, payload: pick);
    if (violation != null) {
      logger?.call('warn', 'pick rejected: $violation');
      onRejected?.call(
        AttachmentRejection.fromPolicyViolation(
          violation,
          fileName: original.fileName,
          sizeBytes: pick.size,
        ),
      );
      return null;
    }
    return pick;
  }

  /// Weighs [policy] the way an upload path has to: what the file *is* comes
  /// from [original], the pick as the system handed it over, and how much of
  /// it travels comes from [payload], whatever [shrinkToPolicy] left behind.
  ///
  /// Splitting the judgement in two closes a hole an [AttachmentShrinker]
  /// would otherwise open. A shrinker re-encodes and renames — that is its
  /// job — so judging the mime type or the extension on its output lets a
  /// `report.pdf` relabelled `image/jpeg` through a policy that accepts
  /// images only. Judging the size on the input is the mirror mistake: a
  /// photo that fits once reduced would be refused for the bytes the picker
  /// happened to hand over.
  ///
  /// The size cap is the one that applies to the original mime type, for the
  /// same reason: a re-labelled payload must not be able to claim a roomier
  /// bucket than the file the policy actually approved.
  @internal
  static AttachmentPolicyViolation? violationFor(
    AttachmentPolicy policy, {
    required AttachmentPickResult original,
    required AttachmentPickResult payload,
  }) {
    final identity = policy.validate(
      mimeType: original.mimeType,
      sizeBytes: 0,
      fileName: original.fileName,
    );
    if (identity != null) return identity;
    final cap = policy.maxBytesFor(original.mimeType);
    if (payload.size > cap) {
      return AttachmentPolicyViolation.tooLarge(
        mimeType: original.mimeType,
        actualBytes: payload.size,
        maxBytes: cap,
      );
    }
    return null;
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
