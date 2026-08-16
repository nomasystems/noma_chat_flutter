import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../controller/message_search_controller.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';

/// Instrumentation id of the [MessageSearchView] row for the message with id
/// [messageId].
String searchResultSemanticsId(String messageId) =>
    'chat_search_result_$messageId';

/// Full-text search UI for messages within a room, with debounced input and result tapping.
class MessageSearchView extends StatefulWidget {
  const MessageSearchView({
    super.key,
    required this.controller,
    required this.roomId,
    this.onMessageTap,
    this.theme = ChatTheme.defaults,
    this.senderNameResolver,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.minQueryLength = 2,
  }) : assert(minQueryLength >= 1, 'minQueryLength must be at least 1');

  final MessageSearchController controller;
  final String roomId;
  final void Function(String roomId, String messageId)? onMessageTap;
  final ChatTheme theme;
  final String Function(String userId)? senderNameResolver;
  final Duration debounceDuration;

  /// Minimum number of characters (after `trim()`) the input must contain
  /// before the search request is dispatched. Shorter queries clear any
  /// prior results without hitting the backend, mirroring WhatsApp's
  /// behaviour where a 1-letter search is suppressed as too broad. Pass
  /// `1` to revert to the legacy "fire on every keystroke" semantics.
  final int minQueryLength;

  @override
  State<MessageSearchView> createState() => _MessageSearchViewState();
}

class _MessageSearchViewState extends State<MessageSearchView> {
  final _textController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < widget.minQueryLength) {
      // Suppress the backend search and clear any prior results so stale
      // matches don't linger while the user is still typing.
      widget.controller.search('', widget.roomId);
      return;
    }
    _debounce = Timer(widget.debounceDuration, () {
      widget.controller.search(trimmed, widget.roomId);
    });
  }

  /// Stamps [radius] onto [border]'s shape without touching its colour or
  /// width. Borders that aren't `Outline`/`Underline` (a host's custom
  /// [InputBorder] subclass) don't expose a radius to stamp, so they pass
  /// through unchanged rather than being silently replaced.
  InputBorder _withRadius(InputBorder border, BorderRadius? radius) {
    if (radius == null) return border;
    return switch (border) {
      final OutlineInputBorder b => b.copyWith(borderRadius: radius),
      final UnderlineInputBorder b => b.copyWith(borderRadius: radius),
      _ => border,
    };
  }

  /// Per-state outline for the query field, given the [ambient] border the
  /// host's own `InputDecorationTheme` would have drawn in that state.
  ///
  /// Returns `null` — "leave the ambient decoration alone" — unless the host
  /// themed [ChatTheme.messageSearchFieldBorderColor]. Absent that, this
  /// degrades to [ambient] wholesale (shape, colour, width) rather than
  /// replacing it, stamping the themed radius on top when one is set — a
  /// radius is a shape tweak, not licence to repaint or reshape a border the
  /// host never asked to have touched.
  ///
  /// [focused] additionally distinguishes the focus ring from the idle
  /// border when the host's colour slot *is* set — that slot is one colour
  /// for every state, so without this the field loses its focus indicator
  /// (focused reads identical to enabled). The ring widens and, when the
  /// theme also carries a [ChatTheme.messageSearchFieldCursorColor] accent,
  /// tints towards it. A host that themes the ambient
  /// `InputDecorationTheme.focusedBorder` directly opts out of this
  /// heuristic — that explicit slot always wins verbatim.
  InputBorder? _fieldBorder(
    ChatTheme theme,
    InputBorder? ambient, {
    bool focused = false,
  }) {
    final color = theme.messageSearchFieldBorderColor;
    final radius = theme.messageSearchFieldBorderRadius;
    if (color == null) {
      if (ambient == null) return null;
      return _withRadius(ambient, radius);
    }
    if (focused && ambient != null) return _withRadius(ambient, radius);
    return OutlineInputBorder(
      borderRadius: radius ?? const BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(
        color: focused ? (theme.messageSearchFieldCursorColor ?? color) : color,
        width: focused ? 2 : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final ambient = InputDecorationTheme.of(context);
    final border =
        _fieldBorder(theme, ambient.border) ??
        OutlineInputBorder(
          borderRadius:
              theme.messageSearchFieldBorderRadius ??
              const BorderRadius.all(Radius.circular(4)),
          borderSide: const BorderSide(),
        );
    final enabledBorder = _fieldBorder(theme, ambient.enabledBorder);
    final focusedBorder = _fieldBorder(
      theme,
      ambient.focusedBorder,
      focused: true,
    );
    final fillColor = theme.messageSearchFieldFillColor;
    final iconColor = theme.messageSearchFieldIconColor;
    final content = Column(
      children: [
        Padding(
          // Match the horizontal/vertical rhythm used by RoomSearchBar
          // so the chat-list and in-room search look identical.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Semantics(
            identifier: 'chat_search_input',
            child: TextField(
              key: const ValueKey('chat_search_input'),
              controller: _textController,
              onChanged: _onQueryChanged,
              style: theme.messageSearchFieldTextStyle,
              cursorColor: theme.messageSearchFieldCursorColor,
              // Outlined style aligned with RoomSearchBar + the host app's
              // login / onboarding TextFields. Earlier "pill" treatment
              // (filled + rounded 24 + borderSide.none) was inconsistent
              // with the rest of the surface and felt out of place.
              decoration: InputDecoration(
                hintText: theme.l10nOf(context).searchMessages,
                hintStyle: theme.messageSearchFieldHintStyle,
                // `null`, not `false`: an explicit `false` overrides an
                // ambient `InputDecorationTheme.filled: true` and strips the
                // fill off a field the host's own theme fills everywhere else.
                filled: fillColor != null ? true : null,
                fillColor: fillColor,
                prefixIcon: Icon(Icons.search, size: 20, color: iconColor),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (_, value, __) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return Semantics(
                      identifier: 'chat_search_clear',
                      child: IconButton(
                        key: const ValueKey('chat_search_clear'),
                        icon: Icon(Icons.close, size: 18, color: iconColor),
                        tooltip: theme.l10nOf(context).clearText,
                        onPressed: () {
                          _textController.clear();
                          _onQueryChanged('');
                        },
                      ),
                    );
                  },
                ),
                // The catch-all fallback `InputDecorator` reaches for whenever
                // a more specific slot (enabled/focused/error/disabled) is
                // left null — degraded above to the ambient border (radius
                // stamped on top) unless the host themed a colour.
                border: border,
                enabledBorder: enabledBorder,
                focusedBorder: focusedBorder,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              if (widget.controller.isLoading &&
                  widget.controller.results.isEmpty) {
                return Center(
                  key: const ValueKey('chat_search_loading'),
                  child: Semantics(
                    identifier: 'chat_search_loading',
                    child: CircularProgressIndicator(
                      color:
                          theme.messageSearchProgressColor ??
                          theme.input.sendButtonColor,
                    ),
                  ),
                );
              }

              if (widget.controller.query.isNotEmpty &&
                  widget.controller.results.isEmpty &&
                  !widget.controller.isLoading) {
                return Center(
                  key: const ValueKey('chat_search_empty'),
                  child: Semantics(
                    identifier: 'chat_search_empty',
                    child: Text(
                      theme.l10nOf(context).noResults,
                      style:
                          theme.messageSearchEmptyTextStyle ??
                          theme.emptyStateTitleStyle ??
                          _defaultEmptyStyle,
                    ),
                  ),
                );
              }

              if (widget.controller.results.isEmpty) {
                return const SizedBox.shrink();
              }

              final results = _dedupeById(widget.controller.results);
              final snippetStyle =
                  theme.messageSearchResultSnippetStyle ?? _defaultSnippetStyle;
              final highlightStyle =
                  theme.messageSearchResultHighlightStyle ??
                  (theme.messageSearchResultSnippetStyle == null
                      ? _defaultHighlightStyle
                      : snippetStyle.merge(
                          const TextStyle(fontWeight: FontWeight.w700),
                        ));

              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final message = results[index];
                  final senderName = widget.senderNameResolver != null
                      ? widget.senderNameResolver!(message.from)
                      : message.from;
                  final now = DateTime.now();
                  final timeStr =
                      DateFormatter.isToday(message.timestamp, now: now)
                      ? DateFormatter.formatTime(message.timestamp)
                      : DateFormatter.formatSeparator(
                          message.timestamp,
                          now: now,
                          todayLabel: theme.l10nOf(context).today,
                          yesterdayLabel: theme.l10nOf(context).yesterday,
                        );
                  final rowId = searchResultSemanticsId(message.id);
                  return Semantics(
                    identifier: rowId,
                    child: ListTile(
                      key: ValueKey(rowId),
                      title: Text(
                        senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.messageSearchResultTitleStyle ??
                            _defaultTitleStyle,
                      ),
                      subtitle: Text.rich(
                        TextSpan(
                          children: _highlightSpans(
                            message.text ?? '',
                            widget.controller.query,
                            baseStyle: snippetStyle,
                            matchStyle: highlightStyle,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        timeStr,
                        style:
                            theme.messageSearchResultTimestampStyle ??
                            _defaultTimestampStyle,
                      ),
                      onTap: () =>
                          widget.onMessageTap?.call(widget.roomId, message.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    final background = theme.messageSearchBackgroundColor;
    if (background == null) return content;
    return ColoredBox(color: background, child: content);
  }
}

/// Baselines reproducing the look the view had before the
/// `messageSearch*` theme slots existed, so an unthemed host is
/// pixel-identical to the previous release.
const TextStyle _defaultTitleStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 14,
);
const TextStyle _defaultSnippetStyle = TextStyle(
  fontSize: 13,
  color: Color(0xFF757575),
);
const TextStyle _defaultHighlightStyle = TextStyle(
  fontSize: 13,
  color: Color(0xFF212121),
  fontWeight: FontWeight.w700,
);
const TextStyle _defaultTimestampStyle = TextStyle(
  fontSize: 11,
  color: Color(0xFF9E9E9E),
);
const TextStyle _defaultEmptyStyle = TextStyle(
  fontSize: 16,
  color: Color(0xFF9E9E9E),
);

/// Drops duplicate results by [ChatMessage.id], keeping the first
/// occurrence's position. A message can legitimately appear more than once
/// in [results] — e.g. the same underlying message re-indexed after being
/// forwarded, or overlapping pages from the backend's search endpoint —
/// and without this the list would render the identical row twice.
List<ChatMessage> _dedupeById(List<ChatMessage> results) {
  final seen = <String>{};
  final deduped = <ChatMessage>[];
  for (final message in results) {
    if (seen.add(message.id)) deduped.add(message);
  }
  return deduped;
}

List<TextSpan> _highlightSpans(
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
