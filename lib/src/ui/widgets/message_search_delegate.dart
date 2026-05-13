import 'dart:async';

import 'package:flutter/material.dart';
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
  });

  final MessageSearchController controller;
  final String roomId;
  final void Function(String roomId, String messageId)? onMessageTap;
  final ChatTheme theme;
  final String Function(String userId)? senderNameResolver;
  final Duration debounceDuration;

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
    _debounce = Timer(widget.debounceDuration, () {
      widget.controller.search(value.trim(), widget.roomId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _textController,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              hintText: widget.theme.l10n.searchMessages,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: widget.theme.searchBarBackgroundColor ??
                  Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
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
                    color: widget.theme.sendButtonColor,
                  ),
                );
              }

              if (widget.controller.query.isNotEmpty &&
                  widget.controller.results.isEmpty &&
                  !widget.controller.isLoading) {
                return Center(
                  child: Text(
                    widget.theme.l10n.noResults,
                    style: widget.theme.emptyStateTitleStyle ??
                        TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                        ),
                  ),
                );
              }

              if (widget.controller.results.isEmpty) {
                return const SizedBox.shrink();
              }

              return ListView.builder(
                itemCount: widget.controller.results.length,
                itemBuilder: (context, index) {
                  final message = widget.controller.results[index];
                  final senderName = widget.senderNameResolver != null
                      ? widget.senderNameResolver!(message.from)
                      : message.from;
                  final now = DateTime.now();
                  final timeStr = DateFormatter.isToday(
                          message.timestamp,
                          now: now)
                      ? DateFormatter.formatTime(message.timestamp)
                      : DateFormatter.formatSeparator(
                          message.timestamp,
                          now: now);
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
                    onTap: () => widget.onMessageTap?.call(
                      widget.roomId,
                      message.id,
                    ),
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
      spans.add(TextSpan(
        text: text.substring(cursor, matchStart),
        style: baseStyle,
      ));
    }
    final matchEnd = matchStart + query.length;
    spans.add(TextSpan(
      text: text.substring(matchStart, matchEnd),
      style: matchStyle,
    ));
    cursor = matchEnd;
  }
  return spans;
}
