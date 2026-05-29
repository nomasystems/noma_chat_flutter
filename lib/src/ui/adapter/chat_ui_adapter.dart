library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImage;
import '../../cache/cache_policy.dart';
import '../../cache/local_datasource.dart';
import '../../client/chat_client.dart';
import '../../client/noma_chat_facade.dart';
import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../events/chat_event.dart';
import '../../models/attachment.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/presence.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/room.dart';
import '../../models/room_user.dart';
import '../../models/user.dart';
import '../../storage/avatar_storage.dart';
import '../controller/chat_controller.dart';
import '../controller/room_list_controller.dart';
import '../l10n/chat_ui_localizations.dart';
import '../models/attachment_policy.dart';
import '../models/room_list_item.dart';
import '../services/attachment_pickers.dart';
import '../widgets/chat_room_options_menu.dart';
import '../widgets/chat_view.dart';
import 'operation_error.dart';
import 'room_title_resolver.dart';

import 'handlers/chat_event_router.dart';
import 'handlers/member_event_handler.dart';
import 'handlers/optimistic_handler.dart';
import 'services/presence_registry.dart';
import 'handlers/room_enricher.dart';
import 'handlers/room_list_mutator.dart';
import 'services/blocked_users_registry.dart';
import 'services/chat_controller_registry.dart';
import 'services/connection_lifecycle.dart';
import 'services/dm_contact_registry.dart';
import 'services/mark_as_read_coordinator.dart';
import 'services/operation_hub.dart';
import 'services/pending_reactions_registry.dart';
import 'services/typing_timer_registry.dart';
import 'services/user_cache_service.dart';
import 'services/voice_upload_registry.dart';

part 'api/contacts_controller.dart';
part 'api/dm_controller.dart';
part 'api/messages_controller.dart';
part 'api/profile_controller.dart';
part 'api/rooms_controller.dart';

/// Adapter-local helper for best-effort cache writes wrapped in
/// [unawaited]. Returns a [ChatFailureResult] so the new
/// `Future<ChatResult<void>>` signature of [ChatLocalDatasource] mutators
/// is satisfied — `unawaited` still drops the outcome, preserving the
/// previous fire-and-forget semantics. The cache impls bundled with
/// the SDK never throw, but a custom datasource could; this keeps the
/// callsite quiet regardless.
ChatResult<void> _swallowCacheThrow(Object _) =>
    const ChatFailureResult<void>(UnexpectedFailure('cache mutator threw'));

/// Predicate the adapter uses to decide whether a room is a DM and therefore
/// should be tracked in the contact-to-room cache. When `null`, falls back to
/// `detail.type == RoomType.oneToOne`.
typedef IsDmRoomPredicate = bool Function(RoomDetail detail);

/// Context handed to a [RoomTitleResolver] when the adapter (re)computes the
/// effective title for a room. [detail] and [otherMembers] may be empty/null
/// during incremental enrichments (e.g. before the DM contact has been
/// resolved) — a robust resolver should tolerate that and either return
/// `null` (to defer) or operate on [currentItem] only.
///
/// [isDm] is the adapter's best current guess of whether this room is a
/// direct message. The adapter precomputes it via the [IsDmRoomPredicate]
/// when [detail] is available, or carries it forward from prior enrichment
/// state when only [otherMembers] is available. A custom resolver can ignore
/// it; the SDK's built-in default only fires when [isDm] is true.
// `RoomTitleContext` + `RoomTitleResolver` typedef were extracted to
// `lib/src/ui/adapter/room_title_resolver.dart` so the standalone
// `RoomEnricher` handler can import them without pulling in the
// entire adapter library.

/// Bridges the [ChatClient] SDK with the UI components's controllers and widgets.
///
/// Subscribes to real-time events and routes them to the appropriate
/// [ChatController] or [RoomListController]. Provides high-level actions
/// (send, edit, delete, react) with optimistic UI updates.
class ChatUiAdapter {
  ChatUiAdapter({
    required this.client,
    required ChatUser currentUser,
    this.l10n = ChatUiLocalizations.en,
    this.onRoomsLoaded,
    this.isDmRoom,
    this.roomTitleResolver,
    this.autoMarkAsRead = true,
    ChatLocalDatasource? cache,
    AvatarStorage? avatarStorage,
  }) : _cache = cache,
       _currentUser = currentUser,
       avatarStorage = avatarStorage ?? DefaultAvatarStorage(client),
       roomListController = RoomListController(),
       _lifecycle = ConnectionLifecycle();

  final ChatClient client;

  // -- Sub-APIs -----------------------------------------------------
  //
  // Grouped facets of the adapter. Each one is a thin wrapper that
  // delegates to the corresponding top-level methods on the adapter
  // (which are now considered package-internal even though they are
  // still public Dart-wise). External consumers should always go
  // through these.

  /// Per-message operations — `load`, `send`, `edit`, `delete`,
  /// reactions, attachments, voice, threads, search, pin, etc.
  late final ChatMessagesController messages = ChatMessagesController(this);

  /// Room-level operations — `load`, `mute`/`unmute`, `pin`/`unpin`,
  /// `hide`/`unhide`, `leave`, `addMembers`, `updateConfig`,
  /// `createGroup`, etc.
  late final ChatRoomsController rooms = ChatRoomsController(this);

  /// Contact / blocked-users operations — `block`, `unblock`,
  /// `loadBlocked`, `pruneBlockedRooms`, `blockedUserIds`.
  late final ChatContactsController contacts = ChatContactsController(this);

  /// Current-user profile mutations — `update`, `uploadAvatar`.
  late final ChatProfileController profile = ChatProfileController(this);

  /// Direct-message helpers — `findExisting`, `openDraft`,
  /// `ensureMaterialized`, `draftRoutingKey`.
  late final ChatDmController dm = ChatDmController(this);

  /// Profile of the user this adapter belongs to. Starts as the value
  /// supplied to the constructor; [profile.update] mutates it
  /// optimistically and the WS `user_updated` echo from the backend can
  /// also push fresh values (e.g. a profile change made from a second
  /// device).
  ChatUser get currentUser => _currentUser;
  ChatUser _currentUser;

  /// Reactive view of [currentUser]. Rebuilds via `ValueListenableBuilder`
  /// whenever displayName / avatarUrl / bio / email / custom change —
  /// either from a local `profile.update` (optimistic write) or from a
  /// `user_updated` WS event echoed back when the profile was changed on
  /// another device. Use this in any widget that paints the current
  /// user's avatar / name and must repaint live (composer, app shell
  /// header, settings entry...). Reading `adapter.currentUser` directly
  /// is fine for one-shot reads but does not trigger rebuilds.
  ValueListenable<ChatUser> get currentUserListenable => _currentUserListenable;
  late final ValueNotifier<ChatUser> _currentUserListenable =
      ValueNotifier<ChatUser>(_currentUser);

  /// Coarse notifier that fires every time [cacheUsers] inserts or
  /// updates an entry (displayName or avatarUrl change). Surfaces that
  /// "any user in the cache changed" — consumers that want fine-grained
  /// per-user listening can wrap a `findCachedUser(id)` read in a
  /// `ListenableBuilder(listenable: userCacheListenable, ...)` and
  /// re-resolve on every fire. The push-update on `MessageList` and
  /// `GroupMembersView` uses exactly this to refresh sender avatars in
  /// group bubbles + member-row avatars without a manual reload.
  Listenable get userCacheListenable => _userCacheListenable;
  final _BroadcastNotifier _userCacheListenable = _BroadcastNotifier();

  /// Fires whenever [blockedUserIds] mutates — either via [blockContact]
  /// / [unblockContact] or a wholesale replacement. Consumers (e.g.
  /// [SuggestionBarController]) subscribe to refresh their derived
  /// state immediately instead of waiting for the next poll tick. The
  /// notifier carries no payload; callers read the current snapshot
  /// from [blockedUserIds].
  Listenable get blockedUsersListenable => _blockedUsersListenable;
  final _BroadcastNotifier _blockedUsersListenable = _BroadcastNotifier();
  final ChatUiLocalizations l10n;
  final IsDmRoomPredicate? isDmRoom;
  final RoomTitleResolver? roomTitleResolver;
  final ChatLocalDatasource? _cache;

  /// Plugged-in storage for avatar uploads. Defaults to
  /// [DefaultAvatarStorage] which delegates to `client.attachments.upload`.
  /// Consumers wire a custom implementation when avatars must live on
  /// their own backend (Firebase, S3, custom CHT/wb pipeline, …).
  final AvatarStorage avatarStorage;

  /// When `true` (default), the adapter fires [markAsRead] automatically
  /// on the two boundaries where WhatsApp would: right after [loadMessages]
  /// finishes (we're now displaying the unread tail) and right before the
  /// controller is disposed via [removeChatController] (the user navigated
  /// away — flush the last read pointer). Both calls are fire-and-forget;
  /// failures are surfaced through [onError] like any other API failure.
  ///
  /// Disable when the consumer wants to drive marking-as-read manually
  /// (e.g. tied to message visibility on screen rather than chat entry).
  final bool autoMarkAsRead;

  bool _isDmDetail(RoomDetail detail) {
    if (isDmRoom != null) return isDmRoom!(detail);
    if (detail.type != RoomType.oneToOne) return false;
    // Defense: a real DM never carries a user-assigned name.
    // If the room has a non-empty name it's an intentional 2-person
    // group — don't classify as DM (otherwise the dedupe path would
    // collapse it against an existing DM with the same other user).
    final name = detail.name?.trim();
    if (name != null && name.isNotEmpty) return false;
    return true;
  }

  void Function(String level, String message)? logger;
  final RoomListController roomListController;

  /// Lifecycle service: owns `connectionStateNotifier`,
  /// `initializedNotifier`, the disposal flag, and the in-flight
  /// `loadRooms` completer.
  final ConnectionLifecycle _lifecycle;

  /// Notifier for the current realtime connection state. Backed by
  /// [_lifecycle] — the getter keeps the public API source-compatible
  /// (`adapter.connectionStateNotifier` still works).
  ValueNotifier<ChatConnectionState> get connectionStateNotifier =>
      _lifecycle.connectionState;

  /// Becomes `true` after the first successful [loadRooms] call.
  ValueNotifier<bool> get initializedNotifier => _lifecycle.initialized;

  /// Fires after each [loadRooms] completes with the loaded room list.
  /// Consumers can use this to enrich metadata (e.g. display names, avatars).
  final void Function(List<RoomListItem> rooms)? onRoomsLoaded;

  // -----------------------------------------------------------------
  // STATE
  //
  // Grouped by concern for readability. A future milestone (1.0) may
  // wrap each group in a private struct (`_TypingState`, `_VoiceState`,
  // `_UserCacheState`, …) so teardown paths can iterate one container
  // instead of remembering to clear N maps. The functional behaviour
  // is identical either way; the grouping below makes the intent
  // explicit in the meantime.
  // -----------------------------------------------------------------

  // -- Per-room runtime state --
  /// Per-room [ChatController] registry. The field is typed as
  /// [ChatControllerRegistry] which mirrors the `Map`-shaped API so
  /// existing `_chatControllers[roomId]` callsites work unchanged.
  /// The added value is the `disposeAll()` lifecycle helper used in
  /// `signOut` / `dispose`.
  final ChatControllerRegistry _chatControllers = ChatControllerRegistry();

  /// Bidirectional `contact ↔ room` map plus stashed draft customs.
  /// Backed by [DmContactRegistry]. The legacy `_dmRoomByContact`
  /// callsites in the `part of` collaborators go through the
  /// service.
  final DmContactRegistry _dmContacts = DmContactRegistry();

  // -- Sub-managers (composition) --
  /// Standalone handler — no `part of` access, fully injected. Lives
  /// in `services/presence_registry.dart`.
  late final PresenceRegistry _presence = PresenceRegistry(
    api: client.presence,
    roomList: roomListController,
    dmContacts: _dmContacts,
    isDisposed: () => _disposed,
    logger: logger,
  );

  /// Standalone handler — `handlers/room_enricher.dart`. Receives
  /// every dep explicitly so tests can mock individual services
  /// instead of building the full adapter.
  late final RoomEnricher _enricher = RoomEnricher(
    client: client,
    controllers: _chatControllers,
    roomList: roomListController,
    dmContacts: _dmContacts,
    userCache: _userCacheService,
    blockedUsers: _blockedUsers,
    presence: _presence,
    currentUser: () => _currentUser,
    cache: _cache,
    l10n: l10n,
    initializedNotifier: initializedNotifier,
    connectionStateNotifier: connectionStateNotifier,
    isDisposed: () => _disposed,
    isDmDetail: _isDmDetail,
    findCachedUser: findCachedUser,
    cacheUsers: cacheUsers,
    ensureUserCached: _ensureUserCached,
    updateRoomLastMessage: (roomId, message) =>
        _roomListMutator.updateRoomLastMessage(roomId, message),
    removeChatController: removeChatController,
    logger: logger,
    onRoomsLoaded: onRoomsLoaded,
    onDmContactResolved: onDmContactResolved,
    roomTitleResolver: roomTitleResolver,
  );

  /// Standalone handler — `handlers/room_list_mutator.dart`. Owns
  /// every mutation to the room-list controller driven by chat
  /// events or optimistic operations (last-message preview, reaction
  /// preview, receipts, unread counts, DM title/avatar refresh,
  /// sender-name backfill and blocked-rooms pruning).
  late final RoomListMutator _roomListMutator = RoomListMutator(
    roomListController: roomListController,
    cache: _cache,
    client: client,
    l10n: l10n,
    currentUser: () => _currentUser,
    findCachedUser: findCachedUser,
    ensureUserCached: _ensureUserCached,
    findChatController: (roomId) => _chatControllers[roomId],
    removeChatController: removeChatController,
    blockedUserIds: () => _blockedUsers.all,
    isUserBlocked: _blockedUsers.isBlocked,
    computeEffectiveTitle:
        ({required currentItem, otherMembers = const [], isDmOverride}) =>
            _enricher.computeEffectiveTitle(
              currentItem: currentItem,
              otherMembers: otherMembers,
              isDmOverride: isDmOverride,
            ),
    isDisposed: () => _disposed,
  );

  /// Standalone handler — `handlers/optimistic_handler.dart`. Wires
  /// every dep explicitly so it can be unit-tested with mocks
  /// instead of building the full adapter.
  late final OptimisticHandler _optimistic = OptimisticHandler(
    client: client,
    controllers: _chatControllers,
    roomList: roomListController,
    pendingReactions: _pendingReactionsRegistry,
    currentUser: () => _currentUser,
    cache: _cache,
    ensureDmRoomMaterialized: ensureDmRoomMaterialized,
    removeChatController: removeChatController,
    updateRoomLastMessage: (roomId, message) =>
        _roomListMutator.updateRoomLastMessage(roomId, message),
    updateRoomReactionPreview: (roomId, reaction, userId, messageId) =>
        _roomListMutator.updateRoomReactionPreview(
          roomId,
          reaction,
          userId,
          messageId,
        ),
    ensureSentReceipt: _ensureSentReceipt,
    isBlockedError: _isBlockedError,
    isMutedError: _isMutedError,
    // 403 "muted" on send → re-fetch the room detail so `selfMuted`
    // propagates and the composer locks behind the read-only banner.
    onModerationLock: _enrichRoomFromDetail,
    // Forwarded so the optimistic handler can distinguish "I am the
    // blocker" (drop the row, WhatsApp-style) from "I am the
    // blockee" (a 403 blocked while sending should leave my chat
    // visible — the blockee should not be silently expelled from
    // their own conversation).
    isUserBlocked: (userId) => _blockedUsers.isBlocked(userId),
    emitFailure: <T>(result, kind, {roomId, messageId, userId}) =>
        _emitFailure<T>(
          result,
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
    emitOperationSuccess: (kind, {roomId, messageId, userId}) =>
        emitOperationSuccess(
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
    swallowCacheThrow: _swallowCacheThrow,
  );

  /// Standalone handler — `handlers/member_event_handler.dart`. Reacts
  /// to membership realtime events (`UserJoinedEvent`, `UserLeftEvent`)
  /// plus the WhatsApp-parity self-rejoin / kick branches; owns the
  /// system-banner counter used to mint synthetic message ids and the
  /// `deleteKickedChat` cache cleanup.
  late final MemberEventHandler _memberEventHandler = MemberEventHandler(
    client: client,
    chatControllers: _chatControllers,
    cache: _cache,
    roomListController: roomListController,
    userCacheService: _userCacheService,
    l10n: l10n,
    currentUser: () => _currentUser,
    displayNameFor: displayNameFor,
    ensureUserCached: _ensureUserCached,
    addRoomFromDetail: _addRoomFromDetail,
    removeChatController: removeChatController,
    isDisposed: () => _disposed,
    swallowCacheThrow: _swallowCacheThrow,
    logger: logger,
  );

  // -- Typing throttle & stop-emit timers --
  // Backed by `TypingTimerRegistry`. Adapter wires the auto-stop
  // callback to the actual REST `sendTyping(stopsTyping)` so the
  // registry stays agnostic about the network.
  late final TypingTimerRegistry _typingTimers = TypingTimerRegistry(
    onAutoStopTriggered: (roomId) {
      client.messages.sendTyping(roomId, activity: ChatActivity.stopsTyping);
    },
  );

  // -- User cache (in-memory only; persistent cache lives in [_cache]).
  // Backed by `UserCacheService` which also owns the in-flight fetch
  // dedupe.
  late final UserCacheService _userCacheService = UserCacheService(
    api: client.users,
    isDisposed: () => _disposed,
  );

  // -- markAsRead backpressure --
  //
  // Bursts of `NewMessageEvent` in an active room would otherwise fan
  // into one HTTP request per message (event_router fires
  // `unawaited(markAsRead(roomId, lastReadMessageId: msg.id))` on every
  // event). The coalescer keeps at most one in-flight markAsRead per
  // room: while a request is running, the latest pending
  // `lastReadMessageId` is queued and only the freshest one is sent
  // when the in-flight call completes — older intermediate ids are
  // discarded (we only care about the high-water mark).
  /// Coalescer for `markRoomAsRead` REST calls — one in flight per
  /// room max, follow-ups stash the latest high-water mark.
  late final MarkAsReadCoordinator _markAsReadCoord = MarkAsReadCoordinator(
    messages: client.messages,
    isDisposed: () => _disposed,
    onMarkedRead: (roomId) => _roomListMutator.updateRoomUnread(roomId, 0),
    emitFailure: <T>(result, kind, {roomId, messageId, userId}) =>
        _emitFailure<T>(
          result,
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
  );
  StreamSubscription<ChatEvent>? _eventSub;
  StreamSubscription<ChatConnectionState>? _stateSub;

  /// Convenience accessor for the lifecycle's disposed flag — used in
  /// the ~25 async paths that need to early-out when the adapter has
  /// been torn down mid-flight.
  bool get _disposed => _lifecycle.isDisposed;

  void Function(String message)? onBroadcast;
  void Function(ChatEvent event)? onError;
  void Function()? onReconnected;
  void Function(String roomId, String userId)? onDmContactResolved;

  /// Fired whenever a new message lands with `metadata.adminSent == true`
  /// — i.e. it was authored from the admin panel. Hosts use this to
  /// surface a subtle snackbar / banner (`Admin: <text>`) without the
  /// SDK having to ship its own opinionated UI. The bubble itself still
  /// renders with the "admin" microcopy in the meta row regardless of
  /// this callback. Default is `null` (silent fallback).
  void Function(ChatMessage message, String roomId)? onAdminMessage;

  /// Fired when a room the local user belonged to is removed. Receives
  /// the room id plus optional `reason` / `adminReason` metadata — set
  /// to `reason: "banned"` + the admin-supplied free-text reason when
  /// the cause was an admin per-room ban (other organic deletions land
  /// here with both fields null). Hosts wire this to render an
  /// explanatory snackbar / toast; the SDK has already popped the room
  /// from the list and disposed any open controller by the time this
  /// fires.
  void Function(String roomId, String? reason, String? adminReason)?
  onRoomRemoved;

  /// Optional notification fired whenever the set of blocked users
  /// changes — both when the consumer pushes a fresh set via
  /// [blockedUserIds] (e.g. on `/users/me` refresh) and when
  /// [blockContact] mutates the set after a local block. Receives the
  /// full updated set so apps can drive analytics, refresh banners,
  /// invalidate caches, etc. Default is `null` (no-op).
  void Function(Set<String> blockedUserIds)? onBlockedUsersChanged;

  /// Backing service for [blockedUserIds]. The registry owns the set
  /// and fires its own onChange callback on real mutations; the
  /// adapter glues that callback to the room-prune flow + the public
  /// `onBlockedUsersChanged` hook below.
  late final BlockedUsersRegistry _blockedUsers = BlockedUsersRegistry(
    onChanged: (ids) {
      _roomListMutator.removeBlockedRooms();
      // Fan-out to derived state. The Listenable lets the SuggestionBar
      // controller refresh immediately on unblock (otherwise it had to
      // wait for the 10s poll tick before re-displaying the contact).
      _blockedUsersListenable.emit();
      onBlockedUsersChanged?.call(ids);
    },
  );

  /// Snapshot of users blocked by (or blocking, depending on the
  /// consumer's source of truth) the current user. The adapter uses this
  /// set to drop DM rooms whose `otherUserId` matches, both at
  /// resolution time ([_doResolveDmContact]) and when the set itself
  /// changes ([blockedUserIds]= …). Consumers typically push the full set
  /// after their own user-info refresh; [blockContact] also keeps it in
  /// sync for the rooms it touches.
  Set<String> get blockedUserIds => contacts.blockedUserIds;

  /// Replaces the blocked-users set wholesale and prunes any DM rooms
  /// whose `otherUserId` ended up blocked. Emits [onBlockedUsersChanged]
  /// after the prune. Idempotent — passing the same set twice is a no-op
  /// (the prune still runs but finds nothing new to remove).
  set blockedUserIds(Set<String> ids) {
    contacts.blockedUserIds = ids;
  }

  /// Re-runs the blocked-rooms prune. Idempotent — useful when the
  /// consumer reloads rooms (e.g. after `loadRooms` finishes a network
  /// sync) and wants to drop any rows that were materialized for
  /// contacts already known to be blocked. The setter [blockedUserIds]=
  /// already invokes this; expose it standalone so consumers don't need
  /// to reassign the set just to trigger the prune.
  @internal
  void pruneBlockedRooms() => contacts.pruneBlockedRooms();

  /// One-shot bootstrap of the blocked-users set from the server.
  /// Fetches `client.contacts.listBlocked()`, replaces [blockedUserIds]
  /// (which also prunes any DM rows that happened to be materialized for
  /// contacts in the set) and fires [onBlockedUsersChanged].
  ///
  /// Typical usage:
  /// ```dart
  /// await chat.connect();
  /// await chat.adapter.rooms.load();
  /// await chat.adapter.contacts.loadBlocked(); // one-shot, NOT polled
  /// ```
  ///
  /// Subsequent mutations come from [blockContact] / [unblockContact]
  /// (local sources of truth) — no polling needed. Re-invoke this method
  /// only on explicit user-triggered refresh (e.g. entering the blocked
  /// users screen) when you want a server-confirmed snapshot.
  @internal
  Future<ChatResult<void>> loadBlockedUsers() => contacts.loadBlocked();

  /// Owns the failure + success broadcast streams. Adapter delegates
  /// every `_emitFailure(...)` / `emitOperationSuccess(...)` callsite
  /// to this hub so the stream lifecycle + "skip if closed" guard
  /// have a single tested home.
  final OperationHub _operations = OperationHub();

  /// Broadcast stream of failures from any adapter operation. The
  /// original `ChatResult.ChatFailureResult` is still returned to the caller; this
  /// stream is for cross-cutting concerns (global snackbars,
  /// telemetry). Multiple subscribers can listen concurrently.
  Stream<OperationError> get operationErrors => _operations.errors;

  /// Broadcast stream of successful operations that have user-visible
  /// side effects worth confirming (pin/unpin a message, delete a
  /// message, forward, mute/unmute, etc.). The default [ChatView]
  /// subscribes when `showOperationFeedback: true` (default) and
  /// shows localized SnackBars. Apps wanting fully custom UI can
  /// listen here directly and pass `showOperationFeedback: false`.
  Stream<OperationSuccess> get operationSuccesses => _operations.successes;

  /// Emit a success event on [operationSuccesses]. No-op when the
  /// controller is closed (post-dispose). Public so collaborator
  /// `part of` files (event router, optimistic handler) can publish
  /// without going through `_emitFailure`-style wrappers.
  void emitOperationSuccess(
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) => _operations.emitSuccess(
    kind,
    roomId: roomId,
    messageId: messageId,
    userId: userId,
  );

  ChatResult<T> _emitFailure<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) => _operations.emitFailure(
    result,
    kind,
    roomId: roomId,
    messageId: messageId,
    userId: userId,
  );

  ChatConnectionState get connectionState => client.connectionState;

  /// Returns (or creates) a [ChatController] for the given room.
  ChatController getChatController(
    String roomId, {
    List<ChatMessage> initialMessages = const [],
    List<ChatUser> otherUsers = const [],
  }) {
    if (otherUsers.isNotEmpty) cacheUsers(otherUsers);
    final existing = _chatControllers[roomId];
    if (existing != null) {
      if (otherUsers.isNotEmpty) existing.setOtherUsers(otherUsers);
      return existing;
    }
    final controller = ChatController(
      initialMessages: initialMessages,
      currentUser: currentUser,
      otherUsers: otherUsers,
    );
    controller.setRoomId(roomId);
    _chatControllers[roomId] = controller;
    return controller;
  }

  /// Looks up a previously cached user by id. Returns `null` when the user is
  /// unknown to the adapter; callers that need the data should trigger a
  /// lookup via `client.users.get` and feed the result back through
  /// [cacheUsers].
  ChatUser? findCachedUser(String userId) => _userCacheService.find(userId);

  /// Resolves a user's display name with a fallback chain that NEVER
  /// returns a raw UUID when a friendlier label exists:
  ///   1) Local user (`currentUser`) gets its own `displayName` — the
  ///      adapter does NOT seed `_userCache` with self, so a plain
  ///      `findCachedUser` lookup would miss this case and the UI would
  ///      end up rendering the local UUID for "by you" rows.
  ///   2) Otherwise, falls back to the cached `ChatUser.displayName` if
  ///      non-empty.
  ///   3) Last-ditch fallback: returns the raw `userId` so callers can
  ///      always render something. Pass it through `pin.pinnedBy`, the
  ///      bubble sender name, etc.
  ///
  /// Use this anywhere the UI shows `by <name>` / `with <name>` — pin
  /// list, room invitations, mention overlays, etc.
  String displayNameFor(String userId) {
    if (userId == currentUser.id) {
      final selfName = currentUser.displayName?.trim();
      if (selfName != null && selfName.isNotEmpty) return selfName;
      return userId;
    }
    final cached = _userCacheService.find(userId)?.displayName?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    return userId;
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
          prev.avatarUrl != u.avatarUrl) {
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

  /// Forces a `sent` receipt on a server-confirmed outgoing message that came
  /// back without one. The server omits the field for the synchronous POST
  /// response, so without this helper an outgoing bubble would render with no
  /// status icon until a `delivered`/`read` event arrives.
  ChatMessage _ensureSentReceipt(ChatMessage message) => message.receipt == null
      ? message.copyWith(receipt: ReceiptStatus.sent)
      : message;

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

  /// Disposes and removes the controller for a room. When [autoMarkAsRead]
  /// is true (default), flushes a `markAsRead` for the room before disposing
  /// so the chat list unread counter and last-read pointer stay in sync
  /// with what the user actually saw (mirrors WhatsApp's "close chat" flush).
  void removeChatController(String roomId) {
    if (autoMarkAsRead && _chatControllers.containsKey(roomId)) {
      unawaited(markAsRead(roomId));
    }
    if (_activeRoomId == roomId) _activeRoomId = null;
    _chatControllers.remove(roomId)?.dispose();
  }

  /// Id of the room the user is currently viewing on screen. `null` means
  /// the chat list (or no chat) is in foreground. Consumers wire it from
  /// their chat-room widget lifecycle: `setActiveRoom(roomId)` on enter,
  /// `setActiveRoom(null)` on leave.
  ///
  /// While set, [_onNewMessage] in the event router fires `markAsRead`
  /// immediately for incoming messages in that room — so the sender sees
  /// the second tick flip to blue in real time, exactly as WhatsApp does
  /// when both peers are in the same conversation.
  String? _activeRoomId;
  String? get activeRoomId => _activeRoomId;

  /// Marks [roomId] as the currently-foregrounded chat. Pass `null` when
  /// the user leaves it. Triggers a one-shot `markAsRead` for [roomId] if
  /// [autoMarkAsRead] is true (cheap; idempotent when nothing changed).
  void setActiveRoom(String? roomId) {
    if (_activeRoomId == roomId) return;
    _activeRoomId = roomId;
    if (roomId != null && autoMarkAsRead) {
      unawaited(markAsRead(roomId));
    }
  }

  /// Returns the [ChatController] for [roomId] only if it has already been
  /// created (does NOT create a new one). Useful for read-only lookups such as
  /// resolving member names from the room list.
  ChatController? findChatController(String roomId) => _chatControllers[roomId];

  /// Associates a contact user ID with its DM room ID for typing indicator routing.
  @internal
  void registerDmRoom(String contactUserId, String roomId) =>
      dm.registerRoom(contactUserId, roomId);

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
      controller.confirmSent(tempId, confirmed);
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
  Future<void> connect() async {
    _cancelSubscriptions();
    start();
    await client.connect();
  }

  /// Disconnects from the server and clears all controllers.
  Future<void> disconnect() async {
    await _cancelSubscriptions();
    client.cancelPendingRequests('disconnect');
    await client.disconnect();
    _chatControllers.disposeAll();
    _dmContacts.clear();
    _typingTimers.clearAll();
    roomListController.setRooms([]);
  }

  /// One-shot teardown for "logout" flows: disconnects, wipes every
  /// in-memory cache (users, DM mapping, blocked-users set, draft custom
  /// payloads, voice-upload progress notifiers) and best-effort flushes
  /// the persistent cache. After this call the adapter is in the same
  /// shape as a fresh instance — safe to either dispose or reconnect
  /// with a new user.
  ///
  /// Hosts typically call this from a "Log out" menu item; in the
  /// example app the chat-list overflow wires it. Subsequent operations
  /// on this adapter throw because [_disposed] is set. Pair with
  /// [NomaChat.dispose] on the facade to release the cache datasource
  /// as well.
  Future<void> signOut() async {
    await disconnect();
    _userCacheService.clear();
    _blockedUsers.clear();
    // _dmContacts is already cleared inside disconnect(); only need to
    // explicitly drop the draft-custom stash here (still under _dmContacts).
    _dmContacts.clear();
    _voiceUploads.disposeAll();
    _pendingReactionsRegistry.clear();
    _activeRoomId = null;
    initializedNotifier.value = false;
    connectionStateNotifier.value = ChatConnectionState.disconnected;
    try {
      await _cache?.clear();
    } catch (_) {
      // best-effort — a partial clear is acceptable on logout
    }
  }

  /// Returns the room ID for a DM with the given contact, or null.
  @internal
  String? getDmRoomId(String contactUserId) => dm.getRoomId(contactUserId);

  /// Returns the existing DM room id with [otherUserId] if there is one, or
  /// `null` if no conversation has been started yet. Checks the contact→room
  /// cache first (`getDmRoomId`) and falls back to scanning the room list for
  /// rows with `otherUserId == otherUserId`.
  ///
  /// Use this before calling [openDirectMessageDraft] to decide whether to
  /// open the existing conversation (`getChatController(existingId)`) or
  /// start a fresh draft.
  @internal
  String? findExistingDmRoom(String otherUserId) =>
      dm.findExisting(otherUserId);

  /// Opens a draft DM with [otherUserId] WhatsApp-style — returns a
  /// [ChatController] in `isDraft` state without creating a room
  /// server-side. The other user is hydrated (from cache or
  /// `client.users.get`) so `controller.otherUsers` is populated and
  /// downstream consumers (e.g. AppBars resolving titles via
  /// `RoomTitleResolver`) can render immediately.
  ///
  /// The draft is cached under the key `draft:<otherUserId>` in
  /// `_chatControllers`. The first successful send through this controller
  /// materializes a real room (`rooms.create` with `members: [otherUserId]`,
  /// plus any [extraRoomCustom]) — see `_OptimisticHandler.sendMessage`.
  ///
  /// Callers that want to reuse an existing conversation should call
  /// [findExistingDmRoom] first.
  ///
  /// [extraRoomCustom] is merged into the `custom` map of the
  /// materialized room. Pass `{'type': 'dm'}` (or whatever marker your app
  /// uses) when the [IsDmRoomPredicate] needs an explicit hint to recognize
  /// the room as a DM.
  @internal
  Future<ChatController> openDirectMessageDraft(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.openDraft(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Key under which a draft DM controller is cached in `_chatControllers`.
  /// Exposed publicly so the UI layer can pass it to [sendMessage] (and
  /// other room-id-keyed APIs) before the draft has been materialized into
  /// a real room. Format: `draft:<otherUserId>`.
  @internal
  String draftRoutingKey(String otherUserId) => dm.draftRoutingKey(otherUserId);

  // Note: draft DM custom payloads (the per-contact map previously
  // here as `_draftRoomCustomByOtherUser`) live in [_dmContacts]
  // under `draftCustomFor`/`setDraftCustom` — same lifecycle as the
  // DM mapping itself, so a single service owns both.

  /// Returns the real server-side `roomId` for the DM with [otherUserId],
  /// creating the room if it does not exist yet. Idempotent — three branches:
  ///
  /// 1. There is already a known room with this contact
  ///    ([findExistingDmRoom] returns non-null) → returns that id.
  /// 2. There is an open draft controller for this contact
  ///    (`_chatControllers['draft:<otherUserId>']`): create the room via
  ///    `client.rooms.create`, rebind the controller from the draft slot to
  ///    the real id (`setRoomId` + `clearDraft`), seed `_dmRoomByContact`,
  ///    and add the row to the room list. Returns the real id.
  /// 3. No room and no draft: same as (2) but no controller to rebind. The
  ///    consumer typically calls [getChatController] afterwards.
  ///
  /// Use this from flows that need the real `roomId` BEFORE sending — e.g.
  /// uploading an attachment whose progress is tied to a row in the list,
  /// or any operation routed via `roomId` (typing, voice send, etc.). The
  /// optimistic `sendMessage` materializes on its own; consumers that only
  /// send text don't need to call this directly.
  ///
  /// [extraRoomCustom] overrides any custom payload previously registered
  /// for [otherUserId] via [openDirectMessageDraft]. Useful for ad-hoc
  /// callers without a draft controller.
  ///
  /// Failures propagate the underlying `ChatResult.ChatFailureResult` so the consumer can
  /// surface a retry. A failure does NOT leave a stale draft entry — the
  /// controller stays in `isDraft = true` and can retry on the next send.
  @internal
  Future<ChatResult<String>> ensureDmRoomMaterialized(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.ensureMaterialized(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Releases all resources. The adapter must not be used after this call.
  Future<void> dispose() async {
    // Lifecycle.dispose() flips isDisposed and disposes the two
    // notifiers. It runs FIRST so any async path racing the teardown
    // sees `_disposed == true` immediately and bails on its early
    // return guards.
    await _lifecycle.dispose();
    await _cancelSubscriptions();
    client.cancelPendingRequests('dispose');
    await client.disconnect();
    _chatControllers.disposeAll();
    _dmContacts.clear();
    _typingTimers.clearAll();
    _voiceUploads.disposeAll();
    roomListController.dispose();
    _currentUserListenable.dispose();
    _userCacheListenable.dispose();
    await _operations.dispose();
  }

  /// Fetches rooms from the server and populates the [roomListController].
  /// Loads user rooms using cache-then-network:
  /// 1. Shows cached room list instantly (if available).
  /// 2. Fetches fresh room list from network and replaces — unless
  ///    realtime (WS) is already connected and the adapter has been
  ///    initialized at least once. In that case the cache is trusted
  ///    and the network round-trip is skipped: incoming events keep
  ///    the room list up-to-date in real time.
  ///
  /// Pass [forceNetwork] to bypass the realtime optimization — useful
  /// for pull-to-refresh interactions where the user explicitly asks
  /// for a fresh server snapshot.
  @internal
  Future<ChatResult<void>> loadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => rooms.load(type: type, forceNetwork: forceNetwork);

  Future<ChatResult<void>> _doLoadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => _enricher.loadAll(type: type, forceNetwork: forceNetwork);

  void _loadReactionsFromMessages(
    ChatController controller,
    List<ChatMessage> messages,
  ) {
    for (final msg in messages) {
      final reactions = msg.metadata?['_reactions'];
      if (reactions is Map) {
        final counts = <String, int>{};
        for (final entry in reactions.entries) {
          counts[entry.key as String] = entry.value as int;
        }
        if (counts.isNotEmpty) controller.setReactions(msg.id, counts);
      }
      final reactionUsers = msg.metadata?['_reactionUsers'];
      if (reactionUsers is Map) {
        final ownEmojis = <String>{};
        for (final entry in reactionUsers.entries) {
          final users = entry.value;
          if (users is List && users.contains(currentUser.id)) {
            ownEmojis.add(entry.key as String);
          }
        }
        if (ownEmojis.isNotEmpty) {
          controller.setUserReactions(msg.id, ownEmojis);
        }
      }
    }
  }

  /// Loads initial messages for a room using cache-then-network:
  /// 1. Shows cached messages instantly (if available).
  /// 2. Fetches fresh messages from network in background and merges.
  Future<ChatResult<List<ChatMessage>>> loadMessages(
    String roomId, {
    int limit = 50,
  }) => messages.load(roomId, limit: limit);

  Future<void> _rehydratePendingMessages(
    String roomId,
    ChatController controller,
  ) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final pending =
          (await cache.getPendingMessages(roomId)).dataOrNull ??
          const <PendingChatMessage>[];
      for (final p in pending) {
        // If a server-confirmed message with the same sender/type/text and a
        // near-identical timestamp already exists, treat the pending entry as
        // an orphan from a lost deletePendingMessage and drop it. Without
        // this, a single failed cache delete would leak a ghost bubble that
        // re-appears on every reload.
        final superseded = controller.messages.any(
          (m) =>
              m.id != p.message.id &&
              m.from == p.message.from &&
              m.messageType == p.message.messageType &&
              m.text == p.message.text &&
              m.timestamp.difference(p.message.timestamp).inSeconds.abs() <= 60,
        );
        if (superseded) {
          unawaited(
            cache
                .deletePendingMessage(roomId, p.message.id)
                .catchError(_swallowCacheThrow),
          );
          continue;
        }
        final exists = controller.messages.any((m) => m.id == p.message.id);
        if (!exists) controller.addMessage(p.message);
        // Anything that survived to the next load couldn't confirm in the
        // previous session: surface it as failed so the user can retry.
        controller.markFailed(p.message.id);
      }
    } catch (_) {
      // Best-effort: cache hydration must never block the chat.
    }
  }

  /// Loads older messages for pagination using cache-then-network.
  /// No-op if already loading or no more pages.
  Future<ChatResult<List<ChatMessage>>> loadMoreMessages(
    String roomId, {
    int limit = 50,
  }) => messages.loadMore(roomId, limit: limit);

  // Message IDs with pending reaction deletes — skip WS refresh for these.
  // Backed by `PendingReactionsRegistry` (services/) so the
  // suppression logic has its own tested home rather than being a
  // loose Set sprinkled across handlers.
  final PendingReactionsRegistry _pendingReactionsRegistry =
      PendingReactionsRegistry();

  /// Sends a message with optimistic UI update. Shows immediately, confirms on server response.
  ///
  /// [operationKind] lets callers like [sendThreadReply] surface a more
  /// specific [OperationKind] on the error stream instead of the default
  /// [OperationKind.sendMessage]; pass `null` to use the default.
  @internal
  Future<ChatResult<ChatMessage>> sendMessage(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    OperationKind? operationKind,
  }) => messages.send(
    roomId,
    text: text,
    referencedMessageId: referencedMessageId,
    messageType: messageType,
    metadata: metadata,
    attachmentUrl: attachmentUrl,
    operationKind: operationKind,
  );

  /// Forwards [messageId] (originally posted in [sourceRoomId]) to every
  /// room in [targetRoomIds]. Returns the list of forwarded message
  /// results in the same order. Successes carry the new server-assigned
  /// `ChatMessage`; failures carry the underlying `ChatFailure`.
  ///
  /// **Optimistic UI**: for each target with an open controller, an
  /// optimistic `MessageType.forward` bubble is inserted *before* the
  /// network call and confirmed/failed once the server responds.
  /// This avoids the visible delay between tapping "Forward" and the
  /// bubble landing via WS roundtrip.
  ///
  /// Materializes draft DMs inline when a target is a draft routing
  /// key — same pattern as [sendMessage] / [sendVoiceMessage]. The
  /// backend persists `forwardedFrom` / `forwardedFromRoom` metadata so
  /// receivers render the WhatsApp-style "Forwarded" chevron via
  /// `ForwardedBubble`.
  Future<List<ChatResult<ChatMessage>>> forwardMessage({
    required String sourceRoomId,
    required String messageId,
    required List<String> targetRoomIds,
    Map<String, dynamic>? extraMetadata,
  }) => messages.forward(
    sourceRoomId: sourceRoomId,
    messageId: messageId,
    targetRoomIds: targetRoomIds,
    extraMetadata: extraMetadata,
  );

  /// Edits a message with optimistic update. Reverts on failure.
  @internal
  Future<ChatResult<void>> editMessage(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => messages.edit(roomId, messageId, text: text, metadata: metadata);

  /// Deletes a message globally. The deleter's own chat flips the
  /// row to a "You deleted this message" tombstone (WhatsApp-style)
  /// instead of removing it outright — other clients render the
  /// same tombstone via the `message_deleted` WS event. Restores on
  /// failure.
  @internal
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId) =>
      messages.delete(roomId, messageId);

  /// "Delete for me": locally hides the tombstone of [messageId] in
  /// [roomId] without touching the server. WhatsApp behaviour for
  /// the deleter who wants to also clear the placeholder from their
  /// own view, or for any client that wants to drop a message
  /// locally. Drops from the controller AND the local cache so it
  /// stays gone after a room re-open / cold start.
  @internal
  Future<ChatResult<void>> deleteMessageLocally(
    String roomId,
    String messageId,
  ) => messages.deleteLocally(roomId, messageId);

  /// Sends an emoji reaction with optimistic update.
  @internal
  Future<ChatResult<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => messages.sendReaction(roomId, messageId: messageId, emoji: emoji);

  /// Fetches aggregated reactions for a message from the server.
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) => messages.getReactions(roomId, messageId);

  /// Removes the current user's reaction from a message with optimistic update.
  @internal
  Future<ChatResult<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => messages.deleteReaction(roomId, messageId: messageId, emoji: emoji);

  /// Sends a typing indicator to a room (throttled per
  /// `TypingTimerRegistry.throttle`, default 3s). When [isTyping] is
  /// `true`, the registry also schedules an auto-stop timer
  /// (`TypingTimerRegistry.stopDelay`, default 1s) so the server gets
  /// a `stopsTyping` even when the caller goes silent.
  @internal
  Future<ChatResult<void>> sendTyping(String roomId, {bool isTyping = true}) =>
      messages.sendTyping(roomId, isTyping: isTyping);

  /// Marks all messages in a room as read.
  ///
  /// When [lastReadMessageId] is omitted, falls back to the id of the last
  /// non-own message currently held by the room's [ChatController]. Passing
  /// the id allows the backend to fan out a `receipt_updated` event to the
  /// original sender so the second tick can flip to "read"; legacy callers
  /// that omit it still get the room-level `lastReadAt` persisted as before.
  @internal
  Future<ChatResult<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => messages.markAsRead(roomId, lastReadMessageId: lastReadMessageId);

  /// Clears chat history for the current user (client-side only).
  @internal
  Future<ChatResult<void>> clearChat(String roomId) =>
      messages.clearChat(roomId);

  /// Sends a read/delivery receipt for a specific message.
  @internal
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => messages.sendReceipt(roomId, messageId, status: status);

  /// Sends a direct message to a contact.
  @internal
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) => messages.sendDirect(
    contactUserId,
    text: text,
    messageType: messageType,
    attachmentUrl: attachmentUrl,
    metadata: metadata,
  );

  /// Uploads a file attachment.
  @internal
  Future<ChatResult<AttachmentUploadResult>> uploadAttachment(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) => messages.uploadAttachment(data, mimeType, onProgress: onProgress);

  /// High-level helper: uploads [pick] and dispatches the resulting
  /// attachment message in one shot. Picks the right [MessageType]
  /// (`audio` for `audio/*`, `attachment` otherwise — image/video also
  /// resolve to `attachment` and let the bubble layer pick the right
  /// renderer via the MIME type), materializes the DM draft inline when
  /// [roomIdOrDraftKey] points to a draft routing key, and
  /// surfaces upload progress via [voiceUploadProgressFor]-style hooks
  /// when [onProgress] is provided.
  ///
  /// When [policy] is supplied (and isn't [AttachmentPolicy.unrestricted]),
  /// the bytes + mime are validated server-side-of-the-app before any
  /// network call. Violations surface as a `ValidationFailure` so the
  /// consumer can render the right error string. The picker helpers
  /// in [AttachmentPickers] already enforce policies at pick time;
  /// passing it here is a belt-and-suspenders for paths that build the
  /// bytes themselves (web drop targets, share-extensions, …).
  ///
  /// Use this when the composer has a single full-in-memory pick result
  /// from [AttachmentPickers]. For voice messages keep using the
  /// dedicated [sendVoiceMessage] (it owns the waveform + duration).
  @internal
  Future<ChatResult<ChatMessage>> sendAttachment(
    String roomIdOrDraftKey, {
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(int sent, int total)? onProgress,
  }) => messages.sendAttachment(
    roomIdOrDraftKey,
    bytes: bytes,
    mimeType: mimeType,
    fileName: fileName,
    policy: policy,
    onProgress: onProgress,
  );

  /// Per-message upload progress notifiers (0..1) for voice messages
  /// that are being uploaded right now. Backed by [VoiceUploadRegistry]
  /// so the lifecycle (register → complete vs drop → disposeAll) lives
  /// in its own tested service rather than scattered across this
  /// class.
  final VoiceUploadRegistry _voiceUploads = VoiceUploadRegistry();

  /// Returns a listenable for the upload progress of a pending voice message.
  /// Returns `null` if there is no upload in flight for that id.
  ValueListenable<double>? voiceUploadProgressFor(String messageId) =>
      _voiceUploads.listenableFor(messageId);

  /// Records and confirms a voice message: optimistic bubble first, then upload
  /// (with progress published to [voiceUploadProgressFor]), then send.
  ///
  /// The optimistic bubble is shown without a usable URL until upload completes
  /// — the UI hides the play button while [voiceUploadProgressFor] returns
  /// non-null. On success the bubble flips to the real URL; on failure it is
  /// marked as failed and the progress notifier is cleaned up.
  @internal
  Future<ChatResult<ChatMessage>> sendVoiceMessage(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
  }) => messages.sendVoice(
    roomIdOrDraftKey,
    audioBytes: audioBytes,
    mimeType: mimeType,
    duration: duration,
    waveform: waveform,
  );

  /// Generic optimistic toggle for a boolean room flag (muted / pinned /
  /// hidden). Flips the visible state immediately, calls [apiCall], and
  /// rolls back on failure. Emits an [OperationError] through
  /// [operationErrors] tagged with [kind] when the API call fails.
  ///
  /// Captured as a helper because the 6 toggle methods below — mute,
  /// unmute, pin, unpin, hide, unhide — share the exact same flow, just
  /// differing on which `RoomListItem` field flips and which `client.rooms`
  /// endpoint runs.
  Future<ChatResult<void>> _toggleRoomFlag(
    String roomId,
    RoomListItem Function(RoomListItem room, bool value) applyFlag,
    bool desiredValue,
    Future<ChatResult<void>> Function(String roomId) apiCall,
    OperationKind kind,
  ) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(applyFlag(room, desiredValue));
    }
    final result = await apiCall(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(applyFlag(room, !desiredValue));
    }
    return _emitFailure(result, kind, roomId: roomId);
  }

  /// Mutes a room with optimistic update.
  @internal
  Future<ChatResult<void>> muteRoom(String roomId) => rooms.mute(roomId);

  /// Unmutes a room with optimistic update.
  @internal
  Future<ChatResult<void>> unmuteRoom(String roomId) => rooms.unmute(roomId);

  /// Pins a room with optimistic update.
  @internal
  Future<ChatResult<void>> pinRoom(String roomId) => rooms.pin(roomId);

  /// Unpins a room with optimistic update.
  @internal
  Future<ChatResult<void>> unpinRoom(String roomId) => rooms.unpin(roomId);

  /// Hides a room with optimistic update (removes from visible list).
  @internal
  Future<ChatResult<void>> hideRoom(String roomId) => rooms.hide(roomId);

  /// Unhides a room with optimistic update.
  @internal
  Future<ChatResult<void>> unhideRoom(String roomId) => rooms.unhide(roomId);

  /// Blocks a contact. WhatsApp-parity: the DM room STAYS in the
  /// blocker's chat list with full history — the composer is replaced
  /// by a "tap to unblock" banner (see [ChatView.isBlocked]) so the
  /// blocker can reverse course. The previous implementation removed
  /// the room entirely and forced consumers to pop the chat page,
  /// which lost the conversation context and surprised users.
  ///
  /// Adds [userId] to [blockedUserIds] and fires
  /// [onBlockedUsersChanged] so the host UI can react (e.g. hide
  /// suggestions, swap the composer for the blocked banner).
  @internal
  Future<ChatResult<void>> blockContact(String userId, {String? roomId}) =>
      contacts.block(userId, roomId: roomId);

  /// Unblocks a contact in the chat system. Removes [userId] from
  /// [blockedUserIds] and fires [onBlockedUsersChanged]. Does NOT
  /// recreate the DM row — consumers that need the room back should
  /// call [loadRooms] or open a fresh draft via
  /// [openDirectMessageDraft].
  @internal
  Future<ChatResult<void>> unblockContact(String userId) =>
      contacts.unblock(userId);

  /// Adds [userIds] to [roomId] as group members. WhatsApp-style default:
  /// [mode] = `RoomUserMode.inviteAndJoin` — the invited users join
  /// immediately without requiring an accept step. Apps that need an
  /// invitation-then-accept flow pass [mode] = `RoomUserMode.invite`.
  ///
  /// On success the adapter does NOT mutate the local
  /// [roomListController] directly — the backend emits a
  /// `UserJoinedEvent` per added user that the event router already
  /// turns into `ChatController.setOtherUsers` updates and metadata
  /// refreshes. This keeps the local state consistent with anyone else
  /// observing the same room (multi-device, web client, etc.).
  @internal
  Future<ChatResult<void>> addMembers(
    String roomId,
    List<String> userIds, {
    RoomUserMode mode = RoomUserMode.inviteAndJoin,
  }) => rooms.addMembers(roomId, userIds, mode: mode);

  /// Updates room metadata (name, subject, avatar, custom). Wrapper
  /// around `client.rooms.updateConfig` that emits [operationErrors]
  /// with [OperationKind.updateRoomConfig] on failure. Backend gates
  /// this on owner/admin role; non-privileged callers get a 403.
  @internal
  Future<ChatResult<void>> updateRoomConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => rooms.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    custom: custom,
  );

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

  /// Creates a group room in a single hop, optionally uploading an
  /// avatar first. Returns the newly-created room id on success so the
  /// caller can navigate straight into it.
  @internal
  Future<ChatResult<String>> createGroupRoom({
    required String name,
    required List<String> memberIds,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    String? subject,
    bool allowInvitations = false,
    RoomAudience audience = RoomAudience.contacts,
    Map<String, dynamic>? custom,
  }) => rooms.createGroup(
    name: name,
    memberIds: memberIds,
    avatarBytes: avatarBytes,
    avatarMimeType: avatarMimeType,
    subject: subject,
    allowInvitations: allowInvitations,
    audience: audience,
    custom: custom,
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

  /// Removes [userId] from [roomId] — used by admins to kick a member.
  /// The backend rejects the call (403) if the caller lacks the
  /// permission; the SDK surfaces the failure via [operationErrors] like
  /// any other adapter op. On success the backend emits `UserLeftEvent`
  /// to all participants, which `ChatEventRouter` already handles.
  @internal
  Future<ChatResult<void>> removeMember(String roomId, String userId) =>
      rooms.removeMember(roomId, userId);

  /// Updates [userId]'s [RoomRole] inside [roomId] — admins promote
  /// members or demote other admins. Backend rejects if the caller lacks
  /// the permission (the SDK surfaces the failure via [operationErrors]).
  /// On success the backend emits `UserRoleChangedEvent` and the event
  /// router refreshes member lists.
  @internal
  Future<ChatResult<void>> updateMemberRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => rooms.updateMemberRole(roomId, userId, role);

  /// Leaves a room and removes it from the list.
  @internal
  Future<ChatResult<void>> leaveRoom(String roomId) => rooms.leave(roomId);

  /// Retries sending a failed message.
  @internal
  Future<ChatResult<ChatMessage>> retrySend(String roomId, String messageId) =>
      messages.retrySend(roomId, messageId);

  /// Loads thread replies for a parent message.
  Future<ChatResult<List<ChatMessage>>> loadThread(
    String roomId,
    String messageId, {
    int limit = 50,
  }) => messages.loadThread(roomId, messageId, limit: limit);

  /// Sends a reply within a thread.
  ///
  /// Emits `OperationKind.sendThreadReply` on failure (not the generic
  /// `sendMessage`), so a single consumer of `operationErrors` does not
  /// receive a duplicate event for the same underlying failure.
  @internal
  Future<ChatResult<ChatMessage>> sendThreadReply(
    String roomId,
    String parentMessageId, {
    required String text,
  }) => messages.sendThreadReply(roomId, parentMessageId, text: text);

  /// Searches messages within a room. Returns a paginated response so callers
  /// (e.g. `MessageSearchController`) can drive load-more via `hasMore`.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> searchMessages(
    String query,
    String roomId, {
    ChatPaginationParams? pagination,
  }) => messages.search(query, roomId, pagination: pagination);

  /// Loads read receipts for a room.
  Future<ChatResult<List<ReadReceipt>>> loadReceipts(String roomId) =>
      messages.loadReceipts(roomId);

  /// Accepts a room invitation.
  @internal
  Future<ChatResult<void>> acceptInvitation(String roomId) =>
      rooms.acceptInvitation(roomId);

  /// Rejects a room invitation and removes it from the list. Restores the
  /// row on failure so a network glitch does not silently lose the invite.
  @internal
  Future<ChatResult<void>> rejectInvitation(String roomId) =>
      rooms.rejectInvitation(roomId);

  /// Pins a message in a room with optimistic update. Restores on failure.
  @internal
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) =>
      messages.pin(roomId, messageId);

  /// Unpins a message from a room with optimistic update. Restores on failure.
  @internal
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) =>
      messages.unpin(roomId, messageId);

  /// Loads all pinned messages for a room and updates the controller state.
  Future<ChatResult<List<MessagePin>>> loadPins(String roomId) =>
      messages.loadPins(roomId);

  // --- Event Handlers ---

  /// Routes a real-time event from the SDK to the right adapter helper.
  /// All cases live in [ChatEventRouter] so this facade only carries the
  /// one-line delegate.
  late final ChatEventRouter _eventRouter = ChatEventRouter(
    ChatEventRouterDeps(
      client: client,
      controllers: _chatControllers,
      roomList: roomListController,
      dmContacts: _dmContacts,
      userCacheService: _userCacheService,
      pendingReactions: _pendingReactionsRegistry,
      presence: _presence,
      cache: _cache,
      connectionStateNotifier: connectionStateNotifier,
      l10n: l10n,
      autoMarkAsRead: autoMarkAsRead,
      currentUser: () => _currentUser,
      setCurrentUser: (user) => _currentUser = user,
      activeRoomId: () => _activeRoomId,
      isDisposed: () => _disposed,
      findCachedUser: findCachedUser,
      cacheUsersFn: cacheUsers,
      ensureUserCachedFn: _ensureUserCached,
      markAsReadFn: markAsRead,
      refreshMessageFn: _refreshMessage,
      refreshReactionsFn: _refreshReactions,
      handleUserJoinedFn: _memberEventHandler.handleUserJoined,
      handleUserLeftFn: _memberEventHandler.handleUserLeft,
      handleUserRejoinedFn: _memberEventHandler.handleUserRejoined,
      addSystemMessageFn: _memberEventHandler.addSystemMessage,
      addRoomFromDetailFn: _addRoomFromDetail,
      enrichRoomFromDetailFn: _enrichRoomFromDetail,
      updateRoomLastMessage: (roomId, message) =>
          _roomListMutator.updateRoomLastMessage(roomId, message),
      updateRoomListReceipt: (roomId, messageId, status) =>
          _roomListMutator.updateRoomListReceipt(roomId, messageId, status),
      updateRoomReactionPreview: (roomId, reaction, userId, messageId) =>
          _roomListMutator.updateRoomReactionPreview(
            roomId,
            reaction,
            userId,
            messageId,
          ),
      updateRoomUnread: (roomId, count) =>
          _roomListMutator.updateRoomUnread(roomId, count),
      removeChatController: removeChatController,
      onAdminMessage: () => onAdminMessage,
      onBroadcast: () => onBroadcast,
      onError: () => onError,
      onReconnected: () => onReconnected,
      onRoomRemoved: () => onRoomRemoved,
    ),
  );

  void _handleEvent(ChatEvent event) => _eventRouter.handle(event);

  void _handleStateChange(ChatConnectionState state) {
    connectionStateNotifier.value = state;
  }

  void _refreshReactions(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .getReactions(roomId, messageId, cachePolicy: CachePolicy.networkOnly)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          if (result.isFailure) {
            active.clearReactions(messageId);
            return;
          }
          final aggregated = result.dataOrThrow;
          final map = <String, int>{};
          final ownEmojis = <String>{};
          for (final r in aggregated) {
            map[r.emoji] = r.count;
            if (r.users.contains(currentUser.id)) {
              ownEmojis.add(r.emoji);
            }
          }
          active.setReactions(messageId, map);
          active.setUserReactions(messageId, ownEmojis);
        })
        .catchError((Object e) {
          logger?.call(
            'warn',
            'Failed to refresh reactions for $messageId: $e',
          );
        });
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

  /// Adds a room to the controller AFTER a successful detail fetch.
  ///
  /// Used when the adapter learns about a new room via realtime events
  /// (`NewMessageEvent`, `RoomCreatedEvent`) and the room is not yet in the
  /// controller. We deliberately do NOT add a placeholder `RoomListItem(id:)`
  /// because doing so would cause the UI to briefly render a "ghost" room
  /// (raw roomId as title, no avatar) until the detail enrichment succeeds.
  ///
  /// If the detail fetch fails, the room is not added. The next `loadRooms`
  /// call will pick it up if the server still knows about it.
  void _addRoomFromDetail(String roomId, {ChatMessage? lastMessage}) =>
      _enricher.addFromDetail(roomId, lastMessage: lastMessage);

  void _enrichRoomFromDetail(String roomId) => _enricher.refreshRoom(roomId);

  void _refreshMessage(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .get(roomId, messageId)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          final updated = result.dataOrNull;
          if (updated != null) {
            active.updateMessage(updated);
            _cache?.updateMessage(roomId, updated);
          }
        })
        .catchError((Object e) {
          logger?.call('warn', 'Failed to refresh message $messageId: $e');
        });
  }

  /// "Delete kicked chat" — WhatsApp's option to manually remove a
  /// chat the user was kicked from. Drops it from the room list,
  /// clears the local cache for the room (messages, detail,
  /// unreads), and unmarks the kicked flag. No network call — the
  /// server already considers the user removed.
  ///
  /// Surfaced via [ChatRoomOption.deleteKickedChat] in the room
  /// options menu when `room.isParticipating == false`. Safe to
  /// call on participating rooms too (does the same cleanup), but
  /// the UI only exposes it after a kick.
  @internal
  Future<void> deleteKickedChat(String roomId) => rooms.deleteKicked(roomId);

  Future<void> _cancelSubscriptions() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
  }

  bool _isBlockedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == 'blocked';
    }
    return false;
  }

  /// A send rejected because an admin muted the user in this room. The
  /// backend returns `403 {"detail":"muted"}` (see `guard_not_muted/2`),
  /// the mute sibling of the `"blocked"` detail handled above.
  bool _isMutedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == 'muted';
    }
    return false;
  }
}

// Note: the `_PendingMarkAsRead` tracker now lives inside
// `services/mark_as_read_coordinator.dart` together with the
// coalescing logic that uses it.

/// Internal `ChangeNotifier` subclass that exposes `notifyListeners` via
/// the public method [emit]. The adapter needs to fire a coarse "user
/// cache changed" signal from outside the notifier itself; the base
/// `notifyListeners` is `@protected` so we wrap it.
class _BroadcastNotifier extends ChangeNotifier {
  void emit() => notifyListeners();
}
