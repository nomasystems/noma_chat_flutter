part of 'room_enricher.dart';

/// The cache-first hydration [RoomEnricher] runs before the network answers:
/// the pass itself, the status it publishes while it runs, the background
/// revalidation that follows it and the kicked-room rebuild that keeps a
/// room the caller was removed from readable from cache.
extension _RoomEnricherHydration on RoomEnricher {
  Future<_HydrationPass> _runHydration(String type) async {
    final epoch = _sessionEpoch;
    // The host's stored names, read alongside the rooms rather than
    // before them, so the first frame painted off disk already carries
    // them without this read standing between the caller and the room
    // cache. Both are awaited before anything is painted.
    final hostNames = userCache.directory.hydrate();
    final cachedResult = await client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.cacheOnly,
    );
    await hostNames;
    // `isSuccess` means the cache ANSWERED, which since the empty/miss
    // split in `RoomsApi.getUserRooms` includes answering "you have zero
    // rooms". [_HydrationPass.cacheHadContent] is the narrower "the cache
    // had something to paint" — the two are not interchangeable, see
    // their use in [loadAll].
    final hasCached = cachedResult.isSuccess;
    final cached = cachedResult.dataOrNull;
    final hasCachedContent =
        cached != null &&
        (cached.rooms.isNotEmpty || cached.invitedRooms.isNotEmpty);
    if (hasCached) {
      await _enrichAndSet(
        cachedResult.dataOrThrow,
        epoch: epoch,
        type: type,
        detailPolicy: CachePolicy.cacheOnly,
        awaitDmResolution: false,
      );
    }
    _publishHydration(type: type, cacheAnswered: hasCached, epoch: epoch);
    if (epoch == _sessionEpoch) _hydratedThisSession = true;
    return _HydrationPass(
      status: _hydration.value,
      cacheAnswered: hasCached,
      cacheHadContent: hasCachedContent,
    );
  }

  /// Publishes the outcome of the cache phase on [hydrationNotifier].
  ///
  /// [cacheAnswered] is whether the cache read succeeded at all; the
  /// outcome is then derived from what actually made it onto the list, so
  /// a cache whose every room was locally deleted reports
  /// [RoomHydrationOutcome.empty] rather than a contradictory "hydrated
  /// with 0 rows".
  void _publishHydration({
    required String type,
    required bool cacheAnswered,
    required int epoch,
  }) {
    if (_stale(epoch)) return;
    final painted = roomList.allRooms.length;
    _hydration.value = RoomHydrationStatus(
      outcome: !cacheAnswered
          ? RoomHydrationOutcome.unavailable
          : painted == 0
          ? RoomHydrationOutcome.empty
          : RoomHydrationOutcome.hydrated,
      roomCount: cacheAnswered ? painted : 0,
      type: type,
    );
  }

  /// Background counterpart of the network pass in [loadAll], fired when
  /// the cache was trusted and the caller was already handed a result. Runs
  /// the same full enrichment pipeline as the foreground network pass
  /// (`awaitDmResolution: true, authoritative: true`) so DM dedupe,
  /// kicked-room reconciliation AND the authoritative prune pass all stay
  /// consistent with every other authoritative caller, but the write to
  /// [roomList] happens via `mergeRooms` (inside [_enrichAndSet]) rather
  /// than the caller ever seeing a gap.
  ///
  /// A failed network read (`result.isFailure`, e.g. a 5xx/timeout) leaves
  /// the list untouched below — the one case this must never be destructive
  /// for. A successful response, including a legitimately empty one, is the
  /// backend's authoritative word on the caller's complete room set (the
  /// listing endpoint fails the request outright rather than answering 200
  /// with a partial/best-effort read), so this background pass converges
  /// the list the same way [loadAll]'s foreground network pass and an
  /// explicit pull-to-refresh do — this is precisely what closes a
  /// cross-device removal (the last room deleted on another device) without
  /// waiting for a realtime event that might never arrive if this device
  /// was offline when the removal happened.
  ///
  /// Guarded by [_revalidating] so repeated `loadAll` calls for the same
  /// [type] never run two of these concurrently, and by
  /// [_revalidateDebounce] so a burst of `loadAll` calls for the same
  /// [type] (e.g. open/close/reopen the same screen) only revalidates once
  /// per window instead of re-fetching + re-enriching every time.
  Future<void> _backgroundRevalidate(String type) async {
    final epoch = _sessionEpoch;
    final now = DateTime.now();
    final last = _lastRevalidatedAt[type];
    if (last != null && now.difference(last) < _revalidateDebounce) return;
    if (!_revalidating.add(type)) return;
    _lastRevalidatedAt[type] = now;
    try {
      if (_stale(epoch)) return;
      final snapshotAt = DateTime.now();
      final seq = roomList.nextSeq();
      final result = await client.rooms.getUserRooms(
        type: type,
        cachePolicy: CachePolicy.networkOnly,
      );
      if (_stale(epoch) || result.isFailure) return;
      await _enrichAndSet(
        result.dataOrThrow,
        epoch: epoch,
        type: type,
        awaitDmResolution: true,
        authoritative: true,
        snapshotAt: snapshotAt,
        seq: seq,
      );
      if (_stale(epoch)) return;
      _initializedNotifier.value = true;
      _onRoomsLoaded?.call(roomList.allRooms);
    } finally {
      _revalidating.remove(type);
    }
  }

  /// Reconstructs a [RoomListItem] from the local cache for a
  /// kicked-out room — WhatsApp-parity. The backend doesn't return
  /// the room in `bulk_conversations` (the user is no longer a
  /// member), so we hydrate from whatever the cache holds:
  ///
  /// - `ChatRoom`     → seed name, avatar, structural fields.
  /// - `RoomDetail`   → user role at kick time, member count, type.
  /// - `UnreadRoom`   → last message preview snapshot at kick time
  ///                     (the user can keep browsing this); unread
  ///                     count irrelevant since they can't read more.
  ///
  /// When the cache has no `ChatRoom` for the id (the kick landed right
  /// after a fresh login/cold start, or the room was never opened and so
  /// never persisted), we still synthesise a minimal stub from whatever
  /// `RoomDetail`/`UnreadRoom` snapshot exists — falling back to bare
  /// structural fields — so the kicked room never silently vanishes. The
  /// flag stays in `kickedRoomIds` and the room comes back richer on the
  /// next successful hydration.
  Future<RoomListItem?> _hydrateKickedRoomFromCache(
    ChatLocalDatasource cache,
    String roomId,
  ) async {
    final room = (await cache.getRoom(roomId)).dataOrNull;
    final detail = (await cache.getRoomDetail(roomId)).dataOrNull;
    final unreads =
        (await cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
    final unread = unreads.where((u) => u.roomId == roomId).firstOrNull;
    final base = RoomListItem(
      id: roomId,
      name: room?.name ?? detail?.name ?? detail?.subject,
      subject: room?.subject ?? detail?.subject,
      avatarUrl: room?.avatarUrl ?? detail?.avatarUrl,
      isGroup: detail?.type == RoomType.group,
      isAnnouncement: detail?.type == RoomType.announcement,
      memberCount: detail?.memberCount,
      // Degrades to the listing snapshot for the same reason `writePolicy`
      // below does, and has to degrade with it: the two are read together,
      // so a stub that knows the room is owner-only but not that this user
      // owns it describes a room nobody may write in. A kicked room this
      // pass had no detail for is exactly the case with a snapshot and no
      // detail to hand.
      userRole: detail?.userRole ?? unread?.userRole,
      // Snapshot of the last message at kick time. The unread
      // counter is forced to 0 — there's nothing the user can mark
      // as read anyway. Muted / pinned flags stay as last seen so
      // the row keeps its visual preferences.
      lastMessage: unread?.lastMessage,
      lastMessageTime: unread?.lastMessageTime,
      lastMessageUserId: unread?.lastMessageUserId,
      lastMessageId: unread?.lastMessageId,
      lastMessageType: unread?.lastMessageType,
      lastMessageMimeType: unread?.lastMessageMimeType,
      lastMessageFileName: unread?.lastMessageFileName,
      lastMessageDurationMs: unread?.lastMessageDurationMs,
      lastMessageIsDeleted: unread?.lastMessageIsDeleted ?? false,
      lastMessageIsSystem: unread?.lastMessageIsSystem ?? false,
      lastMessageReactionEmoji: unread?.lastMessageReactionEmoji,
      lastMessageReactionTargetText: unread?.lastMessageReactionTargetText,
      lastMessageReactionTargetType: unread?.lastMessageReactionTargetType,
      muted: unread?.muted ?? false,
      muteUntil: unread?.muteUntil,
      writePolicy:
          detail?.config.writePolicy ??
          unread?.writePolicy ??
          RoomWritePolicy.members,
      pinned: unread?.pinned ?? false,
      hidden: unread?.hidden ?? false,
      // The defining flag — composer is replaced by the
      // "no longer a participant" banner; the chat itself is fully
      // browsable.
      isParticipating: false,
    );
    final effective = computeEffectiveTitle(currentItem: base, detail: detail);
    return effective == null
        ? base
        : base.copyWith(effectiveDisplayName: effective);
  }
}
