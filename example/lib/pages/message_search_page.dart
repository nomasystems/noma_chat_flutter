import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';

/// Search page wired to `MessageSearchController`. Tapping a result pops the
/// page returning the message id, so the caller can scroll the chat view to
/// that message via [ChatView.initialMessageId].
class MessageSearchPage extends StatefulWidget {
  const MessageSearchPage({super.key, required this.roomId});

  final String roomId;

  @override
  State<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends State<MessageSearchPage> {
  late final NomaChat _chat;
  late final MessageSearchController _controller;
  bool _bound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);
    _controller = MessageSearchController(
      searchFn: _chat.adapter.searchMessages,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search messages')),
      body: MessageSearchView(
        controller: _controller,
        roomId: widget.roomId,
        onMessageTap: (_, messageId) => Navigator.of(context).pop(messageId),
      ),
    );
  }
}
