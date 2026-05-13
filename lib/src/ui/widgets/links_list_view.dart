import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/url_detector.dart';
import 'empty_state.dart';

/// A single shared link with its origin metadata.
class SharedLink {
  const SharedLink({
    required this.url,
    required this.messageId,
    this.timestamp,
    this.senderId,
    this.contextSnippet,
  });

  final String url;
  final String messageId;
  final DateTime? timestamp;
  final String? senderId;

  /// Optional surrounding text from the original message — useful as preview.
  final String? contextSnippet;
}

/// Lists URLs extracted client-side from regular text messages. Designed for
/// the "Links" tab of [MediaGalleryPage], where the surface is intentionally
/// limited to messages already present in the local cache (no extra round trip).
class LinksListView extends StatelessWidget {
  const LinksListView({
    super.key,
    required this.messages,
    this.theme = ChatTheme.defaults,
    this.onTapLink,
  }) : precomputedLinks = null;

  /// Bypasses the on-the-fly URL extraction by accepting an already-built
  /// list of [SharedLink]s. Useful when the parent has already extracted them
  /// (e.g. to decide whether to render an empty state) and wants to avoid the
  /// duplicate work.
  const LinksListView.fromLinks({
    super.key,
    required List<SharedLink> links,
    this.theme = ChatTheme.defaults,
    this.onTapLink,
  })  : messages = const [],
        precomputedLinks = links;

  final List<ChatMessage> messages;
  final List<SharedLink>? precomputedLinks;
  final ChatTheme theme;
  final ValueChanged<SharedLink>? onTapLink;

  static List<SharedLink> extract(List<ChatMessage> messages) {
    final seen = <String>{};
    final out = <SharedLink>[];
    for (final msg in messages) {
      if (msg.isDeleted || msg.isSystem) continue;
      final text = msg.text;
      if (text == null || text.isEmpty) continue;
      final urls = UrlDetector.extractUrls(text);
      for (final url in urls) {
        if (!seen.add(url)) continue;
        out.add(SharedLink(
          url: url,
          messageId: msg.id,
          timestamp: msg.timestamp,
          senderId: msg.from,
          contextSnippet: text,
        ));
      }
    }
    out.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final links = precomputedLinks ?? extract(messages);
    if (links.isEmpty) {
      return EmptyState(
        icon: Icons.link_off,
        title: theme.l10n.galleryNoLinks,
        theme: theme,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: links.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final link = links[index];
        final subtitleParts = <String>[];
        if (link.timestamp != null) {
          subtitleParts.add(DateFormatter.formatRelative(
            link.timestamp!,
            l10n: theme.l10n,
          ));
        }
        if (link.senderId != null && link.senderId!.isNotEmpty) {
          subtitleParts.add(link.senderId!);
        }
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            foregroundColor: Colors.grey.shade700,
            child: const Icon(Icons.link),
          ),
          title: Text(
            link.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: subtitleParts.isEmpty
              ? null
              : Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
          onTap: onTapLink != null ? () => onTapLink!(link) : null,
        );
      },
    );
  }
}
