/// Open Graph / oEmbed-like metadata extracted from a URL. The chat composer
/// fetches it on the fly while the user types and embeds it in the outgoing
/// message so the receiver renders the same preview without re-fetching.
class LinkPreviewMetadata {
  const LinkPreviewMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  bool get hasContent =>
      (title?.isNotEmpty ?? false) ||
      (description?.isNotEmpty ?? false) ||
      (imageUrl?.isNotEmpty ?? false);

  Map<String, dynamic> toMessageMetadata() => {
    'linkUrl': url,
    if (title != null) 'linkTitle': title,
    if (description != null) 'linkDescription': description,
    if (imageUrl != null) 'linkImage': imageUrl,
  };
}
