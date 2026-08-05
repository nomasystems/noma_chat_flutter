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

/// Tallest an image bubble grows before it is scaled down. Overridable
/// through `ChatTheme.imageMaxHeight`.
const double _defaultImageMaxHeight = 250;

/// Floor for the width the metadata row (time + ticks) is aligned within.
/// Extremely narrow images — a sliver scaled down to fit
/// [_defaultImageMaxHeight] — would otherwise squeeze the row until it
/// overflowed.
const double _minMetadataRowWidth = 72;

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
    this.mediaLoader,
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
  /// network image errors. Ignored once [mediaLoader] is wired — the
  /// signed URL this resolves still requires a Bearer token
  /// `CachedNetworkImage` never sends, so [mediaLoader] takes over
  /// rendering entirely when present.
  final AttachmentUrlResolver? urlResolver;

  /// Fetches this attachment's bytes through the authenticated client and
  /// renders from memory (`Image.memory`) instead of handing
  /// `CachedNetworkImage` a URL it can't authenticate. Preferred over
  /// [urlResolver] whenever both are set (together with [attachmentRef]).
  /// `null` (default) keeps the plain-URL path unchanged.
  final AttachmentMediaLoader? mediaLoader;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  String? _resolvedUrl;
  bool _retried = false;

  Uint8List? _bytes;
  Object? _bytesError;
  bool _bytesRetried = false;

  Size? _intrinsicSize;
  ImageStream? _dimensionsStream;
  ImageStreamListener? _dimensionsListener;

  bool get _usesMediaLoader =>
      widget.mediaLoader != null && widget.attachmentRef != null;

  String get _effectiveUrl => _resolvedUrl ?? widget.imageUrl;

  @override
  void initState() {
    super.initState();
    if (_usesMediaLoader) {
      _loadBytes();
    } else {
      _resolve();
    }
  }

  @override
  void didUpdateWidget(covariant ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.attachmentRef?.attachmentId !=
            widget.attachmentRef?.attachmentId) {
      _retried = false;
      _resolvedUrl = null;
      _bytesRetried = false;
      _bytes = null;
      _bytesError = null;
      _intrinsicSize = null;
      _stopListeningForDimensions();
      if (_usesMediaLoader) {
        _loadBytes();
      } else {
        _resolve();
      }
    }
  }

  void _loadBytes() {
    final loader = widget.mediaLoader;
    final ref = widget.attachmentRef;
    if (loader == null || ref == null) return;
    unawaited(
      loader
          .loadBytes(ref)
          .then((bytes) {
            if (!mounted) return;
            setState(() {
              _bytes = bytes;
              _bytesError = null;
            });
            _listenForDimensions(bytes);
          })
          .catchError((Object error) {
            uiDebugLog('ImageBubble', 'authenticated download failed: $error');
            if (!mounted) return;
            setState(() => _bytesError = error);
            _retryBytesAfterError();
          }),
    );
  }

  void _retryBytesAfterError() {
    if (_bytesRetried) return;
    _bytesRetried = true;
    _loadBytes();
  }

  /// Reads the decoded image's pixel dimensions so the bubble can size
  /// itself to the picture's real shape. Resolves the very same
  /// `MemoryImage` the rendering `Image.memory` builds (equal bytes ⇒
  /// equal cache key), so this costs a cache hit, not a second decode.
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

  /// Size the picture is actually painted at: its own aspect ratio scaled
  /// down (never up) to fit inside the bubble's width and the max height.
  /// `null` until the dimensions are known — callers then fall back to
  /// letting the image self-size inside a `ConstrainedBox`, which is what
  /// the plain-URL path does for its whole life.
  Size? _mediaSize(ChatTheme theme, BoxConstraints constraints) {
    final intrinsic = _intrinsicSize;
    if (intrinsic == null || intrinsic.width <= 0 || intrinsic.height <= 0) {
      return null;
    }
    final maxWidth = math.min(
      constraints.maxWidth,
      theme.imageMaxWidth ?? double.infinity,
    );
    if (!maxWidth.isFinite || maxWidth <= 0) return null;
    final maxHeight = theme.imageMaxHeight ?? _defaultImageMaxHeight;
    final scale = math.min(
      1.0,
      math.min(maxWidth / intrinsic.width, maxHeight / intrinsic.height),
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
      label: caption ?? theme.l10nOf(context).imagePreview,
      child: GestureDetector(
        // No tap-to-open while the upload is still in flight — there is
        // no usable URL yet.
        onTap: uploadProgress == null ? widget.onTap : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaSize = _mediaSize(theme, constraints);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius:
                      theme.imageBorderRadius ?? BorderRadius.circular(8),
                  // Tight box at the picture's real aspect ratio once the
                  // decoded dimensions are known, so a portrait photo no
                  // longer leaves the bubble stretched to the full 75% of
                  // the screen with dead space beside it.
                  child: SizedBox(
                    width: mediaSize?.width,
                    height: mediaSize?.height,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            theme.imageMaxHeight ?? _defaultImageMaxHeight,
                        maxWidth: theme.imageMaxWidth ?? double.infinity,
                      ),
                      child: uploadProgress != null
                          ? AttachmentUploadPlaceholder(
                              progress: uploadProgress,
                              theme: theme,
                              height:
                                  theme.imageMaxHeight ??
                                  _defaultImageMaxHeight,
                              icon: Icons.image,
                            )
                          : _usesMediaLoader
                          ? _buildAuthenticatedImage(theme)
                          : CachedNetworkImage(
                              key: ValueKey(_effectiveUrl),
                              imageUrl: _effectiveUrl,
                              // Stable across a re-mint (new signed URL,
                              // same attachment) so the cache doesn't
                              // re-download bytes it already has under the
                              // previous signed URL.
                              cacheKey: widget.attachmentRef?.attachmentId,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox(
                                height: 150,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              // Log the real cause of fallback icons. The
                              // user reported "ícono en vez de foto" — the
                              // error payload tells us whether the URL is
                              // unreachable (network/scheme), the server
                              // replied 500 (broken file_upload backend), or
                              // the bytes are corrupt.
                              errorWidget: (_, url, error) {
                                uiDebugLog(
                                  'ImageBubble',
                                  'CachedNetworkImage error for $url: $error',
                                );
                                _retryAfterError();
                                return const SizedBox(
                                  height: 100,
                                  child: Center(
                                    child: Icon(Icons.broken_image),
                                  ),
                                );
                              },
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
                  // Bound to the picture's width instead of the bubble's:
                  // a bare `Align` expands to the incoming max width and
                  // would drag the whole column back out to full width.
                  SizedBox(
                    width: mediaSize == null
                        ? null
                        : math.max(mediaSize.width, _minMetadataRowWidth),
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

  /// Renders the image from authenticated bytes (`Image.memory`) instead
  /// of handing `CachedNetworkImage` a URL it can't attach a Bearer token
  /// to. Shows the same loading/error affordances as the plain-URL path.
  Widget _buildAuthenticatedImage(ChatTheme theme) {
    final error = _bytesError;
    final bytes = _bytes;
    if (error != null && bytes == null) {
      return const SizedBox(
        height: 100,
        child: Center(child: Icon(Icons.broken_image)),
      );
    }
    if (bytes == null) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Image.memory(
      bytes,
      key: ValueKey(widget.attachmentRef?.attachmentId ?? widget.imageUrl),
      fit: BoxFit.cover,
      errorBuilder: (_, error, __) {
        uiDebugLog('ImageBubble', 'Image.memory decode failed: $error');
        _retryBytesAfterError();
        return const SizedBox(
          height: 100,
          child: Center(child: Icon(Icons.broken_image)),
        );
      },
    );
  }
}
