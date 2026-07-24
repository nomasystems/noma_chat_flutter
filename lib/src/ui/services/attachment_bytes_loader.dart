import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../client/chat_client.dart';
import '../../observability/chat_logger.dart';
import 'attachment_url_resolver.dart';

/// Fetches an attachment's bytes (or a local file holding them) for a
/// bubble to render, given its [AttachmentRef].
///
/// This exists because `GET /attachments/{id}` (and its signed-url variant)
/// requires a Bearer token — the SDK's own `RestClient`/Dio attaches it
/// automatically for every API call, but a plain `<img>`-style widget
/// (`CachedNetworkImage`, `UrlSource`, a video player) never sends it when
/// it loads a URL directly. Loading the raw or signed URL from those
/// widgets therefore always 401s; the only way to display media is to
/// fetch the bytes through the authenticated client and render from
/// memory/disk instead of handing the widget a URL.
abstract class AttachmentMediaLoader {
  /// Downloads (or returns the already-cached copy of) [ref]'s bytes. Used
  /// by bubbles that can render straight from memory (`Image.memory`).
  Future<Uint8List> loadBytes(AttachmentRef ref);

  /// Same as [loadBytes] but persists the bytes to a file and returns its
  /// path — for playback APIs that need a file rather than raw bytes
  /// (`DeviceFileSource` for audio, a video controller).
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix});

  /// Drops every cached entry. Hosts that log out / switch accounts should
  /// call this so a stale attachment never leaks across sessions.
  void clear();
}

/// Default [AttachmentMediaLoader]: downloads bytes via
/// `ChatAttachmentsApi.download` (Dio + Bearer under the hood) and caches
/// them — in memory for instant re-renders (scrolling a bubble off/on
/// screen), and on disk (the app's temp directory) for players that need a
/// file path rather than raw bytes (`DeviceFileSource` for audio, a video
/// file for playback).
///
/// Cache key is [AttachmentRef.attachmentId] when present, falling back to
/// an id recovered from [AttachmentRef.fallbackUrl] via
/// [attachmentIdFromUrl] so legacy messages without a stored id still get
/// a stable key.
class AuthenticatedAttachmentLoader implements AttachmentMediaLoader {
  AuthenticatedAttachmentLoader({
    required ChatClient client,
    ChatLogger? logger,
  }) : _client = client,
       _logger = logger;

  final ChatClient _client;
  final ChatLogger? _logger;

  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, Future<Uint8List>> _inFlight = {};
  final Map<String, String> _filePathCache = {};

  static String? _idFor(AttachmentRef ref) =>
      ref.attachmentId ?? attachmentIdFromUrl(ref.fallbackUrl);

  static String _keyFor(AttachmentRef ref) => _idFor(ref) ?? ref.fallbackUrl;

  /// Downloads (or returns the already-cached copy of) [ref]'s bytes.
  /// Concurrent calls for the same attachment share a single in-flight
  /// request instead of firing one download per bubble instance.
  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) {
    final key = _keyFor(ref);
    final cached = _memoryCache[key];
    if (cached != null) return Future.value(cached);
    return _inFlight[key] ??= _download(ref, key);
  }

  Future<Uint8List> _download(AttachmentRef ref, String key) async {
    try {
      final id = _idFor(ref);
      if (id == null) {
        throw StateError(
          'AuthenticatedAttachmentLoader: no attachmentId available for '
          '${ref.fallbackUrl}',
        );
      }
      final result = await _client.attachments.download(id, roomId: ref.roomId);
      return result.fold((failure) {
        _logger?.attach(
          ChatLogLevel.warn,
          'authenticated attachment download failed',
          fields: {
            'roomId': ref.roomId,
            'attachmentId': id,
            'failure': failure.toString(),
          },
        );
        throw failure;
      }, (bytes) => _memoryCache[key] = bytes);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Same as [loadBytes] but persists the bytes to a file inside the app's
  /// temp directory and returns its path — for playback APIs that need a
  /// file (`DeviceFileSource`, a video controller) rather than raw bytes.
  /// Reuses the on-disk file across calls for the same [ref] within this
  /// process; re-downloads if the file was evicted from the temp dir
  /// between calls.
  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) async {
    final key = _keyFor(ref);
    final cachedPath = _filePathCache[key];
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }
    final bytes = await loadBytes(ref);
    final dir = await getTemporaryDirectory();
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final path = '${dir.path}/noma_chat_attachment_$safeKey$suffix';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    _filePathCache[key] = path;
    return path;
  }

  /// Drops every cached entry (memory + on-disk file references — the
  /// files themselves are left on disk for the OS to reclaim as temp
  /// storage).
  @override
  void clear() {
    _memoryCache.clear();
    _inFlight.clear();
    _filePathCache.clear();
  }
}
