import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';
import '_bubble_metadata.dart';

/// Name the tap-to-open target of the location row for [messageId] answers
/// to.
///
/// Lives inside a [MessageBubble], so the `ValueKey` half is the reachable
/// one and the `identifier` half only reaches a native dump when the bubble
/// is rendered standalone.
String locationBubbleSemanticsId(String messageId) =>
    'chat_message_${messageId}_location';

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
    this.messageId,
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

  /// Id of the message this row renders. Names the tap-to-open target
  /// ([locationBubbleSemanticsId]); `null` (default) leaves it unnamed
  /// rather than publishing a name two rows could answer to.
  final String? messageId;

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

    final id = messageId == null ? null : locationBubbleSemanticsId(messageId!);
    return Semantics(
      key: id == null ? null : ValueKey(id),
      identifier: id,
      label: label ?? theme.l10nOf(context).locationMessage,
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

  Widget _fallback(double height, Color color) => Container(
    height: height,
    width: double.infinity,
    color: color,
    alignment: Alignment.center,
    child: const Icon(Icons.map, color: Colors.white54, size: 48),
  );
}
