# Integration with the Noma chat backend

`noma_chat` is the Flutter client for the Noma chat backend (a chat-core
service built by Nomasystems). This document describes the contract:
endpoints, auth, real-time, sync behavior, and operational caveats.

## Endpoints

The SDK talks to:

| Channel | URL | Purpose |
|---|---|---|
| REST | `<baseUrl>/v1/*` | CRUD: users, rooms, messages, contacts, etc. |
| WebSocket | `<realtimeUrl>/ws` | Bidirectional real-time (auth, message, typing, receipt, ping, auth_refresh, plus server events) |
| SSE | `<realtimeUrl>/events` | Server → client real-time (fallback when WS fails) |

`baseUrl` and `realtimeUrl` are configured via `NomaChat.create(...)`. They typically share the same host but with different schemes/ports (HTTPS REST 8077, WSS WS 8077, HTTPS SSE 2081/2082).

## Authentication

The backend supports several auth modes; the SDK uses Bearer JWT:

```dart
NomaChat.create(
  ...,
  tokenProvider: () async => await authService.getValidJwt(),
);
```

- `tokenProvider` is called per request. It must return a valid JWT (refresh internally if needed).
- The backend validates the JWT against the deployment's JWKS endpoint (e.g. Cognito, Auth0, custom IdP).
- On 401, `BearerAuthInterceptor` retries once after the consumer's refresh, then calls `onAuthFailure`.

### Token rotation

When the consumer refreshes the JWT (e.g. after a Cognito refresh), call:

```dart
chat.notifyTokenRotated();
```

This sends `{"type":"auth_refresh","token":"<new>"}` to the open WebSocket. The backend re-validates (including blacklist check) and reschedules its expiry timer (`send_after(exp - now)`). 30-second cooldown server-side prevents abuse.

### WebSocket close codes

- `4001 auth_timeout` — client didn't send `auth` within 10s.
- `4002 auth_failed` — invalid token at handshake.
- `4003 token_expired` — the server-side timer fired at the JWT's `exp`.
- `4004 token_revoked` — the user's tokens were revoked by the backend (e.g. logout, deactivation) via its revocation list.

Both `4003` and `4004` should trigger the consumer to refresh the cached token and reconnect.

## Real-time event types

The WS/SSE channel emits events that the SDK parses into a sealed `ChatEvent` union:

| Server event | SDK event class |
|---|---|
| `new_message` | `NewMessageEvent` (with enriched message payload) |
| `message_updated` | `MessageUpdatedEvent` (IDs only; SDK fetches via API) |
| `message_deleted` | `MessageDeletedEvent` |
| `room_created` | `RoomCreatedEvent` (IDs only) |
| `room_updated` | `RoomUpdatedEvent` (IDs only) |
| `room_deleted` | `RoomDeletedEvent` |
| `user_joined`, `user_left`, `user_role_changed` | corresponding events |
| `receipt_updated` | `ReceiptUpdatedEvent` (carries the `userId` of the reader) |
| `typing` | `TypingEvent` (room: `roomId`; DM: `contactId`) |
| `presence_changed` | `PresenceChangedEvent` |
| `reaction_added`, `reaction_deleted` | reaction events with `emoji` field |
| `broadcast` | `BroadcastEvent` |

The TransportManager emits these on `client.events` for the consumer to subscribe to. The `ChatUiAdapter` subscribes internally and updates UI controllers.

## Room types and DM disambiguation

The backend supports several room shapes:

- `RoomType.oneToOne` — 1:1 conversations (DMs or 1-on-1 groups).
- `RoomType.group` — group rooms with multiple members.
- `RoomType.announcement` — read-only broadcast rooms (only owner/admin sends; implicit membership).

For a clean DM vs group distinction in your UI when 1:1 rooms can semantically be groups (e.g. a 2-person event group), provide an `isDmRoom` predicate and the backend's `forceGroup` flag at room creation.

## Cache-then-network with delta sync

The adapter and APIs implement a stale-while-revalidate pattern:

1. Show cached data immediately (`cacheOnly` phase).
2. Fetch network in the background (`networkOnly` phase) using `after=newestCachedTimestamp` so only new data comes down.
3. Merge into cache + UI on completion.

This eliminates blank screens after navigation and keeps bandwidth low.

## Offline behavior

- Outbound operations that fail with network errors enqueue in `OfflineQueue` (Hive-persistent, 9 types).
- On reconnect, the queue retries with backoff. 401 errors do not trigger immediate retry (the consumer's refresh flow handles them).
- `OfflineQueue.restore()` runs on boot; persisted operations resume after app restart.

## Internal S2S endpoints

The backend exposes `/v1/internal/*` for service-to-service calls. The SDK exposes them via `client.internal.*` (createUser, deleteUser, createRoom, deleteRoom, addRoomUser, addContact, blockUser, unblockUser, deleteSession, revoke). Authentication uses `X-Api-Key` (not JWT) and `X-User-Id` for the acting user.

These are typically called by another backend service of yours (e.g. your auth or directory service), not by an end-user mobile app. The SDK includes them for completeness — your code should gatekeep them.

## Admin endpoints

The backend's admin endpoints (`/v1/admin/*`) are also exposed via `client.admin.*` (stats, sessions, config, broadcast, content filters, user roles, etc.). They require either an admin JWT or the React panel cookie (`uc_admin_sid`). Use them only when your app has an admin role.

## Operational caveats

- **Health endpoint**: `GET /health` returns `200 {"status":"ok"}` without auth. Used for liveness probes.
- **Rate limiting**: the backend rate-limits per user. Exceeding returns 429 with `Retry-After`. The SDK's `RetryInterceptor` parses and respects this.
- **Webhook circuit breaker**: the backend has a circuit breaker on webhook delivery. Not directly relevant to the SDK, but if your app relies on webhook delivery for some flow, expect transient delays.
- **Multinodo cluster**: the backend may run as a cluster. Session lookups, NRTE events, scheduled messages, and admin config are cluster-coordinated. The SDK is unaware of cluster topology.

## OpenAPI spec

The full backend API is described by an OpenAPI document that your
deployment ships with the backend. When in doubt about a request/response
shape, that document is the source of truth. The SDK's mappers stay in
sync with it.
