import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../_internal/ui_debug_log.dart';
import '../../theme/chat_theme.dart';
import '_bubble_metadata.dart';

/// Bubble that renders an image attachment with cached network loading and
/// tap-to-open behavior.
class ImageBubble extends StatelessWidget {
  const ImageBubble({
    super.key,
    required this.imageUrl,
    this.caption,
    this.timestamp,
    this.onTap,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
    this.statusWidget,
  });

  final String imageUrl;
  final String? caption;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: caption ?? theme.l10n.imagePreview,
      child: GestureDetector(
        onTap: onTap,
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
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
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
                    return const SizedBox(
                      height: 100,
                      child: Center(child: Icon(Icons.broken_image)),
                    );
                  },
                ),
              ),
            ),
            if (caption != null && caption!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                caption!,
                style: theme.imageCaptionStyle ?? const TextStyle(fontSize: 14),
              ),
            ],
            if (timestamp != null || statusWidget != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: BubbleMetadataRow(
                  theme: theme,
                  isOutgoing: isOutgoing,
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
