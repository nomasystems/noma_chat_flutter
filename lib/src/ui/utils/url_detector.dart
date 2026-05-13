class UrlDetector {
  const UrlDetector._();

  static final RegExp urlPattern = RegExp(r'https?://[^\s<>)\]}>]+');

  static final RegExp _trailingPunct = RegExp(r'[.,;:!?]+$');

  static List<String> extractUrls(String text) => urlPattern
      .allMatches(text)
      .map((m) => m.group(0)!.replaceAll(_trailingPunct, ''))
      .where((url) => url.length > 8)
      .toList();

  static bool hasUrl(String text) => extractUrls(text).isNotEmpty;
}
