import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';

/// Demo screen wrapping [BlockedUsersView] from the SDK. The widget owns
/// the loading + refresh + unblock confirmation flow; this page only adds
/// the surrounding [Scaffold] + [AppBar].
class BlockedUsersPage extends StatelessWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = ChatProvider.of(context);
    final l10n = LocaleProvider.of(context).l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedUsers)),
      body: BlockedUsersView(
        client: chat.client,
        theme: ChatTheme.defaults.copyWith(l10n: l10n),
        // Resolve display names from the adapter's user cache when we
        // already know the user (e.g. they appear in some room). Falls back
        // to the userId render path inside the widget.
        displayNameResolver: (id) =>
            chat.adapter.findCachedUser(id)?.displayName,
        avatarUrlResolver: (id) => chat.adapter.findCachedUser(id)?.avatarUrl,
      ),
    );
  }
}
