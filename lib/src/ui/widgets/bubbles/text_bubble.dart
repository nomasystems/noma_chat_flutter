import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/markdown_parser.dart';

/// Bubble that renders a plain or markdown-inlined text message with the
/// sender label, timestamp and receipt status.
class TextBubble extends StatelessWidget {
  const TextBubble({
    super.key,
    required this.text,
    required this.isOutgoing,
    this.timestamp,
    this.isEdited = false,
    this.theme = ChatTheme.defaults,
    this.replyPreview,
    this.linkPreview,
    this.enableSelection = true,
    this.onTapLink,
    this.onTapMention,
    this.statusWidget,
  });

  final String text;
  final bool isOutgoing;
  final DateTime? timestamp;
  final bool isEdited;
  final ChatTheme theme;
  final Widget? replyPreview;
  final Widget? linkPreview;
  final bool enableSelection;
  final ValueChanged<String>? onTapLink;
  final ValueChanged<String>? onTapMention;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    final textStyle = isOutgoing
        ? (theme.outgoingTextStyle ?? const TextStyle(fontSize: 15))
        : (theme.incomingTextStyle ?? const TextStyle(fontSize: 15));

    final timestampStyle = (isOutgoing
            ? theme.outgoingTimestampTextStyle
            : theme.incomingTimestampTextStyle) ??
        theme.timestampTextStyle ??
        TextStyle(fontSize: 11, color: Colors.grey.shade600);

    final hasTimestamp = timestamp != null || isEdited;

    // Build the trailing metadata (time + status)
    Widget? metaRow;
    if (hasTimestamp || statusWidget != null) {
      metaRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEdited)
            Padding(
              padding: EdgeInsets.only(right: timestamp != null ? 2 : 0),
              child: Text(
                theme.l10n.edited,
                style: theme.editedLabelTextStyle ??
                    TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade500,
                    ),
              ),
            ),
          if (timestamp != null)
            Text(DateFormatter.formatTime(timestamp!), style: timestampStyle),
          if (statusWidget != null) ...[
            const SizedBox(width: 3),
            statusWidget!,
          ],
        ],
      );
    }

    // Measure the metadata width to reserve space as an invisible trailing spacer.
    // We use a conservative estimate: ~6px per char for timestamp + icon space.
    double metaWidth = 0;
    if (metaRow != null) {
      var chars = 0;
      if (isEdited) chars += theme.l10n.edited.length + 1;
      if (timestamp != null) chars += 5; // "HH:MM"
      metaWidth = chars * 6.5 + (statusWidget != null ? 20 : 0) + 8;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyPreview != null) ...[replyPreview!, const SizedBox(height: 4)],
        if (metaRow != null)
          Stack(
            children: [
              // Text with invisible trailing spacer for the timestamp
              enableSelection
                  ? SelectableText.rich(
                      TextSpan(
                        children: [
                          ...parseMarkdown(
                            text,
                            baseStyle: textStyle,
                            boldStyle: theme.markdownBoldStyle,
                            italicStyle: theme.markdownItalicStyle,
                            codeStyle: theme.markdownCodeStyle,
                            strikethroughStyle:
                                theme.markdownStrikethroughStyle,
                            linkStyle: theme.markdownLinkStyle,
                            mentionStyle: theme.markdownMentionStyle,
                            onTapLink: onTapLink,
                            onTapMention: onTapMention,
                          ),
                          WidgetSpan(
                            child: SizedBox(width: metaWidth, height: 1),
                          ),
                        ],
                      ),
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          ...parseMarkdown(
                            text,
                            baseStyle: textStyle,
                            boldStyle: theme.markdownBoldStyle,
                            italicStyle: theme.markdownItalicStyle,
                            codeStyle: theme.markdownCodeStyle,
                            strikethroughStyle:
                                theme.markdownStrikethroughStyle,
                            linkStyle: theme.markdownLinkStyle,
                            mentionStyle: theme.markdownMentionStyle,
                            onTapLink: onTapLink,
                            onTapMention: onTapMention,
                          ),
                          WidgetSpan(
                            child: SizedBox(width: metaWidth, height: 1),
                          ),
                        ],
                      ),
                    ),
              // Timestamp + status positioned at bottom-right
              Positioned(
                right: 0,
                bottom: 0,
                child: metaRow,
              ),
            ],
          )
        else if (enableSelection)
          SelectableText.rich(
            TextSpan(
              children: parseMarkdown(
                text,
                baseStyle: textStyle,
                boldStyle: theme.markdownBoldStyle,
                italicStyle: theme.markdownItalicStyle,
                codeStyle: theme.markdownCodeStyle,
                strikethroughStyle: theme.markdownStrikethroughStyle,
                linkStyle: theme.markdownLinkStyle,
                mentionStyle: theme.markdownMentionStyle,
                onTapLink: onTapLink,
                onTapMention: onTapMention,
              ),
            ),
          )
        else
          Text.rich(
            TextSpan(
              children: parseMarkdown(
                text,
                baseStyle: textStyle,
                boldStyle: theme.markdownBoldStyle,
                italicStyle: theme.markdownItalicStyle,
                codeStyle: theme.markdownCodeStyle,
                strikethroughStyle: theme.markdownStrikethroughStyle,
                linkStyle: theme.markdownLinkStyle,
                mentionStyle: theme.markdownMentionStyle,
                onTapLink: onTapLink,
                onTapMention: onTapMention,
              ),
            ),
          ),
        if (linkPreview != null) ...[const SizedBox(height: 6), linkPreview!],
      ],
    );
  }
}
