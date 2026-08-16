import 'package:flutter/foundation.dart';

import 'attachment_policy.dart';

/// Categorical reason an [AttachmentPickers] call rejected a pick.
enum AttachmentRejectReason {
  /// The file exceeds the active [AttachmentPolicy]'s size cap.
  tooLarge,

  /// The file's mime type isn't in the active [AttachmentPolicy]'s
  /// whitelist, **or** its extension is on [AttachmentPolicy.deniedExtensions]
  /// (an OS-executable dropper by default) — the two are reported under the
  /// same reason since both mean "this file's type may not be sent here";
  /// see [AttachmentRejection.fromPolicyViolation].
  mimeNotAllowed,

  /// The picked file's bytes could not be read (plugin/platform error) —
  /// distinct from a policy violation: the file was never validated
  /// because it couldn't be opened at all.
  unreadable,
}

/// Surfaces why [AttachmentPickers] dropped a pick instead of returning it.
///
/// Before this type existed, a policy violation or a plugin read failure
/// was only ever a `logger?.call('warn', ...)` line — the picker returned
/// `null` (or filtered the item out of a multi-pick) with no way for the
/// UI to tell "the user cancelled" apart from "the file was rejected".
/// Passing `onRejected` to any `AttachmentPickers` method now surfaces
/// this instead, so the composer can show a toast/snackbar.
@immutable
class AttachmentRejection {
  const AttachmentRejection({
    this.fileName,
    this.sizeBytes,
    this.mimeType,
    required this.reason,
    required this.message,
  });

  /// Original file name, when the picker plugin exposed one.
  final String? fileName;

  /// Size in bytes, when known (unknown for [AttachmentRejectReason.unreadable]).
  final int? sizeBytes;

  /// Negotiated mime type, when known.
  final String? mimeType;

  final AttachmentRejectReason reason;

  /// Plain-English, ready-to-show summary (e.g. "File exceeds the 25 MB
  /// limit"). Consumers that localize their UI should prefer building
  /// their own string from [reason] + `ChatUiLocalizations.attachmentTooLarge`
  /// / `.attachmentTypeNotAllowed` / `.attachmentUnreadable` instead of
  /// showing this verbatim.
  final String message;

  /// Builds the rejection for an [AttachmentPolicyViolation].
  ///
  /// [AttachmentPolicyViolationKind.extensionDenied] reuses
  /// [AttachmentRejectReason.mimeNotAllowed] rather than a reason of its
  /// own: both describe "this file's type may not be sent here", and every
  /// [AttachmentRejectReason] switch in the SDK (and in host apps) is
  /// written as an exhaustive 3-case match, so this keeps a dangerous-
  /// extension rejection a drop-in replacement for a mime rejection instead
  /// of a breaking addition. [message] still names the extension so a host
  /// reading it directly (rather than switching on [reason]) can tell the
  /// two apart.
  factory AttachmentRejection.fromPolicyViolation(
    AttachmentPolicyViolation violation, {
    String? fileName,
    int? sizeBytes,
  }) => switch (violation.kind) {
    AttachmentPolicyViolationKind.tooLarge => AttachmentRejection(
      fileName: fileName,
      sizeBytes: sizeBytes ?? violation.actualBytes,
      mimeType: violation.mimeType,
      reason: AttachmentRejectReason.tooLarge,
      message:
          'File exceeds the '
          '${(violation.maxBytes / (1024 * 1024)).toStringAsFixed(1)} MB limit.',
    ),
    AttachmentPolicyViolationKind.mimeNotAllowed => AttachmentRejection(
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: violation.mimeType,
      reason: AttachmentRejectReason.mimeNotAllowed,
      message: 'File type "${violation.mimeType}" is not allowed.',
    ),
    AttachmentPolicyViolationKind.extensionDenied => AttachmentRejection(
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: violation.mimeType,
      reason: AttachmentRejectReason.mimeNotAllowed,
      message: 'File type ".${violation.extension}" cannot be sent.',
    ),
  };

  /// Builds the rejection for a plugin/platform read failure.
  factory AttachmentRejection.unreadable({String? fileName}) =>
      AttachmentRejection(
        fileName: fileName,
        reason: AttachmentRejectReason.unreadable,
        message: 'Could not read the selected file.',
      );

  @override
  String toString() =>
      'AttachmentRejection(${reason.name}: $message'
      '${fileName != null ? ', fileName: $fileName' : ''})';
}
