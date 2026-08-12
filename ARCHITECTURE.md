# Architecture

`noma_chat` is a unified Flutter package with three internal layers separated by clear responsibility boundaries.

## High-level diagram

```
App Flutter
  └── NomaChat (plug & play facade)
        ├── ChatClient (lib/src/client/, src/api/)
        │   ├── REST       (RestClient + Dio interceptors)
        │   ├── WebSocket  (WsTransport, primary)
        │   ├── SSE        (SseTransport, fallback)
        │   ├── TransportManager (coordinates WS/SSE + replay buffer)
        │   └── Sub-APIs   (auth, users, rooms, members, messages,
        │                   contacts, presence, attachments — threads,
        │                   pins, receipts and search live on `messages`)
        ├── HiveChatDatasource (lib/src/cache/)
        │   └── Persistent local cache (Hive CE, transparent to consumer)
        └── ChatUiAdapter (lib/src/ui/adapter/)
              ├── Syncs SDK events ↔ UI controllers
              ├── Loads initial data into controllers
              ├── Exposes common actions (send, edit, delete, react, type)
              └── Bootstraps presence + contact cache
```

Earlier in development the package was split into three (`noma_chat_sdk`, `noma_chat_cache_hive`, `noma_chat_ui_kit`); they were unified into a single `noma_chat` so consumers depend on one package and the layering is enforced by directory boundaries rather than separate releases.

## Internal structure

```
lib/
├── noma_chat.dart              # Primary barrel (SDK + cache + UI)
├── noma_chat_advanced.dart     # Opt-in low-level surface (interceptors,
│                               # MetricCallback, backoff, circuit breaker)
├── noma_chat_testing.dart      # MockChatClient, for consumer tests
└── src/
    ├── _internal/              # Non-exported helpers (http/, transport/,
    │                           # cache/, dto/, mappers/, util/)
    ├── api/                    # Sub-APIs (one class per domain)
    ├── cache/                  # HiveChatDatasource + serialization
    ├── client/                 # ChatClient interface, NomaChatClient impl,
    │                           # NomaChat facade
    ├── config/                 # ChatConfig, RealtimeMode, lifecycle policy
    ├── core/                   # ChatResult / ChatFailure + pagination types
    ├── events/                 # ChatEvent (sealed union); the wire parser
    │                           # lives in _internal/transport/
    ├── mock/                   # MockChatClient (for tests)
    ├── models/                 # Freezed domain models (message, room, user…)
    ├── observability/          # ChatLogger, ChatLogExporter
    ├── storage/                # AvatarStorage
    ├── utils/                  # Export, invite links, stable user id
    └── ui/                     # Complete UI components
        ├── adapter/            # ChatUiAdapter + its api/, handlers/,
        │                       # services/ collaborators
        ├── controller/         # ChatController, RoomListController,
        │                       # MessageSearchController, voice recording
        ├── widgets/            # ChatView, MessageList, MessageInput,
        │                       # bubbles/, ReactionBar, TypingIndicator,
        │                       # ImageViewer, voice recorder, etc.
        ├── models/             # UI-only models (RoomListItem, policies)
        ├── services/           # Attachment pickers, authenticated media
        │                       # loader, signed-url resolver, video
        │                       # thumbnailer, link preview fetcher
        ├── pages/              # MediaGalleryPage, StarredMessagesPage,
        │                       # CameraCapturePage (+ its recording gate)
        ├── theme/              # ChatTheme + bubble / input / roomList /
        │                       # markdown sub-themes (155+ fields)
        ├── l10n/               # ChatUiLocalizations — every bundled locale
        │                       # in a single file
        └── utils/              # Formatters, last_message_preview
```

## Facade — `NomaChat`

Minimal consumer setup:

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
);
await chat.connect();
```

`NomaChat.create(...)` performs:
1. Builds a `ChatConfig` with `baseUrl`, `realtimeUrl`, `tokenProvider`, `currentUser`, optionally `encryptionCipher`, `messageTtl`, `maxMessages*`, `logger`.
2. Creates and initializes `HiveChatDatasource` (Hive CE cache).
3. Creates `NomaChatClient` (ChatClient implementation) with the datasource injected.
4. Creates `ChatUiAdapter` with that client.
5. Exposes `chat.client` (SDK direct), `chat.adapter` (UI), `chat.connect()`, `chat.disconnect()`, `chat.dispose()`.

For advanced cases (custom client, mock for tests):

```dart
final chat = NomaChat.fromClient(
  client: myCustomClient,
  currentUser: ChatUser(id: userId, displayName: name),
);
```

## Real-time transports

```
TransportManager               (picks the transport for ChatConfig.realtimeMode)
  └── AutoFailoverTransport    (RealtimeMode.auto — the default)
        ├── WsTransport (primary)
        │   └── /ws bidi   (backend port 8077)
        └── SseTransport (fallback when WS keeps failing)
            └── /events    (backend port 2081/2082 via NRTE)
```

The other `RealtimeMode` values bypass the failover wrapper and run a single
transport: `webSocketOnly`, `serverSentEventsOnly`, `polling` (`PollingTransport`,
interval clamped to a 5 s floor) and `manual` (`ManualTransport`).

**Behavior:**
- Connects WS first. SSE is promoted when the WS drops after a first successful connection, or after 3 consecutive failed initial WS attempts (a proxy blocking WebSocket from the first handshake).
- `_primaryHasConnected` in `AutoFailoverTransport` prevents premature SSE activation.
- Circular replay buffer (`eventBufferSize` in `ChatConfig`, default 20) for late subscribers.
- Opt-in reconnection catch-up (`enableReconnectCatchUp`): after reconnect, requests unread rooms and emits `UnreadUpdatedEvent` for each. `lastDisconnectedAt` exposed.
- WS close 4002 (auth_failed), 4003 (token_expired) and 4004 (token_revoked) — invalidate interceptor token cache + emit signal so the consumer can refresh. Three consecutive such closes with no successful auth in between stop the reconnect loop with a terminal auth error.
- Opt-in frame `auth_refresh` (30s cooldown server-side) to rotate token without reconnecting.

## Cache (Hive CE)

`HiveChatDatasource` implements the `ChatLocalDatasource` interface.

**Why Hive CE**: pure Dart, no native dependencies (clean to publish), box-per-room for messages (O(1) clear/get per room), lazy box opening, opt-in encryption at rest.

**Strategies:**
- Keys are timestamp-sortable (`{iso_timestamp}_{msg_id}`) so alphabetical ordering equals chronological → `getMessages` is O(limit).
- FIFO eviction when exceeding `maxMessagesPerRoom`, `maxRooms`, `maxUsers`.
- Optional message TTL.
- Versioned schema with automatic wipe on migration (it's a cache, refetched).
- Step-by-step migrations with wipe fallback.
- Resilient deserialization: corrupt records are dropped, not crashed on.
- `_safeWrite` wrapper logs Hive errors through the configured `logger`.

**Cache policies** (`CachePolicy`): `cacheFirst`, `networkFirst`, `cacheOnly`, `networkOnly`.

**Cache keys and TTLs** (`CacheConfig`): `rooms:$type` / `roomDetail:$roomId` (`ttlRooms`, 12 h), `user:$userId` (`ttlUsers`, 6 h), `messages:$roomId:…` (`ttlMessages`, 24 h), `members:$roomId` (`ttlMembers`, 12 h), plus `contacts`, `reactions:$roomId:$messageId`, `pins:$roomId`, `receipts:$roomId`.

**Member rosters**: `members:$roomId` holds only the unpaginated, unexpanded `members.list` response (items + `hasMore` + `totalCount`), in the `chat_room_members` box. Any paginated or expanded call bypasses the cache in both directions — one record per room cannot stand in for another page, and a bare roster served to an expanded caller would blank the names and avatars on screen. Invalidated by every local membership mutation and, through `ChatUiAdapter.notifyRoomMembersChanged`, by every `user_joined` / `user_left` / `user_role_changed` event.

**Cache-then-network** (stale-while-revalidate):
- `loadMessages` runs a `cacheOnly` phase (instant) + `networkOnly` phase with delta sync (`after=newestCachedTimestamp`).
- `loadRooms` same pattern with `cacheOnly` enrichment in the cache phase. The cache phase is also reachable on its own via `rooms.hydrate()`, and `connect()` runs it before the handshake when the host has not.

## UI Adapter (`ChatUiAdapter`)

Bridges SDK events to UI controllers.

**Event sync:**
- Subscribes to `client.events`. On `NewMessageEvent`, `MessageUpdatedEvent`, `RoomDeletedEvent`, etc., updates the relevant `ChatController` (per room) or `RoomListController`.
- `MessageUpdatedEvent`, `RoomCreatedEvent`, `RoomUpdatedEvent` carry only IDs (the server keeps real-time frames lean); the adapter fetches the full payload via API.

**Initial load:**
- `loadRooms({type, forceNetwork})` — populates the adapter's own `RoomListController` with `rooms.getUserRooms()` enriched + presence bootstrap.
- `loadMessages(roomId, {limit})` — cache-then-network.
- `RoomEnricher` awaits a presence bootstrap (`presence.getAll()`) before returning, so `RoomListItem.isOnline` is populated from the first render.

**Actions exposed:**
- `sendMessage`, `sendVoiceMessage`, `sendAttachment` (optimistic + upload
  progress + send). `sendAttachment`'s upload is cancellable —
  `cancelAttachmentUpload(messageId)` aborts the transfer via an
  `UploadCancelToken` and removes the provisional bubble; a genuine
  transfer failure is mapped separately (`CancelledFailure` vs.
  `NetworkFailure`) so a deliberate cancel never triggers the
  failed-message/retry or offline-queue paths. A `video/*` payload also
  gets a poster frame: `VideoThumbnailer` extracts one on-device, it is
  uploaded as a second small blob with its own attachment id, and that id
  travels on the message metadata so the bubble can render a real still.
  Strictly best-effort and outside the progress ring / cancel token — it
  runs only once the clip's own upload has succeeded, and any failure sends
  the video preview-less rather than not at all.
- `editMessage`, `deleteMessage`, `sendReaction`, `deleteReaction`, `pinMessage`, etc.
- `markAsRead` on `dispose` (leaving the chat), when `autoMarkAsRead` is on (default).

**`isDmRoom` predicate**:

```dart
final chat = await NomaChat.create(
  ...,
  isDmRoom: (detail) =>
      detail.type == RoomType.oneToOne &&
      detail.custom?['type'] == 'dm',
);
```

Distinguishes real DMs from conceptual groups with 2 participants (e.g. a plan with 2 members). Default predicate: `detail.type == RoomType.oneToOne` **and** no user-assigned room name — a named 2-person room is treated as a group, not a DM.

## Offline queue

`OfflineQueue` persists outbound operations that failed (no connection) and retries them on reconnect. Persists in Hive (`chat_offline_queue`).

- One `PendingOperation` subclass per queued action: send message / attachment / direct message, edit, delete, add & delete reaction, pin & unpin, star & unstar, create room, update room config, add & remove member.
- An `AuthFailure` (401) is never retried immediately: the drain executor reports failure, so the operation goes back to the queue under the standard exponential backoff + jitter instead of hammering a rejected token.
- Deduplication by operation `id` on `restore()`, so a repeated restore (the background → foreground reconnect cycle) never double-queues a pending send.
- Re-persists the queue after every successful operation, so a crash mid-drain never replays work already done.
- Operations are dropped — with the reason handed to `onOperationDropped` — on `queue_full`, `ttl_expired` or `max_retries`.
- Configurable `logger` for deserialization and persistence errors.

## Observability

- Optional `logger` callback in `ChatConfig`, propagated by `ApiFactory` to `BearerAuthInterceptor` and to the sub-APIs that log (users, rooms, messages).
- Structured logging pipeline alongside it — `ChatLogger` with `ChatLogTag` / `ChatLogLevel` and pluggable sinks (`lib/src/observability/`), plus `ChatLogExporter` for a one-tap file dump.
- 11 `catch (_)` cache-best-effort sites replaced with `catch (e) { _logger?.call('warn', '...: $e'); }`.
- `_openBoxSafe()` recovery logs + metrics `box_delete_failed` / `box_reopen_failed`.
- `MetricCallback` (typedef `void Function(String metric, Map<String, dynamic> data)`) exported from `package:noma_chat/noma_chat_advanced.dart`. Metrics are emitted from the cache, the offline queue, the HTTP layer, the auth interceptor and the WebSocket transport — [TELEMETRY.md](./TELEMETRY.md) is the authoritative list of every metric name, its fields and when it fires.

## Backend integration

See [INTEGRATION.md](./INTEGRATION.md) for the full contract with the Noma chat backend.
