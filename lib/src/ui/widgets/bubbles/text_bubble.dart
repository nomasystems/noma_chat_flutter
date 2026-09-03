import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/text_selection_menu.dart';
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
    this.emojiOnly = false,
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

  /// Renders the body through `SelectableText.rich` so it can be selected
  /// and copied.
  ///
  /// Silently yields for a message whose markdown produced a tap target:
  /// `SelectableText.rich` routes every pointer event to its selection
  /// gesture detector and never dispatches `TextSpan.recognizer`, so a
  /// selectable bubble paints live-looking links and mentions that can't
  /// fire. Those bubbles fall back to `Text.rich` — a dead link is worse
  /// than an unselectable one, and it is decided per message, so bubbles
  /// with no tap target keep selection.
  final bool enableSelection;

  /// Paints the body as a message that is nothing but emoji: large, with
  /// the timestamp and ticks moved out from under the glyphs to a line of
  /// their own underneath.
  ///
  /// The caller decides, not this widget: whether a body qualifies depends
  /// on things only [MessageBubble] knows — a quote, a link preview card or
  /// a forward header all keep the ordinary bubble, because the enlarged
  /// glyph is only bubble-less when there is nothing else in the bubble to
  /// hold. See `isEmojiOnlyText`.
  final bool emojiOnly;

  /// Opens the tapped URL. `null` leaves link spans styled but inert — see
  /// [parseMarkdown] for how each inline role treats a missing handler.
  final ValueChanged<String>? onTapLink;

  /// Opens the tapped `@mention`. `null` renders mentions as plain body
  /// text instead of painting an affordance nothing answers.
  final ValueChanged<String>? onTapMention;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    final textStyle = emojiOnly
        ? theme.emojiOnlyTextStyle(isOutgoing: isOutgoing)
        : (isOutgoing
              ? (theme.bubble.outgoingTextStyle ??
                    const TextStyle(fontSize: 15))
              : (theme.bubble.incomingTextStyle ??
                    const TextStyle(fontSize: 15)));

    final editedHint = _resolveEditedHint(context);
    final metaRow = _buildMetaRow(context, editedHint);
    final metaWidth = _estimateMetaWidth(context, metaRow, editedHint);

    // With no bubble behind it there is nothing to tuck the meta row into:
    // overlaying it would put the time on top of the glyph. It goes on its
    // own line underneath instead, which is also where WhatsApp puts it.
    if (emojiOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: textStyle),
          if (metaRow != null) ...[const SizedBox(height: 2), metaRow],
        ],
      );
    }

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
  String? _resolveEditedHint(BuildContext context) {
    if (!isEdited) return null;
    return editedByAdmin
        ? '${theme.l10nOf(context).edited} · by admin'
        : theme.l10nOf(context).edited;
  }

  /// Builds the trailing metadata row (edited hint + admin pill +
  /// timestamp + status). Returns `null` when nothing would be drawn.
  Widget? _buildMetaRow(BuildContext context, String? editedHint) {
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
            child: Text(theme.l10nOf(context).admin, style: adminLabelStyle),
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
  double _estimateMetaWidth(
    BuildContext context,
    Widget? metaRow,
    String? editedHint,
  ) {
    if (metaRow == null) return 0;
    var chars = 0;
    if (editedHint != null) chars += editedHint.length + 1;
    if (adminSent && !isEdited) chars += theme.l10nOf(context).admin.length + 1;
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

  /// Wraps [spans] in the widget that can actually render them: selection
  /// when it was asked for AND nothing in the message needs a gesture
  /// recognizer, `Text.rich` otherwise. See [enableSelection].
  Widget _buildRichText(List<InlineSpan> spans) {
    final textSpan = TextSpan(children: spans);
    final selectable =
        enableSelection &&
        !spans.any((s) => s is TextSpan && s.recognizer != null);
    return selectable
        ? SelectableText.rich(
            textSpan,
            contextMenuBuilder: buildTextSelectionMenu,
          )
        : Text.rich(textSpan);
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
    return Stack(
      children: [
        _buildRichText(spans),
        Positioned(right: 0, bottom: 0, child: metaRow),
      ],
    );
  }

  Widget _buildTextOnly(BuildContext context, TextStyle textStyle) {
    return _buildRichText(_markdownSpans(context, textStyle));
  }
}
