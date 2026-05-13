import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

/// Bubble for a shared location: shows a static map preview centered on the
/// coordinates and opens the system maps app on tap.
class LocationBubble extends StatelessWidget {
  const LocationBubble({
    super.key,
    required this.latitude,
    required this.longitude,
    this.staticMapUrl,
    this.label,
    this.timestamp,
    this.onTap,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
    this.statusWidget,
  });

  final double latitude;
  final double longitude;
  final String? staticMapUrl;
  final String? label;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    final radius =
        theme.videoBorderRadius ??
        theme.imageBorderRadius ??
        BorderRadius.circular(8);
    final mapHeight = theme.videoHeight ?? 180;
    final placeholderColor = theme.videoPlaceholderColor ?? Colors.black26;

    final mapBuilder = theme.locationMapBuilder;
    final hasMapPreview = mapBuilder != null || staticMapUrl != null;

    return Semantics(
      label: label ?? 'Location message',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: mapHeight,
                    width: double.infinity,
                    child: AbsorbPointer(
                      child: mapBuilder != null
                          ? mapBuilder(context, latitude, longitude)
                          : staticMapUrl != null
                          ? CachedNetworkImage(
                              imageUrl: staticMapUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: placeholderColor),
                              errorWidget: (_, __, ___) =>
                                  _fallback(mapHeight, placeholderColor),
                            )
                          : _fallback(mapHeight, placeholderColor),
                    ),
                  ),
                  if (!hasMapPreview)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color:
                            theme.videoPlayIconBackgroundColor ??
                            Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: theme.videoPlayIconColor ?? Colors.white,
                        size: 28,
                      ),
                    ),
                ],
              ),
            ),
            if (label != null && label!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label!,
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

  Widget _fallback(double height, Color color) => Container(
    height: height,
    width: double.infinity,
    color: color,
    alignment: Alignment.center,
    child: const Icon(Icons.map, color: Colors.white54, size: 48),
  );
}
