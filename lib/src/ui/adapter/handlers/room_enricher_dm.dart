part of 'room_enricher.dart';

/// Direct-message resolution for [RoomEnricher]: the walk that maps a
/// contact to the room the two of them already share, and the tie-break
/// that picks one when more than one candidate exists.
extension _RoomEnricherDm on RoomEnricher {
  Future<void> _doResolveDmContact(
    String roomId, {
    bool authoritative = true,
    bool representsCompleteSet = true,
    int? seq,
    CachePolicy? cachePolicy,
    int? epoch,
  }) async {
    final passEpoch = epoch ?? _sessionEpoch;
    try {
      final membersResult = await client.members.list(
        roomId,
        cachePolicy: cachePolicy,
      );
      if (_stale(passEpoch)) return;
      if (membersResult.isFailure) {
        _logger?.call(
          'warn',
          'DM resolve: members.list failed for $roomId: ${membersResult.failureOrNull}',
        );
        return;
      }
      final members = membersResult.dataOrNull?.items ?? [];
      // Filter out empty userIds defensively. The backend sometimes
      // returns members with `userId: ""` for orphan owners (a user
      // that was wiped from `user_client_service` but whose membership
      // entry stayed in the room's member list). Trying to resolve an empty userId
      // pollutes `_dmRoomByContact[''] = roomId` and leaves the row
      // with no displayName / a "?" avatar. Skip those members so DM
      // resolution moves on to the next candidate.
      final otherMember = members
          .where((m) => m.userId.isNotEmpty && m.userId != _currentUser().id)
          .firstOrNull;
      if (otherMember == null) return;

      // Blocking KEEPS the DM chat (read-only via the blocked composer
      // banner), WhatsApp parity — so a blocked peer's row still resolves
      // its title/avatar and stays in the list. (Previously the row was
      // dropped here when the peer was blocked, which made the
      // conversation vanish from the list entirely.) The block only
      // affects the composer, handled elsewhere.

      // Dedupe ghost DM rooms. If we already mapped a different
      // roomId to this contact, the server has two conversations between
      // the same pair (typically: an old DM with history + a fresh empty
      // room created from a race between `findExistingDmRoom` and a
      // background DM resolution). Keep the "best" one — preference order:
      //   1. Room with a non-null lastMessageTime (history wins).
      //   2. Most recent lastMessageTime.
      //   3. The roomId already in `_dmRoomByContact` (stability over the
      //      newly resolved one).
      // The other row is dropped from the list AND removed from the local
      // cache so it doesn't reappear on the next cache-then-network hop.
      final existingMappedRoomId = dmContacts.roomIdFor(otherMember.userId);
      if (existingMappedRoomId != null && existingMappedRoomId != roomId) {
        final keep = _pickPreferredDmRoom(existingMappedRoomId, roomId);
        final drop = keep == existingMappedRoomId
            ? roomId
            : existingMappedRoomId;
        // Persisting the loser's eviction is only safe when THIS pass
        // could itself prune authoritatively — same rule `mergeRooms`
        // applies to its own drop step. A filtered/paginated view
        // (`representsCompleteSet: false`) or a fetch that resolved after
        // a fresher one already landed (`seq` stale) picked its winner from
        // incomplete/outdated information, so evicting the loser from the
        // local cache here would be a PERMANENT data loss the next
        // complete-set pass could not undo.
        final canPersistDrop =
            authoritative &&
            roomList.allowsInferredPrune(
              representsCompleteSet: representsCompleteSet,
              seq: seq,
            );
        _logger?.call(
          'info',
          'DM dedupe: contact=${otherMember.userId} keep=$keep drop=$drop '
              '(authoritative=$authoritative, persist=$canPersistDrop)',
        );
        // Always suppress the loser from the visible list — showing both
        // rows is never correct. Only when `canPersistDrop` holds does the
        // removal persist: disposing the chat controller and evicting the
        // row from the local cache. Otherwise both the cache and the
        // dm-by-contact mapping stay untouched so a later, trustworthy
        // authoritative pass can still reconcile correctly even if this
        // pass picked the "wrong" winner from an incomplete/stale view.
        roomList.removeRoom(drop);
        if (canPersistDrop) {
          _removeChatController(drop);
          unawaited(
            (cache?.deleteRoom(drop) ?? Future<void>.value()).catchError(
              (_) {},
            ),
          );
          unawaited(
            (cache?.deleteRoomDetail(drop) ?? Future<void>.value()).catchError(
              (_) {},
            ),
          );
        }
        dmContacts.bind(otherMember.userId, keep);
        if (keep != roomId) {
          // The newly-resolved room loses — stop enriching it.
          return;
        }
      } else {
        dmContacts.bind(otherMember.userId, roomId);
      }

      // Hydrate the other user so the DM-aware default title can render
      // their `displayName` instead of the raw room id. The cache update
      // also feeds [cacheUsers], which fans out to any other room rows
      // pointing at the same user.
      ChatUser? otherUser = _findCachedUser(otherMember.userId);
      if (otherUser == null) {
        // Explicit `cacheFirst` instead of falling through to
        // `CacheConfig.defaultReadPolicy` (`networkFirst`): we only get
        // here on an in-memory miss, and a peer profile already on disk is
        // a perfectly good title + avatar. Left implicit, every DM cost a
        // `GET /users/{id}` on every cold start even though the answer was
        // stored locally. `cacheFirst` honours `CacheConfig.ttlUsers`
        // (6 h by default) and its timestamps survive restarts, so a
        // renamed peer still refreshes on its own; a network failure falls
        // back to the stale entry rather than leaving the row untitled.
        // An inherited [cachePolicy] wins: a disk-only pass must not reach
        // the wire through this door either.
        final userResult = await client.users.get(
          otherMember.userId,
          cachePolicy: cachePolicy ?? CachePolicy.cacheFirst,
        );
        if (_stale(passEpoch)) return;
        otherUser = userResult.dataOrNull;
        if (otherUser != null) {
          _cacheUsersFn([otherUser]);
        }
      }

      final existing = roomList.getRoomById(roomId);
      if (existing == null) return;
      final cachedPresence = presence.presenceFor(otherMember.userId);
      final effective = computeEffectiveTitle(
        currentItem: existing,
        otherMembers: otherUser != null ? [otherUser] : const [],
        isDmOverride: true,
      );
      roomList.updateRoom(
        existing.copyWith(
          otherUserId: otherMember.userId,
          avatarUrl: otherUser?.avatarUrl ?? existing.avatarUrl,
          isOnline: cachedPresence?.online ?? existing.isOnline,
          presenceStatus: cachedPresence?.status ?? existing.presenceStatus,
          effectiveDisplayName: effective ?? existing.effectiveDisplayName,
        ),
      );
      _onDmContactResolved?.call()?.call(roomId, otherMember.userId);
    } catch (e) {
      _logger?.call(
        'warn',
        'Failed to resolve DM contact for room $roomId: $e',
      );
    }
  }

  /// Picks the "best" of two DM roomIds pointing at the same contact —
  /// the room with history beats the empty one; if both have history, the
  /// most recent wins. Any exact tie (both empty, or identical
  /// `lastMessageTime`) is broken by comparing the room ids themselves
  /// (`compareTo`), NOT by which argument happened to be "existing" vs
  /// "new" — the previous stability heuristic (`existingId` always wins a
  /// tie) made the winner depend on which of the two rooms' DM resolution
  /// happened to complete first, which flips from refresh to refresh under
  /// normal async scheduling and was the actual cause of the room list
  /// flickering between two rows for the same contact. Comparing the ids
  /// is symmetric regardless of call order, so the same pair always
  /// resolves to the same winner. Used by the duplicate-DM dedupe path in
  /// [_doResolveDmContact].
  String _pickPreferredDmRoom(String existingId, String newId) {
    final existing = roomList.getRoomById(existingId);
    final candidate = roomList.getRoomById(newId);
    final existingHasHistory = existing?.lastMessageTime != null;
    final candidateHasHistory = candidate?.lastMessageTime != null;
    if (existingHasHistory && !candidateHasHistory) return existingId;
    if (!existingHasHistory && candidateHasHistory) return newId;
    if (existingHasHistory && candidateHasHistory) {
      final eTime = existing!.lastMessageTime!;
      final cTime = candidate!.lastMessageTime!;
      if (cTime.isAfter(eTime)) return newId;
      if (eTime.isAfter(cTime)) return existingId;
      // Exact same timestamp — fall through to the deterministic tie-break.
    }
    return existingId.compareTo(newId) <= 0 ? existingId : newId;
  }
}
