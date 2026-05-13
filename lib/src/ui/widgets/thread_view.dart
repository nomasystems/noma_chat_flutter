import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

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
  });

  final ChatMessage parentMessage;
  final ChatController controller;
  final List<ChatMessage> replies;
  final ValueChanged<String>? onSendReply;
  final VoidCallback? onLoadMore;
  final VoidCallback? onClose;
  final ChatTheme theme;
  final String? currentUserId;
  final Widget Function(BuildContext, ChatMessage, bool)? messageBubbleBuilder;

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
                  );
                },
              );
            },
          ),
        ),
        MessageInput(
          controller: controller,
          onSendMessage: (text) => onSendReply?.call(text),
          theme: theme.copyWith(
            l10n: theme.l10n.copyWith(writeMessage: theme.l10n.replyInThread),
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
                  theme.l10n.thread,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (replies.isNotEmpty || controller.messages.isNotEmpty)
                  Text(
                    theme.l10n.replies(
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
            IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}
