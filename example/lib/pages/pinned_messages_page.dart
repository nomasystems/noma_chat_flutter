import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';

/// Shows the room's pinned messages and lets the user unpin any of them.
/// Backed by `ChatController.pinnedMessages` so updates from
/// `adapter.pinMessage` / `unpinMessage` propagate automatically.
class PinnedMessagesPage extends StatefulWidget {
  const PinnedMessagesPage({super.key, required this.roomId});

  final String roomId;

  @override
  State<PinnedMessagesPage> createState() => _PinnedMessagesPageState();
}

class _PinnedMessagesPageState extends State<PinnedMessagesPage> {
  late final NomaChat _chat;
  late final ChatController _controller;
  bool _bound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);
    _controller = _chat.adapter.getChatController(widget.roomId);
    _chat.adapter.loadPins(widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pinned messages')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final pins = _controller.pinnedMessages;
          if (pins.isEmpty) {
            return const Center(child: Text('No pinned messages'));
          }
          return ListView.separated(
            itemCount: pins.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final pin = pins[i];
              final message = _controller.getMessageById(pin.messageId);
              return ListTile(
                leading: const Icon(Icons.push_pin),
                title: Text(message?.text ?? '(message not loaded)'),
                subtitle: Text('Pinned by ${pin.pinnedBy}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Unpin',
                  onPressed: () =>
                      _chat.adapter.unpinMessage(widget.roomId, pin.messageId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
