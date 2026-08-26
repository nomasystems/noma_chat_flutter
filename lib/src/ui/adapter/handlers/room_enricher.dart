import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/cache_policy.dart';
import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../events/chat_event.dart';
import '../../../models/message.dart';
import '../../../models/room.dart';
import '../../../models/unread_room.dart';
import '../../../models/user.dart';
import '../../../models/user_rooms.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../../models/room_list_item.dart';
import '../room_title_resolver.dart';
import '../services/blocked_users_registry.dart';
import '../services/chat_controller_registry.dart';
import '../services/dm_contact_registry.dart';
import '../services/user_cache_service.dart';
import '../services/presence_registry.dart';

/// What the cache (disk) phase of a room load was able to say, so a host
/// can pick between "loading", "genuinely empty" and "has content" without
/// guessing from list contents or from listener timing.
///
/// Carried by [RoomHydrationStatus], published on
/// [RoomEnricher.hydrationNotifier].
enum RoomHydrationOutcome {
  /// The cache phase has not completed yet in this session. Nothing has
  /// been painted from disk — show the loading state.
  pending,

  /// The cache phase ran and the local cache could not answer: none is
  /// configured, or the read failed (missing / unreadable / corrupt
  /// store). This is NOT a statement that the account has zero rooms;
  /// keep showing the loading state until the network pass lands.
  unavailable,

  /// The cache phase ran, the cache answered, and there is nothing to
  /// paint. A positive "this device knows you have no chats" — the host
  /// can show its empty state straight away instead of a spinner.
  empty,

  /// The cache phase ran and painted [RoomHydrationStatus.roomCount]
  /// rooms. The host has real content on screen.
  hydrated,
}

/// Immutable snapshot of the cache phase of [RoomEnricher.loadAll],
/// published on [RoomEnricher.hydrationNotifier] as soon as that phase has
/// written to the room list — before any network pass runs.
///
/// This is the SDK's answer to "has the disk pass painted yet?". Listening
/// to the [RoomListController] does not answer it: `mergeRooms` skips
/// `notifyListeners()` when nothing changed, so a warm reopen whose cache
/// returns exactly the rows already on screen produces no notification at
/// all; and `onRoomsLoaded` only fires after a network pass. Because this
/// is a [ValueListenable], a host that attaches late still reads the
/// current value instead of having missed an event.
@immutable
class RoomHydrationStatus {
  const RoomHydrationStatus({
    required this.outcome,
    required this.roomCount,
    required this.type,
  });

  /// Status before any cache phase has completed in this session.
  const RoomHydrationStatus.pending()
    : outcome = RoomHydrationOutcome.pending,
      roomCount = 0,
      type = '';

  /// Which of the three paintable states the host is in.
  final RoomHydrationOutcome outcome;

  /// Number of rows the room list holds after the cache phase wrote —
  /// what the host can actually paint right now. `0` for every outcome
  /// other than [RoomHydrationOutcome.hydrated].
  final int roomCount;

  /// The `type` argument of the [RoomEnricher.loadAll] call this status
  /// came from (`'all'`, `'unread'`, …), so a host that loads more than
  /// one listing can tell them apart. Empty string on
  /// [RoomHydrationStatus.pending].
  final String type;

  /// `true` once the cache phase has completed at least once for this
  /// listing — regardless of whether the cache had anything to give.
  bool get hasRun => outcome != RoomHydrationOutcome.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomHydrationStatus &&
          other.outcome == outcome &&
          other.roomCount == roomCount &&
          other.type == type;

  @override
  int get hashCode => Object.hash(outcome, roomCount, type);

  @override
  String toString() =>
      'RoomHydrationStatus(outcome: ${outcome.name}, '
      'roomCount: $roomCount, type: $type)';
}

/// Internal outcome of one disk phase, richer than the public
/// [RoomHydrationStatus] it publishes.
///
/// [RoomEnricher.loadAll] needs the two raw booleans the cache read
/// produced, not the projection: [cacheHadContent] is what the cache
/// RETURNED, while [RoomHydrationStatus.outcome] is what actually made it
/// onto the list (locally-deleted rooms excluded). Deriving one from the
/// other would silently change which failures `loadAll` masks.
class _HydrationPass {
  const _HydrationPass({
    required this.status,
    required this.cacheAnswered,
    required this.cacheHadContent,
  });

  final RoomHydrationStatus status;
  final bool cacheAnswered;
  final bool cacheHadContent;
}

/// Encapsulates the "fetch room details + populate the room list" flows.
///
/// Three groups of methods, in three flavours of work:
///
/// 1. **Bulk load** — `loadAll()` runs the cache-then-network pull driven by
///    `ChatUiAdapter.loadRooms`.
/// 2. **Incremental enrich** — `addFromDetail()` / `applyDetailToExisting()`
///    / `refreshRoom()` keep the [RoomListController] in sync after live
///    events (`RoomCreatedEvent`, `RoomUpdatedEvent`, `NewMessageEvent`).
/// 3. **DM resolution** — `resolveDmContact()` does the background lookup
///    that maps a DM `roomId` to its `otherUserId`.
///
/// Dependencies arrive via constructor injection so tests can drive
/// the enricher with mock services / a fresh `RoomListController`
/// without instantiating the entire adapter.
class RoomEnricher {
  RoomEnricher({
    required this.client,
    required this.controllers,
    required this.roomList,
    required this.dmContacts,
    required this.userCache,
    required this.blockedUsers,
    required this.presence,
    required ChatUser Function() currentUser,
    required this.cache,
    required ChatUiLocalizations Function() l10n,
    required ValueNotifier<bool> initializedNotifier,
    required ValueNotifier<ChatConnectionState> connectionStateNotifier,
    required bool Function() isDisposed,
    required bool Function(RoomDetail detail) isDmDetail,
    required ChatUser? Function(String userId) findCachedUser,
    required void Function(Iterable<ChatUser> users) cacheUsers,
    required Future<void> Function(String userId) ensureUserCached,
    required void Function(String roomId, ChatMessage message)
    updateRoomLastMessage,
    required void Function(String roomId) removeChatController,
    void Function(String level, String message)? logger,
    void Function(List<RoomListItem> rooms)? onRoomsLoaded,
    void Function(String roomId, String contactUserId)? Function()?
    onDmContactResolved,
    RoomTitleResolver? roomTitleResolver,
    Future<ChatResult<void>> Function(String roomId, String messageId)?
    confirmDelivered,
    Duration revalidateDebounce = const Duration(seconds: 5),
  }) : _currentUser = currentUser,
       _l10n = l10n,
       _initializedNotifier = initializedNotifier,
       _connectionStateNotifier = connectionStateNotifier,
       _isDisposed = isDisposed,
       _isDmDetail = isDmDetail,
       _findCachedUser = findCachedUser,
       _cacheUsersFn = cacheUsers,
       _ensureUserCachedFn = ensureUserCached,
       _updateRoomLastMessage = updateRoomLastMessage,
       _removeChatController = removeChatController,
       _logger = logger,
       _onRoomsLoaded = onRoomsLoaded,
       _onDmContactResolved = onDmContactResolved,
       _roomTitleResolver = roomTitleResolver,
       _confirmDelivered = confirmDelivered,
       _revalidateDebounce = revalidateDebounce;

  final ChatClient client;
  final ChatControllerRegistry controllers;
  final RoomListController roomList;
  final DmContactRegistry dmContacts;
  final UserCacheService userCache;
  final BlockedUsersRegistry blockedUsers;
  final PresenceRegistry presence;
  final ChatLocalDatasource? cache;

  final ChatUser Function() _currentUser;
  final ChatUiLocalizations Function() _l10n;
  final ValueNotifier<bool> _initializedNotifier;
  final ValueNotifier<ChatConnectionState> _connectionStateNotifier;
  final bool Function() _isDisposed;
  final bool Function(RoomDetail detail) _isDmDetail;
  final ChatUser? Function(String userId) _findCachedUser;
  final void Function(Iterable<ChatUser> users) _cacheUsersFn;
  final Future<void> Function(String userId) _ensureUserCachedFn;
  final void Function(String roomId, ChatMessage message)
  _updateRoomLastMessage;
  final void Function(String roomId) _removeChatController;
  final void Function(String level, String message)? _logger;
  final void Function(List<RoomListItem> rooms)? _onRoomsLoaded;

  /// Late-bound accessor for the adapter's `onDmContactResolved` hook.
  /// Resolved on every fire rather than captured once at construction so
  /// a consumer that assigns `adapter.onDmContactResolved` AFTER the
  /// enricher was lazily built still receives the callback. `null` (the
  /// getter itself, or its result) means no hook is wired.
  final void Function(String roomId, String contactUserId)? Function()?
  _onDmContactResolved;
  final RoomTitleResolver? _roomTitleResolver;

  /// Consolidated delivered-cursor confirmation, injected by the
  /// adapter when `autoConfirmDelivery` is on. `null` disables the
  /// post-sync delivery catch-up entirely.
  final Future<ChatResult<void>> Function(String roomId, String messageId)?
  _confirmDelivered;

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

  final ValueNotifier<RoomHydrationStatus> _hydration =
      ValueNotifier<RoomHydrationStatus>(const RoomHydrationStatus.pending());

  /// Public signal for "the cache phase of [loadAll] has painted".
  ///
  /// Updated once per [loadAll] call, immediately after the cache pass has
  /// written to the room list and before the network pass is attempted.
  /// The value tells the host whether the cache answered at all, and with
  /// how many rows — see [RoomHydrationOutcome] for the three states a
  /// host has to distinguish.
  ///
  /// Because it is a [ValueListenable] and not a stream, a host that
  /// attaches after the cache phase already ran still reads the outcome:
  ///
  /// ```dart
  /// ValueListenableBuilder<RoomHydrationStatus>(
  ///   valueListenable: enricher.hydrationNotifier,
  ///   builder: (context, status, _) => switch (status.outcome) {
  ///     RoomHydrationOutcome.hydrated => RoomListView(...),
  ///     RoomHydrationOutcome.empty => const NoChatsYet(),
  ///     _ => const ChatListSkeleton(),
  ///   },
  /// );
  /// ```
  ValueListenable<RoomHydrationStatus> get hydrationNotifier => _hydration;

  /// Releases the [hydrationNotifier]. Call from the owner's `dispose()`.
  void dispose() => _hydration.dispose();

  /// Rooms currently being revalidated in the background, keyed by [type].
  /// Guards [_backgroundRevalidate] against overlapping network passes when
  /// [loadAll] is invoked repeatedly for the same type (e.g. every time a
  /// screen that calls it on `initState` reopens) before the previous pass
  /// has finished — without it, two concurrent authoritative `mergeRooms`
  /// calls could interleave and leave the list in an inconsistent state.
  final Set<String> _revalidating = {};

  /// Rooms with a [refreshRoom] read in flight, and the rooms that asked
  /// for another one while it was.
  final Set<String> _refreshingRooms = {};
  final Set<String> _refreshQueuedRooms = {};

  /// Wall-clock time [_backgroundRevalidate] last actually ran for a given
  /// [type], keyed the same way as [_revalidating]. [_revalidating] alone
  /// only stops *concurrent* passes — a screen that opens, closes and
  /// reopens fires a brand-new `loadAll` -> `_backgroundRevalidate` each
  /// time, and by the time the second call lands the first has usually
  /// already finished, so the concurrency guard never engages. That turns
  /// every reopen (and every trusted-cache reconnect) into a full
  /// `members.list`-per-DM enrichment pass. [_revalidateDebounce] adds a
  /// temporal gate on top so a burst of reopens only revalidates once per
  /// window.
  final Map<String, DateTime> _lastRevalidatedAt = {};

  /// Minimum spacing between [_backgroundRevalidate] runs for the same
  /// [type]. Mirrors `ChatUiAdapter._resyncDebounce`'s value by default;
  /// overridable via the constructor so tests can shrink the window
  /// instead of waiting out the real default.
  final Duration _revalidateDebounce;

  /// Whether the disk phase ([hydrateFromCache]) has completed at least
  /// once since the last [resetSession].
  ///
  /// Tracked explicitly rather than derived from [initializedNotifier]:
  /// that one answers "has a NETWORK pass completed?", a different
  /// question. A session that never reaches the network would leave it
  /// `false` forever, so every reconnect would re-hydrate and overwrite
  /// rows already advanced by realtime events with the disk snapshot.
  bool get hasHydratedFromCache => _hydratedThisSession;
  bool _hydratedThisSession = false;

  /// Single-flight slot for [hydrateFromCache]. Two concurrent callers
  /// (the adapter's `connect()` and a host that hydrates on its own) must
  /// share one cache read + one `_enrichAndSet`, not race two.
  Future<_HydrationPass>? _hydrationInFlight;

  /// The session every pass belongs to, captured before its first
  /// `await` and bumped by [resetSession].
  ///
  /// A pass that started under an older epoch must not report itself as
  /// this session's hydration when it lands — a sign-out racing an
  /// in-flight `connect()` would otherwise leave the incoming session
  /// believing it had already read the disk. Nor may it paint: every
  /// write this class makes to [roomList] and to the notifiers is gated
  /// on [_stale]. Guarding on `_isDisposed()` alone is not enough,
  /// because `signOut()` deliberately does NOT dispose the adapter (the
  /// instance stays usable so the next user can sign in on it), so a pass
  /// started by the outgoing identity is still "alive" when it lands and
  /// would merge that identity's rooms into the incoming one's list —
  /// non-authoritatively, so nothing would ever prune them again.
  int _sessionEpoch = 0;

  /// Whether [epoch] is no longer the running session — either the
  /// adapter was disposed or a [resetSession] happened while the pass
  /// that captured it was awaiting.
  bool _stale(int epoch) => _isDisposed() || epoch != _sessionEpoch;

  /// Rearms [hasHydratedFromCache] so the next session hydrates again.
  /// Invoked from the adapter's shared session-teardown inventory.
  void resetSession() {
    _sessionEpoch++;
    _hydratedThisSession = false;
    _hydrationInFlight = null;
    _refreshQueuedRooms.clear();
    // The deleted-room mirror is per-user and a list build no longer
    // replaces it wholesale, so an identity swap on the same adapter has
    // to drop it here or the outgoing user's ids would keep hiding rooms
    // for the incoming one. Only [signOut] and [dispose] reach this — a
    // [disconnect] must leave the set alone.
    roomList.setDeletedRoomIds(const {});
  }

  /// Paints the room list from the local cache. Never touches the network.
  ///
  /// This is the disk phase of [loadAll] on its own, exposed so a host can
  /// have content on screen before anything else happens: it is safe to
  /// call BEFORE `connect()` and before the user has been created
  /// server-side, because nothing it reads is set up by either (the local
  /// store is open from client construction and `cacheOnly` reads bypass
  /// the TTL ledger entirely).
  ///
  /// It deliberately does NOT set [initializedNotifier] nor fire
  /// `onRoomsLoaded`: both remain the exclusive signal of a completed
  /// network pass, so a host that gates on "the list is authoritative"
  /// keeps gating on the same thing it did before.
  ///
  /// Concurrent calls share a single pass. Returns the
  /// [RoomHydrationStatus] published on [hydrationNotifier].
  Future<RoomHydrationStatus> hydrateFromCache({String type = 'all'}) async =>
      (await _hydrate(type)).status;

  Future<_HydrationPass> _hydrate(String type) {
    final inFlight = _hydrationInFlight;
    if (inFlight != null) return inFlight;
    final pass = () async {
      try {
        return await _runHydration(type);
      } finally {
        _hydrationInFlight = null;
      }
    }();
    _hydrationInFlight = pass;
    return pass;
  }

  Future<_HydrationPass> _runHydration(String type) async {
    final epoch = _sessionEpoch;
    final cachedResult = await client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.cacheOnly,
    );
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

  Future<ChatResult<void>> loadAll({
    String type = 'all',
    bool forceNetwork = false,
    bool revalidateInBackground = true,
  }) async {
    final epoch = _sessionEpoch;
    // Phase 1: Instant load from cache (fire-and-forget DM resolution to
    // keep the first paint snappy — the network pass will await it).
    final hydration = await _hydrate(type);
    final hasCached = hydration.cacheAnswered;
    final hasCachedContent = hydration.cacheHadContent;

    // Trust the cache and skip blocking on the network pass when realtime
    // is already keeping the room list fresh: after the first successful
    // sync the SDK receives `NewMessageEvent` / `UnreadUpdatedEvent` /
    // `RoomCreatedEvent` via WS and applies them incrementally, so
    // re-hitting `/v1/rooms` synchronously on every screen-open just to
    // confirm what we already know would be wasteful. Concrete heuristic:
    // cache present + already initialized + WS connected → return the
    // cached snapshot immediately, but still kick off a background
    // revalidation (unless the caller opts out) so a partial/stale cache
    // self-heals without the caller ever seeing an empty list in between.
    // Pull-to-refresh / forced reload pass `forceNetwork: true` to force
    // the blocking path below instead.
    //
    // This one keys on [hasCached] on purpose, empty cache included: an
    // account with zero rooms and a live WS connection is as up to date as
    // one with fifty, so blocking its every screen-open on the network
    // just to re-confirm zero is the same waste. The background
    // revalidation still runs.
    final realtimeIsFresh =
        _initializedNotifier.value &&
        _connectionStateNotifier.value == ChatConnectionState.connected;
    if (hasCached && realtimeIsFresh && !forceNetwork) {
      _onRoomsLoaded?.call(roomList.allRooms);
      if (revalidateInBackground) {
        unawaited(_backgroundRevalidate(type));
      }
      return const ChatSuccess(null);
    }

    // Phase 2: Sync from network. Await DM resolution before returning so
    // `findExistingDmRoom`, `getDmRoomId`, and the duplicate-DM cleanup
    // all see consistent state by the time `loadRooms` resolves. Without
    // this, a tap on the suggestion bar racing the resolution can create
    // a phantom DM room next to the real one. `snapshotAt` is stamped
    // BEFORE the request goes out so the authoritative merge can tell a
    // room created locally during the round-trip apart from one the server
    // genuinely dropped (see [RoomListController.mergeRooms]). `seq` is
    // reserved at the same instant so a pass that resolves out of order
    // relative to a concurrent fetch (e.g. this call racing a
    // [_backgroundRevalidate] already in flight) is recognized as stale.
    final snapshotAt = DateTime.now();
    final seq = roomList.nextSeq();
    final networkResult = await client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.networkOnly,
    );
    if (networkResult.isSuccess) {
      await _enrichAndSet(
        networkResult.dataOrThrow,
        epoch: epoch,
        type: type,
        awaitDmResolution: true,
        authoritative: true,
        snapshotAt: snapshotAt,
        seq: seq,
      );
      if (_stale(epoch)) return const ChatSuccess(null);
      _initializedNotifier.value = true;
      _onRoomsLoaded?.call(roomList.allRooms);
      return const ChatSuccess(null);
    }

    // A cache hit normally masks a failed network pass — nothing changed
    // for the caller to react to, and the UI already has something to
    // show. `forceNetwork` callers (pull-to-refresh, `ChatUiAdapter.resync`
    // after a reconnect) explicitly asked to bypass the cache because they
    // need to know whether the authoritative fetch actually happened —
    // masking the failure there would let a resync silently do nothing
    // while still being treated as if it succeeded (e.g. consuming its
    // debounce window for no gain).
    //
    // The mask keys on [hasCachedContent], not on [hasCached]: a cache
    // that answered "you have zero rooms" leaves the caller with nothing
    // on screen, so swallowing the network failure there would present a
    // failed load as a successful empty one — exactly the state a host
    // needs to tell apart to decide between "no chats yet" and "we could
    // not reach the server".
    if (hasCachedContent && !forceNetwork) return const ChatSuccess(null);
    return networkResult.castFailure<void>();
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
        selfMuted: detail?.selfMuted ?? false,
        pinned: detail?.pinned ?? false,
        hidden: detail?.hidden ?? false,
        isGroup:
            detail?.type == RoomType.group ||
            detail?.type == RoomType.announcement,
        isAnnouncement: detail?.type == RoomType.announcement,
        userRole: detail?.userRole,
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

  /// Background-resolves the "other" user in a DM room and caches the
  /// mapping. Fire-and-forget on purpose: the room list is already painted
  /// when this runs, so any failure logs a warning rather than blocks the UI.
  ///
  /// [authoritative] controls how a duplicate-DM dedupe (see
  /// [_pickPreferredDmRoom]) is applied: `true` (the default — matches every
  /// call site except the cache pass of [loadAll]) persists the loser's
  /// removal to the local cache; `false` only suppresses it from the
  /// visible list, so a cache-only guess can never destroy state the next
  /// authoritative pass might still need to reconcile correctly. Even when
  /// `true`, the persisted removal additionally requires
  /// [RoomListController.allowsInferredPrune] to agree — see
  /// [_doResolveDmContact].
  ///
  /// [cachePolicy] is threaded into every read this makes — the roster and
  /// the peer profile. `null` keeps each call's own default; passing
  /// [CachePolicy.cacheOnly] makes the whole resolution disk-only, which
  /// is what the cache pass of [loadAll] does.
  ///
  /// [epoch] is the session this resolution belongs to; omitted, it is the
  /// session running at the call. See [_sessionEpoch].
  void resolveDmContact(
    String roomId, {
    bool authoritative = true,
    bool representsCompleteSet = true,
    int? seq,
    CachePolicy? cachePolicy,
    int? epoch,
  }) {
    unawaited(
      _doResolveDmContact(
        roomId,
        authoritative: authoritative,
        representsCompleteSet: representsCompleteSet,
        seq: seq,
        cachePolicy: cachePolicy,
        epoch: epoch,
      ),
    );
  }

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

  /// Adds a room to the list using its server-side detail, deferring the
  /// addition until the detail is available so the UI never shows a "ghost"
  /// row with the raw roomId as the title.
  void addFromDetail(String roomId, {ChatMessage? lastMessage}) {
    client.rooms
        .get(roomId, cachePolicy: CachePolicy.networkFirst)
        .then((result) {
          if (_isDisposed()) return;
          applyFetchedDetail(
            roomId,
            result.dataOrNull,
            lastMessage: lastMessage,
          );
        })
        .catchError((Object e) {
          _logger?.call(
            'warn',
            'Failed to fetch detail for new room $roomId; not adding: $e',
          );
        });
  }

  /// Applies an already-fetched [detail] to [roomId]: enriches the row in
  /// place if it's already in the list, or adds a fresh one built from
  /// [detail] otherwise. `detail == null` (fetch failed/room unknown) is a
  /// no-op when the room isn't listed yet, matching [addFromDetail]'s
  /// long-standing "don't add a ghost row" behavior.
  ///
  /// Shared by [addFromDetail] (which fetches the detail itself) and
  /// [ChatRoomsController.open] (which already has a freshly-fetched
  /// detail in hand from its own network call) — factored out so a
  /// deep-linked room open never issues two network calls for the same
  /// detail.
  void applyFetchedDetail(
    String roomId,
    RoomDetail? detail, {
    ChatMessage? lastMessage,
  }) {
    final existingRow = roomList.getRoomById(roomId);
    if (existingRow != null) {
      // Another path (e.g. loadRooms running in parallel) already added
      // this room; just enrich any missing fields.
      _applyDetailToExisting(roomId, detail, lastMessage);
      if (detail != null &&
          _isDmDetail(detail) &&
          existingRow.otherUserId == null) {
        resolveDmContact(roomId);
      }
      return;
    }
    if (detail == null) {
      _logger?.call(
        'warn',
        'Skipping addRoomFromDetail for $roomId: detail not available',
      );
      return;
    }
    final isOneToOne = detail.type == RoomType.oneToOne;
    final base = RoomListItem(
      id: roomId,
      name: detail.name,
      subject: detail.subject,
      avatarUrl: detail.avatarUrl,
      muted: detail.muted,
      muteUntil: detail.muteUntil,
      pinned: detail.pinned,
      hidden: detail.hidden,
      isGroup: !isOneToOne,
      isAnnouncement: detail.type == RoomType.announcement,
      selfMuted: detail.selfMuted,
      userRole: detail.userRole,
      memberCount: detail.memberCount,
      custom: detail.custom,
      lastMessage: lastMessage?.isDeleted == true ? null : lastMessage?.text,
      lastMessageTime: lastMessage?.timestamp,
      lastMessageUserId: lastMessage?.from,
      lastMessageId: lastMessage?.id,
      lastMessageType: lastMessage?.messageType,
      lastMessageMimeType: lastMessage?.mimeType,
      lastMessageFileName: lastMessage?.fileName,
      lastMessageDurationMs: _durationMsOf(lastMessage),
      lastMessageIsDeleted: lastMessage?.isDeleted ?? false,
      lastMessageIsSystem: lastMessage?.isSystem ?? false,
      // A room added from an incoming message starts with 1 unread
      // when that message is from someone else (e.g. you were just
      // added to a group and the creator's first message arrives).
      // Without this the tile showed the preview but no badge. Own
      // messages (you created the room and sent) stay at 0.
      unreadCount:
          (lastMessage != null && lastMessage.from != _currentUser().id)
          ? 1
          : 0,
    );
    final effective = computeEffectiveTitle(currentItem: base, detail: detail);
    final item = effective == null
        ? base
        : base.copyWith(effectiveDisplayName: effective);
    roomList.addRoom(item);
    if (_isDmDetail(detail)) {
      resolveDmContact(roomId);
    }
  }

  void _applyDetailToExisting(
    String roomId,
    RoomDetail? detail,
    ChatMessage? lastMessage,
  ) {
    final existing = roomList.getRoomById(roomId);
    if (existing == null) return;
    if (detail == null) {
      if (lastMessage != null) {
        _updateRoomLastMessage(roomId, lastMessage);
      }
      return;
    }
    final isOneToOne = detail.type == RoomType.oneToOne;
    final updated = existing.copyWith(
      name: detail.name,
      subject: detail.subject,
      avatarUrl: detail.avatarUrl ?? existing.avatarUrl,
      isGroup: !isOneToOne,
      isAnnouncement: detail.type == RoomType.announcement,
      userRole: detail.userRole,
      memberCount: detail.memberCount,
      custom: detail.custom ?? existing.custom,
    );
    final effective = computeEffectiveTitle(
      currentItem: updated,
      detail: detail,
    );
    roomList.updateRoom(
      updated.copyWith(
        effectiveDisplayName: effective ?? updated.effectiveDisplayName,
      ),
    );
    if (lastMessage != null) {
      _updateRoomLastMessage(roomId, lastMessage);
    }
  }

  /// Refreshes the room detail in-place after a `RoomUpdatedEvent` /
  /// `UserRoleChangedEvent`, or when the room is opened. Also resolves the
  /// DM "other user" if applicable.
  ///
  /// Single-flight per room: a roster fan-out (an admin adding six people,
  /// a plan filling up) delivers one frame per change, and one `GET
  /// /rooms/{id}` per frame is a burst the room only needs the last answer
  /// of. Requests landing while a read is in flight are collapsed into a
  /// single trailing re-read — dropping them outright would keep whatever
  /// count the in-flight response was computed with, which is the stale
  /// number this refresh exists to replace.
  void refreshRoom(String roomId) {
    if (_refreshingRooms.contains(roomId)) {
      _refreshQueuedRooms.add(roomId);
      return;
    }
    _refreshingRooms.add(roomId);
    client.rooms
        .get(roomId, cachePolicy: CachePolicy.networkFirst)
        .then((result) {
          if (_isDisposed()) return;
          final detail = result.dataOrNull;
          if (detail == null) return;
          final existing = roomList.getRoomById(roomId);
          if (existing == null) return;
          final isOneToOne = detail.type == RoomType.oneToOne;
          final updated = existing.copyWith(
            name: detail.name,
            subject: detail.subject,
            // DM rooms carry no room-level avatar — the avatar is the
            // peer's, resolved via _doResolveDmContact and held in
            // `existing.avatarUrl`. Using `detail.avatarUrl` (null for a
            // DM) wiped it on every RoomUpdatedEvent (e.g. a polling tick
            // after opening/leaving the chat). Groups keep detail.avatarUrl
            // as authoritative (incl. null = avatar removed).
            avatarUrl: isOneToOne ? existing.avatarUrl : detail.avatarUrl,
            muted: detail.muted,
            muteUntil: detail.muteUntil,
            // Admin-mute (read-only) state. Propagated here so a live
            // `RoomUpdatedEvent` / polling refresh — or a re-fetch triggered
            // right after a 403-muted send — flips the composer to the
            // read-only banner without reopening the chat.
            selfMuted: detail.selfMuted,
            pinned: detail.pinned,
            hidden: detail.hidden,
            isGroup: !isOneToOne,
            isAnnouncement: detail.type == RoomType.announcement,
            userRole: detail.userRole,
            memberCount: detail.memberCount,
            custom: detail.custom,
          );
          final effective = computeEffectiveTitle(
            currentItem: updated,
            detail: detail,
          );
          roomList.updateRoom(
            updated.copyWith(
              effectiveDisplayName: effective ?? updated.effectiveDisplayName,
            ),
          );
          if (_isDmDetail(detail)) {
            client.members
                .list(roomId)
                .then((membersResult) {
                  if (_isDisposed()) return;
                  final members = membersResult.dataOrNull?.items ?? [];
                  final other = members
                      .where((m) => m.userId != _currentUser().id)
                      .firstOrNull;
                  if (other != null) {
                    dmContacts.bind(other.userId, roomId);
                    final current = roomList.getRoomById(roomId);
                    if (current != null) {
                      final otherUser = _findCachedUser(other.userId);
                      final dmEffective = computeEffectiveTitle(
                        currentItem: current,
                        detail: detail,
                        otherMembers: otherUser != null
                            ? [otherUser]
                            : const [],
                        isDmOverride: true,
                      );
                      roomList.updateRoom(
                        current.copyWith(
                          otherUserId: other.userId,
                          // Re-assert the peer avatar here too: the detail
                          // pass above keeps `existing.avatarUrl` for DMs,
                          // and the resolved peer (if cached) refreshes it.
                          avatarUrl: otherUser?.avatarUrl ?? current.avatarUrl,
                          effectiveDisplayName:
                              dmEffective ?? current.effectiveDisplayName,
                        ),
                      );
                    }
                    _onDmContactResolved?.call()?.call(roomId, other.userId);
                  }
                })
                .catchError((Object e) {
                  _logger?.call(
                    'warn',
                    'Failed to list members for room $roomId: $e',
                  );
                });
          }
        })
        .catchError((Object e) {
          _logger?.call('warn', 'Failed to enrich room detail for $roomId: $e');
        })
        .whenComplete(() {
          _refreshingRooms.remove(roomId);
          if (_refreshQueuedRooms.remove(roomId) && !_isDisposed()) {
            refreshRoom(roomId);
          }
        });
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

  /// Runs the custom [RoomTitleResolver] first, then the SDK's DM-aware
  /// default. Returns `null` when neither produces a value — callers should
  /// preserve the existing `effectiveDisplayName` in that case so a
  /// previously hydrated DM title is not regressed by a partial enrichment.
  String? computeEffectiveTitle({
    required RoomListItem currentItem,
    RoomDetail? detail,
    List<ChatUser> otherMembers = const [],
    bool? isDmOverride,
  }) {
    final isDm = isDmOverride ?? (detail != null && _isDmDetail(detail));
    final ctx = RoomTitleContext(
      currentItem: currentItem,
      currentUser: _currentUser(),
      detail: detail,
      otherMembers: otherMembers,
      isDm: isDm,
    );
    final custom = _roomTitleResolver?.call(ctx);
    if (custom != null) {
      final trimmed = custom.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (isDm && otherMembers.isNotEmpty) {
      final other = otherMembers.firstWhere(
        (u) => u.id != _currentUser().id,
        orElse: () => otherMembers.first,
      );
      final name = other.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
      return other.id;
    }
    // Self-chat / orphan-room fallback. Three scenarios collapse here:
    // 1. WhatsApp-style "Message yourself" (1-member room created on
    //    purpose by the current user as a personal notes channel).
    // 2. A DM where the other user was wiped from the user directory
    //    (their membership entry stayed in the room but `users.get` no
    //    longer resolves them). Current user still owns the history.
    // 3. A group where every other member left / was kicked / was
    //    wiped, leaving the current user alone. Same outcome.
    // Trigger: no resolvable other member AND the room has no
    // user-assigned name to display instead. ChatResult: title becomes
    // `${currentUser.name} (You)` (`{name} (Tú)` in es) — matches
    // WhatsApp's self-chat label and keeps the row clearly
    // identifiable instead of an anonymous "?".
    //
    // Guard against false positives: the room must NOT remember a
    // peer (`currentItem.otherUserId`) and the member count must be
    // <= 1. Otherwise a transient miss from `members.list` on a
    // normal DM with a known peer would flip the title from "Bob"
    // to "alice (You)" — observed 2026-05-27 where alice's view of
    // her DM with bob occasionally rendered "alice (You)" while
    // bob's view stayed correct (asymmetric cache state). With the
    // guards the self-chat title only fires when we genuinely
    // believe nobody else is in the room.
    final hasName = detail?.name?.trim().isNotEmpty ?? false;
    final rememberedPeerId = currentItem.otherUserId;
    final hasRememberedPeer =
        rememberedPeerId != null &&
        rememberedPeerId.isNotEmpty &&
        rememberedPeerId != _currentUser().id;
    final memberCount = detail?.memberCount ?? currentItem.memberCount ?? 1;
    final looksLikeSelfChat =
        otherMembers.isEmpty &&
        !hasName &&
        !hasRememberedPeer &&
        memberCount <= 1;
    if (looksLikeSelfChat) {
      final ownName = _currentUser().displayName?.trim();
      final base = (ownName == null || ownName.isEmpty)
          ? _currentUser().id
          : ownName;
      return _l10n().selfChatTitle(base);
    }
    return null;
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
      userRole: detail?.userRole,
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

  /// Recorded length of a voice note, in milliseconds, as the transport
  /// carries it in the message metadata. `null` for anything else.
  static int? _durationMsOf(ChatMessage? message) {
    final raw = message?.metadata?['duration'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }
}
