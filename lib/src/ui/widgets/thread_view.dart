import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../controller/chat_controller.dart';
import '../theme/chat_theme.dart';
import '../utils/safe_url.dart';
import 'message_bubble.dart';
import 'message_input.dart';

/// Displays a message thread: the parent message, its replies, and an input for new replies.
class ThreadView extends StatelessWidget {
  const ThreadView({
    super.key,
    required this.parentMessage,
    required this.controller,
    this.replies = const [],
    this.onSendReply,
    this.onLoadMore,
    this.onClose,
    this.theme = ChatTheme.defaults,
    this.currentUserId,
    this.messageBubbleBuilder,
    this.onTapLink,
    this.onTapMention,
  });

  final ChatMessage parentMessage;
  final ChatController controller;
  final List<ChatMessage> replies;

  /// Posts a reply typed in the thread composer. Return `true` when the
  /// reply was taken and the composer may clear, `false` when it was
  /// refused and the text should be handed back — same contract as
  /// `ChatViewCallbacks.onSendMessageRequest`.
  final FutureOr<bool> Function(String text)? onSendReply;
  final VoidCallback? onLoadMore;
  final VoidCallback? onClose;
  final ChatTheme theme;
  final String? currentUserId;
  final Widget Function(BuildContext, ChatMessage, bool)? messageBubbleBuilder;

  /// Opens a URL tapped inside a reply. Defaults to the same system-browser
  /// handler `ChatView` uses for the timeline ([openWebUrl]), so a link in
  /// a thread behaves like the identical-looking link one screen back
  /// without the host wiring anything. Pass your own to take it over.
  final ValueChanged<String>? onTapLink;

  /// Opens the profile behind an `@mention` tapped inside a reply. No
  /// default — same rule as `ChatViewCallbacks.onTapMention`: while it is
  /// `null` mentions stay plain text rather than looking tappable.
  final ValueChanged<String>? onTapMention;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final allMessages = [parentMessage, ...controller.messages];
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: allMessages.length,
                itemBuilder: (context, index) {
                  final message = allMessages[index];
                  final isOutgoing = message.from == currentUserId;
                  if (messageBubbleBuilder != null) {
                    return messageBubbleBuilder!(context, message, isOutgoing);
                  }
                  return MessageBubble(
                    message: message,
                    isOutgoing: isOutgoing,
                    theme: theme,
                    onTapLink: onTapLink ?? openWebUrl,
                    onTapMention: onTapMention,
                  );
                },
              );
            },
          ),
        ),
        MessageInput(
          controller: controller,
          onSendMessageRequest: (request) async =>
              await onSendReply?.call(request.text) ?? true,
          theme: theme.copyWith(
            l10n: theme
                .l10nOf(context)
                .copyWith(writeMessage: theme.l10nOf(context).replyInThread),
          ),
          showAttachButton: false,
          showVoiceButton: false,
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  theme.l10nOf(context).thread,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (replies.isNotEmpty || controller.messages.isNotEmpty)
                  Text(
                    theme
                        .l10nOf(context)
                        .replies(
                          replies.isNotEmpty
                              ? replies.length
                              : controller.messages.length,
                        ),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: theme.l10nOf(context).close,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
