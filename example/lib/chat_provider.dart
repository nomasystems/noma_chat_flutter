import 'package:flutter/widgets.dart';
import 'package:noma_chat/noma_chat.dart';

/// Exposes a single [NomaChat] instance to all descendants. Read it from
/// anywhere with `ChatProvider.of(context)`.
class ChatProvider extends InheritedWidget {
  const ChatProvider({
    super.key,
    required this.chat,
    required super.child,
  });

  final NomaChat chat;

  static NomaChat of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<ChatProvider>();
    assert(widget != null, 'No ChatProvider ancestor in widget tree');
    return widget!.chat;
  }

  @override
  bool updateShouldNotify(ChatProvider oldWidget) => chat != oldWidget.chat;
}
