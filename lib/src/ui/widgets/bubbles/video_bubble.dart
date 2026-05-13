import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

/// Bubble that renders a video thumbnail with a play overlay; tap to open.
class VideoBubble extends StatelessWidget {
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
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final String? caption;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: caption ?? 'Video message',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius:
                  theme.videoBorderRadius ??
                  theme.imageBorderRadius ??
                  BorderRadius.circular(8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: thumbnailUrl!,
                      fit: BoxFit.cover,
                      height: theme.videoHeight ?? 180,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        height: theme.videoHeight ?? 180,
                        color: theme.videoPlaceholderColor ?? Colors.black26,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: theme.videoHeight ?? 180,
                        color: theme.videoPlaceholderColor ?? Colors.black26,
                        child: Icon(
                          Icons.videocam,
                          color:
                              theme.videoPlaceholderIconColor ?? Colors.white54,
                        ),
                      ),
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
                          theme.videoPlayIconBackgroundColor ?? Colors.black54,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timestamp != null)
                      Text(
                        DateFormatter.formatTime(timestamp!),
                        style:
                            (isOutgoing
                                ? theme.outgoingTimestampTextStyle
                                : theme.incomingTimestampTextStyle) ??
                            theme.timestampTextStyle ??
                            TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
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
