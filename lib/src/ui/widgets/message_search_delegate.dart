import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../controller/message_search_controller.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          // Match the horizontal/vertical rhythm used by RoomSearchBar
          // so the chat-list and in-room search look identical.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _textController,
            onChanged: _onQueryChanged,
            // Outlined style aligned with RoomSearchBar + the host app's
            // login / onboarding TextFields. Earlier "pill" treatment
            // (filled + rounded 24 + borderSide.none) was inconsistent
            // with the rest of the surface and felt out of place.
            decoration: InputDecoration(
              hintText: widget.theme.l10n.searchMessages,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _textController,
                builder: (_, value, __) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: widget.theme.l10n.clearText,
                    onPressed: () {
                      _textController.clear();
                      _onQueryChanged('');
                    },
                  );
                },
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
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
                  child: CircularProgressIndicator(
                    color: widget.theme.input.sendButtonColor,
                  ),
                );
              }

              if (widget.controller.query.isNotEmpty &&
                  widget.controller.results.isEmpty &&
                  !widget.controller.isLoading) {
                return Center(
                  child: Text(
                    widget.theme.l10n.noResults,
                    style:
                        widget.theme.emptyStateTitleStyle ??
                        TextStyle(fontSize: 16, color: Colors.grey.shade500),
                  ),
                );
              }

              if (widget.controller.results.isEmpty) {
                return const SizedBox.shrink();
              }

              final results = _dedupeById(widget.controller.results);

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
                        );
                  return ListTile(
                    title: Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: _highlightSpans(
                          message.text ?? '',
                          widget.controller.query,
                          baseStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          matchStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    onTap: () =>
                        widget.onMessageTap?.call(widget.roomId, message.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

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
