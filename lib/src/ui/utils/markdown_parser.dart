import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'url_detector.dart';

/// Inline markdown roles recognised by [parseMarkdown].
///
/// **Supported syntax (inline only):**
///
/// * `*bold*` and `**bold**`
/// * `_italic_` (mid-word italics intentionally do not match)
/// * `~~strikethrough~~`
/// * `` `code` ``
/// * URLs, with or without a scheme — `https://example.com` and
///   `www.example.com` / `example.com/path` alike, recognised with the very
///   same definition `UrlDetector` uses for the link preview card and the
///   room's "Links" list
/// * email addresses (`someone@example.com`), linked as `mailto:`
/// * international phone numbers in `+` form (`+34655000011`), linked as
///   `tel:`
/// * `@mentions` of the form `@username`
///
/// **Not supported (rendered verbatim):**
///
/// * Markdown link syntax `[label](url)` — type the URL directly instead.
/// * Block-level features: headings, lists, blockquotes, fences.
/// * HTML, footnotes, tables, images.
///
/// The chat composer is single-line, inline-oriented, so block markdown is
/// outside the scope on purpose.
enum MarkdownStyle { plain, bold, italic, code, strikethrough, link, mention }

/// One contiguous slice of text emitted by [parseMarkdown], carrying its
/// [style] and (for links/mentions) the target URL or user id.
class MarkdownSpan {
  final String text;
  final MarkdownStyle style;
  final String? url;
  final String? mentionUserId;

  const MarkdownSpan(this.text, this.style, {this.url, this.mentionUserId});
}

/// Splits [text] into styled [TextSpan]s according to [MarkdownStyle].
///
/// **Tap targets follow their handler.** A URL is painted blue and
/// underlined — the universal "this is tappable" affordance — and carries a
/// recognizer only when [onTapLink] is supplied; `ChatView` always supplies
/// one, so links are live by default. A `@mention` is the opposite case:
/// opening a profile is host navigation the package cannot guess, so
/// without [onTapMention] the mention renders as plain body text —
/// [mentionStyle] and the built-in colour/weight are skipped entirely —
/// rather than advertising a control that does nothing. Wire
/// [onTapMention] to get the mention style and the recognizer together.
List<TextSpan> parseMarkdown(
  String text, {
  required TextStyle baseStyle,
  TextStyle? boldStyle,
  TextStyle? italicStyle,
  TextStyle? codeStyle,
  TextStyle? strikethroughStyle,
  TextStyle? linkStyle,
  TextStyle? mentionStyle,
  ValueChanged<String>? onTapLink,
  ValueChanged<String>? onTapMention,
}) {
  final spans = _parse(text);
  return spans.map((span) {
    switch (span.style) {
      case MarkdownStyle.bold:
        return TextSpan(
          text: span.text,
          style: boldStyle ?? baseStyle.copyWith(fontWeight: FontWeight.bold),
        );
      case MarkdownStyle.italic:
        return TextSpan(
          text: span.text,
          style: italicStyle ?? baseStyle.copyWith(fontStyle: FontStyle.italic),
        );
      case MarkdownStyle.code:
        return TextSpan(
          text: span.text,
          style:
              codeStyle ??
              baseStyle.copyWith(
                fontFamily: 'monospace',
                backgroundColor: Colors.grey.shade200,
              ),
        );
      case MarkdownStyle.strikethrough:
        return TextSpan(
          text: span.text,
          style:
              strikethroughStyle ??
              baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        );
      case MarkdownStyle.link:
        return TextSpan(
          text: span.text,
          style:
              linkStyle ??
              baseStyle.copyWith(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
          recognizer: onTapLink != null
              ? (TapGestureRecognizer()
                  ..onTap = () => onTapLink(span.url ?? span.text))
              : null,
        );
      case MarkdownStyle.mention:
        if (onTapMention == null) {
          return TextSpan(text: span.text, style: baseStyle);
        }
        return TextSpan(
          text: span.text,
          style:
              mentionStyle ??
              baseStyle.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onTapMention(span.mentionUserId ?? span.text),
        );
      case MarkdownStyle.plain:
        return TextSpan(text: span.text, style: baseStyle);
    }
  }).toList();
}

List<MarkdownSpan> _parse(String text) {
  if (text.isEmpty) return [];

  final spans = <MarkdownSpan>[];
  final buffer = StringBuffer();
  var i = 0;

  void flushPlain() {
    if (buffer.isNotEmpty) {
      spans.add(MarkdownSpan(buffer.toString(), MarkdownStyle.plain));
      buffer.clear();
    }
  }

  while (i < text.length) {
    // Inline code: `...`
    if (text[i] == '`') {
      final end = text.indexOf('`', i + 1);
      if (end != -1) {
        flushPlain();
        spans.add(MarkdownSpan(text.substring(i + 1, end), MarkdownStyle.code));
        i = end + 1;
        continue;
      }
    }

    // Bold: **...**
    if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
      final end = text.indexOf('**', i + 2);
      if (end != -1) {
        flushPlain();
        final inner = text.substring(i + 2, end);
        for (final s in _parse(inner)) {
          spans.add(MarkdownSpan(s.text, MarkdownStyle.bold));
        }
        i = end + 2;
        continue;
      }
    }

    // Strikethrough: ~~...~~
    if (i + 1 < text.length && text[i] == '~' && text[i + 1] == '~') {
      final end = text.indexOf('~~', i + 2);
      if (end != -1) {
        flushPlain();
        spans.add(
          MarkdownSpan(text.substring(i + 2, end), MarkdownStyle.strikethrough),
        );
        i = end + 2;
        continue;
      }
    }

    // Italic: *...*
    if (text[i] == '*') {
      final end = text.indexOf('*', i + 1);
      if (end != -1) {
        flushPlain();
        spans.add(
          MarkdownSpan(text.substring(i + 1, end), MarkdownStyle.italic),
        );
        i = end + 1;
        continue;
      }
    }

    // Email, before both the URL and the mention branches on purpose.
    // Before the URL branch because the local part of `maria.jose@…` is
    // itself a valid bare host, and before the mention branch because the
    // loop would otherwise reach the `@` of `chiara@example.com` and eat
    // `@example` as a mention of a user called "example".
    if (_isTokenStart(text, i)) {
      final email = _emailPattern.matchAsPrefix(text, i);
      if (email != null) {
        final address = email.group(0)!;
        flushPlain();
        spans.add(
          MarkdownSpan(address, MarkdownStyle.link, url: 'mailto:$address'),
        );
        i = email.end;
        continue;
      }

      // URL: schemed or bare host, per `UrlDetector`.
      final url = UrlDetector.matchAt(text, i);
      if (url != null) {
        flushPlain();
        spans.add(MarkdownSpan(url.text, MarkdownStyle.link, url: url.url));
        i = url.end;
        continue;
      }

      // Phone: `+` and 8-15 digits, optionally grouped. Deliberately the
      // narrowest of the three — without the leading `+` a run of digits
      // is far more often a date, a price or a plan size than a number
      // anybody wants to dial.
      final phone = _phonePattern.matchAsPrefix(text, i);
      if (phone != null) {
        final number = phone.group(0)!;
        flushPlain();
        spans.add(
          MarkdownSpan(
            number,
            MarkdownStyle.link,
            url: 'tel:${number.replaceAll(_phoneSeparators, '')}',
          ),
        );
        i = phone.end;
        continue;
      }
    }

    // @mention: @ followed by word chars
    if (text[i] == '@' && i + 1 < text.length && _isWordChar(text[i + 1])) {
      final end = _findMentionEnd(text, i + 1);
      flushPlain();
      final mentionText = text.substring(i, end);
      final userId = text.substring(i + 1, end);
      spans.add(
        MarkdownSpan(mentionText, MarkdownStyle.mention, mentionUserId: userId),
      );
      i = end;
      continue;
    }

    buffer.write(text[i]);
    i++;
  }

  flushPlain();
  return spans;
}

final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?'
  r'(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}',
);

final RegExp _phonePattern = RegExp(r'\+[0-9]([ \-.]?[0-9]){7,14}');

final RegExp _phoneSeparators = RegExp(r'[ \-.]');

final RegExp _tokenTail = RegExp(r'[A-Za-z0-9._%+\-@/]');

/// Whether position [i] can begin a link, an email or a phone number.
///
/// The scan is left to right, so a candidate that failed at the start of a
/// word must not be retried one character in: without this, `informe.pdf`
/// failing as a whole would be re-offered as `nforme.pdf`, and the local
/// part of an address that failed would be re-offered from its second
/// letter. A token starts at the beginning of the string or right after
/// something that is not part of one.
bool _isTokenStart(String text, int i) {
  if (i == 0) return true;
  return !_tokenTail.hasMatch(text[i - 1]);
}

int _findMentionEnd(String text, int start) {
  var i = start;
  while (i < text.length && _isWordChar(text[i])) {
    i++;
  }
  return i;
}

bool _isWordChar(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      code == 0x5F || // _
      code == 0x2D || // -
      code == 0x2E; // .
}
