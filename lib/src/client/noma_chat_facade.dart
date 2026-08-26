import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:hive_ce/hive_ce.dart' show HiveCipher;

import '../_internal/cache/cache_config.dart';
import '../_internal/cache/cache_manager.dart' show MetricCallback;
import '../cache/local_datasource.dart';
import '../models/chat_analytics_event.dart';
import '../_internal/http/retry_config.dart';
import '../cache/hive_chat_datasource.dart';
import '../config/chat_config.dart';
import '../config/lifecycle_policy.dart';
import '../observability/chat_logger.dart' show ChatLogLevel;
import '../storage/avatar_storage.dart';
import '../events/chat_event.dart';
import '../models/user.dart';
import '../ui/adapter/chat_ui_adapter.dart';
import '../ui/adapter/room_title_resolver.dart';
import '../ui/controller/chat_controller.dart';
import '../ui/controller/room_list_controller.dart';
import '../ui/l10n/chat_ui_localizations.dart';
import '../ui/services/video_thumbnailer.dart';
import '../core/result.dart';
import '../models/room.dart';
import 'chat_client.dart';
import 'noma_chat_client.dart';

/// Plug & play entry point for Noma Chat.
///
/// Wires the SDK client, persistent cache, and UI adapter in a single call:
///
/// ```dart
/// final chat = await NomaChat.create(
///   baseUrl: 'https://chat.myapp.com/v1',
///   realtimeUrl: 'https://chat.myapp.com',
///   tokenProvider: () => authService.getToken(),
///   currentUser: ChatUser(id: userId, displayName: name),
/// );
/// await chat.connect();
/// ```
class NomaChat {
  NomaChat._({
    required this.client,
    required this.adapter,
    HiveChatDatasource? cache,
  }) : _cache = cache;

  final ChatClient client;
  final ChatUiAdapter adapter;
  final HiveChatDatasource? _cache;

  RoomListController get roomListController => adapter.roomListController;
  ValueNotifier<ChatConnectionState> get connectionState =>
      adapter.connectionStateNotifier;

  /// Creates a fully configured [NomaChat] instance with sensible defaults.
  ///
  /// Initialises the persistent Hive cache (unless [enableCache] is `false`
  /// or a custom [localDatasource] is supplied), builds the [ChatConfig] with
  /// bearer-token auth, wires the [NomaChatClient], and constructs the
  /// [ChatUiAdapter]. The returned instance is ready to connect — call
  /// [connect] immediately after creation.
  ///
  /// [baseUrl] — full REST base URL including API version prefix, e.g.
  /// `https://chat.myapp.com/v1`. Must use `https://` in release builds.
  ///
  /// [realtimeUrl] — HTTP base used for the WebSocket (`ws://` / `wss://`)
  /// and SSE (`/events`) endpoints. The SDK converts the scheme automatically.
  /// Example: `https://chat.myapp.com`.
  ///
  /// [tokenProvider] — called on demand to supply a fresh bearer token.
  /// Must not throw; return an empty string to signal an unauthenticated state.
  ///
  /// [currentUser] — the authenticated user who owns this session. Passed to
  /// the UI adapter for title resolution and optimistic message rendering.
  ///
  /// [enableCache] — when `true` (default) creates and opens a Hive store
  /// for offline-first access, namespaced to `currentUser.id` so accounts
  /// sharing a device never read each other's data. Set to `false` for
  /// anonymous / ephemeral sessions.
  ///
  /// [adoptUnscopedCacheFor] — assert that the pre-0.16 device-wide cache
  /// still on this device belongs to this user id, so its local history is
  /// carried into the per-user store instead of being reclaimed. Pass
  /// `currentUser.id` only if your app can never have had a second account
  /// signed in on the same install; if it could, omit this and the old
  /// history is dropped. Getting it wrong shows one user the other's chat
  /// history. See [HiveChatDatasource.create] for the full contract.
  ///
  /// [unscopedCacheRetention] — how long that device-wide cache is kept on
  /// disk once an adoption has been refused for want of an owner. 30 days
  /// by default, which is the window in which a host that ships the
  /// scoping first can still add [adoptUnscopedCacheFor] and carry the
  /// history over. Shorten it to reclaim the space sooner, at the cost of
  /// closing that window; [HiveChatDatasource.purgeUnscopedCache] reclaims
  /// it outright.
  ///
  /// [orphanGracePeriod] — how long a room must stay missing from
  /// authoritative room listings before the cache destroys its local
  /// message history. 7 days by default. Lengthen it if your backend can
  /// omit rooms it still serves; the cost of shortening it is history
  /// destroyed for a room that was only temporarily unlisted.
  ///
  /// [maxMessagesPerRoom] — maximum messages stored per room in the local cache.
  /// Defaults to 500. Older messages are evicted when the limit is reached.
  ///
  /// [logger] — optional `(level, message)` sink for SDK log output. Use
  /// [ChatConfig.developerLogger] or [ChatConfig.debugOnlyLogger] for
  /// zero-configuration logging during development.
  ///
  /// [config] — supply a pre-built [ChatConfig] to bypass all convenience
  /// parameters (escape hatch for advanced setups such as custom auth
  /// interceptors).
  ///
  /// Throws [ArgumentError] if [baseUrl] or [realtimeUrl] are malformed, end
  /// with `/`, or use `http://` in a release build.
  ///
  /// Throws [ArgumentError] when the bundled cache is enabled and
  /// `currentUser.id` is blank or nothing but whitespace. Before 0.16 the
  /// id never reached the cache and such a session opened normally; it
  /// now names the store, and a store named after nothing is the
  /// device-wide one every account shares. Hosts that build a session
  /// before the id is known should pass `enableCache: false` for it.
  ///
  /// Example:
  /// ```dart
  /// final chat = await NomaChat.create(
  ///   baseUrl: 'https://chat.myapp.com/v1',
  ///   realtimeUrl: 'https://chat.myapp.com',
  ///   tokenProvider: () => authService.getBearerToken(),
  ///   currentUser: ChatUser(id: userId, displayName: userName),
  ///   logger: ChatConfig.debugOnlyLogger,
  /// );
  /// await chat.connect();
  /// // Mount chat.adapter into your widget tree via ChatUiAdapter.provide(…)
  /// ```
  static Future<NomaChat> create({
    required String baseUrl,
    required String realtimeUrl,
    required Future<String> Function() tokenProvider,
    required ChatUser currentUser,
    // Connection
    String? sseUrl,
    Duration requestTimeout = const Duration(seconds: 30),
    RetryConfig retryConfig = const RetryConfig(),
    void Function()? onAuthFailure,
    // Cache
    bool enableCache = true,
    String? adoptUnscopedCacheFor,
    Duration unscopedCacheRetention = const Duration(days: 30),
    Duration orphanGracePeriod = const Duration(days: 7),
    int maxMessagesPerRoom = 500,
    int? maxRooms,
    Duration? messageTtl,
    HiveCipher? encryptionCipher,
    // UI
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    IsDmRoomPredicate? isDmRoom,
    MembershipBannerFilter? membershipBannerFilter,
    RoomTitleResolver? roomTitleResolver,
    bool autoMarkAsRead = true,
    // Lifecycle
    bool manageAppLifecycle = true,
    ChatLifecyclePolicy lifecyclePolicy = const ChatLifecyclePolicy.standard(),
    bool enableReconnectResync = true,
    // Storage
    AvatarStorage? avatarStorage,
    // Media
    VideoThumbnailer? videoThumbnailer,
    // Advanced
    ChatConfig? config,
    ChatLocalDatasource? localDatasource,
    // Observability
    void Function(String level, String message)? logger,
    MetricCallback? metricCallback,
    ChatAnalyticsSink? analyticsSink,
  }) async {
    HiveChatDatasource? hiveCache;
    ChatLocalDatasource? effectiveDatasource = localDatasource;

    // A supplied `config` bypasses every convenience parameter (it is the
    // documented escape hatch). Creating the convenience HiveChatDatasource
    // here would open a second set of Hive boxes that the provided config
    // never wires to the client, yet NomaChat.dispose() would close them —
    // clashing with (and tearing down) the caller's own datasource on the
    // same box names. Skip it entirely when `config` is provided.
    if (config == null && effectiveDatasource == null && enableCache) {
      hiveCache = await HiveChatDatasource.create(
        // Scope every box to the signed-in user: two accounts on the same
        // device must not share a store, and a logout that keeps the
        // cache must not show the next user the previous one's rooms.
        userId: currentUser.id,
        adoptUnscopedCacheFor: adoptUnscopedCacheFor,
        unscopedCacheRetention: unscopedCacheRetention,
        orphanGracePeriod: orphanGracePeriod,
        maxMessagesPerRoom: maxMessagesPerRoom,
        maxRooms: maxRooms,
        messageTtl: messageTtl,
        encryptionCipher: encryptionCipher,
      );
      effectiveDatasource = hiveCache;
    }

    final effectiveConfig =
        config ??
        ChatConfig(
          baseUrl: baseUrl,
          realtimeUrl: realtimeUrl,
          tokenProvider: tokenProvider,
          onAuthFailure: onAuthFailure,
          sseUrl: sseUrl,
          requestTimeout: requestTimeout,
          retryConfig: retryConfig,
          localDatasource: effectiveDatasource,
          cacheConfig: enableCache
              ? CacheConfig(
                  maxMessagesPerRoom: maxMessagesPerRoom,
                  maxRooms: maxRooms ?? 100,
                )
              : null,
          logger: logger,
          metricCallback: metricCallback,
          analyticsSink: analyticsSink,
        );

    final client = NomaChatClient(config: effectiveConfig);
    await client.restoreCacheTimestamps();

    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      // Share the client's datasource. With a supplied config that is the
      // caller's config.localDatasource, not the convenience one (which is
      // not created in that path), so adapter and client never diverge.
      cache: config != null ? config.localDatasource : effectiveDatasource,
      isDmRoom: isDmRoom,
      membershipBannerFilter: membershipBannerFilter,
      roomTitleResolver: roomTitleResolver,
      autoMarkAsRead: autoMarkAsRead,
      manageAppLifecycle: manageAppLifecycle,
      lifecyclePolicy: lifecyclePolicy,
      enableReconnectResync: enableReconnectResync,
      logLevel: effectiveConfig.logLevel,
      logMessageContent: effectiveConfig.logMessageContent,
      metricCallback: effectiveConfig.metricCallback,
      analyticsSink: effectiveConfig.analyticsSink,
      avatarStorage: avatarStorage ?? DefaultAvatarStorage(client),
      videoThumbnailer: videoThumbnailer,
    );

    return NomaChat._(client: client, adapter: adapter, cache: hiveCache);
  }

  /// Creates a [NomaChat] instance from a pre-built [ChatConfig].
  ///
  /// This is the escape hatch for callers who already have a fully
  /// assembled [ChatConfig] (custom auth interceptors, DI-provided
  /// transport tuning, a pre-opened [ChatLocalDatasource], …) and do
  /// not want to restate the connection parameters. Unlike [create] —
  /// which requires `baseUrl` / `realtimeUrl` / `tokenProvider` even
  /// when a `config` is supplied (they are then silently ignored) —
  /// [fromConfig] takes the [config] as the single source of truth for
  /// transport and cache wiring.
  ///
  /// [config] — the pre-built configuration. Its `baseUrl`,
  /// `realtimeUrl`, `tokenProvider`, `localDatasource`, `logger`, etc.
  /// are used verbatim. No convenience Hive cache is opened here: if you
  /// want persistence, set `config.localDatasource` (e.g. via
  /// [HiveChatDatasource.create]) before calling this. The adapter
  /// shares `config.localDatasource` so client and adapter never
  /// diverge. Pass the signed-in user's id to that constructor:
  /// `HiveChatDatasource.create()` without one opens the device-wide
  /// layout that every account on the device shares, which is what the
  /// per-user scoping exists to avoid.
  ///
  /// [currentUser] — the authenticated user who owns this session.
  ///
  /// The remaining UI parameters mirror [create].
  ///
  /// Example:
  /// ```dart
  /// final config = ChatConfig(
  ///   baseUrl: 'https://chat.myapp.com/v1',
  ///   realtimeUrl: 'https://chat.myapp.com',
  ///   tokenProvider: () => authService.getToken(),
  ///   localDatasource: await HiveChatDatasource.create(userId: userId),
  /// );
  /// final chat = await NomaChat.fromConfig(
  ///   config: config,
  ///   currentUser: ChatUser(id: userId, displayName: userName),
  /// );
  /// await chat.connect();
  /// ```
  static Future<NomaChat> fromConfig({
    required ChatConfig config,
    required ChatUser currentUser,
    // UI
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    IsDmRoomPredicate? isDmRoom,
    MembershipBannerFilter? membershipBannerFilter,
    RoomTitleResolver? roomTitleResolver,
    bool autoMarkAsRead = true,
    // Lifecycle
    bool manageAppLifecycle = true,
    ChatLifecyclePolicy lifecyclePolicy = const ChatLifecyclePolicy.standard(),
    bool enableReconnectResync = true,
    // Storage
    AvatarStorage? avatarStorage,
    // Media
    VideoThumbnailer? videoThumbnailer,
  }) async {
    final client = NomaChatClient(config: config);
    await client.restoreCacheTimestamps();

    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      // Share the config's datasource so adapter and client never
      // diverge. No convenience Hive box is opened here, so
      // NomaChat.dispose() has nothing extra to close (`cache` stays
      // null) — the caller owns the lifecycle of `config.localDatasource`.
      cache: config.localDatasource,
      isDmRoom: isDmRoom,
      membershipBannerFilter: membershipBannerFilter,
      roomTitleResolver: roomTitleResolver,
      autoMarkAsRead: autoMarkAsRead,
      manageAppLifecycle: manageAppLifecycle,
      lifecyclePolicy: lifecyclePolicy,
      enableReconnectResync: enableReconnectResync,
      logLevel: config.logLevel,
      logMessageContent: config.logMessageContent,
      metricCallback: config.metricCallback,
      analyticsSink: config.analyticsSink,
      avatarStorage: avatarStorage ?? DefaultAvatarStorage(client),
      videoThumbnailer: videoThumbnailer,
    );

    return NomaChat._(client: client, adapter: adapter);
  }

  /// Creates a [NomaChat] instance from a pre-configured [ChatClient].
  ///
  /// Use this when you need full control over client construction — for
  /// example when supplying a custom [AuthInterceptor], a DI-provided client,
  /// or a `MockChatClient` in tests. The UI adapter is wired around the given
  /// [client]; the persistent Hive cache is not opened automatically (pass
  /// [cache] explicitly if you have one).
  ///
  /// [client] — a fully constructed [ChatClient] (typically a
  /// [NomaChatClient] or a test double).
  ///
  /// [currentUser] — the authenticated user who owns this session.
  ///
  /// [l10n] — the bundle the adapter composes its off-screen strings with.
  /// Defaults to English, and leaving it at that default is the usual
  /// choice: the SDK's own views then hand the adapter whatever
  /// `ChatUiLocalizations.delegate` resolves for the app locale. Passing
  /// anything else takes the adapter's language into your own hands — the
  /// views stop pushing, and `ChatUiAdapter.l10n` is yours to set.
  ///
  /// [isDmRoom] — predicate used by the adapter to classify rooms as DMs.
  /// When `null`, the UI cannot distinguish DMs from group rooms.
  ///
  /// [membershipBannerFilter] — veto over the SDK's own "Alice joined" /
  /// "Alice left" / role-change banners, per room and per event. Return
  /// `false` to drop one: hosts that already render their own membership
  /// notice for a room use it so the two do not show up side by side.
  /// When `null` (default) every banner is kept.
  ///
  /// [autoMarkAsRead] — when `true` (default) the adapter automatically
  /// marks rooms as read when the user opens them.
  ///
  /// Example:
  /// ```dart
  /// final client = NomaChatClient(
  ///   config: ChatConfig.withAuthInterceptor(
  ///     baseUrl: 'https://chat.myapp.com/v1',
  ///     realtimeUrl: 'https://chat.myapp.com',
  ///     authInterceptor: MyCustomAuthInterceptor(),
  ///   ),
  /// );
  /// final chat = NomaChat.fromClient(
  ///   client: client,
  ///   currentUser: ChatUser(id: userId, displayName: userName),
  /// );
  /// await chat.connect();
  /// ```
  factory NomaChat.fromClient({
    required ChatClient client,
    required ChatUser currentUser,
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    ChatLocalDatasource? cache,
    IsDmRoomPredicate? isDmRoom,
    MembershipBannerFilter? membershipBannerFilter,
    RoomTitleResolver? roomTitleResolver,
    bool autoMarkAsRead = true,
    bool manageAppLifecycle = true,
    ChatLifecyclePolicy lifecyclePolicy = const ChatLifecyclePolicy.standard(),
    bool enableReconnectResync = true,
    ChatLogLevel logLevel = ChatLogLevel.warn,
    bool logMessageContent = false,
    MetricCallback? metricCallback,
    ChatAnalyticsSink? analyticsSink,
    AvatarStorage? avatarStorage,
    VideoThumbnailer? videoThumbnailer,
  }) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      cache: cache,
      isDmRoom: isDmRoom,
      membershipBannerFilter: membershipBannerFilter,
      roomTitleResolver: roomTitleResolver,
      autoMarkAsRead: autoMarkAsRead,
      manageAppLifecycle: manageAppLifecycle,
      lifecyclePolicy: lifecyclePolicy,
      enableReconnectResync: enableReconnectResync,
      logLevel: logLevel,
      logMessageContent: logMessageContent,
      metricCallback: metricCallback,
      analyticsSink: analyticsSink,
      avatarStorage: avatarStorage ?? DefaultAvatarStorage(client),
      videoThumbnailer: videoThumbnailer,
    );
    return NomaChat._(client: client, adapter: adapter);
  }

  /// Connects the real-time transport and starts the UI adapter.
  ///
  /// Restores the offline queue from persistent storage, opens the WebSocket
  /// (or SSE / polling, depending on [ChatConfig.realtimeMode]), and begins
  /// delivering events to the [adapter]. If the connection drops it reconnects
  /// automatically with exponential back-off.
  ///
  /// Must be called after [create] or [fromClient] before sending or
  /// receiving messages. Subsequent calls while already connected are no-ops.
  ///
  /// Throws if the underlying transport throws during the initial handshake
  /// (e.g. malformed URL). Network failures after the first connect are
  /// retried silently.
  ///
  /// Example:
  /// ```dart
  /// final chat = await NomaChat.create(/* ... */);
  /// await chat.connect(); // start receiving real-time events
  /// ```
  Future<void> connect() => adapter.connect();

  /// Disconnects the real-time transport and pauses the UI adapter.
  ///
  /// Cancels the transport event subscription and closes the underlying
  /// WebSocket / SSE stream. Outstanding HTTP requests are not cancelled —
  /// use [dispose] for a full teardown. The local cache and offline queue
  /// are preserved so a subsequent [connect] resumes from a consistent state.
  ///
  /// Safe to call multiple times and when already disconnected.
  ///
  /// Example:
  /// ```dart
  /// // Pause real-time updates when the app goes to background
  /// await chat.disconnect();
  /// ```
  Future<void> disconnect() => adapter.disconnect();

  /// Opens an existing room or creates a new one with the given other users.
  ///
  /// Idempotently adds each `otherId` as a contact (existing contacts are
  /// ignored), then creates a room with `audience: RoomAudience.contacts`
  /// and `members: otherIds`. After the room is created the in-memory
  /// adapter is asked to reload its rooms so the new entry surfaces in
  /// [RoomListController] immediately.
  ///
  /// Use it for both 1-to-1 DMs (`otherIds` of length 1, `name` null) and
  /// group chats (length ≥ 2 plus a `name`). The backend distinguishes by
  /// member count.
  ///
  /// Returns a [ChatResult] holding the created [ChatRoom] on success, or the
  /// first failure encountered (the contacts.add step short-circuits on a
  /// non-Conflict failure).
  Future<ChatResult<ChatRoom>> openOrCreateRoom({
    required List<String> otherIds,
    String? name,
  }) async {
    if (otherIds.isEmpty) {
      return const ChatFailureResult(
        ValidationFailure(message: 'otherIds cannot be empty'),
      );
    }
    for (final id in otherIds) {
      final addResult = await client.contacts.add(id);
      if (addResult.isFailure && addResult.failureOrNull is! ConflictFailure) {
        return addResult.castFailure<ChatRoom>();
      }
    }
    final created = await client.rooms.create(
      audience: RoomAudience.contacts,
      members: otherIds,
      name: name,
    );
    if (created.isSuccess) {
      await adapter.rooms.load();
    }
    return created;
  }

  Future<void> notifyTokenRotated() => client.notifyTokenRotated();

  /// Force a full refresh of the room list and (in `polling`/`manual`
  /// modes) pull new messages for every changed/open room.
  ///
  /// Streaming modes (`auto`, `webSocketOnly`, `serverSentEventsOnly`)
  /// already deliver updates as they happen, so calling `refresh()`
  /// there is safe but redundant. In `manual` mode this is the only
  /// way to receive any update at all — typically wired to a
  /// `RefreshIndicator` on the room list.
  Future<void> refresh() => client.refresh();

  /// Like [refresh] but scoped to a single room. Wire to per-chat
  /// pull-to-refresh on the [MessageList].
  Future<void> refreshRoom(String roomId) => client.refreshRoom(roomId);

  /// Returns the existing DM room id with [otherUserId] if a conversation
  /// is already started, or `null` to indicate that the caller should open
  /// a draft via [openDirectMessageDraft].
  ///
  /// WhatsApp-style usage:
  /// ```dart
  /// final existing = chat.findExistingDmRoom(contact.id);
  /// final controller = existing != null
  ///     ? chat.adapter.getChatController(existing)
  ///     : await chat.openDirectMessageDraft(contact.id);
  /// navigateToChatRoom(controller);
  /// ```
  String? findExistingDmRoom(String otherUserId) =>
      adapter.dm.findExisting(otherUserId);

  /// Opens a draft DM with [otherUserId] without creating the room
  /// server-side. The returned [ChatController] is in `isDraft` state and
  /// has its `otherUsers` pre-populated (so AppBars can resolve the title
  /// immediately via `RoomTitleResolver`). The room is created on the
  /// server on the first successful send — see `sendMessage` materialization
  /// in `_OptimisticHandler`. If the user navigates away without sending,
  /// nothing is persisted.
  ///
  /// Use [extraRoomCustom] to attach app-specific markers (e.g.
  /// `{'type': 'dm'}`) consumed by an [IsDmRoomPredicate] later.
  ///
  /// To later send a message on the draft, use the routing key from
  /// `adapter.dm.draftRoutingKey(otherUserId)` as the `roomId` parameter on
  /// `adapter.sendMessage`.
  Future<ChatController> openDirectMessageDraft(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => adapter.dm.openDraft(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Eagerly materializes the DM room for [otherUserId] without sending a
  /// message — useful for flows that need a real `roomId` before any send
  /// (uploads with row-level progress, typing indicators, voice recordings,
  /// etc.). See `ChatUiAdapter.ensureDmRoomMaterialized` for details.
  Future<ChatResult<String>> ensureDmRoomMaterialized(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => adapter.dm.ensureMaterialized(
    otherUserId,
    extraRoomCustom: extraRoomCustom,
  );

  /// One-shot bootstrap of the blocked-users set from the server. See
  /// `ChatUiAdapter.loadBlockedUsers` for the privacy model — the local
  /// user only learns about users THEY blocked; never about users who
  /// blocked them (WhatsApp-style).
  Future<ChatResult<void>> loadBlockedUsers() => adapter.contacts.loadBlocked();

  /// Releases all resources held by this instance.
  ///
  /// Cancels pending HTTP requests, closes the real-time transport, disposes
  /// the [adapter] (including all controllers and stream subscriptions), and
  /// closes the Hive cache boxes opened by [create]. After calling [dispose]
  /// this object must not be used again.
  ///
  /// Typically called in the `dispose` method of the root widget or
  /// when the user logs out.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   chat.dispose();
  ///   super.dispose();
  /// }
  /// ```
  Future<void> dispose() async {
    await adapter.dispose();
    await _cache?.dispose();
  }
}
