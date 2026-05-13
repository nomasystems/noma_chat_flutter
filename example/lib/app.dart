import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import 'chat_provider.dart';
import 'mock_data.dart';
import 'pages/home_page.dart';
import 'widgets/global_error_banner.dart';

class NomaChatExampleApp extends StatefulWidget {
  const NomaChatExampleApp({super.key});

  @override
  State<NomaChatExampleApp> createState() => _NomaChatExampleAppState();
}

class _NomaChatExampleAppState extends State<NomaChatExampleApp> {
  static const _currentUserId = 'demo-user';
  NomaChat? _chat;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final client = MockChatClient(currentUserId: _currentUserId);
    seedDemoData(client);

    final chat = NomaChat.fromClient(
      client: client,
      currentUser: const ChatUser(id: _currentUserId, displayName: 'Me'),
    );
    await chat.connect();
    await chat.adapter.loadRooms();

    if (mounted) setState(() => _chat = chat);
  }

  @override
  void dispose() {
    _chat?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ChatProvider(
      chat: chat,
      child: MaterialApp(
        title: 'Noma Chat Example',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        builder: (context, child) => GlobalErrorBanner(child: child!),
        home: const HomePage(),
      ),
    );
  }
}
