import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/chat_theme.dart';

/// Bubble decoration that renders the OpenGraph-style preview of a link
/// (image, title, description) above the underlying text bubble.
class LinkPreviewBubble extends StatelessWidget {
  const LinkPreviewBubble({
    super.key,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final bool isOutgoing;
  final ChatTheme theme;

  String get _domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: title ?? _domain,
      child: GestureDetector(
      onTap: () {
        try {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.linkPreviewBackgroundColor ?? Colors.grey.shade100,
          borderRadius:
              theme.linkPreviewBorderRadius ?? BorderRadius.circular(8),
          border: Border.all(color: theme.linkPreviewBorderColor ?? Colors.grey.shade300),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.linkPreviewTitleStyle ??
                          const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                    ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.linkPreviewDescriptionStyle ??
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _domain,
                    style: theme.linkPreviewDomainStyle ??
                        TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
