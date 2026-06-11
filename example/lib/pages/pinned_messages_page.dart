import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';

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
    _chat.adapter.messages.loadPins(widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LocaleProvider.of(context).l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pinnedMessages)),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final pins = _controller.pinnedMessages;
          if (pins.isEmpty) {
            return Center(child: Text(l10n.noPinnedMessages));
          }
          return ListView.separated(
            itemCount: pins.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final pin = pins[i];
              final message = _controller.getMessageById(pin.messageId);
              // `displayNameFor` handles the self / cached / raw-id
              // fallback chain in the SDK so every consumer (this
              // example, WB/mobile, future apps) renders pinners the
              // same way. Never shows a UUID when a friendlier label
              // exists locally.
              final pinnedByName = _chat.adapter.displayNameFor(pin.pinnedBy);
              return ListTile(
                leading: const Icon(Icons.push_pin),
                title: Text(message?.text ?? '…'),
                subtitle: Text(l10n.pinnedBy(pinnedByName)),
                // Tap = jump to the source message in the chat view.
                // Same UX as a search-result tap: we pop with the
                // messageId, the caller (chat_room_page) catches it
                // and feeds `ChatView.initialMessageId` which triggers
                // `_tryScrollToPending` → scroll + 3-second highlight.
                onTap: () => Navigator.of(context).pop(pin.messageId),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.unpin,
                  onPressed: () async {
                    final confirmed =
                        await ChatRoomOptionsMenu.showConfirmation(
                          context: context,
                          confirmation: ChatRoomOptionConfirmation(
                            title: l10n.unpinConfirmTitle,
                            body: l10n.unpinConfirmBody,
                            acceptLabel: l10n.unpin,
                            cancelLabel: l10n.cancel,
                          ),
                          destructive: false,
                        );
                    if (!confirmed) return;
                    await _chat.adapter.messages.unpin(
                      widget.roomId,
                      pin.messageId,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
