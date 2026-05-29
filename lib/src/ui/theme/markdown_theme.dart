import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'markdown_theme.freezed.dart';

/// Theme for the inline-markdown styles applied by [parseMarkdown] inside
/// text bubbles. Each token type maps to a single [TextStyle] that
/// inherits from the bubble's base text style — only override the deltas
/// (color, weight, decoration) for best results.
///
/// Pass an instance to [ChatTheme] to override the matching flat fields;
/// pass nothing and the existing flat fields keep working unchanged
/// (back-compat).
@freezed
abstract class ChatMarkdownTheme with _$ChatMarkdownTheme {
  const factory ChatMarkdownTheme({
    /// Style applied to `*bold*` / `**bold**` tokens.
    TextStyle? boldStyle,

    /// Style applied to `_italic_` tokens.
    TextStyle? italicStyle,

    /// Style applied to inline `` `code` `` tokens. The default sets a
    /// monospace family and a subtle background.
    TextStyle? codeStyle,

    /// Style applied to `~~strikethrough~~` tokens.
    TextStyle? strikethroughStyle,

    /// Style applied to bare URLs (`http://...` / `https://...`).
    TextStyle? linkStyle,

    /// Style applied to `@mentions`. Falls back to [ChatBubbleTheme.mentionColor]
    /// when null.
    TextStyle? mentionStyle,
  }) = _ChatMarkdownTheme;
}
