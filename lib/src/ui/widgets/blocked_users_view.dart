import 'package:flutter/material.dart';

import '../../client/chat_client.dart';
import '../theme/chat_theme.dart';
import 'chat_room_options_menu.dart';
import 'user_avatar.dart';

/// Lists the contacts the current user has blocked, with per-row "Unblock"
/// action that confirms before calling `client.contacts.unblock(userId)`.
///
/// Pass [displayNameResolver] to render a human-friendly name instead of the
/// raw userId. Consumers typically resolve the name from their own user
/// directory or from `ChatUiAdapter.findCachedUser(userId)?.displayName`.
///
/// The widget owns its own loading + refresh cycle: pulls
/// `client.contacts.listBlocked()` on mount and after each successful
/// unblock. Wrap in a [Scaffold] (with `AppBar(title: l10n.blockedUsers)`)
/// at the consumer side.
class BlockedUsersView extends StatefulWidget {
  const BlockedUsersView({
    super.key,
    required this.client,
    this.theme = ChatTheme.defaults,
    this.displayNameResolver,
    this.avatarUrlResolver,
  });

  final ChatClient client;
  final ChatTheme theme;

  /// Resolver from blocked userId → display name. Return `null` to fall
  /// back to rendering the raw userId.
  final String? Function(String userId)? displayNameResolver;

  /// Resolver from blocked userId → avatar URL. Return `null` to use the
  /// initials fallback in [UserAvatar].
  final String? Function(String userId)? avatarUrlResolver;

  @override
  State<BlockedUsersView> createState() => _BlockedUsersViewState();
}

class _BlockedUsersViewState extends State<BlockedUsersView> {
  List<String>? _blocked;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.client.contacts.listBlocked();
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.toString();
      }),
      (paginated) => setState(() {
        _loading = false;
        _blocked = paginated.items;
      }),
    );
  }

  Future<void> _confirmUnblock(String userId) async {
    final l10n = widget.theme.l10n;
    final resolved = widget.displayNameResolver?.call(userId);
    final hasName = resolved != null && resolved.trim().isNotEmpty;
    final confirmed = await ChatRoomOptionsMenu.showConfirmation(
      context: context,
      confirmation: ChatRoomOptionConfirmation(
        title: l10n.unblockUserConfirmTitle,
        body: l10n.unblockUserConfirmBody,
        acceptLabel: hasName
            ? l10n.unblockUserName(resolved.trim())
            : l10n.unblock,
        cancelLabel: l10n.cancel,
      ),
      destructive: false,
      theme: widget.theme,
    );
    if (!confirmed || !mounted) return;
    final result = await widget.client.contacts.unblock(userId);
    if (!mounted) return;
    if (result.isSuccess) {
      await _load();
    } else {
      // Surface a basic error message; the consumer can wrap the widget
      // with their own SnackBar pipeline (via operationErrors) for richer
      // handling.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(result.failureOrNull?.toString() ?? 'Unblock failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    if (_loading && _blocked == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_blocked == null || _blocked!.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final blocked = _blocked ?? const <String>[];
    if (blocked.isEmpty) {
      return Center(child: Text(l10n.blockedUsersEmpty));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: blocked.length,
        separatorBuilder: (_, _) => const Divider(height: 0),
        itemBuilder: (context, index) {
          final userId = blocked[index];
          final resolvedName = widget.displayNameResolver?.call(userId);
          final displayName =
              (resolvedName != null && resolvedName.trim().isNotEmpty)
              ? resolvedName.trim()
              : userId;
          final avatarUrl = widget.avatarUrlResolver?.call(userId);
          return ListTile(
            leading: UserAvatar(
              imageUrl: avatarUrl,
              displayName: displayName,
              size: 40,
              theme: widget.theme,
              excludeSemantics: true,
            ),
            title: Text(displayName),
            // Subtitle used to expose the raw UUID under the display
            // name as "@<uuid>". The id is internal-by-design — surfacing
            // it as a pseudo-handle is misleading (it's not a usable
            // mention) and clutters the row. Drop it: when we have a
            // friendly name we just show the name; when we don't, the
            // title already renders the id alone.
            subtitle: null,
            trailing: TextButton(
              onPressed: () => _confirmUnblock(userId),
              child: Text(l10n.unblock),
            ),
          );
        },
      ),
    );
  }
}
