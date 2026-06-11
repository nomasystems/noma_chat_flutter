class UrlDetector {
  const UrlDetector._();

  /// Matches either an explicitly-schemed URL (`https://…`, `http://…`) or a
  /// bare host that looks like a domain (`www.example.com`,
  /// `example.com/path`). The bare-host branch requires at least one dot and a
  /// 2+ letter TLD so plain prose like `end.Then` is not picked up.
  static final RegExp urlPattern = RegExp(
    r'(?:https?://[^\s<>)\]}>]+'
    r'|(?:www\.)?[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*'
    r'\.[a-zA-Z]{2,}(?:[/?#][^\s<>)\]}>]*)?)',
  );

  static final RegExp _trailingPunct = RegExp(r'[.,;:!?]+$');

  static final RegExp _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  /// Prepends `https://` to a matched URL that has no scheme so downstream
  /// consumers (`Uri.parse`, the preview fetcher, `launchUrl`) always receive
  /// an absolute URL.
  static String _normalize(String url) =>
      _hasScheme.hasMatch(url) ? url : 'https://$url';

  static List<String> extractUrls(String text) => urlPattern
      .allMatches(text)
      .map((m) => m.group(0)!.replaceAll(_trailingPunct, ''))
      .where((url) => url.length > 8)
      .map(_normalize)
      .toList();

  static bool hasUrl(String text) => extractUrls(text).isNotEmpty;
}
