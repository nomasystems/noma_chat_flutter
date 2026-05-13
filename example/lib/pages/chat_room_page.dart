import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import 'message_search_page.dart';
import 'pinned_messages_page.dart';

/// Demonstrates the [ChatView] wired against the SDK adapter: send, edit,
/// delete, react and reply all flow through `chat.adapter` so the SDK's
/// optimistic UI + operationErrors stream are exercised end-to-end.
class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.roomId,
    this.title,
  });

  final String roomId;
  final String? title;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final NomaChat _chat;
  late final ChatController _controller;
  String? _initialMessageId;

  @override
  void initState() {
    super.initState();
    // initState runs before the first build, so we cannot read the
    // InheritedWidget yet. Defer to didChangeDependencies.
  }

  bool _bound = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);
    _controller = _chat.adapter.getChatController(widget.roomId);
    // Load history + pins so both the chat view and the pins page have data.
    _chat.adapter.loadMessages(widget.roomId);
    _chat.adapter.loadPins(widget.roomId);
  }

  Future<void> _openSearch() async {
    final messageId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MessageSearchPage(roomId: widget.roomId),
      ),
    );
    if (messageId == null || !mounted) return;
    setState(() => _initialMessageId = messageId);
  }

  void _openPins() {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => PinnedMessagesPage(roomId: widget.roomId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.roomId),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: 'Pinned',
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: _openPins,
          ),
        ],
      ),
      body: ChatView(
        controller: _controller,
        initialMessageId: _initialMessageId,
        onSendMessage: (text) =>
            _chat.adapter.sendMessage(widget.roomId, text: text),
        onEditMessage: (message, text) => _chat.adapter
            .editMessage(widget.roomId, message.id, text: text),
        onDeleteMessage: (message) =>
            _chat.adapter.deleteMessage(widget.roomId, message.id),
        onReactionSelected: (message, emoji) => _chat.adapter
            .sendReaction(widget.roomId, messageId: message.id, emoji: emoji),
        onDeleteReaction: (message, emoji) => _chat.adapter.deleteReaction(
          widget.roomId,
          messageId: message.id,
          emoji: emoji,
        ),
        onLoadMoreMessages: () =>
            _chat.adapter.loadMoreMessages(widget.roomId),
        onTypingChanged: (isTyping) =>
            _chat.adapter.sendTyping(widget.roomId, isTyping: isTyping),
        contextMenuActions: const {
          MessageAction.reply,
          MessageAction.copy,
          MessageAction.edit,
          MessageAction.delete,
          MessageAction.react,
          MessageAction.pin,
        },
        onContextMenuAction: (message, action) {
          if (action == MessageAction.pin) {
            _chat.adapter.pinMessage(widget.roomId, message.id);
          }
        },
      ),
    );
  }
}
