part of 'room_enricher.dart';

/// The enrichment pass itself: what [RoomEnricher] turns a raw room list
/// into before it reaches the room list controller — titles, avatars,
/// previews, unread counts, presence and the host names it prefetches to
/// resolve them.
extension _RoomEnrichment on RoomEnricher {
  /// Resolves [userId] to a human-readable name using the adapter's user
  /// cache. Returns `null` when the user is the current user, when [userId]
  /// is null, or when the user hasn't been fetched yet — in that last case
  /// the room list refreshes automatically when [ChatUiAdapter.updateUser]
  /// later seeds the cache (via [_refreshLastSenderNamesFor]).
  String? _resolveSenderName(String? userId) {
    if (userId == null) return null;
    if (userId == _currentUser().id) return null;
    final cached = _findCachedUser(userId);
    final name = cached?.displayName?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  /// Builds the enriched rows for [userRooms] and paints them.
  ///
  /// [epoch] is the session the caller captured before its first `await`
  /// (see [_sessionEpoch]). Every write below is gated on it, so a pass
  /// whose session ended mid-flight is dropped instead of merged into
  /// whatever session is running when it lands.
  Future<void> _enrichAndSet(
    UserRooms userRooms, {
    required int epoch,
    String type = 'all',
    CachePolicy? detailPolicy,
    bool awaitDmResolution = false,
    bool authoritative = false,
    DateTime? snapshotAt,
    int? seq,
  }) async {
    // `detailPolicy == cacheOnly` marks the disk-only pass of [loadAll]:
    // the caller asked for what this device already knows, with no
    // network. `detailPolicy` used to reach only `client.rooms.get`, so
    // everything downstream — delivery confirmations, sender hydration,
    // presence bootstrap, DM resolution — went to the wire on the one
    // pass whose entire purpose is painting instantly from disk (and,
    // offline, whose awaited network call parked the first paint behind
    // a timeout). Each of those sites is now gated on this flag; see
    // each one for why deferring it to the network pass loses nothing.
    //
    // The deferral is safe by construction: the cache-trusting shortcut
    // in [loadAll] requires `_initializedNotifier`, which only a
    // completed network pass ever sets, so a cache pass is always
    // followed by a network pass (foreground on a cold start,
    // [_backgroundRevalidate] on a warm reopen) that does the full work.
    final cacheOnlyPass = detailPolicy == CachePolicy.cacheOnly;
    final detailFutures = userRooms.rooms.map(
      (unread) => client.rooms.get(unread.roomId, cachePolicy: detailPolicy),
    );
    final details = await Future.wait(detailFutures);

    // Per-user DELETED rooms (WhatsApp "Delete chat" parity). The set is
    // never-evictable in the cache; a deleted room stays gone from BOTH
    // lists until a peer writes again. We reconcile each one against its
    // (preserved) `clearedAt` cutoff below: a message newer than the
    // cutoff means the peer wrote again → resurrect (clear the marker,
    // surface the row empty-but-for-the-new-message); otherwise skip the
    // room entirely. `deletedRoomIds` tracks the survivors so the
    // controller's getters keep them excluded after [setRooms].
    // Read through the CLIENT surface — this is where
    // `ChatRoomsController.delete` persists the marker via
    // `client.rooms.markRoomDeleted`, so the filter survives even when the
    // adapter itself was built without a `cache:` arg (e.g. WB). The
    // adapter-level `cache` is consulted too as a backstop for hosts that
    // wired one directly before this client-level surface existed.
    // Both readers answer with a [ChatResult]: a failed read must not be
    // taken for "nothing was deleted", because the only consequence of
    // that answer is destructive — every chat the user deleted comes back
    // with its old preview. When neither reader could answer, this pass
    // carries the controller's own set forward instead of inventing one.
    final localCacheForDeleted = cache;
    final clientDeleted = await client.rooms.getDeletedRoomIds();
    final adapterDeleted = localCacheForDeleted == null
        ? null
        : await localCacheForDeleted.getDeletedRoomIds();
    final deletedReadFailed =
        clientDeleted.isFailure &&
        (adapterDeleted == null || adapterDeleted.isFailure);
    final deletedRoomIds = deletedReadFailed
        ? {...roomList.deletedRoomIds}
        : {...?clientDeleted.dataOrNull, ...?adapterDeleted?.dataOrNull};
    // Ids this pass proved a peer wrote to after the delete cutoff. Only
    // these may leave the controller's set.
    final resurrectedRoomIds = <String>{};

    final items = <RoomListItem>[];
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;

      final clearedAtResult = await client.messages.getClearedAt(unread.roomId);
      final clearedAt = clearedAtResult.dataOrNull;
      // Same rule as the deleted set above, for the same reason: a cutoff
      // this pass could not read is not proof the chat was never cleared,
      // and the only consequence of that answer is destructive — the row
      // repaints with the preview and the unread badge the user just
      // cleared. An unreadable pass paints the row without a preview
      // instead; the next readable pass restores whatever is really there.
      final isCleared =
          clearedAtResult.isFailure ||
          (clearedAt != null &&
              unread.lastMessageTime != null &&
              !unread.lastMessageTime!.isAfter(clearedAt));

      if (deletedRoomIds.contains(unread.roomId)) {
        // Resurrect only when the backend reports a message strictly newer
        // than the delete cutoff (a peer wrote again). Otherwise the chat
        // stays deleted — drop it from this list build. A cutoff this pass
        // could not read is not proof of anything, so it never resurrects:
        // the marker outlives one unreadable pass.
        final resurrected =
            clearedAtResult.isSuccess &&
            clearedAt != null &&
            unread.lastMessageTime != null &&
            unread.lastMessageTime!.isAfter(clearedAt);
        if (resurrected) {
          deletedRoomIds.remove(unread.roomId);
          resurrectedRoomIds.add(unread.roomId);
          // Gated on the epoch for the same reason the paint below is: a
          // pass that started under the outgoing identity would otherwise
          // still be writing to the store after `signOut()` cleared it,
          // and the id of a room the previous user deleted would survive
          // into the next session's cache. Skipping the write costs this
          // pass nothing — it is about to be dropped whole at [_stale].
          if (!_stale(epoch)) {
            unawaited(
              client.rooms
                  .clearRoomDeleted(unread.roomId)
                  .catchError(
                    (_) => const ChatFailureResult<void>(
                      UnexpectedFailure('clearRoomDeleted threw'),
                    ),
                  ),
            );
            unawaited(
              (localCacheForDeleted?.clearDeletedRoom(unread.roomId) ??
                      Future<void>.value())
                  .catchError((_) {}),
            );
          }
        } else {
          continue;
        }
      }

      // DM identity this session already resolved, replayed from memory
      // instead of from the wire. [RoomListController.mergeRooms] replaces
      // rows wholesale, so without this a cache pass on a warm reopen
      // overwrote an enriched DM row with a blank one (`otherUserId: null`,
      // no effective title, no peer avatar) and depended on a
      // `members.list` round-trip to put it back — a visible flash of
      // untitled rows, paid in network on the one pass that must not touch
      // it. Every read here is in-memory: the contact registry, the user
      // cache, the presence cache. Non-DM rooms and DMs never resolved on
      // this device produce `null` and behave exactly as before.
      final knownPeerId = dmContacts.contactIdFor(unread.roomId);
      final knownPeer = knownPeerId == null
          ? null
          : _findCachedUser(knownPeerId);
      final knownPresence = knownPeerId == null
          ? null
          : presence.presenceFor(knownPeerId);

      final base = RoomListItem(
        id: unread.roomId,
        name: detail?.name,
        subject: detail?.subject,
        avatarUrl: knownPeer?.avatarUrl ?? detail?.avatarUrl,
        isOnline: knownPresence?.online,
        presenceStatus: knownPresence?.status,
        lastMessage: isCleared ? null : unread.lastMessage,
        lastMessageTime: isCleared ? null : unread.lastMessageTime,
        lastMessageUserId: isCleared ? null : unread.lastMessageUserId,
        lastMessageSenderName: isCleared
            ? null
            : _resolveSenderName(unread.lastMessageUserId),
        lastMessageId: isCleared ? null : unread.lastMessageId,
        lastMessageReceipt: isCleared
            ? null
            : (unread.lastMessageReceipt ??
                  (unread.lastMessageUserId == _currentUser().id
                      ? ReceiptStatus.sent
                      : null)),
        lastMessageType: isCleared ? null : unread.lastMessageType,
        lastMessageMimeType: isCleared ? null : unread.lastMessageMimeType,
        lastMessageFileName: isCleared ? null : unread.lastMessageFileName,
        lastMessageDurationMs: isCleared ? null : unread.lastMessageDurationMs,
        lastMessageIsDeleted: isCleared ? false : unread.lastMessageIsDeleted,
        lastMessageIsSystem: isCleared ? false : unread.lastMessageIsSystem,
        lastMessageReactionEmoji: isCleared
            ? null
            : unread.lastMessageReactionEmoji,
        lastMessageReactionTargetText: isCleared
            ? null
            : unread.lastMessageReactionTargetText,
        lastMessageReactionTargetType: isCleared
            ? null
            : unread.lastMessageReactionTargetType,
        // Own last message → 0 unread (sending implies reading). Guards
        // the cold-load path against the backend counting the sender's own
        // message; the RefreshEngine has the polling-path twin.
        unreadCount:
            (isCleared || unread.lastMessageUserId == _currentUser().id)
            ? 0
            : unread.unreadMessages,
        unreadMentions:
            (isCleared || unread.lastMessageUserId == _currentUser().id)
            ? 0
            : unread.unreadMentions,
        muted: detail?.muted ?? false,
        muteUntil: detail?.muteUntil ?? unread.muteUntil,
        selfMuted: detail?.selfMuted ?? unread.selfMuted,
        // The detail is authoritative when the fetch landed; the listing
        // projection carries the same fields, so a row whose detail is still
        // missing already knows whether the room refuses messages — both
        // because the policy closed it and because a moderator silenced
        // this user.
        writePolicy: detail?.config.writePolicy ?? unread.writePolicy,
        pinned: detail?.pinned ?? false,
        hidden: detail?.hidden ?? false,
        isGroup:
            detail?.type == RoomType.group ||
            detail?.type == RoomType.announcement,
        isAnnouncement: detail?.type == RoomType.announcement,
        // Degrades to the listing for the same reason `writePolicy` above
        // does, and it has to degrade with it: the two are read together by
        // `isReadOnly`, so a row that knows the room is owner-only but not
        // that this user owns it closes the composer on the owner. The
        // listing projection carries `userRole` on every row, so the pair is
        // always complete on a pass with no detail — a cold start off the
        // cache, or any offline pass.
        userRole: detail?.userRole ?? unread.userRole,
        memberCount: detail?.memberCount,
        otherUserId: knownPeerId,
        custom: detail?.custom,
      );

      // Custom resolver may already produce an effective title from the
      // detail alone (e.g. an app that maps `detail.custom['nickname']` to
      // the title). The DM-aware default needs the peer: it is supplied
      // here when the session already knows it, and otherwise arrives
      // later via `_doResolveDmContact`.
      final effective = computeEffectiveTitle(
        currentItem: base,
        detail: detail,
        otherMembers: knownPeer != null ? [knownPeer] : const [],
        isDmOverride: knownPeerId != null ? true : null,
      );
      items.add(
        effective == null
            ? base
            : base.copyWith(effectiveDisplayName: effective),
      );
    }

    // Process invited rooms
    final invitedFutures = userRooms.invitedRooms.map(
      (inv) => client.rooms.get(inv.roomId, cachePolicy: detailPolicy),
    );
    final invitedDetails = userRooms.invitedRooms.isNotEmpty
        ? await Future.wait(invitedFutures)
        : <ChatResult<RoomDetail>>[];

    for (var i = 0; i < userRooms.invitedRooms.length; i++) {
      final inv = userRooms.invitedRooms[i];
      final detail = invitedDetails[i].dataOrNull;
      final base = RoomListItem(
        id: inv.roomId,
        name: detail?.name,
        avatarUrl: detail?.avatarUrl,
        isGroup: detail?.type == RoomType.group,
        writePolicy: detail?.config.writePolicy ?? RoomWritePolicy.members,
        custom: {
          ...?detail?.custom,
          'invited': true,
          'invitedBy': inv.invitedBy,
        },
      );
      final effective = computeEffectiveTitle(
        currentItem: base,
        detail: detail,
      );
      items.add(
        effective == null
            ? base
            : base.copyWith(effectiveDisplayName: effective),
      );
    }

    // WhatsApp-parity: merge locally-retained "kicked rooms" so a
    // user who was removed from a group keeps the chat visible
    // (read-only) across cold starts. `bulk_conversations` doesn't
    // return these rooms because the user isn't a member anymore;
    // we hydrate them from the local cache (`ChatRoom`,
    // `RoomDetail`, last `UnreadRoom` snapshot) and set
    // `isParticipating=false` so the UI swaps the composer for the
    // banner. Re-add by an admin removes the id from `kickedRoomIds`
    // (`_handleUserRejoined`) so the next sync surfaces the live
    // version of the room. Same for an explicit
    // `ChatRoomOption.deleteKickedChat` tap.
    final localCache = cache;
    if (localCache != null) {
      try {
        final kickedIds =
            (await localCache.getKickedRoomIds()).dataOrNull ??
            const <String>{};
        if (kickedIds.isNotEmpty) {
          final backendIds = items.map((r) => r.id).toSet();
          for (final kickedId in kickedIds) {
            if (backendIds.contains(kickedId)) {
              if (authoritative) {
                // Network pass: the backend authoritatively returned
                // this room → admin re-added the user. Clear the local
                // kicked flag so it doesn't linger. Epoch-gated like
                // every other write in this pass: a pass belonging to the
                // identity that just signed out must not put ids back
                // into the store after `clear()` emptied it.
                if (!_stale(epoch)) {
                  unawaited(
                    localCache
                        .unmarkKicked(kickedId)
                        .catchError(
                          (Object _) => const ChatFailureResult<void>(
                            UnexpectedFailure('cache mutator threw'),
                          ),
                        ),
                  );
                }
              } else {
                // Cache pass: a stale unreads box may still list the
                // room — do NOT treat it as a re-add and do NOT clear
                // the kicked flag. Keep the matched row read-only so the
                // stale snapshot can't wipe the kicked state before the
                // authoritative network pass reconciles.
                final idx = items.indexWhere((r) => r.id == kickedId);
                if (idx != -1 && items[idx].isParticipating) {
                  items[idx] = items[idx].copyWith(isParticipating: false);
                }
              }
              continue;
            }
            final hydrated = await _hydrateKickedRoomFromCache(
              localCache,
              kickedId,
            );
            if (hydrated != null) items.add(hydrated);
          }
        }
      } catch (_) {
        // Cache miss / corruption: degrade silently to the unmerged
        // backend-only list. The kicked room reappears the next
        // time the user gets the live event (rare; mostly cold
        // start scenarios where the kick happened mid-network drop).
      }
    }

    if (_stale(epoch)) return;
    // Only `type == 'all'` with no `hasMore` is the complete room set
    // (mirrors `RoomsApi.getUserRooms`'s cache-write distinction) — a
    // filtered or paginated view never prunes. Computed once and reused by
    // both the write below and the DM dedupe pass further down so the two
    // agree on whether this fetch may make a destructive call.
    final representsCompleteSet =
        (type == 'all' || type.isEmpty) && !userRooms.hasMore;
    // The very first population of a fresh list (nothing shown yet, cache
    // or otherwise) uses a plain replace — there's nothing to preserve and
    // no risk of a flash. Every subsequent pass merges in place instead:
    // a non-authoritative (cache) pass never drops a row it doesn't know
    // about, and an authoritative (network) pass still reconciles fully,
    // but without ever clearing the list en route to the new snapshot.
    if (roomList.allRooms.isEmpty) {
      roomList.setRooms(items, seq: seq);
    } else {
      roomList.mergeRooms(
        items,
        authoritative: authoritative,
        representsCompleteSet: representsCompleteSet,
        snapshotAt: snapshotAt,
        seq: seq,
      );
    }
    // Seed the controller's in-memory deleted set so its synchronous
    // getters keep excluding any deleted room that some other path (a
    // late `addFromDetail`, a polling re-add) might re-insert before the
    // next live resurrection event clears it. Merged, not replaced: an id
    // leaves the set only when this pass proved the room was resurrected.
    roomList.mergeDeletedRoomIds(deletedRoomIds, remove: resurrectedRoomIds);

    // Resolve DM contacts. The network pass awaits them so the room list
    // is internally consistent before `loadRooms` resolves: every DM has
    // its `otherUserId` set, `_dmRoomByContact` is populated, and any
    // duplicate DM rooms have been collapsed.
    //
    // The cache pass resolves them too, but with [CachePolicy.cacheOnly]
    // threaded all the way down: `members.list` and the peer's
    // `users.get` both read the local store and stop there, so the pass
    // stays at zero requests while still recovering the peer identity of
    // a DM this session has never seen. Replaying `dmContacts` (done when
    // the rows were built above) only covers a warm reopen; on a cold
    // start that registry is empty and the roster on disk is the only
    // thing that can name the row. A DM with no roster stored falls
    // through to a miss and paints exactly as it did before, corrected by
    // the network pass of this same [loadAll].
    final dmPolicy = cacheOnlyPass ? CachePolicy.cacheOnly : null;
    final dmFutures = <Future<void>>[];
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;
      if (detail != null && _isDmDetail(detail)) {
        if (awaitDmResolution) {
          dmFutures.add(
            _doResolveDmContact(
              unread.roomId,
              authoritative: authoritative,
              representsCompleteSet: representsCompleteSet,
              seq: seq,
              cachePolicy: dmPolicy,
              epoch: epoch,
            ),
          );
        } else {
          resolveDmContact(
            unread.roomId,
            authoritative: authoritative,
            representsCompleteSet: representsCompleteSet,
            seq: seq,
            cachePolicy: dmPolicy,
            epoch: epoch,
          );
        }
      }
    }
    if (dmFutures.isNotEmpty) {
      await Future.wait(dmFutures);
      if (_stale(epoch)) return;
    }

    // Pre-fetch the user behind every `lastMessageUserId` we don't yet
    // know about. Without this, the chat list paints groups with a
    // null `lastMessageSenderName` until the next `new_message` event
    // pulls the sender's profile into the cache — so freshly-loaded
    // groups looked broken ("hola" with no "Alice: " prefix). Each
    // `_ensureUserCached` resolves into `cacheUsers`, which in turn
    // fires `_refreshLastSenderNamesFor` and flips the row to
    // "Alice: hola" automatically. Fire-and-forget — UI refreshes
    // when each fetch resolves.
    //
    // Not on the cache pass: `ensureUserCached` is a REST read per unknown
    // sender and has no cache path of its own. Nothing is lost by waiting
    // — a sender absent from the cache has no name to render either way,
    // so the row paints identically; the network pass hydrates them and
    // the prefix appears then. On a warm reopen the senders are already
    // cached, so this loop was empty anyway.
    if (!cacheOnlyPass) {
      final senderIds = <String>{};
      for (final room in roomList.allRooms) {
        final senderId = room.lastMessageUserId;
        if (senderId == null) continue;
        if (senderId == _currentUser().id) continue;
        if (userCache.contains(senderId)) continue;
        senderIds.add(senderId);
      }
      for (final id in senderIds) {
        unawaited(_ensureUserCachedFn(id));
      }
    }

    // Everyone this listing needs a name for, asked of the host in one
    // batch instead of one call per row: the senders above plus the peer
    // of every one-to-one row. Runs on the cache pass too — unlike the
    // chat profile fetch, the directory has a disk answer of its own and
    // the point is to fill in the titles that came back blank.
    _prefetchHostNames();

    // Confirm delivery for every room whose last message came from
    // someone else AND is still unread. Mirrors WhatsApp: as soon as
    // the recipient comes online (loadRooms resolves), the sender sees
    // ✓✓ even if the recipient hasn't opened the chat yet. The
    // `_onNewMessage` path already covers messages received during the
    // live session — this catches the backlog accumulated while
    // offline. One consolidated cursor per room (≤1 confirmation per
    // conversation per sync); the server max-merges, so re-confirming
    // across reconnects is free.
    //
    // Not on the cache pass: each entry is a POST, and confirming
    // delivery from a snapshot read off disk claims a receipt this device
    // has not actually taken from the server yet. The network pass of the
    // same [loadAll] sends the real ones; a reconnect re-runs them via
    // `resync` -> `loadRooms(forceNetwork: true)`.
    final confirmDelivered = _confirmDelivered;
    if (confirmDelivered != null && !cacheOnlyPass) {
      for (final room in roomList.allRooms) {
        final lastId = room.lastMessageId;
        final lastFrom = room.lastMessageUserId;
        if (lastId == null) continue;
        if (lastFrom == null) continue;
        if (lastFrom == _currentUser().id) continue;
        if (room.unreadCount <= 0) continue;
        unawaited(confirmDelivered(room.id, lastId));
      }
    }

    // Bootstrap presence BEFORE returning so any consumer that reads
    // `presenceFor(userId)` right after `loadRooms()` resolves sees a
    // populated cache. Failures are swallowed (rooms keep `isOnline: null`).
    //
    // Not on the cache pass: this is an AWAITED `GET /presence` with no
    // cache path (`PresenceApi` takes no `CacheManager`), so it put a
    // whole round-trip — a whole timeout, offline — in front of the first
    // paint. The contract above still holds for `loadRooms()`: the
    // blocking path always ends in a network pass, which bootstraps; and
    // the only path that returns without one requires an already
    // initialized, connected session, i.e. presence was bootstrapped by an
    // earlier pass and is being kept current by `presence_changed` events.
    if (!cacheOnlyPass) await presence.bootstrap();
  }

  /// Queues every id in the current listing the host might have a name
  /// for. No-op when no directory is wired.
  void _prefetchHostNames() {
    final directory = userCache.directory;
    if (!directory.isEnabled) return;
    final me = _currentUser().id;
    final ids = <String>{};
    for (final room in roomList.allRooms) {
      final peerId = room.otherUserId;
      if (peerId != null && peerId.isNotEmpty && peerId != me) ids.add(peerId);
      final senderId = room.lastMessageUserId;
      if (senderId != null && senderId.isNotEmpty && senderId != me) {
        ids.add(senderId);
      }
    }
    if (ids.isNotEmpty) directory.prefetch(ids);
  }
}
