import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../_internal/ui_debug_log.dart';
import '../../services/attachment_url_resolver.dart';
import '../../theme/chat_theme.dart';
import '_attachment_upload_overlay.dart';
import '_bubble_metadata.dart';

/// Bubble that renders an image attachment with cached network loading and
/// tap-to-open behavior.
class ImageBubble extends StatefulWidget {
  const ImageBubble({
    super.key,
    required this.imageUrl,
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

  final String imageUrl;
  final String? caption;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  /// While not null, the bubble shows a placeholder + upload-progress ring
  /// instead of resolving [imageUrl] (which is typically empty/unusable
  /// until the upload completes) and disables tap-to-open. Once the
  /// upload finishes the caller passes `null` here alongside the real
  /// [imageUrl]. Expected range 0..1 — same contract as
  /// `AudioBubble.uploadProgress`.
  final ValueListenable<double>? uploadProgress;

  /// Identifies this attachment for [urlResolver]. `null` (default) keeps
  /// [imageUrl] as the sole source, unchanged from before this parameter
  /// existed.
  final AttachmentRef? attachmentRef;

  /// Resolves a fresh image URL for [attachmentRef] on demand, re-minting
  /// on expiry. Consulted before the first load and once more if the
  /// network image errors.
  final AttachmentUrlResolver? urlResolver;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  String? _resolvedUrl;
  bool _retried = false;

  String get _effectiveUrl => _resolvedUrl ?? widget.imageUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.attachmentRef?.attachmentId !=
            widget.attachmentRef?.attachmentId) {
      _retried = false;
      _resolvedUrl = null;
      _resolve();
    }
  }

  void _resolve() {
    final resolver = widget.urlResolver;
    final ref = widget.attachmentRef;
    if (resolver == null || ref == null) return;
    unawaited(
      resolver(ref)
          .then((resolved) {
            if (!mounted || resolved == _resolvedUrl) return;
            setState(() => _resolvedUrl = resolved);
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
            setState(() => _resolvedUrl = resolved);
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
    final uploadProgress = widget.uploadProgress;
    return Semantics(
      image: true,
      label: caption ?? theme.l10n.imagePreview,
      child: GestureDetector(
        // No tap-to-open while the upload is still in flight — there is
        // no usable URL yet.
        onTap: uploadProgress == null ? widget.onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: theme.imageBorderRadius ?? BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: theme.imageMaxHeight ?? 250,
                  maxWidth: theme.imageMaxWidth ?? double.infinity,
                ),
                child: uploadProgress != null
                    ? AttachmentUploadPlaceholder(
                        progress: uploadProgress,
                        theme: theme,
                        height: theme.imageMaxHeight ?? 250,
                        icon: Icons.image,
                      )
                    : CachedNetworkImage(
                        key: ValueKey(_effectiveUrl),
                        imageUrl: _effectiveUrl,
                        // Stable across a re-mint (new signed URL, same
                        // attachment) so the cache doesn't re-download bytes it
                        // already has under the previous signed URL.
                        cacheKey: widget.attachmentRef?.attachmentId,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(
                          height: 150,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        // Log the real cause of fallback icons. The
                        // user reported "ícono en vez de foto" — the error
                        // payload tells us whether the URL is unreachable
                        // (network/scheme), the server replied 500 (broken
                        // file_upload backend), or the bytes are corrupt.
                        errorWidget: (_, url, error) {
                          uiDebugLog(
                            'ImageBubble',
                            'CachedNetworkImage error for $url: $error',
                          );
                          _retryAfterError();
                          return const SizedBox(
                            height: 100,
                            child: Center(child: Icon(Icons.broken_image)),
                          );
                        },
                      ),
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
