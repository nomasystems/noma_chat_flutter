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

part 'room_enricher_dm.dart';
part 'room_enricher_enrichment.dart';
part 'room_enricher_hydration.dart';

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
      writePolicy: detail.config.writePolicy,
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
      // messages and system events stay at 0.
      unreadCount:
          (lastMessage != null &&
              lastMessage.from != _currentUser().id &&
              !lastMessage.isSystem)
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
            // Same reason as `selfMuted`: an owner closing the room to
            // everyone but themselves arrives as a `RoomUpdatedEvent`, and
            // the open chat has to swap its composer for the notice without
            // being reopened.
            writePolicy: detail.config.writePolicy,
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
    final peer = isDm && otherMembers.isNotEmpty
        ? otherMembers.firstWhere(
            (u) => u.id != _currentUser().id,
            orElse: () => otherMembers.first,
          )
        : null;
    final rawPeerId = peer?.id ?? currentItem.otherUserId;
    final ctx = RoomTitleContext(
      currentItem: currentItem,
      currentUser: _currentUser(),
      detail: detail,
      otherMembers: otherMembers,
      isDm: isDm,
      rawPeerId: rawPeerId,
    );
    final custom = _roomTitleResolver?.call(ctx);
    if (custom != null) {
      final trimmed = custom.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (peer != null) {
      // The host's directory first: it is the app's own address book,
      // and where the two disagree the person reading the row expects
      // the name they gave the contact, not the one chat happens to
      // hold.
      final hostName = userCache.hostDisplayName(peer.id);
      if (hostName != null && hostName.isNotEmpty) return hostName;
      final name = peer.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
      // Not the peer's id: an empty title lets `RoomListItem.displayName`
      // fall through to the room's own name and then to the host's own
      // placeholder.
      return null;
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

  /// Recorded length of a voice note, in milliseconds, as the transport
  /// carries it in the message metadata. `null` for anything else.
  static int? _durationMsOf(ChatMessage? message) {
    final raw = message?.metadata?['duration'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }
}
