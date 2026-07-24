import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../_internal/ui_debug_log.dart';
import '../../services/attachment_bytes_loader.dart';
import '../../services/attachment_url_resolver.dart';
import '../../theme/chat_theme.dart';
import '_attachment_upload_overlay.dart';
import '_bubble_metadata.dart';

/// Bubble that renders a video thumbnail with a play overlay; tap to open.
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
    this.attachmentRef,
    this.urlResolver,
    this.mediaLoader,
    this.uploadProgress,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final String? caption;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  /// While not null, the bubble shows a placeholder + upload-progress ring
  /// instead of the thumbnail/play-button and disables tap-to-open. Same
  /// contract as `ImageBubble.uploadProgress`/`AudioBubble.uploadProgress`.
  final ValueListenable<double>? uploadProgress;

  /// Identifies this attachment for [urlResolver]. `null` (default) keeps
  /// [thumbnailUrl] as the sole source, unchanged from before this
  /// parameter existed. Playback itself (opened via [onTap]) is the
  /// host's responsibility and re-mints separately if it needs to.
  final AttachmentRef? attachmentRef;

  /// Resolves a fresh thumbnail URL for [attachmentRef] on demand,
  /// re-minting on expiry. Consulted before the first load and once more
  /// if the thumbnail image errors. Ignored once [mediaLoader] is wired —
  /// same reasoning as `ImageBubble.urlResolver`.
  final AttachmentUrlResolver? urlResolver;

  /// Fetches the thumbnail's bytes through the authenticated client and
  /// renders from memory instead of handing `CachedNetworkImage` a URL it
  /// can't authenticate. Preferred over [urlResolver] whenever both are
  /// set (together with [attachmentRef]). `null` (default) keeps the
  /// plain-URL path unchanged. Playback itself (opened via [onTap]) stays
  /// the host's responsibility.
  final AttachmentMediaLoader? mediaLoader;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  String? _resolvedThumbnailUrl;
  bool _retried = false;

  Uint8List? _thumbnailBytes;
  Object? _thumbnailBytesError;
  bool _thumbnailBytesRetried = false;

  bool get _usesMediaLoader =>
      widget.mediaLoader != null &&
      widget.attachmentRef != null &&
      widget.thumbnailUrl != null;

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
        oldWidget.attachmentRef?.attachmentId !=
            widget.attachmentRef?.attachmentId) {
      _retried = false;
      _resolvedThumbnailUrl = null;
      _thumbnailBytesRetried = false;
      _thumbnailBytes = null;
      _thumbnailBytesError = null;
      if (_usesMediaLoader) {
        _loadThumbnailBytes();
      } else {
        _resolve();
      }
    }
  }

  void _loadThumbnailBytes() {
    final loader = widget.mediaLoader;
    final ref = widget.attachmentRef;
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

  void _resolve() {
    final resolver = widget.urlResolver;
    final ref = widget.attachmentRef;
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
    final ref = widget.attachmentRef;
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
    return Semantics(
      label: caption ?? theme.l10n.videoPreview,
      button: widget.onTap != null && uploadProgress == null,
      child: GestureDetector(
        // No tap-to-open while the upload is still in flight.
        onTap: uploadProgress == null ? widget.onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius:
                  theme.videoBorderRadius ??
                  theme.imageBorderRadius ??
                  BorderRadius.circular(8),
              child: uploadProgress != null
                  ? AttachmentUploadPlaceholder(
                      progress: uploadProgress,
                      theme: theme,
                      height: theme.videoHeight ?? 180,
                      icon: Icons.videocam,
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
                            cacheKey: widget.attachmentRef?.attachmentId,
                            fit: BoxFit.cover,
                            height: theme.videoHeight ?? 180,
                            width: double.infinity,
                            placeholder: (_, __) => Container(
                              height: theme.videoHeight ?? 180,
                              color:
                                  theme.videoPlaceholderColor ?? Colors.black26,
                            ),
                            errorWidget: (_, __, ___) {
                              _retryAfterError();
                              return Container(
                                height: theme.videoHeight ?? 180,
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
                            height: theme.videoHeight ?? 180,
                            width: double.infinity,
                            color:
                                theme.videoPlaceholderColor ?? Colors.black26,
                            child: const Icon(
                              Icons.videocam,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
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
                            color: theme.videoPlayIconColor ?? Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
            ),
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                caption,
                style: theme.imageCaptionStyle ?? const TextStyle(fontSize: 14),
              ),
            ],
            if (timestamp != null || statusWidget != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: BubbleMetadataRow(
                  theme: theme,
                  isOutgoing: widget.isOutgoing,
                  timestamp: timestamp,
                  statusWidget: statusWidget,
                  gap: 4,
                ),
              ),
            ],
          ],
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
    final height = theme.videoHeight ?? 180;
    if (error != null && bytes == null) {
      return Container(
        height: height,
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
        color: theme.videoPlaceholderColor ?? Colors.black26,
      );
    }
    return Image.memory(
      bytes,
      key: ValueKey(widget.attachmentRef?.attachmentId ?? widget.thumbnailUrl),
      fit: BoxFit.cover,
      height: height,
      width: double.infinity,
      errorBuilder: (_, error, __) {
        uiDebugLog('VideoBubble', 'Image.memory decode failed: $error');
        _retryThumbnailBytesAfterError();
        return Container(
          height: height,
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
