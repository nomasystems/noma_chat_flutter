import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../controller/message_search_controller.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/highlight_spans.dart';
import '../utils/text_selection_menu.dart';

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
    this.autofocus = true,
    this.currentUserId,
    this.emptyPromptText,
    this.tooShortPromptText,
    this.resultCountLabelBuilder,
    this.showResultNavigation = true,
  }) : assert(minQueryLength >= 1, 'minQueryLength must be at least 1');

  final MessageSearchController controller;
  final String roomId;
  final void Function(String roomId, String messageId)? onMessageTap;
  final ChatTheme theme;
  final String Function(String userId)? senderNameResolver;
  final Duration debounceDuration;

  /// Focuses the query field on mount so the keyboard is already up when the
  /// screen opens — a search screen that needs a tap before it can be typed
  /// into reads as broken. Set `false` to open the screen unfocused.
  final bool autofocus;

  /// The local user's id. Results they wrote are labelled with the
  /// localized "You" instead of their own name, matching every other
  /// self-attribution in the SDK. When `null`, own results are labelled
  /// like anyone else's.
  final String? currentUserId;

  /// Copy for the initial state, before anything has been typed. Defaults
  /// to `ChatUiLocalizations.searchPromptEmpty` in the ambient locale.
  final String? emptyPromptText;

  /// Copy for the state where something has been typed but it is still
  /// shorter than [minQueryLength]. Defaults to
  /// `ChatUiLocalizations.searchPromptTooShort`, which names the minimum.
  final String? tooShortPromptText;

  /// Builds the header line above the results ("2 results"). Defaults to
  /// `ChatUiLocalizations.searchResultCount`, which picks the singular or
  /// plural template of the ambient locale.
  final String Function(int count)? resultCountLabelBuilder;

  /// Shows the previous / next arrows next to the result count, which walk
  /// the result list and re-fire [onMessageTap] for each step — the way
  /// WhatsApp steps a user through matches without making them aim at rows.
  final bool showResultNavigation;

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
  final _focusNode = FocusNode();
  Timer? _debounce;

  // Which result the arrows are parked on. Reset whenever the result set
  // changes underneath them, so "next" never steps off a stale index.
  int _focusedIndex = 0;
  String _focusedForQuery = '';

  bool _tooShort = false;

  @override
  void didUpdateWidget(covariant MessageSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.minQueryLength == oldWidget.minQueryLength) return;
    final trimmed = _textController.text.trim();
    _tooShort = trimmed.isNotEmpty && trimmed.length < widget.minQueryLength;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < widget.minQueryLength) {
      // Suppress the backend search and clear any prior results so stale
      // matches don't linger while the user is still typing.
      _setTooShort(trimmed.isNotEmpty);
      widget.controller.search('', widget.roomId);
      return;
    }
    _setTooShort(false);
    _debounce = Timer(widget.debounceDuration, () {
      widget.controller.search(trimmed, widget.roomId);
    });
  }

  void _setTooShort(bool value) {
    if (_tooShort == value || !mounted) return;
    setState(() => _tooShort = value);
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

  /// Keeps the arrows' cursor inside the current result set: a new query
  /// parks it back on the first match, a shrunken set clamps it.
  void _syncFocusedIndex(int length) {
    final query = widget.controller.query;
    if (query != _focusedForQuery) {
      _focusedForQuery = query;
      _focusedIndex = 0;
      return;
    }
    if (_focusedIndex >= length) _focusedIndex = length - 1;
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  void _stepFocus(int delta, List<ChatMessage> results) {
    final next = _focusedIndex + delta;
    if (next < 0 || next >= results.length) return;
    setState(() => _focusedIndex = next);
    widget.onMessageTap?.call(widget.roomId, results[next].id);
  }

  /// The name a result row is titled with — the localized "You" for the
  /// local user's own messages, the resolved display name otherwise.
  String _senderLabelFor(BuildContext context, ChatMessage message) {
    final me = widget.currentUserId;
    if (me != null && message.from == me) {
      return widget.theme.l10nOf(context).you;
    }
    final resolve = widget.senderNameResolver;
    return resolve != null ? resolve(message.from) : message.from;
  }

  Widget _buildResultsHeader(BuildContext context, List<ChatMessage> results) {
    final theme = widget.theme;
    final label =
        widget.resultCountLabelBuilder?.call(results.length) ??
        theme.l10nOf(context).searchResultCount(results.length);
    final iconColor = theme.messageSearchFieldIconColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              identifier: 'chat_search_result_count',
              child: Text(
                label,
                key: const ValueKey('chat_search_result_count'),
                style:
                    theme.messageSearchResultTimestampStyle ??
                    _defaultCountStyle,
              ),
            ),
          ),
          if (widget.showResultNavigation) ...[
            Semantics(
              identifier: 'chat_search_prev',
              child: IconButton(
                key: const ValueKey('chat_search_prev'),
                icon: Icon(Icons.keyboard_arrow_up, size: 20, color: iconColor),
                onPressed: _focusedIndex <= 0
                    ? null
                    : () => _stepFocus(-1, results),
              ),
            ),
            Semantics(
              identifier: 'chat_search_next',
              child: IconButton(
                key: const ValueKey('chat_search_next'),
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: iconColor,
                ),
                onPressed: _focusedIndex >= results.length - 1
                    ? null
                    : () => _stepFocus(1, results),
              ),
            ),
          ],
        ],
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
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              contextMenuBuilder: buildTextSelectionMenu,
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
                      label: theme.l10nOf(context).clearText,
                      button: true,
                      child: IconButton(
                        key: const ValueKey('chat_search_clear'),
                        icon: Icon(Icons.close, size: 18, color: iconColor),
                        tooltip: null,
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
                final promptId = _tooShort
                    ? 'chat_search_too_short'
                    : 'chat_search_prompt';
                return Center(
                  key: ValueKey(promptId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Semantics(
                      identifier: promptId,
                      child: Text(
                        _tooShort
                            ? (widget.tooShortPromptText ??
                                  theme
                                      .l10nOf(context)
                                      .searchPromptTooShort(
                                        widget.minQueryLength,
                                      ))
                            : (widget.emptyPromptText ??
                                  theme.l10nOf(context).searchPromptEmpty),
                        textAlign: TextAlign.center,
                        style:
                            theme.messageSearchEmptyTextStyle ??
                            theme.emptyStateTitleStyle ??
                            _defaultEmptyStyle,
                      ),
                    ),
                  ),
                );
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

              _syncFocusedIndex(results.length);

              return Column(
                children: [
                  _buildResultsHeader(context, results),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final message = results[index];
                        final senderName = _senderLabelFor(context, message);
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
                                children: chatHighlightSpans(
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
                            onTap: () {
                              setState(() => _focusedIndex = index);
                              widget.onMessageTap?.call(
                                widget.roomId,
                                message.id,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
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

const TextStyle _defaultCountStyle = TextStyle(
  fontSize: 12,
  color: Color(0xFF757575),
);
