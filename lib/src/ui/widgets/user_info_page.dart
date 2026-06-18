import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// Read-only WhatsApp-style "User info" page for a peer in a DM. Shows
/// the large avatar, display name and bio when present. Loaded by
/// [userId] through the adapter's user cache + REST fallback.
///
/// For editing the *own* profile use [ProfileSettingsPage] instead; this
/// page never exposes mutation controls because the user does not own
/// the peer's record.
class UserInfoPage extends StatefulWidget {
  const UserInfoPage({
    super.key,
    required this.adapter,
    required this.userId,
    this.theme = ChatTheme.defaults,
  });

  final ChatUiAdapter adapter;
  final String userId;
  final ChatTheme theme;

  static Future<void> show({
    required BuildContext context,
    required ChatUiAdapter adapter,
    required String userId,
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            UserInfoPage(adapter: adapter, userId: userId, theme: theme),
      ),
    );
  }

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  ChatUser? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Hydrate from cache for instant first paint, then ALWAYS hit the
    // backend — the cached entry may have been populated by a roster /
    // members endpoint that omits `bio`, so trusting the cache would
    // hide the description even when the user has set one.
    final cached = widget.adapter.findCachedUser(widget.userId);
    if (cached != null) {
      setState(() {
        _user = cached;
        _loading = false;
      });
    }
    final result = await widget.adapter.client.users.get(widget.userId);
    if (!mounted) return;
    if (result.isFailure) {
      if (_user == null) {
        setState(() {
          _loading = false;
          _error = result.failureOrNull?.message;
        });
      }
      return;
    }
    final fresh = result.dataOrThrow;
    // Feed the authoritative backend record back into the shared user
    // cache so the cache (which `_buildBody` reads via `findCachedUser`,
    // and which `userCacheListenable` repaints on) reflects the freshly
    // fetched profile — including a `bio` a roster / members endpoint may
    // have omitted. Without this, the stale cached entry would shadow the
    // fetch and the description would never update.
    widget.adapter.cacheUsers([fresh]);
    setState(() {
      _user = fresh;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListenableBuilder(
        listenable: widget.adapter.userCacheListenable,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(err, textAlign: TextAlign.center),
        ),
      );
    }
    final user = widget.adapter.findCachedUser(widget.userId) ?? _user;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.id;
    final bio = user.bio?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Center(
          child: UserAvatar(
            imageUrl: user.avatarUrl,
            displayName: user.displayName,
            size: 140,
            theme: widget.theme,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.theme.l10n.about,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(bio, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
