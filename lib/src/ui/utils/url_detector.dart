/// One URL found inside a longer string: the slice as the sender typed it,
/// where it ends, and the absolute form to hand a launcher.
class DetectedUrl {
  /// The matched slice, verbatim and with no trailing punctuation — what
  /// the bubble paints.
  final String text;

  /// [text] made absolute (`https://` prepended when it had no scheme) —
  /// what the tap handler receives.
  final String url;

  /// Index just past [text] in the string it was found in.
  final int end;

  const DetectedUrl({required this.text, required this.url, required this.end});
}

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

  /// The minimum length a match has to reach to count as a link. Cheap
  /// defence against a two-letter word followed by a two-letter "TLD".
  static bool _isLongEnough(String url) => url.length > 8;

  /// Whether a match at `[start, end)` of [text] is really a piece of an
  /// email address rather than a link of its own.
  ///
  /// Both halves of `maria.jose@example.com` match the bare-host branch on
  /// their own — the local part because a dotted word with a 4-letter tail
  /// looks exactly like a domain, and the domain because it is one. Neither
  /// is a page: linkifying them fetches a preview card for `example.com`
  /// under a message that was only giving out an address, and lists it in
  /// the room's "Links".
  static bool _isEmailFragment(String text, int start, int end) {
    if (start > 0 && text[start - 1] == '@') return true;
    if (end < text.length && text[end] == '@') return true;
    return false;
  }

  static List<String> extractUrls(String text) => urlPattern
      .allMatches(text)
      .where((m) => !_isEmailFragment(text, m.start, m.end))
      .map((m) => m.group(0)!.replaceAll(_trailingPunct, ''))
      .where(_isLongEnough)
      .map(_normalize)
      .toList();

  static bool hasUrl(String text) => extractUrls(text).isNotEmpty;

  /// Same definition as [extractUrls], anchored at [index] instead of
  /// scanning: returns the URL that *starts exactly there*, or `null`.
  ///
  /// This is the hook a left-to-right parser needs, and it exists so that
  /// the message bubble, the link preview card and the room's "Links" list
  /// all answer "is this a link?" with one definition instead of three.
  /// Trailing punctuation is trimmed and the same minimum length applies,
  /// so a string is a link in the bubble exactly when it is a link in the
  /// other two.
  static DetectedUrl? matchAt(String text, int index) {
    final match = urlPattern.matchAsPrefix(text, index);
    if (match == null) return null;
    if (_isEmailFragment(text, match.start, match.end)) return null;
    final raw = match.group(0)!;
    final trimmed = raw.replaceAll(_trailingPunct, '');
    if (trimmed.isEmpty || !_isLongEnough(trimmed)) return null;
    return DetectedUrl(
      text: trimmed,
      url: _normalize(trimmed),
      end: index + trimmed.length,
    );
  }
}
