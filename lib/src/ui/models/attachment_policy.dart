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
    this.deniedExtensions = defaultDeniedExtensions,
  });

  /// Set of accepted mime types. Wildcards are supported via the
  /// `prefix/*` syntax (e.g. `image/*` matches `image/jpeg`,
  /// `image/png`, etc.). `null` means accept anything that survives
  /// the size and [deniedExtensions] checks.
  final Set<String>? allowedMimeTypes;

  /// Per-prefix size caps. The first prefix that [matches] a mime type
  /// wins; mime types without a matching prefix fall back to [maxBytes].
  /// Example: `{'image/': 16 << 20, 'video/': 100 << 20}` lets images
  /// be up to 16 MB and videos up to 100 MB.
  final Map<String, int> maxBytesByMimePrefix;

  /// Default upper bound applied when no prefix in
  /// [maxBytesByMimePrefix] matches.
  final int maxBytes;

  /// File extensions (lowercase, no leading dot) [validate] refuses
  /// regardless of [allowedMimeTypes] — checked first, so a host that opens
  /// up `allowedMimeTypes` (or leaves it `null`, the default) never
  /// re-opens the door to an OS-executable dropper by accident.
  ///
  /// Defaults to [defaultDeniedExtensions], which is *the* mechanism behind
  /// this policy's WhatsApp-like stance: default-allow every file type,
  /// except a short list of dangerous ones. That is deliberately the
  /// opposite of [allowedMimeTypes]'s empty-set-means-nothing default —
  /// an allow-list that started empty would reject every uncommon-but-safe
  /// extension (`.xyz`, `.log`, `.md5`, a proprietary export, …), which is
  /// the exact rejection this field exists to avoid.
  ///
  /// Extension checks apply to the extension embedded in the file name
  /// only — they say nothing about the negotiated mime type, so a host that
  /// wants to also block, say, every `application/x-*` mime should still
  /// use [allowedMimeTypes] for that. Clone with `copyWith(deniedExtensions:
  /// {...})` to use a different list, or `copyWith(deniedExtensions: {})`
  /// to disable the check entirely.
  final Set<String> deniedExtensions;

  static const int _defaultMaxBytes = 25 * 1024 * 1024; // 25 MB

  /// OS-executable droppers blocked by every [AttachmentPolicy] unless a
  /// host opts out via `copyWith(deniedExtensions: {...})`. Extensions are
  /// lowercase and dot-less, matched case-insensitively against the picked
  /// file name.
  ///
  /// Covers, in order: Windows native/installer executables (`exe`, `msi`),
  /// Windows batch/command scripts (`bat`, `cmd`), legacy DOS executables
  /// and screensavers (`com`, `scr`, `pif`), Windows Control Panel /
  /// Management Console droppers (`cpl`, `msc`), Android app/bytecode
  /// packages (`apk`, `dex`), POSIX shell scripts (`sh`), PowerShell
  /// scripts (`ps1`), Windows Script Host scripts (`vbs`, `vbe`, `jse`,
  /// `wsf`, `wsh`), a Windows Registry patch (`reg`), and a Java archive
  /// that can carry executable bytecode (`jar`).
  static const Set<String> defaultDeniedExtensions = {
    'exe',
    'msi',
    'bat',
    'cmd',
    'com',
    'scr',
    'pif',
    'cpl',
    'msc',
    'apk',
    'dex',
    'sh',
    'ps1',
    'vbs',
    'vbe',
    'jse',
    'wsf',
    'wsh',
    'reg',
    'jar',
  };

  /// "No mime whitelist" policy. The 25 MB default cap from [maxBytes] and
  /// the [defaultDeniedExtensions] deny-list still apply — apps that truly
  /// want no size limit should clone with `copyWith(maxBytes: 1 << 50)`
  /// rather than rely on `unrestricted` alone. The name reflects "no mime
  /// restriction", not "no constraints at all".
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

  /// `true` if [fileName]'s extension is on [deniedExtensions]. `false`
  /// when [fileName] is `null` or carries no extension — there is nothing
  /// to compare against the deny-list, and a policy is not the place to
  /// decide whether an extension-less file is suspicious.
  ///
  /// Only a trailing token that *looks* like an extension counts: up to
  /// eight ASCII letters/digits. A prose tail
  /// (`report.final version`, `notes.backup copy 2`) is not an extension and
  /// never reaches the deny-list. What the shape check cannot separate is a
  /// name whose last token happens to spell a denied extension without being
  /// one — `newsletter-acme.com`, `www.example.com`. Those are refused, and
  /// deliberately so: nothing in a file name tells a domain-looking tail
  /// apart from a DOS executable, and Windows runs `.com` through `PATHEXT`
  /// whatever the bytes are. A host that would rather take that trade the
  /// other way drops the entry: `copyWith(deniedExtensions: {
  /// ...AttachmentPolicy.defaultDeniedExtensions}..remove('com'))`.
  bool deniesFileName(String? fileName) {
    final extension = _extensionOf(fileName);
    return extension != null && deniedExtensions.contains(extension);
  }

  /// Up to 8 ASCII letters/digits — long enough for every real extension
  /// (`webp`, `sqlite3`, `tar.gz`'s `gz`), short enough that a sentence
  /// fragment after a dot is not mistaken for one.
  static final RegExp _extensionShape = RegExp(r'^[a-z0-9]{1,8}$');

  static String? _extensionOf(String? fileName) {
    if (fileName == null) return null;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) return null;
    final candidate = fileName.substring(dot + 1).toLowerCase();
    return _extensionShape.hasMatch(candidate) ? candidate : null;
  }

  /// Returns `null` if the attachment satisfies the policy, otherwise
  /// an [AttachmentPolicyViolation] describing why it was rejected.
  ///
  /// [fileName] is optional and only used for the [deniedExtensions] check
  /// — omit it (as the image/video pick paths do, since none of their
  /// extensions are ever dangerous) to validate mime/size alone.
  AttachmentPolicyViolation? validate({
    required String mimeType,
    required int sizeBytes,
    String? fileName,
  }) {
    if (deniesFileName(fileName)) {
      return AttachmentPolicyViolation.extensionDenied(
        extension: _extensionOf(fileName)!,
        mimeType: mimeType,
      );
    }
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
    Set<String>? deniedExtensions,
  }) {
    return AttachmentPolicy(
      allowedMimeTypes: allowedMimeTypes ?? this.allowedMimeTypes,
      maxBytesByMimePrefix: maxBytesByMimePrefix ?? this.maxBytesByMimePrefix,
      maxBytes: maxBytes ?? this.maxBytes,
      deniedExtensions: deniedExtensions ?? this.deniedExtensions,
    );
  }
}

/// Categorical reasons for an attachment policy rejection.
enum AttachmentPolicyViolationKind { mimeNotAllowed, tooLarge, extensionDenied }

/// Concrete rejection emitted by [AttachmentPolicy.validate].
@immutable
class AttachmentPolicyViolation {
  const AttachmentPolicyViolation._({
    required this.kind,
    required this.mimeType,
    required this.actualBytes,
    required this.maxBytes,
    this.extension,
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

  /// Built by [AttachmentPolicy.validate] when the file name's extension is
  /// on [AttachmentPolicy.deniedExtensions] — checked, and so reported,
  /// ahead of [mimeNotAllowed] and [tooLarge].
  factory AttachmentPolicyViolation.extensionDenied({
    required String extension,
    required String mimeType,
  }) => AttachmentPolicyViolation._(
    kind: AttachmentPolicyViolationKind.extensionDenied,
    mimeType: mimeType,
    extension: extension,
    actualBytes: 0,
    maxBytes: 0,
  );

  final AttachmentPolicyViolationKind kind;
  final String mimeType;

  /// Observed size when [kind] is [AttachmentPolicyViolationKind.tooLarge],
  /// otherwise `0`.
  final int actualBytes;

  /// Cap that was exceeded when [kind] is
  /// [AttachmentPolicyViolationKind.tooLarge], otherwise `0`.
  final int maxBytes;

  /// The denied extension (lowercase, no leading dot) when [kind] is
  /// [AttachmentPolicyViolationKind.extensionDenied], otherwise `null`.
  final String? extension;

  @override
  String toString() => switch (kind) {
    AttachmentPolicyViolationKind.mimeNotAllowed =>
      'AttachmentPolicyViolation(mimeNotAllowed: $mimeType)',
    AttachmentPolicyViolationKind.tooLarge =>
      'AttachmentPolicyViolation(tooLarge: $actualBytes > $maxBytes for $mimeType)',
    AttachmentPolicyViolationKind.extensionDenied =>
      'AttachmentPolicyViolation(extensionDenied: .$extension)',
  };
}
