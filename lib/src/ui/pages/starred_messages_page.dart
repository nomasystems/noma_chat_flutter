import 'package:flutter/material.dart';

import '../../models/starred_message.dart';
import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';
import '../widgets/starred_messages_view.dart';

/// WhatsApp-style "Starred messages" page: the current user's bookmarked
/// messages across every room, most recent first.
///
/// Thin [Scaffold]/[AppBar] wrapper around [StarredMessagesView.fromAdapter],
/// backed by the same [ChatUiAdapter] the rest of the SDK uses. Tapping a row
/// pops the page with the selected message's room + id so the caller can
/// scroll to and highlight it — starred messages span all rooms, so the
/// result carries the [StarredMessage.roomId] too.
class StarredMessagesPage extends StatelessWidget {
  const StarredMessagesPage({
    super.key,
    required this.adapter,
    this.theme = ChatTheme.defaults,
  });

  final ChatUiAdapter adapter;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.starredMessages)),
      body: StarredMessagesView.fromAdapter(
        adapter,
        theme: theme,
        onOpen: (starred) => Navigator.of(context).pop(starred),
      ),
    );
  }
}
