import 'package:flutter/foundation.dart';

/// Declarative attachment-validation policy.
///
/// Apps embedding the chat composer typically need to gate uploads by
/// mime type and size — large videos cost bandwidth, exotic mime types
/// confuse the backend, and so on. Hard-coding those checks inside the
/// composer is repetitive across consumers, so the SDK ships a policy
/// type that any picker or send path can consult.
///
/// A policy is *additive*: anything not explicitly rejected is allowed.
/// Both [AttachmentPickers] and [ChatUiAdapter.sendAttachment] honour
/// it. When validation fails the call returns (or filters) without
/// uploading; the consumer can surface the [AttachmentPolicyViolation]
/// in whatever shape its UI prefers.
@immutable
class AttachmentPolicy {
  const AttachmentPolicy({
    this.allowedMimeTypes,
    this.maxBytesByMimePrefix = const {},
    this.maxBytes = _defaultMaxBytes,
  });

  /// Set of accepted mime types. Wildcards are supported via the
  /// `prefix/*` syntax (e.g. `image/*` matches `image/jpeg`,
  /// `image/png`, etc.). `null` means accept anything that survives
  /// the size check.
  final Set<String>? allowedMimeTypes;

  /// Per-prefix size caps. The first prefix that [matches] a mime type
  /// wins; mime types without a matching prefix fall back to [maxBytes].
  /// Example: `{'image/': 16 << 20, 'video/': 100 << 20}` lets images
  /// be up to 16 MB and videos up to 100 MB.
  final Map<String, int> maxBytesByMimePrefix;

  /// Default upper bound applied when no prefix in
  /// [maxBytesByMimePrefix] matches.
  final int maxBytes;

  static const int _defaultMaxBytes = 25 * 1024 * 1024; // 25 MB

  /// "No mime whitelist" policy. The 25 MB default cap from [maxBytes]
  /// still applies — apps that truly want no size limit should clone
  /// with `copyWith(maxBytes: 1 << 50)` rather than rely on
  /// `unrestricted` alone. The name reflects "no mime restriction",
  /// not "no constraints at all".
  static const AttachmentPolicy unrestricted = AttachmentPolicy();

  /// Approximate WhatsApp 2024 limits. Use as a starting point; clone
  /// with [copyWith] if your numbers differ.
  static const AttachmentPolicy whatsappLike = AttachmentPolicy(
    maxBytesByMimePrefix: {
      'image/': 16 * 1024 * 1024,
      'video/': 100 * 1024 * 1024,
      'audio/': 16 * 1024 * 1024,
      'application/': 100 * 1024 * 1024,
    },
    maxBytes: 100 * 1024 * 1024,
  );

  /// `true` if [mimeType] is whitelisted (or no whitelist is set).
  bool allowsMimeType(String mimeType) {
    final whitelist = allowedMimeTypes;
    if (whitelist == null) return true;
    if (whitelist.contains(mimeType)) return true;
    for (final pattern in whitelist) {
      if (pattern.endsWith('/*')) {
        final prefix = pattern.substring(0, pattern.length - 1);
        if (mimeType.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  /// Resolves the size cap that applies to [mimeType].
  int maxBytesFor(String mimeType) {
    for (final entry in maxBytesByMimePrefix.entries) {
      if (mimeType.startsWith(entry.key)) return entry.value;
    }
    return maxBytes;
  }

  /// Returns `null` if the attachment satisfies the policy, otherwise
  /// an [AttachmentPolicyViolation] describing why it was rejected.
  AttachmentPolicyViolation? validate({
    required String mimeType,
    required int sizeBytes,
  }) {
    if (!allowsMimeType(mimeType)) {
      return AttachmentPolicyViolation.mimeNotAllowed(mimeType);
    }
    final cap = maxBytesFor(mimeType);
    if (sizeBytes > cap) {
      return AttachmentPolicyViolation.tooLarge(
        actualBytes: sizeBytes,
        maxBytes: cap,
        mimeType: mimeType,
      );
    }
    return null;
  }

  AttachmentPolicy copyWith({
    Set<String>? allowedMimeTypes,
    Map<String, int>? maxBytesByMimePrefix,
    int? maxBytes,
  }) {
    return AttachmentPolicy(
      allowedMimeTypes: allowedMimeTypes ?? this.allowedMimeTypes,
      maxBytesByMimePrefix: maxBytesByMimePrefix ?? this.maxBytesByMimePrefix,
      maxBytes: maxBytes ?? this.maxBytes,
    );
  }
}

/// Categorical reasons for an attachment policy rejection.
enum AttachmentPolicyViolationKind { mimeNotAllowed, tooLarge }

/// Concrete rejection emitted by [AttachmentPolicy.validate].
@immutable
class AttachmentPolicyViolation {
  const AttachmentPolicyViolation._({
    required this.kind,
    required this.mimeType,
    required this.actualBytes,
    required this.maxBytes,
  });

  factory AttachmentPolicyViolation.mimeNotAllowed(String mimeType) =>
      AttachmentPolicyViolation._(
        kind: AttachmentPolicyViolationKind.mimeNotAllowed,
        mimeType: mimeType,
        actualBytes: 0,
        maxBytes: 0,
      );

  factory AttachmentPolicyViolation.tooLarge({
    required String mimeType,
    required int actualBytes,
    required int maxBytes,
  }) => AttachmentPolicyViolation._(
    kind: AttachmentPolicyViolationKind.tooLarge,
    mimeType: mimeType,
    actualBytes: actualBytes,
    maxBytes: maxBytes,
  );

  final AttachmentPolicyViolationKind kind;
  final String mimeType;

  /// Observed size when [kind] is [AttachmentPolicyViolationKind.tooLarge],
  /// otherwise `0`.
  final int actualBytes;

  /// Cap that was exceeded when [kind] is
  /// [AttachmentPolicyViolationKind.tooLarge], otherwise `0`.
  final int maxBytes;

  @override
  String toString() => switch (kind) {
    AttachmentPolicyViolationKind.mimeNotAllowed =>
      'AttachmentPolicyViolation(mimeNotAllowed: $mimeType)',
    AttachmentPolicyViolationKind.tooLarge =>
      'AttachmentPolicyViolation(tooLarge: $actualBytes > $maxBytes for $mimeType)',
  };
}
