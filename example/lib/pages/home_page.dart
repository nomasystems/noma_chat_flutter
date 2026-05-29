import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../chat_session.dart';
import '../locale_provider.dart';
import 'blocked_users_page.dart';
import 'catalog_page.dart';
import 'chat_room_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.mode, this.onLogout});

  final ChatMode mode;
  final Future<void> Function()? onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Drives the suggestion bar above the chat list. Delegates roster +
  /// demo-discovery + filtering to the SDK so this page stays a thin
  /// wiring layer. Auto-refresh is on for CHT mode; mock mode uses a
  /// static seed.
  SuggestionBarController? _suggestionController;

  // Multi-select state for creating a group. Empty Set = not selecting.
  // Non-empty = selection mode is active.
  final Set<String> _selectedIds = <String>{};
  bool _selecting = false;
  // Inline user search (AppBar magnifier icon). Distinct from RoomListView's
  // built-in search which filters existing rooms.
  bool _searchOpen = false;
  final _searchController = TextEditingController();
  List<ChatUser> _searchResults = const [];
  bool _searching = false;
  bool _suggestionsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ChatProvider is an InheritedWidget — accessing it in initState would
    // crash. didChangeDependencies is the canonical Flutter spot for
    // one-shot init that needs inherited state.
    if (!_suggestionsRequested) {
      _suggestionsRequested = true;
      _bootstrapSuggestions();
    }
  }

  void _bootstrapSuggestions() {
    final adapter = ChatProvider.of(context).adapter;
    // Both mock and CHT share the same flow: SuggestionBarController with
    // demoDisplayNames + load() + auto-refresh. The previous mock branch
    // used a fixed const list that drifted out of sync with the seeded
    // contacts — on refresh a contradictory state appeared (3 with avatars
    // from seedDemoData vs 4 with initials from the const). Unifying the
    // flow removes the inconsistency.
    final List<String> demoNames;
    if (widget.mode == ChatMode.mock) {
      // Only real users in the suggestion bar. Newsroom stays accessible
      // as an announcements room but is NOT shown as a suggested DM
      // contact — placing a bot next to real contacts was confusing and
      // users could accidentally try to open a DM with it.
      demoNames = const <String>['Alice', 'Bob', 'Carol'];
    } else {
      // CHT: DEMO_CONTACTS env (set by harness/up-noma) drives the
      // demo discovery; when running `flutter run` directly without the
      // harness it falls back to the canonical 3-user dev set so the
      // example is usable out of the box.
      final envNames = demoContactsFromEnv();
      demoNames = envNames.isNotEmpty
          ? envNames
          : const <String>['alice', 'bob', 'charlie'];
    }
    final ctrl = SuggestionBarController(
      adapter,
      demoDisplayNames: demoNames,
      // CHT/live: discover EVERY active user so any newly-created user is
      // visible to everyone (not just the fixed DEMO_CONTACTS set). Mock
      // keeps the curated seeded set (which deliberately excludes the
      // Newsroom bot), so it stays demoDisplayNames-driven.
      discoverAll: widget.mode != ChatMode.mock,
    );
    ctrl.addListener(() => mounted ? setState(() {}) : null);
    _suggestionController = ctrl;
    ctrl.load();
    ctrl.startAutoRefresh();
  }

  @override
  void dispose() {
    _suggestionController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Bottom sheet language picker — surfaces every code in
  /// `ChatUiLocalizations.supportedLanguageCodes` with its native
  /// label, marks the currently active one, and persists the
  /// selection via `LocaleProvider.setLanguageCode`. The app
  /// rebuilds top-down because the provider lives at the root.
  Future<void> _openLanguagePicker() async {
    final provider = LocaleProvider.of(context);
    final current = provider.languageCode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (v) => Navigator.of(sheetCtx).pop(v),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    LocaleProvider.of(context).strings.languageMenu,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final code in ChatUiLocalizations.supportedLanguageCodes)
                RadioListTile<String>(
                  value: code,
                  title: Text(_languageName(code)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await provider.setLanguageCode(picked);
  }

  /// Native-name label for each supported language. Stays self-
  /// referential ("Català" not "Catalan") so the user can find
  /// their language even when they don't speak the current one.
  String _languageName(String code) => switch (code) {
    'en' => 'English',
    'es' => 'Español',
    'fr' => 'Français',
    'de' => 'Deutsch',
    'it' => 'Italiano',
    'pt' => 'Português',
    'ca' => 'Català',
    _ => code,
  };

  /// Convenience: bridge call sites that want to re-trigger discovery
  /// (e.g. returning from BlockedUsersPage). Delegates to the SDK
  /// controller, which handles concurrency + filter recomputation.
  Future<void> _loadSuggestions() async {
    await _suggestionController?.load();
  }

  List<SuggestedContact> get _suggestions =>
      _suggestionController?.suggestions ?? const [];

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() => _searchResults = const []);
      return;
    }
    setState(() => _searching = true);
    final chat = ChatProvider.of(context);
    final result = await chat.client.users.search(q);
    if (!mounted) return;
    result.fold(
      (failure) {
        setState(() {
          _searchResults = const [];
          _searching = false;
        });
      },
      (paginated) {
        setState(() {
          _searchResults = paginated.items;
          _searching = false;
        });
      },
    );
  }

  void _exitSelectionMode() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (!_selectedIds.add(userId)) _selectedIds.remove(userId);
    });
  }

  /// Opens (or creates) a room with the given other-user ids and navigates
  /// into it.
  ///
  /// **DMs** (`otherIds.length == 1 && name == null`) use the WhatsApp-style
  /// draft flow from the SDK: if a room already exists with that contact we
  /// open it; otherwise we open a draft via
  /// [NomaChat.openDirectMessageDraft] (no server-side room) and let the
  /// first send materialize it. No `openOrCreateRoom` call, no failure
  /// snackbar.
  ///
  /// **Groups** (`otherIds.length >= 1 && name != null`) keep eager
  /// creation via [NomaChat.openOrCreateRoom] — matches WhatsApp's behavior
  /// of creating the group as soon as the user confirms.
  Future<void> _openRoomWith({
    required List<String> otherIds,
    String? name,
  }) async {
    final filteredIds = otherIds.where((id) => id.trim().isNotEmpty).toList();
    if (filteredIds.isEmpty) return;
    final chat = ChatProvider.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Capture the failure template before any awaits — `context` is
    // unsafe to read across async gaps once we've crossed an `await`.
    final failedToOpenTemplate = LocaleProvider.of(
      context,
    ).strings.failedToOpenRoomTemplate;

    final isDm = filteredIds.length == 1 && name == null;
    if (isDm) {
      final otherId = filteredIds.first;
      final existing = chat.findExistingDmRoom(otherId);
      if (!mounted) return;
      if (existing != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatRoomPage(roomId: existing),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatRoomPage(
              roomId: chat.adapter.dm.draftRoutingKey(otherId),
              draftOtherUserId: otherId,
            ),
          ),
        );
      }
      await _loadSuggestions();
      return;
    }

    final result = await chat.openOrCreateRoom(
      otherIds: filteredIds,
      name: name,
    );
    if (result.isFailure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failedToOpenTemplate.replaceAll(
              '{error}',
              '${result.failureOrNull}',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ChatRoom room = result.dataOrNull!;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPage(roomId: room.id, title: name ?? room.name),
      ),
    );
    await _loadSuggestions();
  }

  /// Long-press handler on a row of the room list. Opens the SAME set of
  /// options as the three-dots overflow inside the chat — view members,
  /// search, media gallery, mute/pin toggles, clear/delete/leave/block.
  /// Mirrors WhatsApp's behaviour where the long-press sheet is the
  /// shortcut to actions otherwise requiring to enter the chat first.
  void _showRoomOptionsForRow(RoomListItem room) {
    final chat = ChatProvider.of(context);
    final l10n = LocaleProvider.of(context).l10n;
    final otherUserId = room.otherUserId;
    final isDm = otherUserId != null && !room.isGroup;
    final isGroup = room.isGroup;
    final otherUser = isDm ? chat.adapter.findCachedUser(otherUserId) : null;
    final roomId = room.id;
    ChatRoomOptionsMenu.show(
      context: context,
      options: [
        // Single info entry point. For groups this opens the unified
        // GroupInfoPage (avatar+name+description+members+role mgmt);
        // for DMs the read-only UserInfoPage.
        ChatRoomOption(
          icon: const Icon(Icons.info_outline),
          label: isGroup ? l10n.groupInfo : l10n.profile,
          onTap: () => _openRoomInfoFromList(room),
        ),
        ChatRoomOption.muteRoom(
          l10n: l10n,
          muted: room.muted,
          onToggle: () => room.muted
              ? chat.adapter.rooms.unmute(roomId)
              : chat.adapter.rooms.mute(roomId),
        ),
        ChatRoomOption.pinRoom(
          l10n: l10n,
          pinned: room.pinned,
          onToggle: () => room.pinned
              ? chat.adapter.rooms.unpin(roomId)
              : chat.adapter.rooms.pin(roomId),
        ),
        ChatRoomOption.clearChat(
          l10n: l10n,
          onConfirm: () => chat.adapter.messages.clearChat(roomId),
        ),
        ChatRoomOption.deleteChat(
          l10n: l10n,
          onConfirm: () => chat.adapter.rooms.hide(roomId),
        ),
        if (isGroup)
          ChatRoomOption.leaveGroup(
            l10n: l10n,
            onConfirm: () => chat.adapter.rooms.leave(roomId),
          ),
        if (isDm)
          ChatRoomOption.blockUser(
            l10n: l10n,
            otherUserName: otherUser?.displayName ?? room.displayName,
            onConfirm: () =>
                chat.adapter.contacts.block(otherUserId, roomId: roomId),
          ),
      ],
    );
  }

  Future<void> _openNewGroupFlow() async {
    final chat = ChatProvider.of(context);
    final l10n = LocaleProvider.of(context).l10n;
    final demoNames = _suggestionController?.demoDisplayNames ?? const [];
    final result = await GroupSetupPage.show(
      context: context,
      adapter: chat.adapter,
      theme: ChatTheme.defaults.copyWith(l10n: l10n),
      audience: RoomAudience.unrestricted,
      demoDisplayNames: demoNames,
    );
    if (result == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPage(roomId: result.roomId),
      ),
    );
  }

  Future<void> _openRoomInfoFromList(RoomListItem room) async {
    final chat = ChatProvider.of(context);
    final l10n = LocaleProvider.of(context).l10n;
    final theme = ChatTheme.defaults.copyWith(l10n: l10n);
    if (room.isGroup) {
      await GroupInfoPage.show(
        context: context,
        adapter: chat.adapter,
        roomId: room.id,
        theme: theme,
      );
    } else {
      final otherUserId = room.otherUserId;
      if (otherUserId == null) return;
      await UserInfoPage.show(
        context: context,
        adapter: chat.adapter,
        userId: otherUserId,
        theme: theme,
      );
    }
  }

  Future<void> _confirmGroupCreation() async {
    if (_selectedIds.length < RoomDefaults.minOtherUsersInGroup) return;
    final chat = ChatProvider.of(context);
    // Resolve the selected ids to ChatUser objects so the SDK's
    // GroupSetupPage can render member avatars / names while the user
    // types the group name. The set is small (≤ ~10) so a sequential
    // adapter cache hit + REST fallback is fine.
    final members = <ChatUser>[];
    for (final id in _selectedIds) {
      final cached = chat.adapter.findCachedUser(id);
      if (cached != null) {
        members.add(cached);
        continue;
      }
      final fetched = await chat.client.users.get(id);
      if (fetched.isSuccess) {
        members.add(fetched.dataOrNull!);
      }
    }
    if (!mounted || members.isEmpty) return;
    final result = await GroupSetupPage.show(
      context: context,
      adapter: chat.adapter,
      initialMembers: members,
      audience: RoomAudience.unrestricted,
    );
    if (result == null) return;
    _exitSelectionMode();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPage(roomId: result.roomId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ChatProvider.of(context);

    // Title makes the active context explicit: "(mock)" or "(alice)".
    // Helps when both alice and bob run side-by-side in different sims.
    final modeLabel = widget.mode == ChatMode.mock
        ? '(mock)'
        : '(${chat.adapter.currentUser.displayName ?? chat.adapter.currentUser.id})';

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
                tooltip: LocaleProvider.of(context).strings.cancelSelection,
              )
            : null,
        title: Text(
          _selecting
              ? LocaleProvider.of(context).strings.selectedCountTemplate
                    .replaceAll('{count}', '${_selectedIds.length}')
              : 'Noma Chat $modeLabel',
        ),
        actions: [
          if (_selecting) ...[
            TextButton(
              onPressed:
                  _selectedIds.length >= RoomDefaults.minOtherUsersInGroup
                  ? _confirmGroupCreation
                  : null,
              child: Text(LocaleProvider.of(context).l10n.create),
            ),
          ] else ...[
            if (widget.mode == ChatMode.cht)
              IconButton(
                icon: Icon(_searchOpen ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _searchController.clear();
                      _searchResults = const [];
                    }
                  });
                },
                tooltip: _searchOpen
                    ? LocaleProvider.of(context).strings.closeSearch
                    : LocaleProvider.of(context).strings.openSearch,
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: LocaleProvider.of(context).strings.refreshTooltip,
              onPressed: () async {
                await chat.refresh();
                // Reload suggestions: `chat.refresh()` reloads rooms and
                // cache but `SuggestionBarController` has its own poll
                // cycle (~10 s) and only refreshes when asked. Without
                // this call the refresh button left the suggestion bar
                // showing stale data until the next automatic poll.
                await _loadSuggestions();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      LocaleProvider.of(context).strings.refreshDone,
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'settings') {
                  await ProfileSettingsPage.show(
                    context: context,
                    adapter: chat.adapter,
                    theme: ChatTheme.defaults.copyWith(
                      l10n: LocaleProvider.of(context).l10n,
                    ),
                  );
                } else if (value == 'blocked') {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BlockedUsersPage(),
                    ),
                  );
                  if (mounted) await _loadSuggestions();
                } else if (value == 'language') {
                  await _openLanguagePicker();
                } else if (value == 'catalog') {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CatalogPage(),
                    ),
                  );
                } else if (value == 'logout') {
                  await widget.onLogout?.call();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'settings',
                  child: Text(LocaleProvider.of(context).l10n.settings),
                ),
                PopupMenuItem(
                  value: 'blocked',
                  child: Text(LocaleProvider.of(context).l10n.blockedUsers),
                ),
                PopupMenuItem(
                  value: 'language',
                  child: Text(LocaleProvider.of(context).strings.languageMenu),
                ),
                const PopupMenuItem(
                  value: 'catalog',
                  child: Text('Widget Catalog'),
                ),
                if (widget.onLogout != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Text(
                      LocaleProvider.of(context).l10n.logout,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_searchOpen) _buildSearchPane(),
          if (!_searchOpen && _suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _SelectableSuggestionsBar(
                title: LocaleProvider.of(context).strings.suggestionsTitle,
                contacts: _suggestions,
                selectedIds: _selectedIds,
                selecting: _selecting,
                onTap: (c) {
                  if (_selecting) {
                    _toggleSelection(c.id);
                  } else {
                    _openRoomWith(otherIds: [c.id]);
                  }
                },
              ),
            ),
          Expanded(
            child: RoomListView(
              controller: chat.roomListController,
              // Drives the "own message" gates in each tile (the
              // sent/delivered/read tick on the preview row + the
              // "You: …" prefix in groups). Without this id the tile
              // can't tell which last messages are yours.
              currentUserId: chat.adapter.currentUser.id,
              onTapRoom: (item) {
                // Pass `displayName` (the SDK-resolved title — other
                // user's name in DMs, room name in groups) instead of
                // `item.name` (raw server field, empty for DMs).
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatRoomPage(roomId: item.id, title: item.displayName),
                  ),
                );
              },
              onLongPressRoom: _showRoomOptionsForRow,
              onAcceptInvitation: (item) async {
                final messenger = ScaffoldMessenger.of(context);
                final strings = LocaleProvider.of(context).strings;
                await chat.adapter.rooms.acceptInvitation(item.id);
                if (!mounted) return;
                final name = item.displayName.isEmpty
                    ? strings.acceptedInvitationFallback
                    : item.displayName;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      strings.acceptedInvitationTemplate.replaceAll(
                        '{name}',
                        name,
                      ),
                    ),
                  ),
                );
              },
              onRejectInvitation: (item) async {
                final messenger = ScaffoldMessenger.of(context);
                final label = LocaleProvider.of(
                  context,
                ).l10n.invitationRejected;
                await chat.adapter.rooms.rejectInvitation(item.id);
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(label)));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNewGroupFlow,
              icon: const Icon(Icons.group_add),
              label: Text(LocaleProvider.of(context).l10n.newGroup),
            ),
    );
  }

  Widget _buildSearchPane() {
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: LocaleProvider.of(context).strings.searchUsersHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _runSearch,
            ),
            if (_searchResults.isNotEmpty)
              SizedBox(
                height: 240,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final u = _searchResults[i];
                    final label = u.displayName ?? u.id;
                    return ListTile(
                      leading: UserAvatar(
                        imageUrl: u.avatarUrl,
                        displayName: label,
                        size: 40,
                      ),
                      title: Text(label),
                      // The `@<uuid>` that appeared previously was the
                      // user's internal id (an opaque UUID), not a mention
                      // handle — it was visually confusing. Removed.
                      onTap: () async {
                        setState(() {
                          _searchOpen = false;
                          _searchController.clear();
                          _searchResults = const [];
                        });
                        await _openRoomWith(otherIds: [u.id]);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wraps [ContactSuggestionsBar] with selection-mode visuals: a check overlay
/// on selected items.
class _SelectableSuggestionsBar extends StatelessWidget {
  const _SelectableSuggestionsBar({
    required this.title,
    required this.contacts,
    required this.selectedIds,
    required this.selecting,
    required this.onTap,
  });

  final String title;
  final List<SuggestedContact> contacts;
  final Set<String> selectedIds;
  final bool selecting;
  final ValueChanged<SuggestedContact> onTap;

  @override
  Widget build(BuildContext context) {
    return ContactSuggestionsBar(
      title: title,
      contacts: contacts,
      onTap: onTap,
      avatarBuilder: selecting
          ? (context, c) {
              final isSelected = selectedIds.contains(c.id);
              return Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(
                      c.displayName.isEmpty
                          ? '?'
                          : c.displayName.characters.first,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              );
            }
          : null,
    );
  }
}
