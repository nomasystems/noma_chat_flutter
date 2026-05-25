import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/markdown_parser.dart';
import '_bubble_metadata.dart';

/// Bubble that renders a plain or markdown-inlined text message with the
/// sender label, timestamp and receipt status.
class TextBubble extends StatelessWidget {
  const TextBubble({
    super.key,
    required this.text,
    required this.isOutgoing,
    this.timestamp,
    this.isEdited = false,
    this.editedByAdmin = false,
    this.adminSent = false,
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

  /// When `true`, replaces the standard "edited" hint with "edited by
  /// admin" so moderation actions are visible (but still subtle —
  /// same italic grey style as "edited", just longer label).
  final bool editedByAdmin;

  /// When `true`, appends a small "admin" pill to the meta row to mark
  /// messages composed from the admin panel. Distinct from `isEdited` —
  /// a brand-new admin send still flips this without needing a fake
  /// edit history.
  final bool adminSent;
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
        ? (theme.bubble.outgoingTextStyle ?? const TextStyle(fontSize: 15))
        : (theme.bubble.incomingTextStyle ?? const TextStyle(fontSize: 15));

    final editedHint = _resolveEditedHint();
    final metaRow = _buildMetaRow(editedHint);
    final metaWidth = _estimateMetaWidth(metaRow, editedHint);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyPreview != null) ...[replyPreview!, const SizedBox(height: 4)],
        if (metaRow != null)
          _buildTextWithMeta(context, textStyle, metaRow, metaWidth)
        else
          _buildTextOnly(context, textStyle),
        if (linkPreview != null) ...[const SizedBox(height: 6), linkPreview!],
      ],
    );
  }

  /// Resolves the "edited" hint once. When the edit came from an admin,
  /// suffix " · by admin" so the consumer always sees a single hint
  /// tag, never two. Cheap and avoids reflowing the meta row layout.
  String? _resolveEditedHint() {
    if (!isEdited) return null;
    return editedByAdmin
        ? '${theme.l10n.edited} · by admin'
        : theme.l10n.edited;
  }

  /// Builds the trailing metadata row (edited hint + admin pill +
  /// timestamp + status). Returns `null` when nothing would be drawn.
  Widget? _buildMetaRow(String? editedHint) {
    final hasTimestamp = timestamp != null || isEdited || adminSent;
    if (!hasTimestamp && statusWidget == null) return null;

    final timestampStyle = BubbleMetadataRow.resolveTimestampStyle(
      theme,
      isOutgoing,
    );

    // Subtle italic grey style shared by every admin-related sublabel
    // ("edited by admin", "admin"). Matches the existing "edited" hint
    // so the row reads uniformly. Theme `editedLabelTextStyle` is the
    // override for both — admin actions are not a separate visual
    // concept, they just borrow the same hint slot.
    final adminLabelStyle =
        theme.bubble.editedLabelStyle ??
        TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Colors.grey.shade500,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (editedHint != null)
          Padding(
            padding: EdgeInsets.only(
              right: (timestamp != null || adminSent) ? 2 : 0,
            ),
            child: Text(editedHint, style: adminLabelStyle),
          ),
        // Brand-new admin send (no edit history) — show a tiny "admin"
        // tag instead of "edited by admin". Skipped when `editedHint`
        // already carries the "by admin" suffix to avoid duplication.
        if (adminSent && !isEdited)
          Padding(
            padding: EdgeInsets.only(right: timestamp != null ? 2 : 0),
            child: Text('admin', style: adminLabelStyle),
          ),
        if (timestamp != null)
          Text(DateFormatter.formatTime(timestamp!), style: timestampStyle),
        if (statusWidget != null) ...[const SizedBox(width: 3), statusWidget!],
      ],
    );
  }

  /// Measures the metadata width to reserve space as an invisible
  /// trailing spacer. Conservative estimate: ~6px per char for the
  /// timestamp text plus icon space when a status widget is present.
  double _estimateMetaWidth(Widget? metaRow, String? editedHint) {
    if (metaRow == null) return 0;
    var chars = 0;
    if (editedHint != null) chars += editedHint.length + 1;
    if (adminSent && !isEdited) chars += 6;
    if (timestamp != null) chars += 5;
    return chars * 6.5 + (statusWidget != null ? 20 : 0) + 8;
  }

  TextStyle _resolveMentionStyle(BuildContext context) {
    return theme.markdown.mentionStyle ??
        TextStyle(
          color:
              theme.bubble.mentionColor ??
              (isOutgoing
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary),
          fontWeight: FontWeight.w600,
        );
  }

  List<InlineSpan> _markdownSpans(BuildContext context, TextStyle textStyle) {
    return parseMarkdown(
      text,
      baseStyle: textStyle,
      boldStyle: theme.markdown.boldStyle,
      italicStyle: theme.markdown.italicStyle,
      codeStyle: theme.markdown.codeStyle,
      strikethroughStyle: theme.markdown.strikethroughStyle,
      linkStyle: theme.markdown.linkStyle,
      mentionStyle: _resolveMentionStyle(context),
      onTapLink: onTapLink,
      onTapMention: onTapMention,
    );
  }

  Widget _buildTextWithMeta(
    BuildContext context,
    TextStyle textStyle,
    Widget metaRow,
    double metaWidth,
  ) {
    final spans = <InlineSpan>[
      ..._markdownSpans(context, textStyle),
      WidgetSpan(child: SizedBox(width: metaWidth, height: 1)),
    ];
    final textSpan = TextSpan(children: spans);
    return Stack(
      children: [
        if (enableSelection)
          SelectableText.rich(textSpan)
        else
          Text.rich(textSpan),
        Positioned(right: 0, bottom: 0, child: metaRow),
      ],
    );
  }

  Widget _buildTextOnly(BuildContext context, TextStyle textStyle) {
    final textSpan = TextSpan(children: _markdownSpans(context, textStyle));
    if (enableSelection) {
      return SelectableText.rich(textSpan);
    }
    return Text.rich(textSpan);
  }
}
