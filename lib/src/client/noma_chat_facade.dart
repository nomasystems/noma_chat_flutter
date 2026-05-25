import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:hive_ce/hive_ce.dart' show HiveCipher;

import '../_internal/cache/cache_config.dart';
import '../_internal/cache/cache_manager.dart' show MetricCallback;
import '../cache/local_datasource.dart';
import '../_internal/http/retry_config.dart';
import '../cache/hive_chat_datasource.dart';
import '../config/chat_config.dart';
import '../storage/avatar_storage.dart';
import '../events/chat_event.dart';
import '../models/user.dart';
import '../ui/adapter/chat_ui_adapter.dart';
import '../ui/adapter/room_title_resolver.dart';
import '../ui/controller/chat_controller.dart';
import '../ui/controller/room_list_controller.dart';
import '../ui/l10n/chat_ui_localizations.dart';
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
  /// for offline-first access. Set to `false` for anonymous / ephemeral sessions.
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
  /// interceptors or certificate pinning).
  ///
  /// Throws [ArgumentError] if [baseUrl] or [realtimeUrl] are malformed, end
  /// with `/`, or use `http://` in a release build.
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
    int maxMessagesPerRoom = 500,
    int? maxRooms,
    Duration? messageTtl,
    HiveCipher? encryptionCipher,
    // UI
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    IsDmRoomPredicate? isDmRoom,
    RoomTitleResolver? roomTitleResolver,
    bool autoMarkAsRead = true,
    // Storage
    AvatarStorage? avatarStorage,
    // Advanced
    ChatConfig? config,
    ChatLocalDatasource? localDatasource,
    List<String>? certificatePins,
    // Observability
    void Function(String level, String message)? logger,
    MetricCallback? metricCallback,
  }) async {
    HiveChatDatasource? hiveCache;
    ChatLocalDatasource? effectiveDatasource = localDatasource;

    if (effectiveDatasource == null && enableCache) {
      hiveCache = await HiveChatDatasource.create(
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
          certificatePins: certificatePins,
        );

    final client = NomaChatClient(config: effectiveConfig);
    await client.restoreCacheTimestamps();

    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      cache: effectiveDatasource,
      isDmRoom: isDmRoom,
      roomTitleResolver: roomTitleResolver,
      autoMarkAsRead: autoMarkAsRead,
      avatarStorage: avatarStorage ?? DefaultAvatarStorage(client),
    );

    return NomaChat._(client: client, adapter: adapter, cache: hiveCache);
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
  /// [l10n] — UI string overrides. Defaults to English.
  ///
  /// [isDmRoom] — predicate used by the adapter to classify rooms as DMs.
  /// When `null`, the UI cannot distinguish DMs from group rooms.
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
    RoomTitleResolver? roomTitleResolver,
    bool autoMarkAsRead = true,
    AvatarStorage? avatarStorage,
  }) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      cache: cache,
      isDmRoom: isDmRoom,
      roomTitleResolver: roomTitleResolver,
      autoMarkAsRead: autoMarkAsRead,
      avatarStorage: avatarStorage ?? DefaultAvatarStorage(client),
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
