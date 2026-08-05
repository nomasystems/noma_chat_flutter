import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/chat_theme.dart';
import '../../utils/safe_url.dart';

/// Bubble decoration that renders the OpenGraph-style preview of a link
/// (image, title, description) above the underlying text bubble.
///
/// [url] is sender content — it arrives on the message `metadata`, which
/// the transport copies through verbatim — so the card is painted only
/// when that URL is an `http` / `https` address (see [webUrlOrNull]).
/// A card carrying any other scheme renders nothing at all: it cannot be
/// opened, and its title, description and image are chosen by whoever
/// sent it, so showing it would offer a tap target that lies about where
/// it goes.
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

  @override
  Widget build(BuildContext context) {
    final uri = webUrlOrNull(url);
    if (uri == null) return const SizedBox.shrink();
    final domain = uri.host;
    return Semantics(
      link: true,
      label: title ?? domain,
      child: GestureDetector(
        onTap: () {
          launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          ).catchError((Object _) => false);
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.linkPreviewBackgroundColor ?? Colors.grey.shade100,
            borderRadius:
                theme.linkPreviewBorderRadius ?? BorderRadius.circular(8),
            border: Border.all(
              color: theme.linkPreviewBorderColor ?? Colors.grey.shade300,
            ),
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
                            TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      domain,
                      style:
                          theme.linkPreviewDomainStyle ??
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
