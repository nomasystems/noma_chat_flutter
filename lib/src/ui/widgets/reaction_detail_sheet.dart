import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Signature for a custom presenter of the reaction detail sheet. Receives the
/// already-built content widget and is responsible for displaying it in the
/// host app's preferred bottom sheet style. When `null`, [ReactionDetailSheet]
/// falls back to a vanilla [showModalBottomSheet].
typedef ReactionDetailSheetBuilder =
    Future<void> Function(BuildContext context, Widget content);

/// Bottom sheet that lists every user who reacted to a message, grouped by
/// emoji. Use the static [show] entry point.
class ReactionDetailSheet {
  ReactionDetailSheet._();

  static Future<void> show(
    BuildContext context, {
    required Future<List<AggregatedReaction>> Function() fetchReactions,
    required String currentUserId,
    required UserResolver userResolver,
    required ValueChanged<String> onRemoveReaction,
    ChatTheme theme = ChatTheme.defaults,
    ReactionDetailSheetBuilder? sheetBuilder,
  }) {
    final content = ReactionDetailContent(
      fetchReactions: fetchReactions,
      currentUserId: currentUserId,
      userResolver: userResolver,
      onRemoveReaction: onRemoveReaction,
      theme: theme,
    );
    if (sheetBuilder != null) {
      return sheetBuilder(context, content);
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => content,
    );
  }
}

/// Content of the reaction detail sheet (tabs per emoji + user list). Public
/// so consumers can embed it inside their own bottom sheet wrapper via
/// [ReactionDetailSheet.show]'s `sheetBuilder` parameter.
class ReactionDetailContent extends StatefulWidget {
  const ReactionDetailContent({
    super.key,
    required this.fetchReactions,
    required this.currentUserId,
    required this.userResolver,
    required this.onRemoveReaction,
    required this.theme,
  });

  final Future<List<AggregatedReaction>> Function() fetchReactions;
  final String currentUserId;
  final UserResolver userResolver;
  final ValueChanged<String> onRemoveReaction;
  final ChatTheme theme;

  @override
  State<ReactionDetailContent> createState() => _ReactionDetailContentState();
}

class _ReactionDetailContentState extends State<ReactionDetailContent>
    with SingleTickerProviderStateMixin {
  List<AggregatedReaction>? _reactions;
  Map<String, ReactionUser> _resolvedUsers = {};
  bool _loading = true;
  String? _error;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadReactions() async {
    try {
      final reactions = await widget.fetchReactions();
      if (!mounted) return;

      final userIds = <String>{};
      for (final r in reactions) {
        userIds.addAll(r.users);
      }

      final resolved = <String, ReactionUser>{};
      final futures = userIds.map((id) async {
        try {
          resolved[id] = await widget.userResolver(id);
        } catch (_) {
          resolved[id] = ReactionUser(id: id, displayName: id);
        }
      });
      await Future.wait(futures);
      if (!mounted) return;

      _tabController?.dispose();
      _tabController = TabController(length: reactions.length + 1, vsync: this);

      setState(() {
        _reactions = reactions;
        _resolvedUsers = resolved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.45;

    if (_loading) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _reactions == null) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            _error ?? 'Error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final reactions = _reactions!;
    final allUsers = <_UserWithEmoji>[];
    for (final r in reactions) {
      for (final userId in r.users) {
        allUsers.add(
          _UserWithEmoji(
            user:
                _resolvedUsers[userId] ??
                ReactionUser(id: userId, displayName: userId),
            emoji: r.emoji,
          ),
        );
      }
    }
    final totalCount = allUsers.length;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(text: '${widget.theme.l10n.allReactions} $totalCount'),
              ...reactions.map((r) => Tab(text: '${r.emoji} ${r.count}')),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(allUsers),
                ...reactions.map((r) {
                  final users = r.users
                      .map(
                        (id) => _UserWithEmoji(
                          user:
                              _resolvedUsers[id] ??
                              ReactionUser(id: id, displayName: id),
                          emoji: r.emoji,
                        ),
                      )
                      .toList();
                  return _buildUserList(users);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(List<_UserWithEmoji> users) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final item = users[index];
        final isCurrentUser = item.user.id == widget.currentUserId;

        return ListTile(
          leading: UserAvatar(
            imageUrl: item.user.avatarUrl,
            displayName: item.user.displayName,
            size: 40,
          ),
          title: Text(
            isCurrentUser ? widget.theme.l10n.you : item.user.displayName,
            style: widget.theme.reactionDetailUserNameStyle,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 20)),
              if (isCurrentUser) ...[
                const SizedBox(width: 8),
                Semantics(
                  label: widget.theme.l10n.removeReaction,
                  button: true,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color:
                          widget.theme.reactionDetailRemoveColor ??
                          Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () {
                      widget.onRemoveReaction(item.emoji);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _UserWithEmoji {
  final ReactionUser user;
  final String emoji;
  const _UserWithEmoji({required this.user, required this.emoji});
}
