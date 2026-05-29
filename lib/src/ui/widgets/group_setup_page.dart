import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/room.dart';
import '../../models/user.dart';
import '../../storage/avatar_storage.dart';
import '../adapter/chat_ui_adapter.dart';
import '../room_defaults.dart';
import '../theme/chat_theme.dart';
import 'avatar_picker_field.dart';
import 'avatar_picker_sheet.dart';
import 'user_avatar.dart';

/// Result of a successful group creation. Returned by
/// [GroupSetupPage.show] so the caller can navigate straight into the
/// newly-minted room.
class GroupCreationResult {
  final String roomId;
  final List<String> memberIds;
  const GroupCreationResult({required this.roomId, required this.memberIds});
}

/// WhatsApp-style "new group" screen — single-page flow that gathers
/// avatar, name, optional description and the member list in one
/// place. The classic two-step flow (pick members → name the group)
/// remains supported by pre-populating [initialMembers]; consumers that
/// want the unified flow can leave it empty and let the user pick
/// inside this page.
///
/// Tap a suggestion to add it to the chip row at the top; tap the chip
/// `x` to remove. Suggestions come from `users.search(query)`; when
/// the query is empty the SDK exposes the user's contacts (typed below
/// the search field) so the most common members are one tap away.
class GroupSetupPage extends StatefulWidget {
  const GroupSetupPage({
    super.key,
    required this.adapter,
    this.initialMembers = const <ChatUser>[],
    this.theme = ChatTheme.defaults,
    this.minNameLength = RoomDefaults.minGroupNameLength,
    this.minOtherUsers = RoomDefaults.minOtherUsersInGroup,
    this.audience = RoomAudience.contacts,
    this.demoDisplayNames = const <String>[],
  });

  final ChatUiAdapter adapter;
  final List<ChatUser> initialMembers;
  final ChatTheme theme;
  final int minNameLength;
  final int minOtherUsers;
  final RoomAudience audience;

  /// Extra usernames (same list used by `SuggestionBarController`) that
  /// should appear in the member picker even when they are not part of
  /// the local user's roster yet. Each name is resolved via
  /// `client.users.search(<name>)` at initState and merged with the
  /// contact list. Use it to mirror in the picker the same set of
  /// "easy starters" the home suggestion bar exposes.
  final List<String> demoDisplayNames;

  static Future<GroupCreationResult?> show({
    required BuildContext context,
    required ChatUiAdapter adapter,
    List<ChatUser> initialMembers = const <ChatUser>[],
    ChatTheme theme = ChatTheme.defaults,
    int minNameLength = RoomDefaults.minGroupNameLength,
    int minOtherUsers = RoomDefaults.minOtherUsersInGroup,
    RoomAudience audience = RoomAudience.contacts,
    List<String> demoDisplayNames = const <String>[],
  }) {
    return Navigator.of(context).push<GroupCreationResult>(
      MaterialPageRoute<GroupCreationResult>(
        builder: (_) => GroupSetupPage(
          adapter: adapter,
          initialMembers: initialMembers,
          theme: theme,
          minNameLength: minNameLength,
          minOtherUsers: minOtherUsers,
          audience: audience,
          demoDisplayNames: demoDisplayNames,
        ),
      ),
    );
  }

  @override
  State<GroupSetupPage> createState() => _GroupSetupPageState();
}

class _GroupSetupPageState extends State<GroupSetupPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  AvatarSnapshot? _pickedAvatar;
  bool _creating = false;
  late List<ChatUser> _members;
  List<ChatUser> _suggestions = const [];
  List<ChatUser> _searchResults = const [];
  Timer? _searchDebounce;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _members = List<ChatUser>.from(widget.initialMembers);
    _nameController.addListener(_rebuild);
    _searchController.addListener(_onSearchChanged);
    _loadSuggestions();
  }

  /// Pulls the user's contact roster + the optional `demoDisplayNames`
  /// (resolved via `users.search`) so the picker shows familiar faces
  /// by default — no typing required. The search field still overrides
  /// this list with `users.search` results when the user types ≥ 2
  /// chars. Without merging demo names, the picker would mismatch the
  /// home suggestion bar: e.g. a "Newsroom" bot is visible in the home
  /// (via demoDisplayNames) but missing in the group picker because
  /// it's not a contact. This keeps both surfaces consistent.
  Future<void> _loadSuggestions() async {
    final me = widget.adapter.currentUser.id;
    final users = <ChatUser>[];
    final seen = <String>{};

    void absorb(ChatUser u) {
      if (u.id.isEmpty || u.id == me) return;
      if (!seen.add(u.id)) return;
      users.add(u);
    }

    // 1) Roster
    final rosterRes = await widget.adapter.client.contacts.list();
    if (!mounted) return;
    rosterRes.fold((_) {}, (paginated) {
      for (final c in paginated.items) {
        if (c.userId.isEmpty || c.userId == me) continue;
        if (seen.contains(c.userId)) continue;
        final cached = widget.adapter.findCachedUser(c.userId);
        absorb(
          cached ??
              ChatUser(
                id: c.userId,
                displayName: widget.adapter.displayNameFor(c.userId),
              ),
        );
      }
    });

    // 2) Demo names — each resolved by exact-displayName match. Drives
    //    parity with the home suggestion bar even when these users are
    //    not in the local roster yet.
    for (final raw in widget.demoDisplayNames) {
      final trimmed = raw.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      final res = await widget.adapter.client.users.search(trimmed);
      if (!mounted) return;
      if (res.isFailure) continue;
      for (final u in res.dataOrThrow.items) {
        final dn = (u.displayName ?? '').trim().toLowerCase();
        if (dn != trimmed) continue;
        absorb(u);
      }
    }

    if (!mounted) return;
    setState(() => _suggestions = users);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _nameValid =>
      _nameController.text.trim().length >= widget.minNameLength;

  bool get _enoughMembers => _members.length >= widget.minOtherUsers;

  bool get _canCreate => _nameValid && _enoughMembers && !_creating;

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (q.length < 2) {
      if (_searchResults.isNotEmpty || _currentQuery.isNotEmpty) {
        setState(() {
          _searchResults = const [];
          _currentQuery = '';
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    final result = await widget.adapter.client.users.search(q);
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _searchResults = const [];
        _currentQuery = q;
      });
      return;
    }
    final me = widget.adapter.currentUser.id;
    final memberIds = _members.map((u) => u.id).toSet();
    final items = result.dataOrThrow.items
        .where((u) => u.id != me && !memberIds.contains(u.id))
        .toList();
    setState(() {
      _searchResults = items;
      _currentQuery = q;
    });
  }

  void _addMember(ChatUser user) {
    if (_members.any((u) => u.id == user.id)) return;
    setState(() {
      _members = [..._members, user];
      _searchResults = _searchResults
          .where((u) => u.id != user.id)
          .toList(growable: false);
    });
  }

  void _removeMember(String userId) {
    setState(() {
      _members = _members.where((u) => u.id != userId).toList(growable: false);
    });
  }

  Future<void> _onCreate() async {
    if (!_canCreate) return;
    setState(() => _creating = true);
    final memberIds = _members.map((u) => u.id).toList();
    final descriptionRaw = _descriptionController.text.trim();
    final result = await widget.adapter.rooms.createGroup(
      name: _nameController.text.trim(),
      memberIds: memberIds,
      avatarBytes: _pickedAvatar?.bytes,
      avatarMimeType: _pickedAvatar?.mimeType,
      subject: descriptionRaw.isEmpty ? null : descriptionRaw,
      audience: widget.audience,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.message ??
                widget.theme.l10n.photoUploadFailed,
          ),
        ),
      );
      return;
    }
    final roomId = result.dataOrThrow;
    Navigator.of(
      context,
    ).pop(GroupCreationResult(roomId: roomId, memberIds: memberIds));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newGroup),
        actions: [
          if (_creating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: l10n.create,
              onPressed: _canCreate ? _onCreate : null,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: AvatarPickerField(
              kind: AvatarKind.room,
              size: 140,
              theme: widget.theme,
              onChanged: (snap, _) => setState(() => _pickedAvatar = snap),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _nameController,
              autofocus: widget.initialMembers.isNotEmpty,
              decoration: InputDecoration(
                labelText: l10n.groupName,
                helperText: l10n.minCharsTemplate.replaceAll(
                  '{n}',
                  '${widget.minNameLength}',
                ),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.groupDescription,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${l10n.groupMembers} (${_members.length})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.minCharsTemplate.replaceAll(
                  '{n}',
                  '${widget.minOtherUsers}',
                ),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          for (final member in _members)
            ListTile(
              leading: UserAvatar(
                imageUrl: member.avatarUrl,
                displayName: member.displayName,
                size: 40,
              ),
              title: Text(member.displayName ?? member.id),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: () => _removeMember(member.id),
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.search,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          // Show search results when the user typed; otherwise fall back
          // to the contact suggestions populated at initState so the
          // picker is never empty (WhatsApp-style "type to filter, but
          // your contacts are already here").
          Builder(
            builder: (context) {
              final memberIds = _members.map((u) => u.id).toSet();
              final candidates = _searchController.text.trim().length >= 2
                  ? _searchResults
                  : _suggestions
                        .where((u) => !memberIds.contains(u.id))
                        .toList(growable: false);
              if (candidates.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    for (final candidate in candidates)
                      ListTile(
                        leading: UserAvatar(
                          imageUrl: candidate.avatarUrl,
                          displayName: candidate.displayName,
                          size: 40,
                        ),
                        title: Text(candidate.displayName ?? candidate.id),
                        trailing: const Icon(Icons.add),
                        onTap: () => _addMember(candidate),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
