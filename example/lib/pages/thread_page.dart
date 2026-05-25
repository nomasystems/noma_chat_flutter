import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';

/// Demo page wrapping the SDK's [ThreadView] for a single root message.
///
/// Loads the existing thread on mount (cache-then-network via the
/// adapter) and lets the user post replies via the parent room's
/// `ChatController`. Reuses the room controller so reactions/edits
/// flow through the same state machine — the dedicated thread
/// controller in the SDK is for tests with a separate replies list;
/// for a one-screen demo the parent controller is enough.
class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.roomId,
    required this.rootMessage,
  });

  final String roomId;
  final ChatMessage rootMessage;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  late final NomaChat _chat;
  bool _bound = false;
  List<ChatMessage> _replies = const [];
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);
    _loadThread();
  }

  Future<void> _loadThread() async {
    final res = await _chat.adapter.messages.loadThread(
      widget.roomId,
      widget.rootMessage.id,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _replies = res.dataOrNull ?? const [];
    });
  }

  Future<void> _sendReply(String text) async {
    final res = await _chat.adapter.messages.sendThreadReply(
      widget.roomId,
      widget.rootMessage.id,
      text: text,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() => _replies = [..._replies, res.dataOrNull!]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _chat.adapter.getChatController(widget.roomId);
    return Scaffold(
      appBar: AppBar(title: Text(LocaleProvider.of(context).l10n.thread)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ThreadView(
              parentMessage: widget.rootMessage,
              controller: controller,
              replies: _replies,
              onSendReply: _sendReply,
              currentUserId: _chat.adapter.currentUser.id,
            ),
    );
  }
}
