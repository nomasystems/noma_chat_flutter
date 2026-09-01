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
  /// `example.com/path`). This is only the shape gate: a bare host still has
  /// to pass [_looksLikeHost] before it counts as a link, which is what keeps
  /// `informe.pdf` out.
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

  /// Suffixes accepted as a top-level domain. Deliberately short: the common
  /// generic ones plus the country codes of the locales the SDK ships, which
  /// is what the messages in this product actually carry.
  ///
  /// A finite list is the whole point. The dotted-word shape is far more
  /// common in prose (`informe.pdf`, `notas.txt`, a full stop typed without
  /// the space after it) than a bare domain with an exotic suffix, and the
  /// two escapes below cover the domains this list misses.
  static final Set<String> _knownTlds =
      'com net org edu gov int mil info biz name pro eu io ai app dev me tv '
              'co cc gg xyz online site shop store blog cloud tech page link '
              'live news email digital agency studio design media art '
              'es cat gal eus fr de at ch it pt br uk us ca nl be ie se no dk '
              'fi pl cz gr ro hu mx ar cl ru jp cn in au nz za tr il ma'
          .split(' ')
          .toSet();

  /// Extra suffixes a host app wants treated as top-level domains, on top of
  /// [_knownTlds] — `UrlDetector.extraTlds.add('barcelona')`.
  ///
  /// Reach for it when your users routinely write bare domains under a
  /// suffix the list above does not carry. Entries are matched
  /// case-insensitively, so `'Barcelona'` and `'barcelona'` behave alike.
  static final Set<String> extraTlds = <String>{};

  static final RegExp _pathStart = RegExp(r'[/?#]');

  /// Whether a match is a link rather than a dotted word.
  ///
  /// A match with an explicit scheme always is. A bare one has to earn it:
  /// it starts with `www.`, or it carries a path, query or fragment, or its
  /// last label is a suffix [_knownTlds] or [extraTlds] recognises.
  static bool _looksLikeHost(String url) {
    if (_hasScheme.hasMatch(url)) return true;
    final lower = url.toLowerCase();
    if (lower.startsWith('www.')) return true;
    if (lower.contains(_pathStart)) return true;
    final lastDot = lower.lastIndexOf('.');
    if (lastDot < 0) return false;
    final tld = lower.substring(lastDot + 1);
    return _knownTlds.contains(tld) ||
        extraTlds.any((extra) => extra.toLowerCase() == tld);
  }

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
      .where(_looksLikeHost)
      .map(_normalize)
      .toList();

  static bool hasUrl(String text) => extractUrls(text).isNotEmpty;

  /// Same definition as [extractUrls], anchored at [index] instead of
  /// scanning: returns the URL that *starts exactly there*, or `null`.
  ///
  /// This is the hook a left-to-right parser needs, and it exists so that
  /// the message bubble, the link preview card and the room's "Links" list
  /// all answer "is this a link?" with one definition instead of three.
  /// Trailing punctuation is trimmed and the same minimum length and
  /// [_looksLikeHost] gate apply, so a string is a link in the bubble
  /// exactly when it is a link in the other two.
  static DetectedUrl? matchAt(String text, int index) {
    final match = urlPattern.matchAsPrefix(text, index);
    if (match == null) return null;
    if (_isEmailFragment(text, match.start, match.end)) return null;
    final raw = match.group(0)!;
    final trimmed = raw.replaceAll(_trailingPunct, '');
    if (trimmed.isEmpty || !_isLongEnough(trimmed)) return null;
    if (!_looksLikeHost(trimmed)) return null;
    return DetectedUrl(
      text: trimmed,
      url: _normalize(trimmed),
      end: index + trimmed.length,
    );
  }
}
