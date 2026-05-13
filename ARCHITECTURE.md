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
        │   └── Sub-APIs   (messages, rooms, users, contacts, presence,
        │                   search, threads, pins, attachments, members,
        │                   blocked, scheduledMessages, admin, internal)
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
├── noma_chat.dart              # Single barrel export (SDK + cache + UI)
└── src/
    ├── _internal/              # Non-exported helpers
    ├── api/                    # Sub-APIs (one class per domain)
    ├── cache/                  # HiveChatDatasource + serialization
    ├── client/                 # ChatClient interface + NomaChatClient impl
    ├── config/                 # ChatConfig, ChatUser, callbacks
    ├── core/                   # Result type, Pagination, errors, helpers
    ├── events/                 # ChatEvent (sealed union) + EventParser
    ├── mock/                   # MockChatClient + MockDataStore (for tests)
    ├── models/                 # 30+ Freezed models
    └── ui/                     # Complete UI Kit
        ├── adapter/            # ChatUiAdapter
        ├── controllers/        # ChatController, RoomListController
        ├── widgets/            # ChatView, MessageList, MessageInput,
        │                       # bubbles/, ReactionBar, TypingIndicator,
        │                       # ImageViewer, voice recorder, etc.
        ├── pages/              # MediaGalleryPage
        ├── theme/              # ChatTheme (~50 properties)
        ├── l10n/               # 7 locales (en, es, fr, de, it, pt, ca)
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
TransportManager
  ├── WsTransport (primary)
  │   └── /ws bidi   (backend port 8077)
  └── SseTransport (fallback when WS keeps failing)
      └── /events    (backend port 2081/2082 via NRTE)
```

**Behavior:**
- Connects WS first. After N attempts with exponential backoff + jitter, opens SSE as fallback.
- `_wsHasConnected` flag prevents premature SSE activation.
- Optional circular replay buffer (`eventBufferSize` in `ChatConfig`, default 0) for late subscribers.
- Opt-in reconnection catch-up (`enableReconnectCatchUp`): after reconnect, requests unread rooms and emits `UnreadUpdatedEvent` for each. `lastDisconnectedAt` exposed.
- WS close 4003 (token_expired) and 4004 (token_revoked) — invalidate interceptor token cache + emit signal so the consumer can refresh.
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

**Cache-then-network** (stale-while-revalidate):
- `loadMessages` runs a `cacheOnly` phase (instant) + `networkOnly` phase with delta sync (`after=newestCachedTimestamp`).
- `loadRooms` same pattern with `cacheOnly` enrichment in the cache phase.

## UI Adapter (`ChatUiAdapter`)

Bridges SDK events to UI controllers.

**Event sync:**
- Subscribes to `client.events`. On `NewMessageEvent`, `MessageUpdatedEvent`, `RoomDeletedEvent`, etc., updates the relevant `ChatController` (per room) or `RoomListController`.
- `MessageUpdatedEvent`, `RoomCreatedEvent`, `RoomUpdatedEvent` carry only IDs (the server keeps real-time frames lean); the adapter fetches the full payload via API.

**Initial load:**
- `loadRooms(controller)` — populates `RoomListController` with `rooms.getUserRooms()` enriched + presence bootstrap.
- `loadMessages(roomId, controller)` — cache-then-network.
- `_enrichAndSetRooms` runs `presence.getAll()` to populate `RoomListItem.isOnline` from the first render.

**Actions exposed:**
- `sendMessage`, `sendVoiceMessage` (optimistic + upload progress + send).
- `editMessage`, `deleteMessage`, `addReaction`, `deleteReaction`, `pinMessage`, etc.
- `markAsRead` on `dispose` (leaving the chat).

**`isDmRoom` predicate**:

```dart
final chat = await NomaChat.create(
  ...,
  isDmRoom: (detail) =>
      detail.type == RoomType.oneToOne &&
      detail.custom?['type'] == 'dm',
);
```

Distinguishes real DMs from conceptual groups with 2 participants (e.g. a plan with 2 members). Default predicate: `detail.type == RoomType.oneToOne`.

## Offline queue

`OfflineQueue` persists outbound operations that failed (no connection) and retries them on reconnect. Persists in Hive (`chat_offline_queue`).

- **9 operation types**: send, edit, delete, addReaction, deleteReaction, createRoom, updateRoomConfig, addMember, removeMember.
- 401 errors do NOT trigger immediate retry (wait for auth resolution).
- Deduplication on enqueue.
- Persists each successful operation atomically.
- Configurable `logger` for deserialization errors.

## Observability

- Optional `logger` in `ChatConfig`, propagated to `BearerAuthInterceptor` and the 4 main APIs (users, rooms, messages, contacts).
- 11 `catch (_)` cache-best-effort sites replaced with `catch (e) { _logger?.call('warn', '...: $e'); }`.
- `_openBoxSafe()` recovery logs + metrics `box_delete_failed` / `box_reopen_failed`.
- Exported `MetricCallback`: `cache_hit`, `cache_miss`, `cache_eviction`, `cache_ttl_expired`.

## Backend integration

See [INTEGRATION.md](./INTEGRATION.md) for the full contract with the Noma chat backend.
