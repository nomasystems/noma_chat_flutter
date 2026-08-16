import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../_internal/ui_debug_log.dart';
import '../../services/attachment_bytes_loader.dart';
import '../../services/attachment_url_resolver.dart';
import '../../theme/chat_theme.dart';
import '_attachment_upload_overlay.dart';
import '_bubble_metadata.dart';

/// Bubble that renders a video thumbnail; tap the play overlay to open.
///
/// The package ships no video player, so playback belongs to [onTap]. The
/// play overlay is painted only when [onTap] is wired: without a handler
/// the thumbnail renders on its own rather than offering a button that
/// would swallow the tap.
class VideoBubble extends StatefulWidget {
  const VideoBubble({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.caption,
    this.timestamp,
    this.onTap,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
    this.statusWidget,
    this.thumbnailRef,
    this.urlResolver,
    this.mediaLoader,
    this.uploadProgress,
    this.onCancelUpload,
    this.isFailed = false,
    this.onRetry,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final String? caption;
  final DateTime? timestamp;

  /// Opens the video. `null` (default) also hides the play overlay — the
  /// bubble never paints an affordance it cannot honour.
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  /// While not null, the bubble shows a placeholder + upload-progress ring
  /// instead of the thumbnail/play-button and disables tap-to-open. Same
  /// contract as `ImageBubble.uploadProgress`/`AudioBubble.uploadProgress`.
  final ValueListenable<double>? uploadProgress;

  /// Cancels the in-flight upload. `null` (default) renders the ring's
  /// center icon as a plain, non-interactive glyph — same contract as
  /// `ImageBubble.onCancelUpload`/`FileBubble.onCancelUpload`.
  final VoidCallback? onCancelUpload;

  /// `true` once the upload/send behind this attachment has failed
  /// (`MessageBubble.isFailed`). Only while [uploadProgress] is null —
  /// uploading and failed are mutually exclusive — this swaps the
  /// thumbnail for [AttachmentFailedPlaceholder] instead of attempting to
  /// resolve [thumbnailUrl], which is typically empty or local-only when
  /// the upload never completed.
  final bool isFailed;

  /// Retries the failed upload/send. Same contract as [onCancelUpload]:
  /// forward the exact callback `MessageBubble.onRetry` already uses for
  /// the status-row retry icon — never a second retry path. `null`
  /// (default) still paints the failed placeholder, with a static error
  /// glyph in place of the retry arrow — a failure no retry can clear
  /// must not offer a button that does nothing.
  final VoidCallback? onRetry;

  /// Identifies the **poster frame**, never the clip: the thumbnail is a
  /// blob of its own with its own attachment id
  /// (`ChatMessage.thumbnailAttachmentId`), which is why this is not the
  /// video's [AttachmentRef] — handing that one down would make
  /// [mediaLoader] fetch the clip and `Image.memory` try to decode a video
  /// as a picture. Enough on its own for [mediaLoader]: the frame is
  /// fetched by id, so a message that carries one but no [thumbnailUrl]
  /// still paints. `null` (default) keeps [thumbnailUrl] as the sole
  /// source. Playback itself (opened via [onTap]) is the host's
  /// responsibility and re-mints separately if it needs to.
  final AttachmentRef? thumbnailRef;

  /// Resolves a fresh thumbnail URL for [thumbnailRef] on demand,
  /// re-minting on expiry. Consulted before the first load and once more
  /// if the thumbnail image errors. Ignored once [mediaLoader] is wired —
  /// same reasoning as `ImageBubble.urlResolver`.
  final AttachmentUrlResolver? urlResolver;

  /// Fetches the thumbnail's bytes through the authenticated client and
  /// renders from memory instead of handing `CachedNetworkImage` a URL it
  /// can't authenticate. Preferred over [urlResolver] whenever both are
  /// set (together with [thumbnailRef]). `null` (default) keeps the
  /// plain-URL path unchanged. Playback itself (opened via [onTap]) stays
  /// the host's responsibility.
  final AttachmentMediaLoader? mediaLoader;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  /// Cap applied to the poster frame's own height when the theme sets none,
  /// mirroring `ImageBubble`'s default so a clip and a photo of the same
  /// shape occupy the same bubble.
  static const double _defaultVideoMaxHeight = 250;

  /// Height of every state that has no real frame to size from — pending
  /// download, upload/failed placeholders, a broken or absent thumbnail. The
  /// pre-intrinsic look of the bubble, unchanged from before the bubble
  /// learned to take the clip's own shape: full width, fixed height.
  /// [_maxHeight] only caps the REAL poster frame once its dimensions are
  /// known; letting it size the placeholders made an empty grey box taller
  /// than any actual content and collapsed the plain-URL error state to the
  /// width of its icon.
  static const double _placeholderHeight = 180;

  String? _resolvedThumbnailUrl;
  bool _retried = false;

  Uint8List? _thumbnailBytes;
  Object? _thumbnailBytesError;
  bool _thumbnailBytesRetried = false;

  Size? _intrinsicSize;
  ImageStream? _dimensionsStream;
  ImageStreamListener? _dimensionsListener;

  bool get _usesMediaLoader =>
      widget.mediaLoader != null && widget.thumbnailRef != null;

  String? get _effectiveThumbnailUrl =>
      _resolvedThumbnailUrl ?? widget.thumbnailUrl;

  @override
  void initState() {
    super.initState();
    if (_usesMediaLoader) {
      _loadThumbnailBytes();
    } else {
      _resolve();
    }
  }

  @override
  void didUpdateWidget(covariant VideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl ||
        oldWidget.thumbnailRef?.attachmentId !=
            widget.thumbnailRef?.attachmentId) {
      _retried = false;
      _resolvedThumbnailUrl = null;
      _thumbnailBytesRetried = false;
      _thumbnailBytes = null;
      _thumbnailBytesError = null;
      _intrinsicSize = null;
      _stopListeningForDimensions();
      if (_usesMediaLoader) {
        _loadThumbnailBytes();
      } else {
        _resolve();
      }
    }
  }

  void _loadThumbnailBytes() {
    final loader = widget.mediaLoader;
    final ref = widget.thumbnailRef;
    if (loader == null || ref == null) return;
    unawaited(
      loader
          .loadBytes(ref)
          .then((bytes) {
            if (!mounted) return;
            setState(() {
              _thumbnailBytes = bytes;
              _thumbnailBytesError = null;
            });
            _listenForDimensions(bytes);
          })
          .catchError((Object error) {
            uiDebugLog(
              'VideoBubble',
              'authenticated thumbnail download failed: $error',
            );
            if (!mounted) return;
            setState(() => _thumbnailBytesError = error);
            _retryThumbnailBytesAfterError();
          }),
    );
  }

  void _retryThumbnailBytesAfterError() {
    if (_thumbnailBytesRetried) return;
    _thumbnailBytesRetried = true;
    _loadThumbnailBytes();
  }

  /// Reads the decoded poster frame's pixel dimensions so the bubble can take
  /// the clip's real shape. Resolves the very same `MemoryImage` the rendering
  /// `Image.memory` builds (equal bytes ⇒ equal cache key), so it costs a
  /// cache hit rather than a second decode. Same mechanism as `ImageBubble`.
  void _listenForDimensions(Uint8List bytes) {
    _stopListeningForDimensions();
    final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      info.dispose();
      if (!mounted || _intrinsicSize == size) return;
      setState(() => _intrinsicSize = size);
    }, onError: (_, __) {});
    _dimensionsStream = stream;
    _dimensionsListener = listener;
    stream.addListener(listener);
  }

  void _stopListeningForDimensions() {
    final stream = _dimensionsStream;
    final listener = _dimensionsListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _dimensionsStream = null;
    _dimensionsListener = null;
  }

  double get _maxHeight => widget.theme.videoHeight ?? _defaultVideoMaxHeight;

  /// Size the poster frame is painted at: its own aspect ratio scaled down
  /// (never up) to fit the bubble's width and [_maxHeight]. `null` until the
  /// dimensions are known, and for the whole life of the plain-URL path,
  /// where the thumbnail self-sizes inside a `ConstrainedBox` instead.
  Size? _mediaSize(BoxConstraints constraints) {
    final intrinsic = _intrinsicSize;
    if (intrinsic == null || intrinsic.width <= 0 || intrinsic.height <= 0) {
      return null;
    }
    if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
      return null;
    }
    final scale = math.min(
      1.0,
      math.min(
        constraints.maxWidth / intrinsic.width,
        _maxHeight / intrinsic.height,
      ),
    );
    return Size(intrinsic.width * scale, intrinsic.height * scale);
  }

  @override
  void dispose() {
    _stopListeningForDimensions();
    super.dispose();
  }

  void _resolve() {
    final resolver = widget.urlResolver;
    final ref = widget.thumbnailRef;
    if (resolver == null || ref == null || widget.thumbnailUrl == null) return;
    unawaited(
      resolver(ref)
          .then((resolved) {
            if (!mounted || resolved == _resolvedThumbnailUrl) return;
            setState(() => _resolvedThumbnailUrl = resolved);
          })
          .catchError((_) {}),
    );
  }

  void _retryAfterError() {
    if (_retried) return;
    final resolver = widget.urlResolver;
    final ref = widget.thumbnailRef;
    if (resolver == null || ref == null) return;
    _retried = true;
    unawaited(
      resolver(ref)
          .then((resolved) {
            if (!mounted) return;
            setState(() => _resolvedThumbnailUrl = resolved);
          })
          .catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final caption = widget.caption;
    final timestamp = widget.timestamp;
    final statusWidget = widget.statusWidget;
    final thumbnailUrl = _effectiveThumbnailUrl;
    final uploadProgress = widget.uploadProgress;
    final showFailed = paintsAttachmentFailure(
      isFailed: widget.isFailed,
      uploadProgress: uploadProgress,
    );
    return Semantics(
      label: caption ?? theme.l10nOf(context).videoPreview,
      button: widget.onTap != null && uploadProgress == null && !showFailed,
      child: GestureDetector(
        // No tap-to-open while the upload is still in flight, nor once it
        // has failed.
        onTap: uploadProgress == null && !showFailed ? widget.onTap : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaSize = _mediaSize(constraints);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius:
                      theme.videoBorderRadius ??
                      theme.imageBorderRadius ??
                      BorderRadius.circular(8),
                  // Tight box at the clip's real aspect ratio once the poster
                  // frame's dimensions are known, so a portrait video is no
                  // longer cropped into a fixed-height landscape strip.
                  child: SizedBox(
                    width: mediaSize?.width,
                    height: mediaSize?.height,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: _maxHeight),
                      child: uploadProgress != null
                          ? AttachmentUploadPlaceholder(
                              progress: uploadProgress,
                              theme: theme,
                              height: _placeholderHeight,
                              icon: Icons.videocam,
                              onCancel: widget.onCancelUpload,
                            )
                          : showFailed
                          ? AttachmentFailedPlaceholder(
                              theme: theme,
                              height: _placeholderHeight,
                              icon: Icons.videocam,
                              onRetry: widget.onRetry,
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_usesMediaLoader)
                                  _buildAuthenticatedThumbnail(theme)
                                else if (thumbnailUrl != null)
                                  CachedNetworkImage(
                                    key: ValueKey(thumbnailUrl),
                                    imageUrl: thumbnailUrl,
                                    cacheKey: widget.thumbnailRef?.attachmentId,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => Container(
                                      height: _placeholderHeight,
                                      width: double.infinity,
                                      color:
                                          theme.videoPlaceholderColor ??
                                          Colors.black26,
                                    ),
                                    errorWidget: (_, __, ___) {
                                      _retryAfterError();
                                      return Container(
                                        height: _placeholderHeight,
                                        width: double.infinity,
                                        color:
                                            theme.videoPlaceholderColor ??
                                            Colors.black26,
                                        child: Icon(
                                          Icons.videocam,
                                          color:
                                              theme.videoPlaceholderIconColor ??
                                              Colors.white54,
                                        ),
                                      );
                                    },
                                  )
                                else
                                  Container(
                                    height: _placeholderHeight,
                                    width: double.infinity,
                                    color:
                                        theme.videoPlaceholderColor ??
                                        Colors.black26,
                                    child: const Icon(
                                      Icons.videocam,
                                      color: Colors.white54,
                                      size: 48,
                                    ),
                                  ),
                                if (widget.onTap != null)
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color:
                                          theme.videoPlayIconBackgroundColor ??
                                          Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.play_arrow,
                                      color:
                                          theme.videoPlayIconColor ??
                                          Colors.white,
                                      size: 32,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
                if (caption != null && caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style:
                        theme.imageCaptionStyle ??
                        const TextStyle(fontSize: 14),
                  ),
                ],
                if (timestamp != null || statusWidget != null) ...[
                  const SizedBox(height: 2),
                  // Bound to the thumbnail's width, not the bubble's: a bare
                  // `Align` expands to the incoming max width and would drag
                  // the column back out to full width.
                  SizedBox(
                    width: mediaSize?.width,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: BubbleMetadataRow(
                        theme: theme,
                        isOutgoing: widget.isOutgoing,
                        timestamp: timestamp,
                        statusWidget: statusWidget,
                        gap: 4,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Renders the thumbnail from authenticated bytes (`Image.memory`)
  /// instead of handing `CachedNetworkImage` a URL it can't authenticate.
  /// Same loading/error affordances as the plain-URL path.
  Widget _buildAuthenticatedThumbnail(ChatTheme theme) {
    final error = _thumbnailBytesError;
    final bytes = _thumbnailBytes;
    const height = _placeholderHeight;
    if (error != null && bytes == null) {
      return Container(
        height: height,
        width: double.infinity,
        color: theme.videoPlaceholderColor ?? Colors.black26,
        child: Icon(
          Icons.videocam,
          color: theme.videoPlaceholderIconColor ?? Colors.white54,
        ),
      );
    }
    if (bytes == null) {
      return Container(
        height: height,
        width: double.infinity,
        color: theme.videoPlaceholderColor ?? Colors.black26,
      );
    }
    return Image.memory(
      bytes,
      key: ValueKey(widget.thumbnailRef?.attachmentId ?? widget.thumbnailUrl),
      fit: BoxFit.contain,
      errorBuilder: (_, error, __) {
        uiDebugLog('VideoBubble', 'Image.memory decode failed: $error');
        _retryThumbnailBytesAfterError();
        return Container(
          height: height,
          width: double.infinity,
          color: theme.videoPlaceholderColor ?? Colors.black26,
          child: Icon(
            Icons.videocam,
            color: theme.videoPlaceholderIconColor ?? Colors.white54,
          ),
        );
      },
    );
  }
}
