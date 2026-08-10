import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

import '../../_internal/ui_debug_log.dart';
import '../room_defaults.dart';
import '../utils/platform_support.dart';

/// A poster frame extracted from a video, ready to be uploaded as its own
/// attachment and rendered by `VideoBubble`.
///
/// No dimensions: the bubble crops to `ChatTheme.videoHeight` with
/// `BoxFit.cover` over the full bubble width, so it never needs the source
/// resolution. Add them here (and to the metadata the adapter stamps) if a
/// future aspect-ratio-preserving bubble does.
@immutable
class VideoThumbnailData {
  const VideoThumbnailData({required this.bytes, this.mimeType = 'image/jpeg'});

  /// Encoded image bytes, decodable by `Image.memory`.
  final Uint8List bytes;

  /// MIME type [bytes] are encoded in — uploaded alongside them so the
  /// backend stores the blob under the right content type.
  final String mimeType;
}

/// Produces the poster frame a video message displays before playback.
///
/// The backend is a pure blob store — it never transcodes or samples an
/// uploaded video — so the only place a preview frame can come from is the
/// sending client. `ChatMessagesController.sendAttachment` calls this
/// whenever it is about to send a `video/*` attachment, uploads the result
/// as a second small blob, and stamps its id onto the message.
///
/// Wired by default to [NativeVideoThumbnailer]; hosts override it through
/// `ChatUiAdapter(videoThumbnailer: …)` / `NomaChat.create(videoThumbnailer: …)`
/// when they have their own extractor (a server-side pipeline, an ffmpeg
/// build, a platform channel of their own).
///
/// Implementations must never throw: this is a best-effort enrichment and
/// the send goes ahead without a preview when it cannot be produced.
abstract class VideoThumbnailer {
  /// Extracts a poster frame from [videoBytes], a video encoded as
  /// [mimeType]. Returns `null` — never throws — when no frame can be
  /// produced (unsupported platform, unreadable container, decoder error).
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  });
}

/// Default [VideoThumbnailer]: extracts the first frame through the
/// platform's own decoder (`MediaMetadataRetriever` on Android,
/// `AVAssetImageGenerator` on iOS) via the `get_thumbnail_video` plugin.
///
/// The plugin only reads from a path, so this spools [generate]'s bytes to
/// a temp file first and deletes it before returning (plus, once per
/// process, any copy an earlier run was killed before deleting) — the
/// bridge is an implementation detail, deliberately kept out of the
/// [VideoThumbnailer] contract so an extractor that accepts bytes directly
/// can replace this one without touching a single caller.
///
/// Off on every non-mobile target (see
/// [PlatformSupport.supportsVideoThumbnails]), where [generate] returns
/// `null` without touching the plugin.
class NativeVideoThumbnailer implements VideoThumbnailer {
  const NativeVideoThumbnailer({
    this.maxWidth = RoomDefaults.videoThumbnailMaxWidth,
    this.quality = RoomDefaults.videoThumbnailQuality,
  });

  /// Longest edge of the generated frame, in pixels. `0` keeps the video's
  /// own resolution — which would upload a full-size still per clip.
  final int maxWidth;

  /// JPEG quality (0-100).
  final int quality;

  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) async {
    if (!PlatformSupport.supportsVideoThumbnails) return null;
    File? spooled;
    try {
      final dir = await getTemporaryDirectory();
      unawaited(_sweepStaleSpools(dir));
      spooled = File('${dir.path}/${_spoolName(mimeType)}');
      await spooled.writeAsBytes(videoBytes, flush: true);
      final bytes = await VideoThumbnail.thumbnailData(
        video: spooled.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: quality,
      );
      if (bytes.isEmpty) return null;
      return VideoThumbnailData(bytes: bytes);
    } catch (error) {
      uiDebugLog('NativeVideoThumbnailer', 'frame extraction failed: $error');
      return null;
    } finally {
      await _discard(spooled);
    }
  }

  /// Name for the spooled copy. Held by [generate] BEFORE the write, so a
  /// write that dies partway (no space left, a quota) still leaves a path
  /// [_discard] can delete.
  String _spoolName(String mimeType) =>
      '$_spoolPrefix${DateTime.now().microsecondsSinceEpoch}'
      '${videoFileExtensionFor(mimeType)}';

  Future<void> _discard(File? file) async {
    if (file == null) return;
    try {
      if (file.existsSync()) await file.delete();
    } catch (error) {
      uiDebugLog('NativeVideoThumbnailer', 'temp file cleanup failed: $error');
    }
  }

  static bool _staleSweepStarted = false;
  static const String _spoolPrefix = 'noma_chat_thumbnail_source_';
  static const Duration _staleSpoolAge = Duration(hours: 1);

  /// Deletes spooled copies a previous run of the app left behind —
  /// [_discard] cannot reach them when the process dies mid-generation, and
  /// each one is a full copy of a video. Runs at most once per process, over
  /// this class's own prefix only; [_staleSpoolAge] sits orders of magnitude
  /// above the bounded lifetime of a live spool, so a concurrent generation
  /// can never be its target. Best-effort — a failure to list or delete
  /// leaves the file for the next run.
  ///
  /// Per entry, deliberately: a temp directory is shared and mutable, so a
  /// file vanishing between `list` and `statSync` is ordinary. With the walk
  /// in one `try` that ordinary event would end the only sweep the process
  /// ever gets and strand every remaining copy until the next launch.
  Future<void> _sweepStaleSpools(Directory dir) async {
    if (_staleSweepStarted) return;
    _staleSweepStarted = true;
    final cutoff = DateTime.now().subtract(_staleSpoolAge);
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.uri.pathSegments.last.startsWith(_spoolPrefix)) continue;
        try {
          if (entity.statSync().modified.isAfter(cutoff)) continue;
          await entity.delete();
        } catch (error) {
          uiDebugLog(
            'NativeVideoThumbnailer',
            'stale spool skipped: ${entity.path} ($error)',
          );
        }
      }
    } catch (error) {
      uiDebugLog('NativeVideoThumbnailer', 'stale spool sweep failed: $error');
    }
  }
}

/// [VideoThumbnailer] that never produces a frame — the documented way to
/// turn poster frames off (`ChatUiAdapter(videoThumbnailer:
/// const NoVideoThumbnailer())`). Videos then send exactly as they did
/// before the feature existed: one blob, no preview.
class NoVideoThumbnailer implements VideoThumbnailer {
  const NoVideoThumbnailer();

  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) async => null;
}

/// File extension (leading dot) the spooled copy of a `video/*` payload
/// should carry.
///
/// Both native extractors sniff the container from the file's extension
/// before they look at its bytes, so a `.tmp` suffix makes them fail on
/// perfectly valid input. Unknown subtypes fall back to `.mp4`, by far the
/// most common container a camera roll or an in-app capture produces.
String videoFileExtensionFor(String mimeType) =>
    switch (mimeType.toLowerCase().split(';').first.trim()) {
      'video/quicktime' => '.mov',
      'video/x-matroska' => '.mkv',
      'video/webm' => '.webm',
      'video/3gpp' => '.3gp',
      'video/x-msvideo' => '.avi',
      'video/mpeg' => '.mpeg',
      _ => '.mp4',
    };
