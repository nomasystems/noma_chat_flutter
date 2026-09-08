import 'package:flutter/painting.dart';

/// Splits [text] into spans so that every occurrence of [query] carries
/// [matchStyle] and everything around it carries [baseStyle].
///
/// Matching is case-insensitive and literal — no regular expression, so a
/// query with `.`, `(` or `*` in it highlights those characters instead of
/// throwing. An empty [query] or [text] yields the text as one plain span, so
/// a caller never has to special-case "nothing typed yet".
///
/// The in-room message search has always highlighted its results this way.
/// It is public because a host builds rows of its own — a chat list telling
/// the reader WHY a room matched, for one — and a second implementation of
/// the same highlight is a second thing to keep in step with the theme.
List<TextSpan> chatHighlightSpans(
  String text,
  String query, {
  required TextStyle baseStyle,
  required TextStyle matchStyle,
}) {
  if (query.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final spans = <TextSpan>[];
  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  var cursor = 0;
  while (cursor < text.length) {
    final matchStart = lowerText.indexOf(lowerQuery, cursor);
    if (matchStart == -1) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
      break;
    }
    if (matchStart > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, matchStart), style: baseStyle),
      );
    }
    final matchEnd = matchStart + query.length;
    spans.add(
      TextSpan(text: text.substring(matchStart, matchEnd), style: matchStyle),
    );
    cursor = matchEnd;
  }
  return spans;
}
