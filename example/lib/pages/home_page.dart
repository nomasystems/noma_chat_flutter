import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import 'chat_room_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = ChatProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Noma Chat — Demo')),
      body: RoomListView(
        controller: chat.roomListController,
        onTapRoom: (item) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatRoomPage(roomId: item.id, title: item.name),
            ),
          );
        },
      ),
    );
  }
}
