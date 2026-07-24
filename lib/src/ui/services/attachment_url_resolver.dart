import '../../client/chat_client.dart';
import '../../observability/chat_logger.dart';

/// Resolves the URL a bubble should load bytes from for an attachment
/// message, given its stable id. Implementations typically re-mint a
/// short-lived signed URL on demand rather than trusting a persisted one
/// that may have expired — see [SignedAttachmentUrlResolver], the default
/// implementation the adapter wires into `NomaChatView`/`ChatView`.
typedef AttachmentUrlResolver = Future<String> Function(AttachmentRef ref);

/// Identifies the attachment a bubble needs a download URL for.
class AttachmentRef {
  const AttachmentRef({
    required this.roomId,
    this.attachmentId,
    required this.fallbackUrl,
  });

  /// Room the attachment belongs to — required by the signed-url endpoint's
  /// membership check.
  final String roomId;

  /// Stable attachment id (`ChatMessage.attachmentId`). `null` for legacy
  /// messages the backend stored before it echoed the field; resolvers
  /// fall back to parsing an id out of [fallbackUrl] via
  /// [attachmentIdFromUrl], or to [fallbackUrl] itself when that fails.
  final String? attachmentId;

  /// `ChatMessage.attachmentUrl` — the last URL the SDK knows about for
  /// this attachment. Used verbatim when [attachmentId] is unavailable.
  final String fallbackUrl;
}

/// Default [AttachmentUrlResolver]: caches a signed URL per
/// `(roomId, attachmentId)` alongside its expiry, and re-mints via
/// `ChatAttachmentsApi.signedUrl` when the cached entry is within
/// [safetyMargin] of expiring (or has none yet). Falls back to
/// [AttachmentRef.fallbackUrl] when [AttachmentRef.attachmentId] is `null`
/// — first trying to recover an id out of the URL via [attachmentIdFromUrl]
/// so legacy messages still benefit from re-minting once an id can be
/// derived.
class SignedAttachmentUrlResolver {
  SignedAttachmentUrlResolver({
    required ChatClient client,
    ChatLogger? logger,
    Duration safetyMargin = const Duration(seconds: 30),
  }) : _client = client,
       _logger = logger,
       _safetyMargin = safetyMargin;

  final ChatClient _client;
  final ChatLogger? _logger;
  final Duration _safetyMargin;

  final Map<String, _CachedSignedUrl> _cache = {};

  static String _cacheKey(String roomId, String attachmentId) =>
      '$roomId/$attachmentId';

  /// Resolves the URL to load for [ref], reusing a cached signed URL while
  /// it is still valid (outside [safetyMargin] of its expiry) and
  /// re-minting otherwise. Falls back to [AttachmentRef.fallbackUrl] when
  /// no attachment id is available (directly, or via [attachmentIdFromUrl])
  /// or when the re-mint call fails.
  Future<String> resolve(AttachmentRef ref) async {
    final attachmentId =
        ref.attachmentId ?? attachmentIdFromUrl(ref.fallbackUrl);
    if (attachmentId == null) return ref.fallbackUrl;

    final key = _cacheKey(ref.roomId, attachmentId);
    final cached = _cache[key];
    final now = DateTime.now();
    if (cached != null &&
        cached.expiresAt.subtract(_safetyMargin).isAfter(now)) {
      return cached.url;
    }
    return _mint(ref, attachmentId, key);
  }

  /// Forces a fresh signed URL regardless of what is cached. Bubbles call
  /// this once after a load error in case the cached URL looks fresh by
  /// its recorded expiry but actually stopped working (clock skew, early
  /// server-side invalidation, transient network blip).
  Future<String> refresh(AttachmentRef ref) async {
    final attachmentId =
        ref.attachmentId ?? attachmentIdFromUrl(ref.fallbackUrl);
    if (attachmentId == null) return ref.fallbackUrl;
    return _mint(ref, attachmentId, _cacheKey(ref.roomId, attachmentId));
  }

  Future<String> _mint(
    AttachmentRef ref,
    String attachmentId,
    String key,
  ) async {
    final result = await _client.attachments.signedUrl(
      attachmentId,
      roomId: ref.roomId,
    );
    if (result.isFailure) {
      _logger?.attach(
        ChatLogLevel.warn,
        'signedUrl re-mint failed, using fallbackUrl',
        fields: {'roomId': ref.roomId, 'attachmentId': attachmentId},
      );
      return ref.fallbackUrl;
    }
    final signed = result.dataOrThrow;
    _cache[key] = _CachedSignedUrl(
      url: signed.url,
      expiresAt: _expiryFrom(signed.raw),
    );
    _logger?.attach(
      ChatLogLevel.debug,
      're-minted signed url',
      fields: {'roomId': ref.roomId, 'attachmentId': attachmentId},
    );
    return signed.url;
  }

  /// Backend TTL default is 3600s (documented for `GET
  /// /attachments/{id}/signed-url`), but `raw` — the endpoint's JSON body —
  /// is honoured first in case a deployment starts echoing it back
  /// (`expiresAt` ISO-8601, or `expiresIn`/`ttl` seconds). Falls back to a
  /// conservative 5 minutes when neither is present: short enough to never
  /// serve a URL the real 3600s TTL has already invalidated, long enough
  /// that a chat screen scrolling through recent media doesn't re-mint on
  /// every frame.
  DateTime _expiryFrom(Map<String, dynamic> raw) {
    final expiresAt = raw['expiresAt'];
    if (expiresAt is String) {
      final parsed = DateTime.tryParse(expiresAt);
      if (parsed != null) return parsed;
    }
    final ttlSeconds = raw['expiresIn'] ?? raw['ttl'];
    if (ttlSeconds is num) {
      return DateTime.now().add(Duration(seconds: ttlSeconds.toInt()));
    }
    return DateTime.now().add(const Duration(minutes: 5));
  }
}

class _CachedSignedUrl {
  const _CachedSignedUrl({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;
}

/// Extracts an attachment id from a raw attachment slot URL. Recognizes both
/// the signed-url shape `.../attachments/{id}` (or `.../attachments/{id}/...`)
/// and the raw upload-backend shape `.../media/{id}` the SDK persists as
/// `ChatMessage.attachmentUrl` right after upload (the id is the last path
/// segment in both cases). Returns `null` when the URL doesn't match either
/// shape (e.g. an arbitrary external URL with no recognizable segment).
String? attachmentIdFromUrl(String url) {
  final uri = Uri.tryParse(url);
  final segments = uri?.pathSegments ?? const <String>[];
  for (final marker in const ['attachments', 'media']) {
    final index = segments.indexOf(marker);
    if (index == -1 || index + 1 >= segments.length) continue;
    final id = segments[index + 1];
    if (id.isNotEmpty) return id;
  }
  return null;
}
