import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  /// if the thumbnail image errors.
  final AttachmentUrlResolver? urlResolver;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  String? _resolvedThumbnailUrl;
  bool _retried = false;

  String? get _effectiveThumbnailUrl =>
      _resolvedThumbnailUrl ?? widget.thumbnailUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant VideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl ||
        oldWidget.attachmentRef?.attachmentId !=
            widget.attachmentRef?.attachmentId) {
      _retried = false;
      _resolvedThumbnailUrl = null;
      _resolve();
    }
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
                        if (thumbnailUrl != null)
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
                                  theme.videoPlaceholderColor ??
                                  Colors.black26,
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
                            color: theme.videoPlaceholderColor ?? Colors.black26,
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
}
