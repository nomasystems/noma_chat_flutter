import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Inline markdown roles recognised by [parseMarkdown].
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
        return TextSpan(
          text: span.text,
          style:
              mentionStyle ??
              baseStyle.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
          recognizer: onTapMention != null
              ? (TapGestureRecognizer()
                  ..onTap = () => onTapMention(span.mentionUserId ?? span.text))
              : null,
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
        final innerSpans = _parse(inner);
        for (final s in innerSpans) {
          if (s.style == MarkdownStyle.italic) {
            spans.add(MarkdownSpan(s.text, MarkdownStyle.bold));
          } else {
            spans.add(MarkdownSpan(s.text, MarkdownStyle.bold));
          }
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

    // URL: http:// or https://
    if (_isUrlStart(text, i)) {
      final end = _findUrlEnd(text, i);
      flushPlain();
      final url = text.substring(i, end);
      spans.add(MarkdownSpan(url, MarkdownStyle.link, url: url));
      i = end;
      continue;
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

bool _isUrlStart(String text, int i) {
  return text.startsWith('https://', i) || text.startsWith('http://', i);
}

int _findUrlEnd(String text, int start) {
  var i = start;
  while (i < text.length && !_isWhitespace(text[i])) {
    i++;
  }
  return i;
}

int _findMentionEnd(String text, int start) {
  var i = start;
  while (i < text.length && _isWordChar(text[i])) {
    i++;
  }
  return i;
}

bool _isWhitespace(String ch) {
  return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
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
