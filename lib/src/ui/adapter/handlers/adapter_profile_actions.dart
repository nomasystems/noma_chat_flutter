part of '../chat_ui_adapter.dart';

/// Everything [ChatUiAdapter] knows about people rather than rooms: the
/// in-memory user cache and the names it resolves, the per-room roster,
/// the avatar and profile writes ([ChatUiAdapter.uploadAvatar],
/// [ChatUiAdapter.updateMyProfile], [ChatUiAdapter.refreshCurrentUser])
/// and the presence lookups.
///
/// Lives next to the adapter as a `part`, so every member reads and writes
/// the same private fields it did when it sat in the class body.
extension ChatUiAdapterProfileActions on ChatUiAdapter {
  /// Best-effort resolution of a room's other participants from state the
  /// adapter already holds — currently the resolved DM contact hydrated
  /// from the in-memory user cache. Returns `const []` for group rooms,
  /// unresolved DMs, or DMs whose peer hasn't been cached yet. Never
  /// triggers a network fetch; callers that need a guaranteed roster use
  /// the room-detail / members flows.
  List<ChatUser> _cachedOtherUsersForRoom(String roomId) {
    final contactId = _dmContacts.contactIdFor(roomId);
    if (contactId == null) return const [];
    final cached = _userCacheService.find(contactId);
    return cached == null ? const [] : [cached];
  }

  /// Looks up a previously cached user by id. Returns `null` when the user is
  /// unknown to the adapter; callers that need the data should trigger a
  /// lookup via `client.users.get` and feed the result back through
  /// [cacheUsers].
  ChatUser? findCachedUser(String userId) => _userCacheService.find(userId);

  /// Resolves a user's display name with a fallback chain that NEVER
  /// returns a raw UUID:
  ///   1) Local user (`currentUser`) gets its own `displayName` — the
  ///      adapter does NOT seed `_userCache` with self, so a plain
  ///      `findCachedUser` lookup would miss this case and the UI would
  ///      end up rendering the local UUID for "by you" rows.
  ///   2) The host's own directory ([userDirectoryResolver]), which is
  ///      authoritative about who someone is when it is wired.
  ///   3) The cached `ChatUser.displayName` if non-empty.
  ///   4) The empty string. An id is not a name: a room full of UUIDs is
  ///      worse than a room full of blanks, and a host that wants a
  ///      placeholder there knows better than the SDK what it should say.
  ///
  /// Use this anywhere the UI shows `by <name>` / `with <name>` — pin
  /// list, room invitations, mention overlays, etc.
  String displayNameFor(String userId) {
    if (userId == currentUser.id) {
      final selfName = currentUser.displayName?.trim();
      if (selfName != null && selfName.isNotEmpty) return selfName;
      return '';
    }
    final fromHost = _userCacheService.hostDisplayName(userId)?.trim();
    if (fromHost != null && fromHost.isNotEmpty) return fromHost;
    final cached = _userCacheService.find(userId)?.displayName?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    return '';
  }

  /// Records who belongs to [roomId] so the room list can be searched by
  /// member without a round trip. Every roster the SDK reads feeds this —
  /// opening a chat, its info page or its member list — and a host that
  /// keeps its own roster is free to add it too:
  ///
  /// ```dart
  /// chat.adapter.recordRoomRoster(roomId, myDirectory.memberIdsOf(roomId));
  /// ```
  ///
  /// Pass `complete: false` for a page of a paginated roster, which adds to
  /// what is already known instead of replacing it. The names shown come
  /// from [displayNameFor], so ids nobody can name cost nothing.
  ///
  /// This is a search index, not a membership source: it never drives who
  /// may read or write a room.
  void recordRoomRoster(
    String roomId,
    Iterable<String> userIds, {
    bool complete = true,
  }) {
    if (_disposed) return;
    if (complete) {
      _roomRosters.record(roomId, userIds);
    } else {
      _roomRosters.addAll(roomId, userIds);
    }
    roomListController.notifyMembersChanged();
  }

  /// Members known for [roomId] — what [recordRoomRoster] and the member
  /// events have recorded so far. Empty for a room whose roster the SDK has
  /// never seen.
  Set<String> roomRosterOf(String roomId) => _roomRosters.membersOf(roomId);

  /// People the room-list text filter matches on top of the room's own
  /// title: the ones this adapter can name for a row without a round trip.
  ///
  /// Those are the peer of a one-to-one chat, whoever wrote the last
  /// message, and every member of a roster the SDK has already seen (see
  /// [recordRoomRoster]) — all resolved through [displayNameFor], so the
  /// host's own directory answers first and an id nobody can name
  /// contributes nothing instead of making the row searchable by its UUID.
  /// The local user is left out: every chat has them in it, so their name
  /// would match everything.
  ///
  /// A group whose roster has never been read is still searchable by its
  /// title and its last writer alone. A host that keeps its own roster
  /// either feeds it through [recordRoomRoster] or replaces this default
  /// outright via [RoomListController.setParticipantNameResolver].
  Iterable<String> _participantNamesFor(RoomListItem room) {
    final names = <String>{};
    final ids = <String?>[
      room.otherUserId,
      room.lastMessageUserId,
      ..._roomRosters.membersOf(room.id),
    ];
    for (final id in ids) {
      if (id == null || id.isEmpty || id == currentUser.id) continue;
      final name = displayNameFor(id);
      if (name.isNotEmpty) names.add(name);
    }
    return names;
  }

  /// Inserts or updates the given users in the in-memory cache.
  void cacheUsers(Iterable<ChatUser> users) {
    if (_disposed) return;
    var changed = false;
    final displayNameChanges = <ChatUser>[];
    final avatarChanges = <ChatUser>[];
    // Snapshot the previous avatar URLs of the users that change so we
    // can evict them from Flutter's image cache after the fact. Without
    // the evict, if the backend ever reuses the same URL (CDN with
    // stable path + new bytes) the on-device decoded image stays
    // cached and the new avatar never renders.
    final evictUrls = <String>[];
    for (final u in users) {
      final prev = _userCacheService.find(u.id);
      if (prev == null ||
          prev.displayName != u.displayName ||
          prev.avatarUrl != u.avatarUrl ||
          prev.bio != u.bio ||
          prev.email != u.email) {
        _userCacheService.insert(u);
        changed = true;
        if (prev == null || prev.displayName != u.displayName) {
          displayNameChanges.add(u);
        }
        if (prev == null || prev.avatarUrl != u.avatarUrl) {
          avatarChanges.add(u);
          final old = prev?.avatarUrl;
          if (old != null && old.isNotEmpty) evictUrls.add(old);
        }
      }
    }
    if (changed) {
      roomListController.notifyMembersChanged();
      _userCacheListenable.emit();
    }
    if (displayNameChanges.isNotEmpty) {
      _roomListMutator.refreshDmTitlesForUsers(displayNameChanges);
      _roomListMutator.refreshLastSenderNamesFor(displayNameChanges);
    }
    if (avatarChanges.isNotEmpty) {
      _roomListMutator.refreshDmAvatarsForUsers(avatarChanges);
    }
    for (final url in evictUrls) {
      _evictAvatarFromImageCache(url);
    }
  }

  void _evictAvatarFromImageCache(String url) {
    try {
      NetworkImage(url).evict();
    } catch (_) {
      // Image cache eviction is best-effort. Any failure simply leaves
      // the stale entry in memory until it gets LRU-displaced.
    }
  }

  Future<void> _ensureUserCached(String userId) async {
    // Delegate to the service's deduped fetch. We only need
    // `cacheUsers` (with its room-list propagation) if the fetch
    // actually returned a NEW user; the service already inserted into
    // its map, but `cacheUsers` does the change-detection +
    // notifyMembersChanged + DM title/avatar refresh side-effects.
    if (_disposed) return;
    final wasCached = _userCacheService.contains(userId);
    final fetched = await _userCacheService.ensureCached(userId);
    if (_disposed) return;
    if (!wasCached && fetched != null) {
      cacheUsers([fetched]);
    }
  }

  /// Uploads a freshly-picked avatar through the configured
  /// [avatarStorage] and returns the resolved URL. Used as a building
  /// block by [updateMyProfile] and [createGroupRoom]; consumers wiring
  /// their own forms can call it directly.
  @internal
  Future<ChatResult<String>> uploadAvatar(
    Uint8List bytes,
    String mimeType,
    AvatarKind kind,
  ) => profile.uploadAvatar(bytes, mimeType, kind);

  /// One-shot profile edit: optionally uploads a new avatar (or clears
  /// it when [removeAvatar] is `true`) and then PATCHes `/v1/users/<id>`.
  /// Returns the resolved avatar URL on success so the caller can update
  /// optimistic UI without waiting for the [UserUpdatedEvent] echo.
  ///
  /// Pass [newAvatarBytes]/[newAvatarMimeType] together to replace; pass
  /// `removeAvatar: true` to clear; omit both to leave the avatar
  /// untouched.
  @internal
  Future<ChatResult<String?>> updateMyProfile({
    String? displayName,
    Uint8List? newAvatarBytes,
    String? newAvatarMimeType,
    bool removeAvatar = false,
    String? bio,
    String? email,
  }) => profile.update(
    displayName: displayName,
    newAvatarBytes: newAvatarBytes,
    newAvatarMimeType: newAvatarMimeType,
    removeAvatar: removeAvatar,
    bio: bio,
    email: email,
  );
  void _applyOptimisticCurrentUser({
    String? displayName,
    String? avatarUrl,
    required bool avatarFieldTouched,
    String? bio,
    String? email,
  }) {
    final updated = currentUser.copyWith(
      displayName: displayName ?? currentUser.displayName,
      avatarUrl: avatarFieldTouched ? avatarUrl : currentUser.avatarUrl,
      bio: bio ?? currentUser.bio,
      email: email ?? currentUser.email,
    );
    _currentUser = updated;
    _currentUserListenable.value = updated;
    cacheUsers([updated]);
  }

  /// Replaces the in-memory `currentUser` with the freshest snapshot
  /// from the backend (avatarUrl, displayName, bio, email, custom). Use
  /// it after a successful `users.create` / `users.update` to push
  /// fields the adapter cannot infer locally — typically the avatarUrl
  /// uploaded during onboarding, which is committed to the server but
  /// never makes it back to `adapter.currentUser` unless we refetch.
  /// Idempotent: if the backend returns the same data nothing visible
  /// changes; if it returns more (bio, email...) the adapter cache and
  /// downstream widgets see it on the next rebuild.
  Future<void> refreshCurrentUser() async {
    if (_disposed) return;
    final result = await client.users.get(_currentUser.id);
    if (_disposed || result.isFailure) return;
    final fresh = result.dataOrThrow;
    _currentUser = fresh;
    _currentUserListenable.value = fresh;
    cacheUsers([fresh]);
  }

  /// Fills in the local user's own avatar, once, when the snapshot the
  /// host handed over at sign-in carries none.
  ///
  /// The local user's face is painted in one place the other members' is
  /// not: inside their own voice note. A host that sets the profile photo
  /// through its own backend never pushes it into `currentUser`, and
  /// [refreshCurrentUser] — the lever for that — has no caller of its own,
  /// so the bubble falls back to initials for an account that plainly has
  /// a photo. [NomaChatView] calls this on every room open, which is why
  /// it costs at most one request per adapter and none at all once a
  /// photo is known. Use [refreshCurrentUser] for the unconditional
  /// refetch after writing the profile.
  Future<void> ensureCurrentUserAvatar() async {
    if (_disposed || _currentUserAvatarProbed) return;
    final own = _currentUser.avatarUrl?.trim();
    if (own != null && own.isNotEmpty) return;
    _currentUserAvatarProbed = true;
    await refreshCurrentUser();
  }

  /// Returns the cached presence for a contact user, or null when unknown.
  /// Populated by the internal presence bootstrap (after every reconnect)
  /// and live `PresenceChangedEvent`s.
  ChatPresence? presenceFor(String userId) => _presence.presenceFor(userId);

  /// Stream of presence updates filtered to a single user. Useful for widgets
  /// like the Suggestions list that need to subscribe per-user.
  Stream<ChatPresence> presenceStreamFor(String userId) {
    return client.events
        .where((e) => e is PresenceChangedEvent)
        .map((e) {
          final ev = e as PresenceChangedEvent;
          return ChatPresence(
            userId: ev.userId,
            online: ev.online,
            status: ev.status,
            statusText: ev.statusText,
            lastSeen: ev.lastSeen,
          );
        })
        .where((p) => p.userId == userId);
  }
}
