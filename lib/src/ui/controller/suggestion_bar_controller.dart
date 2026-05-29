import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../models/suggested_contact.dart';
import '../room_defaults.dart';

/// Drives the "suggestion bar" surface (chips above the chat list of users
/// the local user is likely to message). Merges two discovery sources:
///
/// 1. **Roster** — every entry in `client.contacts.list()`. Filters out
///    self, blocked users and globally-deactivated rows. Display names
///    are resolved through `adapter.displayNameFor` so cached users
///    surface a friendly label instead of their raw id.
/// 2. **Demo / well-known names** — when [demoDisplayNames] is non-empty,
///    each name is looked up via `client.users.search(name)` and matched
///    by exact display name. Useful for harness flows or "pinned demo
///    contacts" without sharing a prefix on the user id.
///
/// Exposes a [ChangeNotifier] so the host wraps it in a
/// `ListenableBuilder` and gets free rebuilds as suggestions land. Auto-
/// refresh is opt-in via [startAutoRefresh] / [stopAutoRefresh] —
/// typically 10s in demo flows so a peer who logs in AFTER the current
/// session still shows up without manual action.
class SuggestionBarController extends ChangeNotifier {
  SuggestionBarController(
    this._adapter, {
    List<String> demoDisplayNames = const [],
    bool discoverAll = false,
    void Function(String label, Object? error)? onError,
  }) : _demoDisplayNames = List.unmodifiable(demoDisplayNames),
       _discoverAll = discoverAll,
       _onError = onError {
    // React to block / unblock immediately instead of waiting for the
    // next poll tick. Without this, after `unblock(bob)` the contact
    // stayed missing from the bar until the next 10s timer ran — and
    // the user (legitimately) read that as "still blocked".
    _adapter.blockedUsersListenable.addListener(_onBlockedUsersChanged);
  }

  final ChatUiAdapter _adapter;
  final List<String> _demoDisplayNames;

  /// When true the bar lists EVERY active user (an empty `users.search`)
  /// instead of resolving only [demoDisplayNames] by exact name — so any
  /// newly-created user becomes discoverable by everyone. Opt-in
  /// (demo/discovery surfaces); the roster-only default stays
  /// privacy-preserving for production consumers.
  final bool _discoverAll;
  final void Function(String label, Object? error)? _onError;

  List<SuggestedContact> _suggestions = const [];
  bool _isLoading = false;
  bool _disposed = false;
  Timer? _pollTimer;

  void _onBlockedUsersChanged() {
    if (_disposed) return;
    unawaited(load());
  }

  /// Current snapshot. Updated atomically per `load()` call.
  List<SuggestedContact> get suggestions => _suggestions;

  /// `true` while a fetch is in flight.
  bool get isLoading => _isLoading;

  /// Display names polled via `users.search`. Empty when only roster
  /// drives suggestions.
  List<String> get demoDisplayNames => _demoDisplayNames;

  /// Fetches roster + demo discovery and updates [suggestions].
  /// Safe to call repeatedly; concurrent calls coalesce.
  Future<void> load() async {
    if (_disposed || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    final currentUserId = _adapter.currentUser.id;
    final blockedUsers = _adapter.blockedUserIds;

    // Freshly-resolved users (roster `users.get` + demo-name `users.search`)
    // are pushed into the adapter cache below. This is what keeps avatars /
    // display names live in the OPEN CHAT (bubbles + title) and the chat-list
    // tiles, not just the suggestion bar: those surfaces read the adapter
    // cache (and rebuild on `userCacheListenable`), whereas the suggestion bar
    // renders its own search results directly. Without this, a peer changing
    // their photo refreshed in suggestions but stayed stale in the chats —
    // and polling/manual clients never get a `user_updated` push at all, so
    // this periodic search is their only path to fresh peer profiles.
    final freshUsers = <ChatUser>[];
    final rosterIds = <String>{};
    final rosterMap = <String, SuggestedContact>{};
    final rosterResult = await _adapter.client.contacts.list();
    if (rosterResult.isFailure) {
      _onError?.call('contacts.list', rosterResult.failureOrNull);
    } else {
      final paginated = rosterResult.dataOrThrow;
      for (final c in paginated.items) {
        if (c.userId.isEmpty) continue;
        if (c.userId == currentUserId) continue;
        if (blockedUsers.contains(c.userId)) continue;
        final cached = _adapter.findCachedUser(c.userId);
        if (cached != null && cached.active == false) continue;
        rosterIds.add(c.userId);
        // Fall back to a one-shot `users.get` when the adapter cache
        // hasn't seen this contact yet (typical right after login when
        // no DM has materialised). Without this the suggestion bar
        // renders initials forever even though the backend has a
        // perfectly good avatarUrl for the contact. Fire-and-forget if
        // it fails — initials is still a fine fallback.
        var resolved = cached;
        if (resolved == null) {
          final fetchRes = await _adapter.client.users.get(c.userId);
          if (fetchRes.isSuccess) resolved = fetchRes.dataOrNull;
          if (resolved != null) freshUsers.add(resolved);
        }
        if (_disposed) return;
        rosterMap[c.userId] = SuggestedContact(
          id: c.userId,
          displayName:
              resolved?.displayName ?? _adapter.displayNameFor(c.userId),
          avatarUrl: resolved?.avatarUrl,
        );
      }
    }

    final searchMap = <String, SuggestedContact>{};
    // Discovery mode lists every active user via a single empty-query
    // search; otherwise resolve only the configured demo/well-known names
    // by exact match. `''` is sent verbatim — the backend treats an empty
    // `q` as "all users".
    final searchQueries = _discoverAll ? const <String>[''] : _demoDisplayNames;
    for (final raw in searchQueries) {
      if (_disposed) return;
      final trimmed = raw.trim().toLowerCase();
      if (!_discoverAll && trimmed.isEmpty) continue;
      final result = await _adapter.client.users.search(trimmed);
      result.fold(
        (failure) => _onError?.call('users.search($trimmed)', failure),
        (paginated) {
          for (final u in paginated.items) {
            if (u.id.isEmpty) continue;
            if (u.id == currentUserId) continue;
            // Fresh peer profile from the backend — feed the cache so the
            // open chat + chat-list reflect avatar / name changes, not just
            // the suggestion bar.
            freshUsers.add(u);
            // Exact-name match only when resolving a specific demo name;
            // discovery mode keeps every user the backend returns.
            if (!_discoverAll) {
              final dn = (u.displayName ?? '').trim().toLowerCase();
              if (dn != trimmed) continue;
            }
            if (blockedUsers.contains(u.id)) continue;
            if (u.active == false) continue;
            searchMap[u.id] = SuggestedContact(
              id: u.id,
              displayName: u.displayName ?? u.id,
              avatarUrl: u.avatarUrl,
            );
          }
        },
      );
    }

    if (_disposed) return;

    // Push the freshly-resolved peers into the adapter cache. `cacheUsers`
    // does its own change-detection (no-op when nothing changed) and, on an
    // avatar/name change, evicts the stale image, re-stamps chat-list DM
    // tiles and fires `userCacheListenable` so open ChatViews repaint. This
    // is what makes a peer's photo/name update live inside the chats, not
    // only in the suggestion bar.
    if (freshUsers.isNotEmpty) _adapter.cacheUsers(freshUsers);

    final merged = <SuggestedContact>[];
    for (final id in rosterIds) {
      merged.add(searchMap[id] ?? rosterMap[id]!);
    }
    for (final entry in searchMap.entries) {
      if (rosterIds.contains(entry.key)) continue;
      merged.add(entry.value);
    }
    _suggestions = List.unmodifiable(merged);
    _isLoading = false;
    notifyListeners();
  }

  /// Sets a static list of suggestions and stops any polling. Useful for
  /// mock mode where the suggestion bar is fixed up front.
  void setStatic(List<SuggestedContact> suggestions) {
    stopAutoRefresh();
    _suggestions = List.unmodifiable(suggestions);
    _isLoading = false;
    notifyListeners();
  }

  /// Starts polling [load] on [interval]. Cancels any previous timer.
  /// Default interval is [RoomDefaults.suggestionPollInterval].
  void startAutoRefresh({
    Duration interval = RoomDefaults.suggestionPollInterval,
  }) {
    stopAutoRefresh();
    _pollTimer = Timer.periodic(interval, (_) => load());
  }

  /// Cancels the periodic refresh timer. Idempotent.
  void stopAutoRefresh() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _adapter.blockedUsersListenable.removeListener(_onBlockedUsersChanged);
    stopAutoRefresh();
    super.dispose();
  }
}

/// Reads `DEMO_CONTACTS` (comma-separated) from compile-time dart-defines.
/// Returns the trimmed, non-empty entries. Empty list when the env var is
/// missing — the suggestion bar then surfaces only roster contacts.
List<String> demoContactsFromEnvironment() {
  const raw = String.fromEnvironment('DEMO_CONTACTS', defaultValue: '');
  if (raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
