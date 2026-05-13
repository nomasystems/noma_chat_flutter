import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

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
      label: caption ?? 'Image',
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
                errorWidget: (_, __, ___) => const SizedBox(
                  height: 100,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(caption!, style: theme.imageCaptionStyle ?? const TextStyle(fontSize: 14)),
          ],
          if (timestamp != null || statusWidget != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (timestamp != null)
                    Text(
                      DateFormatter.formatTime(timestamp!),
                      style: (isOutgoing
                              ? theme.outgoingTimestampTextStyle
                              : theme.incomingTimestampTextStyle) ??
                          theme.timestampTextStyle ??
                          TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                    ),
                  if (statusWidget != null) ...[
                    const SizedBox(width: 4),
                    statusWidget!,
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}
