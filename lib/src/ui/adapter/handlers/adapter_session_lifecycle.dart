part of '../chat_ui_adapter.dart';

/// Session lifecycle of [ChatUiAdapter]: the client stream subscriptions,
/// [ChatUiAdapter.connect], the debounced post-reconnect
/// [ChatUiAdapter.resync], [ChatUiAdapter.disconnect],
/// [ChatUiAdapter.signOut] and [ChatUiAdapter.dispose], plus the state each
/// of them resets.
///
/// Lives next to the adapter as a `part` and is mixed into [ChatUiAdapter],
/// so every member stays a real instance member of the adapter and reads
/// and writes the same private fields it did when it sat in the class body.
mixin _AdapterSessionLifecycle on _AdapterCore {
  /// Starts listening to SDK events without connecting. Call [connect] instead for full setup.
  void start() {
    _cancelSubscriptions();
    _eventSub = client.events.listen(_handleEvent);
    _stateSub = client.stateChanges.listen(_handleStateChange);
    // The offline-queue callback is part of the `ChatClient` contract as of
    // 0.3.0; mocks implement it as a no-op. No `is`/`as` cast needed.
    client.onOfflineMessageSent = _handleOfflineMessageSent;
  }

  void _handleOfflineMessageSent(
    String roomId,
    String tempId,
    ChatMessage message,
  ) {
    final controller = _chatControllers[roomId];
    final confirmed = _ensureSentReceipt(message);
    if (controller != null) {
      if (confirmed.isProvisional) {
        // The drained send returned an ack_mode=async provisional echo:
        // its id is untrusted, so flip the bubble from failed back to
        // pending and let the authoritative `new_message` event reconcile
        // it by clientMessageId.
        controller.markPending(tempId);
      } else {
        controller.confirmSent(tempId, confirmed);
      }
    }
    unawaited(
      _cache
              ?.deletePendingMessage(roomId, tempId)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
    _roomListMutator.updateRoomLastMessage(roomId, confirmed);
  }

  /// Connects to the server and starts listening for real-time events.
  ///
  /// Hydrates the room list from disk first (see [ChatRoomsController.hydrate])
  /// when the host has not already done so, so a cache-first SDK never
  /// hands over its cached rows behind a handshake. That adds local I/O
  /// ahead of the socket; a store that throws is logged and skipped —
  /// an unreadable cache must never stop a connection.
  ///
  /// Under [bootstrapCurrentUser] the chat account is settled here too,
  /// once the socket is up and before the host gets a chance to load its
  /// rooms: see [ChatProfileController.ensureRegistered]. It never aborts
  /// the connection — a bootstrap that cannot run is logged, and the
  /// session carries on with whatever account the server does have.
  Future<void> connect() async {
    _cancelSubscriptions();
    start();
    if (!_enricher.hasHydratedFromCache) {
      try {
        await rooms.hydrate();
      } catch (e) {
        logger?.call('warn', 'connect: cache hydration failed: $e');
      }
    }
    await client.connect();
    if (bootstrapCurrentUser) {
      try {
        await profile.ensureRegistered();
      } catch (e) {
        logger?.call('warn', 'connect: current user bootstrap failed: $e');
      }
    }
  }

  /// Full realtime resync after a reconnect: refreshes the room list from
  /// the network (`forceNetwork: true`) and, if a room is currently
  /// foregrounded ([activeRoomId]), reloads its messages — which also
  /// re-confirms delivery/read receipts as a side effect of the normal
  /// [loadMessages] flow, backfilling anything that arrived during the
  /// disconnected window. Presence is deliberately NOT re-bootstrapped
  /// here: the adapter's existing reconnect hook already does that (see
  /// `ChatEventRouter._onConnected`) right before this runs, so doing it
  /// again here would just be a redundant network call.
  ///
  /// A no-op until [initializedNotifier] has gone `true` once (i.e. a first
  /// [loadRooms] has actually completed): there is nothing to "resync" for
  /// a session that never loaded its rooms yet, and firing a network fetch
  /// ahead of the host's own initial [loadRooms] call could race it.
  ///
  /// Debounced to at most once every 5 seconds so a burst of flappy
  /// reconnects (or an app resume racing an in-flight reconnect) doesn't
  /// fan out into repeated network round-trips. Called automatically on
  /// every reconnect when [enableReconnectResync] is `true`; hosts can also
  /// call it directly (e.g. from a pull-to-refresh gesture), subject to
  /// the same debounce.
  ///
  /// A trigger is never simply dropped: one that lands *while a resync is
  /// already running* is coalesced into a single follow-up pass
  /// ([_resyncPending]); one that lands inside the *time* debounce window
  /// arms a single deferred call for whatever remainder of the window is
  /// left ([_scheduleDeferredResync]). Either way, a reconnect's own
  /// disconnected-window backlog always gets a resync pass once the
  /// current one (in-flight or debounced) clears.
  ///
  /// The debounce timestamp is committed per attempt and only survives once
  /// the attempt succeeds: `loadRooms`/`loadMessages` normally surface
  /// network/auth errors as a failed [ChatResult] rather than an exception,
  /// but a raw throw is treated identically — either way the seal is reverted
  /// (only if this attempt still owns it) so the very next reconnect or caller
  /// retries immediately instead of waiting out the window on a resync that
  /// silently did nothing.
  Future<void> resync() async {
    if (_disposed) return;
    if (!initializedNotifier.value) return;

    // Already running: don't let the time debounce drop this trigger —
    // remember it and let the running loop take one more pass.
    if (_resyncInFlight) {
      _resyncPending = true;
      return;
    }

    final now = DateTime.now();
    if (_lastResyncAt != null &&
        now.difference(_lastResyncAt!) < _resyncDebounce) {
      _scheduleDeferredResync(now);
      return;
    }

    _resyncDeferredTimer?.cancel();
    _resyncDeferredTimer = null;

    _resyncInFlight = true;
    try {
      do {
        _resyncPending = false;
        final attemptAt = DateTime.now();
        _lastResyncAt = attemptAt;
        bool ok;
        try {
          ok = await _runResyncOnce();
        } catch (_) {
          ok = false;
        }
        if (_disposed) return;
        // Revert the seal only if this attempt still owns it (no newer
        // attempt re-stamped it) — a per-attempt seal, never a shared one.
        if (!ok && identical(_lastResyncAt, attemptAt)) {
          _lastResyncAt = null;
        }
      } while (_resyncPending && !_disposed);
    } finally {
      _resyncInFlight = false;
    }
  }

  /// Arms a single deferred [resync] call for the remainder of the current
  /// debounce window, so a trigger the time debounce just dropped still
  /// runs once the window clears instead of being lost outright. A burst of
  /// triggers inside the same window coalesces into the one already-armed
  /// timer rather than stacking up several.
  void _scheduleDeferredResync(DateTime triggeredAt) {
    if (_resyncDeferredTimer != null) return;
    final lastResyncAt = _lastResyncAt;
    if (lastResyncAt == null) return;
    final elapsed = triggeredAt.difference(lastResyncAt);
    final remaining = _resyncDebounce - elapsed;
    final wait = remaining.isNegative ? Duration.zero : remaining;
    _resyncDeferredTimer = Timer(wait, () {
      _resyncDeferredTimer = null;
      if (_disposed) return;
      unawaited(resync());
    });
  }

  /// One resync pass: refresh the room list from the network and, if a room
  /// is foregrounded, reload its messages. Returns `true` only when every
  /// leg succeeded. Throws propagate to [resync], which treats them as a
  /// failed attempt.
  ///
  /// This pass runs after `ChatEventRouter._onConnected` fires (reconnect),
  /// and — same as an explicit pull-to-refresh — trusts a successful
  /// `loadRooms` response as the caller's authoritative complete room set:
  /// the listing endpoint fails the request outright on a bad read rather
  /// than answering 200 with a partial page, so there's nothing here left
  /// to distrust about a 200. This is what reconciles a room removed on
  /// another device while this one was offline/reconnecting.
  ///
  /// The foregrounded room also gets its detail re-read. The roster frames
  /// that keep `memberCount` (and the title, the avatar, the read-only
  /// flag) current only arrive while the socket is up, and the list pass
  /// above resolves each room's detail through the cache — so a join that
  /// happened while this device was backgrounded or disconnected came back
  /// as a visible system message in the transcript next to a header still
  /// counting the members the room had on the way in, and stayed that way
  /// for as long as the user kept the room open (`setActiveRoom` does not
  /// fire again for a room already active). Re-reading the detail here is
  /// the same self-healing moment opening the room already is, for the one
  /// room whose header is on screen.
  Future<bool> _runResyncOnce() async {
    final roomsResult = await loadRooms(forceNetwork: true);
    if (_disposed) return false;
    if (roomsResult.isFailure) return false;
    final activeRoomId = _activeRoomId;
    if (activeRoomId != null) {
      if (roomListController.getRoomById(activeRoomId) != null) {
        _enrichRoomFromDetail(activeRoomId);
      }
      final messagesResult = await loadMessages(activeRoomId);
      if (_disposed) return false;
      if (messagesResult.isFailure) return false;
    }
    return true;
  }

  /// Disconnects from the server.
  ///
  /// Cache-first by default (`clearRooms: false`): only the realtime
  /// connection itself is torn down. The room list, the currently
  /// foregrounded room's controller ([activeRoomId]) and the DM
  /// contact↔room binding all survive — the list never flashes empty
  /// across a background/reconnect cycle, and a subsequent [resync] can
  /// backfill the open conversation. Pass `clearRooms: true` for the old
  /// eager-wipe behavior (also used internally by [signOut] / [dispose]).
  /// The cross-session caches — user cache, blocked-users set, presence —
  /// always survive; use [signOut] to wipe those too.
  Future<void> disconnect({bool clearRooms = false}) async {
    await _cancelSubscriptions();
    client.cancelPendingRequests('disconnect');
    await client.disconnect();
    // Subscriptions are cancelled BEFORE `client.disconnect()` (above) so
    // the transport's own disconnected event/state never reaches the event
    // router mid-teardown — which means neither `connectionStateNotifier`
    // nor the router's own reconnect-detection latch would otherwise ever
    // flip off `connected`. A later `connect()` computes `wasConnected` from
    // that latch in `ChatEventRouter._onConnected`, so leaving it stale
    // would silently skip the presence bootstrap + resync on the very next
    // reconnect — exactly the resume-after-background path
    // `ChatPauseAction.disconnect` relies on. Reset both explicitly here,
    // mirroring `signOut()`'s existing notifier reset below.
    connectionStateNotifier.value = ChatConnectionState.disconnected;
    _eventRouter.markDisconnected();
    _resetConnectionState(clearRooms: clearRooms);
  }

  /// Wipes the state tied to a single realtime connection. Shared by
  /// [disconnect] and (transitively) [signOut] / [dispose] — the latter two
  /// always pass [clearRooms] `true` via the default, so neither can
  /// accidentally leave stale rooms/controllers behind. Keeps the
  /// cross-session caches intact — see [_resetSessionState] for the wider
  /// wipe.
  ///
  /// With [clearRooms] `false` (the resumable [disconnect] path):
  /// [_activeRoomId], the active room's [ChatController] and [_dmContacts]
  /// (the DM dedupe binding) are preserved, and the room list is left as-is
  /// — so a `ChatRoomPage` open at the moment of backgrounding keeps its
  /// controller mounted, and [resync] has something to backfill on resume.
  void _resetConnectionState({bool clearRooms = true}) {
    if (clearRooms) {
      _sessionEpoch++;
      // Paired with the bump, on the same line of execution, because the
      // window where an upload turns into an orphan blob has no other
      // trigger. `onProgress` cannot carry the abort: it stops firing when
      // the last byte of the body is written, which is precisely when the
      // bytes are billable and no message references them yet. An upload
      // parked there waiting for its response never ticks again, so an
      // abort that lives inside the tick never runs — the clip lands for a
      // session that is gone, and no API can reclaim it.
      //
      // This reaches it from outside the transfer, tick or no tick, and the
      // reach is a real abort rather than a flag someone has to notice:
      // `UploadCancelToken.cancel` runs the callback `RestClient.uploadBinary`
      // bound to it (`bindOnCancel`), which cancels the request's own Dio
      // `CancelToken` and tears the connection down. Nothing polls
      // `isCancelled` for this to work.
      //
      // A host-supplied `ChatAttachmentsApi` is free to accept the token and
      // ignore it — `UploadCancelToken`'s own contract says so — and then
      // the bytes do land. That case is not covered here but downstream: the
      // epoch each send captured no longer matches, so `sendAttachment` and
      // `sendVoice` refuse to build a message on the blob instead of posting
      // one into a session that is over.
      _attachmentUploadCancels.cancelAll();
      _chatControllers.disposeAll();
      _dmContacts.clear();
      _roomRosters.clear();
      _activeRoomId = null;
      // Raised only across the wipe itself: `setRooms([])` notifies
      // synchronously, so every listener that has to tell this apart from a
      // removal reads [isTearingDown] from inside that notification. The
      // adapter stays reusable after a `disconnect` / `signOut`, so the flag
      // must not outlive the call; [dispose] keeps it raised through
      // [_disposed] instead.
      //
      // Restored to what it was rather than forced back down:
      // [_resetSessionState] raises the same flag across a wider wipe that
      // keeps notifying after this call returns, and lowering it here would
      // cut that cover in half.
      final wasClearing = _clearingRooms;
      _clearingRooms = true;
      try {
        roomListController.setRooms([]);
      } finally {
        _clearingRooms = wasClearing;
      }
    }
    _typingTimers.clearAll();
    _lastMembersChangedRoomId = null;
  }

  /// Wipes every in-memory registry the adapter owns — both the
  /// per-connection state ([_resetConnectionState], which also aborts every
  /// in-flight upload) and the cross-session caches (user cache, blocked
  /// users, presence, confirmed delivered cursors, pending-reaction
  /// suppression, voice-upload progress).
  /// Shared by [signOut] and [dispose] so neither can drift from the full
  /// state inventory: adding a new registry to the adapter means clearing it
  /// here once, and both teardown paths pick it up.
  void _resetSessionState() {
    // Raised across the WHOLE inventory, not just the `setRooms([])` inside
    // [_resetConnectionState]: the wipe keeps notifying the room list after
    // that call returns — `_enricher.resetSession()` drops the deleted-room
    // mirror, and `setDeletedRoomIds` notifies too — and a listener reading
    // [isTearingDown] to tell a teardown from a removal has to get the same
    // answer on every notification the teardown emits. Without this,
    // [signOut] told the truth on the first one and lied on the last.
    _clearingRooms = true;
    try {
      // Runs first: it cancels the upload tokens, so the progress notifiers
      // let go of just below are released after their transfers were told to
      // stop, not while one is still writing to them. (Nothing here disposes
      // a notifier — they are published through the adapter's getters and a
      // host may hold one; the registry only drops its references.)
      _resetConnectionState();
      _userCacheService.clear();
      _blockedUsers.clear();
      _presence.clear();
      // The suppression map is keyed by room id alone, so a cursor confirmed
      // for the outgoing identity would silently suppress the incoming one's
      // first confirmation for the same room.
      _deliveredCoord.reset();
      _pendingReactionsRegistry.clear();
      _voiceUploads.releaseAll();
      // Raw media belonging to the account being torn down must not survive
      // into the next one — same reasoning as flushing the offline queue.
      _failedUploads.clear();
      _enricher.resetSession();
    } finally {
      _clearingRooms = false;
    }
  }

  /// One-shot teardown for "logout" flows: disconnects, wipes every
  /// in-memory cache (users, DM mapping, blocked-users set, draft custom
  /// payloads, voice-upload progress notifiers) and best-effort flushes
  /// the persistent cache. After this call the adapter is in the same
  /// shape as a fresh instance — safe to either dispose or reconnect
  /// with a new user.
  ///
  /// Hosts typically call this from a "Log out" menu item. Pair with
  /// [NomaChat.dispose] on the facade to release the cache datasource
  /// as well.
  ///
  /// Routes through [ChatClient.logout] so the client-owned session state
  /// goes too — above all the offline queue. A send or an upload that
  /// failed on a connectivity error is parked there
  /// (`client.enqueueOfflineAttachment`) with no record of who queued it,
  /// and it drains on the *next* connection whoever that connection now
  /// authenticates as: without this call an attachment queued by the
  /// account being signed out would be uploaded and posted under the
  /// account that signs in next. Clearing the persistent cache alone is
  /// not enough — that only wipes the queue's persisted copy, and the
  /// client's in-memory queue survives it and re-persists on the next
  /// enqueue. Unconditional because [signOut] has exactly one meaning: a
  /// teardown the queue is meant to survive — backgrounding, a connection
  /// blip — is [disconnect], which leaves both the queue and the caches
  /// alone.
  ///
  /// This does **not** set [_disposed] — the adapter deliberately stays
  /// usable so the next user can sign in on the same instance. Anything
  /// long-running that has to notice the logout therefore has to test
  /// [_sessionEndedSince] and not [_disposed]; the two upload paths capture
  /// the epoch up front for exactly this reason.
  Future<void> signOut() async {
    await disconnect();
    // Before the logout below, not after: it bumps the session epoch and
    // aborts the in-flight uploads, and an upload aborted after the queue
    // was emptied would re-enqueue itself into the session that just ended.
    _resetSessionState();
    initializedNotifier.value = false;
    connectionStateNotifier.value = ChatConnectionState.disconnected;
    try {
      await client.logout();
    } catch (_) {
      // best-effort, like the cache clear below: `logout` ends with its own
      // cache wipe, so a datasource that throws there must not turn a
      // logout into a failure the host has to handle. The queue clear runs
      // before that wipe, so it has already happened by the time a cache
      // error can surface here.
    }
    try {
      await _cache?.clear();
    } catch (_) {
      // best-effort — a partial clear is acceptable on logout
    }
  }

  /// Releases all resources. The adapter must not be used after this call.
  Future<void> dispose() async {
    // Lifecycle.dispose() flips isDisposed and disposes the two
    // notifiers. It runs FIRST so any async path racing the teardown
    // sees `_disposed == true` immediately and bails on its early
    // return guards.
    await _lifecycle.dispose();
    _lifecycleObserver?.detach();
    _resyncDeferredTimer?.cancel();
    _resyncDeferredTimer = null;
    await _cancelSubscriptions();
    client.cancelPendingRequests('dispose');
    await client.disconnect();
    _resetSessionState();
    // Owns `roomHydrationNotifier`. Safe here: `_lifecycle.dispose()` above
    // already flipped the disposed flag the enricher's publish path checks,
    // so no in-flight load can write to the notifier after this point.
    _enricher.dispose();
    roomListController.dispose();
    _currentUserListenable.dispose();
    _userCacheListenable.dispose();
    _roomMembersListenable.dispose();
    _blockedUsersListenable.dispose();
    _attachmentMediaLoader.clear();
    await _operations.dispose();
  }

  void _handleEvent(ChatEvent event) => _eventRouter.handle(event);

  void _handleStateChange(ChatConnectionState state) {
    connectionStateNotifier.value = state;
  }

  /// Snapshots the current subscriptions into locals and nulls the fields
  /// SYNCHRONOUSLY, before awaiting either cancellation. [connect] calls
  /// this (unawaited) and then immediately calls [start] — which reassigns
  /// `_eventSub`/`_stateSub` to a fresh pair before this function's first
  /// `await` has a chance to resume. Re-reading the instance fields after
  /// that first await (the previous shape of this method) meant the second
  /// `await _stateSub?.cancel()` picked up [start]'s brand-new subscription
  /// instead of the stale one, killing it right after creation — silently
  /// disabling `client.stateChanges` delivery (`connecting`/`authenticating`/
  /// `reconnecting` never reached `connectionStateNotifier`) while orphaning
  /// the stale `_eventSub` (nulled but never actually cancelled, leaking a
  /// listener that piles up on every reconnect cycle). Operating on local
  /// snapshots makes this safe regardless of what the fields get reassigned
  /// to in between.
  Future<void> _cancelSubscriptions() async {
    final eventSub = _eventSub;
    final stateSub = _stateSub;
    _eventSub = null;
    _stateSub = null;
    await eventSub?.cancel();
    await stateSub?.cancel();
  }
}
