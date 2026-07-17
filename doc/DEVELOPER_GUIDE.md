# noma_chat — Developer Guide

Complete technical reference for integrating and customizing `noma_chat`.

**Contents**

1. [Architecture](#architecture)
2. [Setup & configuration](#setup--configuration)
3. [NomaChat facade](#nomachat-facade)
4. [SDK — sub-APIs](#sdk--sub-apis)
5. [Real-time modes](#real-time-modes)
6. [Events](#events)
7. [Cache](#cache)
8. [UI components — controllers](#ui-components--controllers)
9. [UI components — widgets](#ui-components--widgets) · [NomaChatView](#nomachatview)
10. [Customization hooks](#customization-hooks)
11. [Theming](#theming)
12. [Localization](#localization)
13. [Testing](#testing)
14. [Troubleshooting](#troubleshooting)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Your Flutter app                  │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│                  NomaChat (facade)                  │
│  ┌───────────────┐  ┌──────────────────────────┐   │
│  │  ChatClient   │  │     HiveChatDatasource    │   │
│  │  (8 sub-APIs) │  │  (persistent Hive cache)  │   │
│  └───────┬───────┘  └──────────────────────────┘   │
│          │  ┌──────────────────────────────────┐    │
│          └──│       ChatUiAdapter              │    │
│             │  (bridges SDK → UI controllers)  │    │
│             └──────────────┬─────────────────--┘    │
└────────────────────────────┼────────────────────────┘
                             │
             ┌───────────────┴──────────────┐
             │                              │
   ┌─────────▼──────────┐       ┌──────────▼──────────┐
   │   ChatController   │       │ RoomListController  │
   │  (single room UI)  │       │  (room list UI)     │
   └────────────────────┘       └─────────────────────┘
```

**Three layers:**

- **ChatClient** — pure SDK, no Flutter dependency. Handles transport, auth, retry, circuit breaker. Pluggable: bring your own implementation via `NomaChat.fromClient()`.
- **HiveChatDatasource** — local persistence. Caches messages, rooms, receipts. Transparent to consumers; `NomaChat.create()` wires it automatically (unless you pass `enableCache: false` or your own `localDatasource`).
- **ChatUiAdapter** — stateful bridge. Subscribes to `ChatClient.events`, maintains a DM contact-to-room index, drives `ChatController` and `RoomListController` with live updates.

---

## Setup & configuration

### Minimal

The default persistent cache is Hive-backed, and `NomaChat.create()` opens its
boxes immediately, so you must initialise Hive **before** calling it. Do this
once at app start:

```dart
import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

WidgetsFlutterBinding.ensureInitialized();
await Hive.initFlutter();        // skip only if you disable the cache

final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
);
await chat.connect();
```

Add `hive_ce_flutter` to your `pubspec.yaml` dependencies for the import above.

### Cache options

The cache is **on by default** (a `HiveChatDatasource` is created for you).
You tune or replace it through `NomaChat.create()` parameters — there is no
`cache:` parameter:

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),

  // Tune the bundled Hive cache:
  maxMessagesPerRoom: 500,                 // ring-buffer size per room
  maxRooms: 200,                           // null = unlimited
  messageTtl: const Duration(days: 30),    // purge older messages on startup
  encryptionCipher: HiveAesCipher(key),    // optional at-rest encryption
);
```

In-memory only (no Hive, no `Hive.initFlutter()` needed):

```dart
final chat = await NomaChat.create(
  /* ...required params... */
  enableCache: false,
);
```

Bring your own store by implementing `ChatLocalDatasource` and passing it as
`localDatasource:` — `NomaChat.create()` then uses it instead of the bundled
Hive one.

### Full ChatConfig reference

Most apps configure through `NomaChat.create()` parameters above. For full
control over transport/auth, build a `ChatConfig` yourself and pass it as
`config:` — note that a supplied `config` **bypasses** the convenience params
(including the bundled cache), so wire your own `localDatasource` into it:

```dart
final chat = await NomaChat.create(
  currentUser: ChatUser(id: userId, displayName: name),
  // A supplied config owns baseUrl/realtimeUrl/cache/etc.; the top-level
  // baseUrl/realtimeUrl/tokenProvider are still required by the signature
  // but ignored when `config` is non-null.
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  config: ChatConfig(
    baseUrl: 'https://chat.myapp.com/v1',  // REST base URL
    realtimeUrl: 'https://chat.myapp.com', // WebSocket / SSE base URL
    tokenProvider: () => authService.getToken(),
    realtimeMode: RealtimeMode.auto,       // see Real-time modes
    logger: ChatConfig.debugOnlyLogger,    // routes to dart:developer in debug
    enableHttpLog: false,                  // log full HTTP request bodies
    ssePath: '/eventsource',               // SSE endpoint path (CHT/NRTE default)
    actAsUserId: null,                     // managed-user delegation (REST only); see below
    localDatasource: await HiveChatDatasource.create(),
  ),
  isDmRoom: (detail) =>                    // see Customization hooks
      detail.type == RoomType.oneToOne &&
      detail.custom?['type'] == 'dm',
);
```

#### Managed-user delegation — `actAsUserId`

Set `ChatConfig.actAsUserId` to act on behalf of a managed user: every REST
request then carries `X-From-User-Id: <actAsUserId>`. The backend enforces the
parent→managed relationship and answers `403` when it is not allowed. This
applies to REST calls only — it does not change the real-time identity: the
WebSocket / SSE connection still authenticates as the parent (the realtime
backends do not carry the delegation header). Delegated real-time streams are
a backlog item pending backend support; for now, run a managed user's live
stream from a client authenticated as that user.

```dart
config: ChatConfig(
  actAsUserId: managedUserId,
),
```

**End-to-end walkthrough.** The parent account authenticates as itself
(`tokenProvider` still returns the parent's token); `actAsUserId` only changes
which user id is *attributed* to REST writes:

```dart
// Parent account "coach-1" manages "player-7". Auth stays as coach-1 —
// only the header changes which user REST calls act as.
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getCoachToken(), // always the parent's token
  currentUser: ChatUser(id: 'player-7', displayName: 'Player Seven'),
  config: ChatConfig(
    baseUrl: 'https://chat.myapp.com/v1',
    realtimeUrl: 'https://chat.myapp.com',
    tokenProvider: () => authService.getCoachToken(),
    actAsUserId: 'player-7',
  ),
);

// This send is attributed to player-7, not coach-1, on the backend.
final res = await chat.client.messages.send(roomId, text: 'Hi from the team!');
if (res case ChatFailureResult(failure: ForbiddenFailure())) {
  // coach-1 is not an authorized manager of player-7 — the relationship
  // check failed server-side (403). Fall back to acting as the parent, or
  // surface a permissions error.
}
```

Because the WS/SSE connection still authenticates (and receives events) as
the parent, a UI built for a managed user typically needs to filter or relabel
incoming events client-side rather than relying on the transport identity —
there is no `X-From-User-Id`-scoped event stream to subscribe to.

### Observability — `metricCallback` and `noma_chat_otel`

`ChatConfig.metricCallback` is a single sink —
`void Function(String metric, Map<String, dynamic> data)` — fed by every
observable SDK event (cache hits/misses, HTTP request durations, WebSocket
lifecycle, auth refresh failures, offline-queue depth, …). It is `null` by
default; nothing is collected or sent anywhere unless you wire it. See
`TELEMETRY.md` for the full metric-by-metric reference (name, fields, firing
condition).

```dart
config: ChatConfig(
  metricCallback: (metric, data) => myAnalytics.track(metric, data),
),
```

For OpenTelemetry specifically, use the `noma_chat_otel` companion package
(`packages/noma_chat_otel` in this repo) instead of hand-rolling the mapping:

```dart
import 'package:noma_chat_otel/noma_chat_otel.dart';

final tracer = openTelemetry.getTracer('noma_chat');
config: ChatConfig(
  metricCallback: nomaChatOtelCallback(tracer),
),
```

Every metric becomes an instantaneous point-in-time OTel span (started and
ended immediately, so span start/end timestamps are identical — these are
observations, not measured durations) named `noma_chat.<metric>`, falling
back to a small built-in table (`OtelSpanBuilder.spanNames`) of friendlier
names for a subset of events. There is currently no supported way to
customize span names or shape — `OtelSpanBuilder` is a `static`-only,
non-instantiable class, so it cannot be subclassed. Fork
`nomaChatOtelCallback` if you need different span naming. See
`packages/noma_chat_otel/README.md`.

### Teardown

```dart
await chat.disconnect();
chat.dispose();
```

Call `dispose()` to release controllers and close Hive boxes. Typically in your top-level widget's `dispose()`.

---

## NomaChat facade

| Member | Description |
|---|---|
| `chat.client` | Raw `ChatClient` — 8 sub-APIs |
| `chat.adapter` | `ChatUiAdapter` — drives UI controllers |
| `chat.connect()` | Opens real-time connection |
| `chat.disconnect()` | Closes transport gracefully |
| `chat.dispose()` | Frees all resources |
| `chat.currentUser` | The `ChatUser` passed at creation |

### Pre-configured client

Use `NomaChat.fromClient()` when you need to inject a custom or pre-wired `ChatClient` (e.g. from a DI container):

```dart
final chat = NomaChat.fromClient(
  client: myCustomClient,
  currentUser: ChatUser(id: userId, displayName: name),
  isDmRoom: (detail) => ...,
);
```

---

## SDK — sub-APIs

Access all sub-APIs through `chat.client`:

```dart
chat.client.rooms
chat.client.messages
chat.client.members
chat.client.users
chat.client.contacts
chat.client.presence
chat.client.attachments
chat.client.auth
```

### Rooms

```dart
// List joined rooms
final rooms = await chat.client.rooms.list();

// Get a specific room
final detail = await chat.client.rooms.get(roomId);

// Create a room
await chat.client.rooms.create(
  name: 'Team Alpha',
  audience: RoomAudience.contacts,
);

// Force a group even with a single other member. By default a contacts room
// with one peer collapses to a DM-style room; pass forceGroup to keep it a
// named group.
await chat.client.rooms.create(
  name: 'Team Alpha',
  audience: RoomAudience.contacts,
  members: [otherUserId],
  forceGroup: true,
);

// Update room config
await chat.client.rooms.updateConfig(roomId, name: 'New name');

// Per-user preferences (private; invisible to other members).
// `patchPreferences` is the single entry point: set any subset of
// `muted` / `muteUntil` / `pinned` / `hidden` in one round-trip and read
// back the merged server-side state.
final prefs = await chat.client.rooms.patchPreferences(
  roomId,
  muted: true,             // permanent mute
  // muteUntil: someInstant, // timed mute (WhatsApp-style); wins over `muted`
  pinned: true,
  hidden: false,           // archive == hidden: true
);
switch (prefs) {
  case ChatSuccess(:final data):
    print('${data.muted} ${data.pinned} ${data.hidden} ${data.muteUntil}');
  case ChatFailureResult(:final failure):
    showError(failure);
}
// (Single-flag convenience wrappers with optimistic UI updates live on the
// UI adapter: `adapter.rooms.mute/unmute/pin/unpin/hide/unhide`.)

// Discover public rooms
final results = await chat.client.rooms.discover(query: 'flutter');

// Delete (owner only)
await chat.client.rooms.delete(roomId);
```

### Messages

```dart
// Send (REST). All content fields are named optional params — there is no
// SendMessageRequest object. A clientMessageId is auto-generated when omitted,
// so a retried send is de-duplicated server-side.
await chat.client.messages.send(
  roomId,
  text: 'Hello!',
  referencedMessageId: parentMessageId, // optional reply / thread parent
  metadata: {'custom': true},           // optional custom payload
);

// Send via WebSocket (transport-agnostic; falls back to REST). Same named
// params as send() minus tempId/clientMessageId.
await chat.client.messages.sendViaWs(roomId, text: 'Hello!');
```

> **The id returned by `send()` can be provisional.** Under the backend's
> `ack_mode = async` (opt-in; the backend default is `sync`) the `201` response is an echo built
> *before* persistence: its `id` does not match the stored message and the
> returned `ChatMessage` has `isProvisional == true`. The authoritative
> message — real id included — arrives moments later as a `NewMessageEvent`
> carrying the same `clientMessageId`. Correlate on
> `ChatMessage.clientMessageId` and never use a provisional id for
> follow-up operations (react / edit / delete / pin). The bundled
> `ChatUiAdapter` already does this: it keeps the optimistic bubble in the
> *sending* state until the event confirms it, and `ChatController`
> reconciles the rows by `clientMessageId` so no duplicate appears. The
> same applies to `contacts.sendDirectMessage()` and to the synthetic
> message `sendViaWs()` returns after a WS ack.

```dart

// Fetch paginated (newest-first). See "Paginating message history" below.
final page = await chat.client.messages.list(
  roomId,
  pagination: ChatCursorPaginationParams(limit: 30),
);

// Search messages globally across every room the caller belongs to
final hits = await chat.client.messages.search('flutter');
// ...or scope to a single room
final roomHits = await chat.client.messages.search('flutter', roomId: roomId);

// Edit / delete
await chat.client.messages.update(roomId, messageId, text: 'Edited');
await chat.client.messages.delete(roomId, messageId);

// React (canonical endpoint) — a reaction is a sub-resource of the
// message, POSTed to /rooms/{roomId}/messages/{messageId}/reactions.
// This is the only supported way to react: it never adds a synthetic
// message to the timeline. A NetworkFailure (or pre-response timeout)
// enqueues it for retry on reconnect, same as send()/delete() — see
// "Offline queue" below. The backend emits `reaction_added` so every
// member updates live.
await chat.client.messages.addReaction(roomId, messageId, emoji: '👍');
// Remove: omit `emoji` to clear the user's reaction wholesale (historical
// single-reaction-per-user behaviour), or pass it to remove a specific one
// (sends DELETE …/reactions?emoji=👍) on backends that track several.
await chat.client.messages.deleteReaction(roomId, messageId);
await chat.client.messages.deleteReaction(roomId, messageId, emoji: '👍');
// Aggregated counts + reactor lists for a message.
final reactions = await chat.client.messages.getReactions(roomId, messageId);

// Mark a whole room as read (optionally up to a specific message).
await chat.client.messages.markRoomAsRead(roomId);
await chat.client.messages.markRoomAsRead(roomId, lastReadMessageId: messageId);
// Batch mark several rooms read in one round-trip (rooms API).
await chat.client.rooms.batchMarkAsRead([roomId1, roomId2]);

// Confirm delivery (double gray tick) — cursor semantics: one call per
// conversation covers every message at-or-before the given one, for any
// author. Idempotent (the server max-merges; older cursors are no-ops).
// With `ChatUiAdapter.autoConfirmDelivery` (default true) the adapter
// fires this automatically on live messages, chat load and the
// post-login room sync; call it manually only when that flag is off.
await chat.client.messages.markRoomAsDelivered(
  roomId,
  lastDeliveredMessageId: newestMessageId,
);

// Unread counts (rooms API)
final counts = await chat.client.rooms.batchGetUnread([roomId1, roomId2]);

// Pins — same offline-queue retry as reactions above.
await chat.client.messages.pinMessage(roomId, messageId);
await chat.client.messages.unpinMessage(roomId, messageId);

// Scheduled messages — sendAt is a required named param; text/metadata named.
await chat.client.messages.schedule(roomId, sendAt: futureDate, text: 'Later!');

// Clear room history (own messages only by default)
await chat.client.messages.clearChat(roomId);
```

#### Scheduled messages

`messages.schedule` books a message for future delivery instead of sending it
immediately. The backend holds it and emits it into the room's timeline at
`sendAt`. It returns a `ScheduledMessage`, not a `ChatMessage` — the message
does not exist in the room's history until it actually fires, and there is no
"scheduled by X" preview visible to other members in the meantime.

```dart
final res = await chat.client.messages.schedule(
  roomId,
  sendAt: DateTime.now().add(const Duration(hours: 2)),
  text: 'Standup reminder',
  metadata: {'kind': 'reminder'},
);

switch (res) {
  case ChatSuccess(:final data):
    // data.id is the scheduled entry id — keep it to cancel later.
    myScheduledList.add(data);
  case ChatFailureResult(:final failure):
    showError(failure);
}

// List the caller's own pending (not-yet-sent) scheduled messages in a room.
// Already-sent entries are not returned; there is no visibility into other
// users' scheduled queue.
final pending = await chat.client.messages.listScheduled(roomId);

// Cancel before sendAt. Cancelling after delivery (or someone else's
// scheduled message) fails — the backend enforces both checks.
await chat.client.messages.cancelScheduled(roomId, res.dataOrNull!.id);
```

#### Offline queue

`send`, `delete`, `addReaction`, `pinMessage`, `unpinMessage`, `starMessage`
and `unstarMessage` retry automatically when they fail with a
`NetworkFailure`, or a pre-response `TimeoutFailure` (the request provably
never reached the server). The failed call still returns its failure to the
caller immediately — the retry happens transparently in the background on
the next reconnect. `send` is the one non-idempotent op in that list: it
additionally requires the pre-response condition (a `receive`-phase or
unknown-phase timeout is NOT retried automatically, since the message may
already have reached the server) to avoid duplicating a message.

If the offline queue exhausts its retries (or the operation sits too long /
the queue is full), `NomaChatClient.onOperationDropped` fires. The default
implementation records the operation id so you can show a "delivery failed"
badge:

```dart
final client = chat.client as NomaChatClient;
if (client.isOperationPermanentlyFailed(pendingOperationId)) {
  showDeliveryFailedBadge();
}
```

Override `onOperationDropped` to replace this behaviour entirely (e.g. to
persist the failure server-side or show a toast instead):

```dart
client.onOperationDropped = (op, reason) {
  myAnalytics.track('offline_op_dropped', {'reason': reason});
};
```

#### Paginating message history — bidirectional opaque cursors

`messages.list` returns a `ChatPaginatedResponse<ChatMessage>` newest-first.
Each page carries two **opaque, seq-based cursors**:

- `ChatPaginatedResponse.prevCursor` — anchored on the **oldest** message of
  the page. Feed it back as `ChatCursorPaginationParams.cursor` with
  `direction: ChatCursorDirection.older` to load **older history**.
- `ChatPaginatedResponse.nextCursor` — anchored on the **newest** message of
  the page. Feed it back with `direction: ChatCursorDirection.newer` (the
  backend default) to **catch up** on newer messages.

`hasMore` reflects whether more pages exist *in the requested direction*.

```dart
// Walk older history
final first = await chat.client.messages.list(roomId);
var page = first.dataOrNull;
while (page != null && page.hasMore && page.prevCursor != null) {
  final res = await chat.client.messages.list(
    roomId,
    pagination: ChatCursorPaginationParams(
      cursor: page.prevCursor,
      direction: ChatCursorDirection.older,
      limit: 30,
    ),
  );
  page = res.dataOrNull;
  if (page != null) renderOlder(page.items);
}
```

The cursor is **seq-based**, so it never skips or re-delivers messages that
share an exact millisecond. There is no timestamp paging — the removed
`before`/`after` ISO-8601 fields are gone; always page with the opaque
`prevCursor`/`nextCursor` and a `direction`.

> The polling/manual transports (`RealtimeMode.polling` / `.manual`) catch up
> using the forward cursor automatically: once a poll returns a `next` token
> the engine resumes from it (`direction: newer`) on every subsequent tick.
> Until a room has a cursor the first poll fetches the most recent page and
> adopts the `next` it returns.

#### Exporting a chat — `adapter.messages.exportChat`

The adapter exports a room's full history to a WhatsApp-style plain-text
transcript. It pages backward through `messages.list` until the history is
exhausted, resolves sender display names through the user cache, and returns
a `ChatExport` (`text` + `messageCount`). No new dependency: writing the file
and sharing it is left to the host so the SDK ships no platform share package.

```dart
final res = await chat.adapter.messages.exportChat(roomId);
final export = res.dataOrNull;
if (export != null) {
  final file = File('${(await getTemporaryDirectory()).path}/chat.txt');
  await file.writeAsString(export.text);
  await Share.shareXFiles([XFile(file.path)]); // host app's share package
}
```

Each line reads `12/06/26, 14:02 - Alice: Hello`. Deleted messages and media
render with overridable placeholders (`deletedPlaceholder` /
`mediaPlaceholder`; attachment file names are used when present). Override
`displayNameFor` for the name column, `dateFormat` for the timestamp, or
`maxMessages` to cap the export. Surface it from the room menu with the
`ChatRoomOption.exportChat` preset.

### Members

```dart
await chat.client.members.add(roomId, userId: targetUserId);
await chat.client.members.remove(roomId, userId: targetUserId);
await chat.client.members.leave(roomId);
await chat.client.members.updateRole(roomId, userId: targetUserId, role: MemberRole.admin);
```

#### Listing members — `list` and the `users` expansion

`members.list` returns a paginated list of `RoomUser` items. By default each
row is the bare `{userId, role}`, so rendering a roster with names and avatars
meant a follow-up `users.get(id)` per member — an **N+1** for every group
screen.

Pass `expand: [RoomMemberExpand.users]` and the backend embeds each member's
`displayName` + `avatarUrl` directly in the row. One request renders the whole
roster — **no per-member `GET /users/{id}` round-trip**. This is the
recommended default for any "participants" screen:

```dart
final res = await chat.client.members.list(
  roomId,
  expand: const [RoomMemberExpand.users],
  // pagination: ChatPaginationParams(limit: 50),
);

switch (res) {
  case ChatSuccess(:final data):
    for (final m in data.items) {
      renderRow(
        name: m.displayName ?? m.userId, // embedded by the expansion
        avatarUrl: m.avatarUrl,          // null without expand or no avatar
        role: m.role,
      );
    }
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

`displayName` / `avatarUrl` are `null` when `expand` is omitted (or when a
backend ignores the param), so the field-resolution fallback through the user
cache still works unchanged. The built-in `GroupMembersView` widget already
requests this expansion and seeds the adapter user cache from the embedded
fields, so the group-members screen renders names and avatars with no extra
fetches out of the box.

#### Inviting users — `invite` and `InviteResult`

`members.invite` adds or invites one or more users in a single call. A
successful HTTP call does **not** mean every user was added: the backend
returns `207 Multi-Status` on mixed outcomes (e.g. one user banned, another
already a member), so inspect the returned `InviteResult` instead of assuming
success.

```dart
final result = await chat.client.members.invite(
  roomId,
  userIds: ['user-123', 'user-456'],
  mode: RoomUserMode.inviteAndJoin, // add directly (admin/owner); default is .invite
  // token: publicRoomToken,        // optional: public-room join by token
);

switch (result) {
  case ChatSuccess(:final data) when data.hasFailures:
    // Some users could not be added — surface the per-user breakdown.
    for (final f in data.failed) {
      showError('${f.userId}: ${f.detail ?? 'failed'} (${f.code})');
    }
  case ChatSuccess(:final data):
    showOk('${data.succeeded.length} invited'); // data.allSucceeded == true
  case ChatFailureResult(:final failure):
    // Every user failed (non-2xx), or a transport error.
    showError(failure);
}
```

`InviteResult` exposes:

| Member | Type | Meaning |
|---|---|---|
| `results` | `List<InviteUserResult>` | One entry per requested user (`userId`, `success`, `code?`, `detail?`). |
| `succeeded` | `List<InviteUserResult>` | The users that were added. |
| `failed` | `List<InviteUserResult>` | The users that could not be added. |
| `hasFailures` | `bool` | `true` if any user failed. |
| `allSucceeded` | `bool` | `true` if the result is non-empty and every user succeeded. |

The backend does not accept a per-invite role; assign roles after the
invitation with `updateRole`.

#### Invite links — `joinWithToken` + `ChatInviteLink`

Public / invitable rooms carry a `publicToken` (`ChatRoom.publicToken`). Turn
it into a shareable deep link with `ChatInviteLink`, and self-join from a
link with `members.joinWithToken` (a thin wrapper over
`invite(mode: inviteAndJoin, token: …)` for the current user):

```dart
// Share side — build a link from the room's public token:
final link = ChatInviteLink(roomId: room.id, token: room.publicToken!)
    .toUri(Uri.parse('https://myapp.com/invite'));
// -> https://myapp.com/invite?room=<id>&token=<token>
// Hand link.toString() to your share sheet, or use the
// ChatRoomOption.inviteViaLink menu preset (copies to clipboard by default).

// Join side — resolve an incoming deep link and join:
final invite = ChatInviteLink.tryParse(incomingUri);
if (invite != null) {
  final res = await chat.client.members.joinWithToken(
    invite.roomId,
    token: invite.token,
  );
  // Still gated server-side (ban/audience): inspect res.dataOrNull?.hasFailures.
}
```

The query-parameter names default to `room` / `token` and are overridable on
both `toUri` and `tryParse` to fit an existing deep-link scheme.

### Contacts & DMs

```dart
// Add / remove contacts
await chat.client.contacts.add(userId);
await chat.client.contacts.remove(userId);
final contacts = await chat.client.contacts.list();

// Get DM conversation messages
final messages = await chat.client.contacts.getConversationMessages(userId);

// Block / unblock
await chat.client.contacts.block(userId);
await chat.client.contacts.unblock(userId);
final blocked = await chat.client.contacts.listBlocked();
```

`contacts.sendDirectMessage()` returns success even when the recipient has
blocked the sender — the backend answers `204 No Content` in that case and
the SDK synthesizes a local `ChatMessage` with `ReceiptStatus.sent` so the
composer clears normally. Check `message.silentlyDropped` to tell that case
apart from a real send and show a distinct state (e.g. a single grey check
that never progresses) instead of a plain "sent":

```dart
final result = await chat.client.contacts.sendDirectMessage(userId, text: 'hi');
final message = result.dataOrNull;
if (message != null && message.silentlyDropped) {
  // Accepted by the server but never delivered — recipient has blocked us.
}
```

DM typing indicators (`contacts.sendTyping()`) always travel over REST
(`POST /contacts/{id}/activity`), regardless of the realtime connection
state: the backend's WS `typing` frame is room-scoped, so REST is the only
route that reaches the peer as a `DmActivityEvent`. Room typing
(`messages.sendTyping()`) still prefers the WS frame when connected.

### Users — profile & account deletion

```dart
// Look up / search / update profiles
final user = await chat.client.users.get(userId);
final results = await chat.client.users.search('alice');
await chat.client.users.update(myId, displayName: 'New name');
```

#### Self-deletion (GDPR right-to-erasure)

Use `deleteCurrentUser()` for self-service account deletion. It calls
`DELETE /users/me`: the server resolves the principal from the auth token, so
it **cannot target the wrong account** — this is the robust default.

```dart
final res = await chat.client.users.deleteCurrentUser();
res.fold(
  (failure) => showError(failure),
  (_) async {
    await chat.dispose();        // tear the client down…
    navigateToOnboarding();      // …and return to sign-in / onboarding
  },
);
```

The deletion is irreversible: the backend tombstones messages, removes the
profile record, and cascades out any managed users owned by the principal.

`users.delete(userId)` still exists for admin-style flows, but the backend now
enforces **own-account-only**: the `userId` MUST be the caller's own id.
Passing any other id returns a 403 that surfaces as a `ForbiddenFailure`
carrying `errorToken == ChatErrorTokens.cannotDeleteOtherUser`:

```dart
final res = await chat.client.users.delete(someOtherUserId);
res.fold(
  (failure) {
    if (failure.errorToken == ChatErrorTokens.cannotDeleteOtherUser) {
      showError('You can only delete your own account.');
    }
  },
  (_) {},
);
```

Prefer `deleteCurrentUser()` over `delete(myId)` for self-service erasure.

### Presence

```dart
final own = await chat.client.presence.getOwn();
final all = await chat.client.presence.getAll();
await chat.client.presence.update(status: PresenceStatus.online);
await chat.client.presence.update(status: PresenceStatus.dnd);
```

> **Note:** `statusText:` is accepted by `presence.update` but is **not
> persisted server-side** — the backend currently ignores it, so a custom
> status string will not round-trip to other users. Pass it only if/when the
> backend gains support.

### Attachments

```dart
// Upload a file and send in one step (UI adapter helper)
await chat.ui.sendAttachment(
  roomId,
  bytes: bytes,
  mimeType: 'image/jpeg',
  fileName: 'photo.jpg',
);

// Low-level upload: get back the attachment id (+ optional url)
final up = await chat.client.attachments.upload(bytes, 'image/jpeg');
final attachmentId = up.dataOrNull?.attachmentId;

// List and clean up
final files = await chat.client.attachments.listInRoom(roomId);
await chat.client.attachments.deleteInRoom(roomId, messageId);
```

#### Downloading / displaying — signed URLs (primary path)

The robust default is the **signed-URL** flow. Given an attachment id and the
room it lives in, resolve a short-lived, self-authorizing URL and feed it
straight to an image widget, a cache, or a native viewer — no auth headers to
re-attach. The backend authorizes by room membership (fail-closed).

```dart
final res = await chat.client.attachments.signedUrl(
  attachmentId,
  roomId: roomId,
);
switch (res) {
  case ChatSuccess(:final data):
    // data.url is absolute and ephemeral — use it now, don't persist it.
    return Image.network(data.url); // or CachedNetworkImage(imageUrl: data.url)
  case ChatFailureResult(:final failure):
    if (failure.errorToken == ChatErrorTokens.notARoomMember) {
      // Caller isn't in the room — show a "no access" placeholder.
    }
}
```

Need the raw bytes (documents, voice notes)? `download` takes the same
signed-URL path when you pass `roomId`:

```dart
final bytes = await chat.client.attachments.download(
  attachmentId,
  roomId: roomId, // takes the signed-URL path under the hood
);
```

> **Deprecated:** the old header-only download (`download(id, metadata: ...)`
> without `roomId`) relied on the `x-attachment-metadata` header alone. The
> backend now requires a membership-checked `roomId` and returns
> `not_a_room_member` (403) otherwise. Always pass `roomId` — the SDK knows it
> wherever an attachment is shown. See `MIGRATING.md`.

#### Filtering by MIME type / size — `AttachmentPolicy`

`AttachmentPolicy` is a declarative allow-list + size-cap gate that both
`AttachmentPickers` (pick time) and `ChatUiAdapter.sendAttachment` /
`messages.sendAttachment` (send time) honour, so a picked-but-rejected file
never reaches an upload call. It is additive: anything not explicitly
rejected is allowed.

```dart
const imagesAndDocsOnly = AttachmentPolicy(
  allowedMimeTypes: {'image/*', 'application/pdf'},
  maxBytesByMimePrefix: {'image/': 16 << 20}, // 16 MB cap for images
  maxBytes: 25 << 20,                          // 25 MB cap for everything else allowed
);

// Enforced at pick time — a rejected file never reaches the composer.
final pick = await AttachmentPickers.pickImageFromGallery(
  policy: imagesAndDocsOnly,
  logger: (level, msg) => myLogger.log(level, msg), // logs the violation
);

// Belt-and-suspenders re-check at send time (e.g. bytes built by a web
// drop target instead of AttachmentPickers) — surfaces as a typed
// ValidationFailure instead of silently dropping.
final res = await chat.adapter.messages.sendAttachment(
  roomId,
  bytes: bytes,
  mimeType: mimeType,
  policy: imagesAndDocsOnly,
);
if (res case ChatFailureResult(failure: ValidationFailure(:final message))) {
  showError(message); // "attachment policy violation: <AttachmentPolicyViolation>"
}
```

Two presets ship out of the box: `AttachmentPolicy.unrestricted` (default —
only the 25 MB fallback cap applies, no MIME whitelist) and
`AttachmentPolicy.whatsappLike` (per-type caps approximating WhatsApp's 2024
limits). Clone either with `copyWith(...)` rather than hand-rolling a new
policy for small tweaks. There is no separate "attachment builder" hook —
extra picker entries (e.g. a location share button) are added via
`ChatView.attachmentPickerExtraOptions`, documented under "Customization
hooks → AttachmentPickerSheet — extra slots" below; `AttachmentPolicy` only
governs validation, not the picker sheet's layout.

---

## Real-time modes

Set via `ChatConfig.realtimeMode`:

| Mode | Behaviour |
|---|---|
| `RealtimeMode.auto` *(default)* | WebSocket first; falls back to SSE, then polling if WS fails or is unavailable. Reconnects automatically. When the server disables the WS transport at runtime (close code `4006` `transport_disabled`), the SDK stops retrying WS for the session and promotes the fallback immediately; a later `connect()` tries WS again. |
| `RealtimeMode.webSocketOnly` | WS only. Throws if connection fails. On close `4006` the transport stays down (state `error`) until the app calls `connect()` again. |
| `RealtimeMode.serverSentEventsOnly` | SSE only. Good for environments where WS is blocked. |
| `RealtimeMode.polling` | HTTP long-poll. Higher latency, no server push. |
| `RealtimeMode.manual` | No automatic transport. Call `chat.client.refresh()` or `chat.client.refreshRoom(roomId)` to pull updates. |

### Manual refresh

```dart
// Refresh all rooms and messages
await chat.client.refresh();

// Refresh a specific room only
await chat.client.refreshRoom(roomId);
```

---

## Events

Subscribe to the raw event stream from `ChatClient`:

```dart
chat.client.events.listen((event) {
  switch (event) {
    case NewMessageEvent(:final message):
      print('New message: ${message.text}');
    case MessageUpdatedEvent(:final message):
      // ...
    case PresenceChangedEvent(:final userId, :final status):
      // ...
    // ...
  }
});
```

### Full event catalogue

| Event | Payload |
|---|---|
| `NewMessageEvent` | `message: ChatMessage` |
| `MessageUpdatedEvent` | `message: ChatMessage` |
| `MessageDeletedEvent` | `messageId`, `roomId` |
| `RoomCreatedEvent` | `room: RoomDetail` |
| `RoomUpdatedEvent` | `room: RoomDetail` |
| `RoomDeletedEvent` | `roomId` |
| `UserJoinedEvent` | `userId`, `roomId` |
| `UserLeftEvent` | `userId`, `roomId` |
| `UserRoleChangedEvent` | `userId`, `roomId`, `role: MemberRole` |
| `ReceiptUpdatedEvent` | `roomId`, `receipts: List<ChatReceipt>` |
| `MessageAckedEvent` | `roomId?`/`toUserId?` (room vs DM form), `messageId`, `seq: int`, `metadata?` — the server durably persisted an own message (single gray tick). Correlate WS sends by echoing a client id in the message `metadata`. |
| `MessageDeliveredEvent` | `roomId?` (absent in the DM form), `userId` (the confirmer), `messageId`, `seq: int` — the confirmer's delivered cursor advanced: every message at-or-before `messageId` is delivered to them. |
| `UserActivityEvent` | `userId`, `roomId`, `activity: UserActivity` |
| `DmActivityEvent` | `userId`, `activity: UserActivity` |
| `PresenceChangedEvent` | `userId`, `status: PresenceStatus` |
| `ReactionAddedEvent` | `messageId`, `reaction: ChatReaction` |
| `ReactionDeletedEvent` | `messageId`, `reactionId` |
| `BroadcastEvent` | `payload: Map<String, dynamic>` |
| `UnreadUpdatedEvent` | `roomId`, `count: int` |

> **Delivery & read receipts.** The single-/double-tick lifecycle is fully
> event-driven: the backend emits `message_acked` (durably persisted →
> `MessageAckedEvent`), `message_delivered` (delivered cursor advanced →
> `MessageDeliveredEvent`) and `receipt_updated` (`ReceiptUpdatedEvent`), and
> the SDK parses and dispatches all three out of the box. No extra wiring is
> needed to drive WhatsApp-style ticks.

---

## Error handling

Every SDK call returns a `ChatResult<T>` — either `ChatSuccess<T>` or
`ChatFailureResult<T>` wrapping a typed `ChatFailure`. Pattern-match or `fold`:

```dart
final result = await chat.client.messages.send(roomId, text: 'hi');
result.fold(
  (failure) => showError(failure.message),
  (message) => print('sent ${message.id}'),
);
```

### Branch on a stable token, not on English prose — `errorToken`

Every `ChatFailure` carries a `String? errorToken`: a **stable, snake_case
symbolic code** from the server's vocabulary. It is the contractual key for
branching and localization — the `message` field is English and meant for
logs, not UI copy or `==` checks.

```dart
result.fold(
  (failure) {
    final label = switch (failure.errorToken) {
      ChatErrorTokens.editWindowExpired => l10n.editTooLate,
      ChatErrorTokens.deleteWindowExpired => l10n.deleteTooLate,
      ChatErrorTokens.blocked => l10n.youAreBlocked,
      ChatErrorTokens.banned => l10n.youAreBanned,
      ChatErrorTokens.rateLimited => l10n.slowDown,
      ChatErrorTokens.cannotDeleteOtherUser => l10n.cannotDeleteOther,
      ChatErrorTokens.roomNotFound => l10n.roomGone,
      _ => l10n.genericError, // null / unknown / older server
    };
    showSnackBar(label);
  },
  (data) => render(data),
);
```

`errorToken` is `null` when the server attached none (older servers, or a
response for which no token applies) — never the empty string. It is a
`String?`, not an enum, on purpose: a new server token arrives **verbatim** and
never breaks the SDK or forces a release. The `ChatErrorTokens` class holds the
well-known constants the SDK itself reasons about (`room_not_found`,
`not_a_member`, `blocked`, `banned`, `edit_window_expired`,
`delete_window_expired`, `message_blocked_by_content_filter`, `rate_limited`,
`cannot_delete_other_user`, …) — match against those constants rather than
hard-coding string literals.

### Typed failures

For common cases you can also switch on the failure **type** (each maps to an
HTTP outcome and, where applicable, carries the canonical `errorToken`):

| Failure | When | `errorToken` |
|---|---|---|
| `AuthFailure` | 401, or a 403 account-deactivation token | passthrough |
| `ForbiddenFailure` | other 403s (ban, missing membership, wrong account) | passthrough (e.g. `cannot_delete_other_user`) |
| `EditWindowExpiredFailure` | edit attempted past the window | `edit_window_expired` |
| `DeleteWindowExpiredFailure` | "delete for everyone" past the window | `delete_window_expired` |
| `NotFoundFailure` | 404 | passthrough |
| `ValidationFailure` | 400 (field errors in `errors`) | passthrough |
| `ContentFilterFailure` | 400 blocked by content filter | `message_blocked_by_content_filter` |
| `ConflictFailure` | 409 | passthrough |
| `RateLimitFailure` | 429 (`retryAfter`) | `rate_limited` |
| `ServerFailure` | 5xx / unmapped | passthrough |
| `NetworkFailure` / `TimeoutFailure` | transport-level (no server body) | `null` |

The SDK chooses the typed failure **token-first** — e.g. a 403 with
`error: "edit_window_expired"` becomes `EditWindowExpiredFailure` — and falls
back to matching the legacy `detail` string for servers that don't yet emit the
token, so handling works against old and new backends alike.

### Centralized handling — `operationErrors`

The same token rides on `OperationError.failure.errorToken`, so a single
`chatAdapter.operationErrors` listener can localize every failure centrally
instead of branching at each call site:

```dart
chatAdapter.operationErrors.listen((e) {
  final key = e.failure.errorToken ?? 'generic';
  showGlobalSnackBar(l10n.errorFor(key));
});
```

---

## Cache

`HiveChatDatasource` wraps Hive CE. It is **enabled by default** — `NomaChat.create()`
builds one for you (after you call `Hive.initFlutter()`; see Setup). You don't
pass it in; you tune it through `create()` params, or you disable it:

```dart
// Default: bundled Hive cache, tuned via create() params.
final chat = await NomaChat.create(
  /* ...required params... */
  maxMessagesPerRoom: 500,
  messageTtl: const Duration(days: 30),       // auto-purge old messages on startup
  encryptionCipher: HiveAesCipher(key32),     // AES at-rest encryption (key is yours)
);

// Disabled: no-op in-memory store that discards data on restart.
final ephemeral = await NomaChat.create(/* ... */, enableCache: false);
```

### Building the datasource yourself

If you build a `ChatConfig` by hand (the `config:` escape hatch), construct the
datasource with `HiveChatDatasource.create()` (not `open()`) and wire it as
`localDatasource`:

```dart
final ds = await HiveChatDatasource.create(
  maxMessagesPerRoom: 500,
  maxRooms: 200,
  messageTtl: const Duration(days: 30),
  encryptionCipher: HiveAesCipher(key32),     // optional
);
final config = ChatConfig(/* ...urls/tokenProvider... */, localDatasource: ds);
```

### Backup and restore

`HiveChatDatasource` exposes a JSON-serialisable snapshot via `exportData()` /
`importData(Map)`. To use them you need a reference to the datasource, so build
it yourself and pass it as `localDatasource` (the bundled one created by
`NomaChat.create()` is not exposed):

```dart
final ds = await HiveChatDatasource.create();
final chat = await NomaChat.create(/* ...required... */, localDatasource: ds);

final snapshot = await ds.exportData(); // Map<String, dynamic>
await ds.importData(snapshot);          // replaces the current cache contents
```

---

## UI components — controllers

### ChatController

`ChatController` is a `ChangeNotifier` holding the live state of one room
(messages, typing, reactions, receipts, reply/edit, pagination). The adapter
**owns** the per-room instances — get one with `adapter.getChatController(roomId)`
rather than constructing it directly. Mutations go through the adapter's
`messages` controller; the `ChatController` reflects the resulting state.

```dart
// Get (or create) the room's controller — same instance ChatView uses.
final controller = chat.adapter.getChatController(roomId);

// Render with the lower-level ChatView (NomaChatView wires this for you).
ChatView(controller: controller, currentUser: chat.currentUser);

// Mark the room active (auto-marks as read when autoMarkAsRead is on).
chat.adapter.setActiveRoom(roomId);

// Send (optimistic; text is a required named param).
await chat.adapter.messages.send(roomId, text: 'Hello');

// React / un-react.
await chat.client.messages.addReaction(roomId, messageId, emoji: '👍');
await chat.client.messages.deleteReaction(roomId, messageId, emoji: '👍');

// Forward one message to several rooms.
await chat.adapter.messages.forward(
  sourceRoomId: roomId,
  messageId: messageId,
  targetRoomIds: [roomId1, roomId2],
);
```

The adapter disposes the controllers it owns (on `removeChatController` / facade
`dispose`); don't dispose an adapter-owned controller yourself.

#### Reading forwarding metadata — `ForwardInfo`

A forwarded message has `messageType == MessageType.forward`.
`ChatMessage.forwardInfo` extracts the origin (sender, source room, source
message id) from the message's `metadata`, falling back to the message-level
`from`/`referencedMessageId` fields when the backend didn't populate the
metadata keys — the host never needs to parse `metadata` directly:

```dart
final info = message.forwardInfo; // null when messageType != forward
if (info != null) {
  final label = 'Forwarded from ${displayNameFor(info.forwardedFrom)}';
  return ForwardedBubble(
    sourceLabel: label,
    theme: theme,
    child: TextBubble(text: message.text ?? '', isOutgoing: isOutgoing, timestamp: message.timestamp, theme: theme),
  );
}
```

`ForwardInfo.forwardedFromRoom` and `forwardedMessageId` let a host build a
"jump to original" action; the SDK does not provide that navigation itself
since it depends on the host's room-opening flow.

> **No E2EE, including on forwards.** `noma_chat` has no end-to-end
> encryption (see "What the SDK does *not* guarantee" in `SECURITY.md`) — the
> backend can read every message body to support moderation, push previews
> and search. Forwarding does not change this: the forwarded copy is plain
> content on the wire and at rest, identical in that respect to an original
> send. If a host app layers its own E2EE on top, it is also responsible for
> re-encrypting the payload for the new room's recipients on forward — the
> SDK has no hook for that and treats `text`/`metadata` as opaque.

### RoomListController

Manages the full room list. The SDK owns a `RoomListController` — get it from
the facade (`chat.roomListController`); its lifecycle is managed for you, so do
**not** dispose it yourself. Invitation actions are `RoomListView` callbacks,
each receiving the tapped `RoomListItem` (`item.id` is the room id):

```dart
RoomListView(
  controller: chat.roomListController,
  // Drives own-message ticks and the "You:" prefix in group previews.
  currentUserId: chat.adapter.currentUser.id,
  onAcceptInvitation: (item) => chat.adapter.rooms.acceptInvitation(item.id),
  onRejectInvitation: (item) => chat.adapter.rooms.rejectInvitation(item.id),
)
```

---

## UI components — widgets

### NomaChatView

`NomaChatView` is the recommended drop-in for a single chat room. It wraps a
`ChatRoomAppBar` + `ChatView` and auto-wires every piece of room-entry logic a
host would otherwise reimplement, with WhatsApp-parity defaults. Pull the
`adapter` straight from the facade:

```dart
NomaChatView(
  roomId: room.id,
  adapter: chat.adapter,
  title: room.displayName,
  onAppBarTap: (room) => openRoomInfo(room),
  onRoomLeft: () => Navigator.of(context).maybePop(),
)
```

The only required arguments are `roomId` and `adapter`. On mount the widget
marks `roomId` as the foregrounded conversation (so incoming messages
auto-mark read) and clears it on dispose.

**The seven behaviors it auto-wires** (each overridable):

1. **History + pin load** — calls `messages.load` / `messages.loadPins` for the room.
2. **Unread divider snapshot** — freezes the open-time unread boundary before mark-as-read clears it (WhatsApp parity; later arrivals don't move it).
3. **Group member hydration** — fetches the member list and pushes real names/avatars into the controller so group sender labels and @mention autocomplete resolve. Best-effort; toggle with `hydrateGroupMembers: false`.
4. **Blocked + room-removed reactions** — rebuilds when the blocked-user set changes and pops (or calls `onRoomLeft`) when the room is removed under it (local user left/blocked, or the peer deleted the room).
5. **Role-aware context menu** — the bubble long-press menu hides `pin` when the current user lacks permission (owner/admin in any room; either member in a 2-person DM) so a tap never triggers a 403.
6. **Report dialog** — long-press → Report opens the bundled `ReportMessageDialog` and posts `messages.report`. Customize the field placeholder with `reportReasonHint`, or replace the whole flow via `callbacks.onReportMessage`.
7. **Reaction-detail user fetcher** — resolves reactor profiles (cache-first, then `users.get`) for the reaction-detail sheet.

#### Customizing

Everything composes *over* the auto-wired defaults — any non-null override you
pass wins, the rest keep the sensible behavior.

| Argument | Type | Purpose |
|---|---|---|
| `theme` | `ChatTheme?` | Visual theme. Defaults to `ChatTheme.defaults`. |
| `builders` | `ChatViewBuilders?` | Override `ChatView` builder/resolver slots (avatar, system message, header, link preview…). Merged over the defaults. |
| `callbacks` | `ChatViewCallbacks?` | Override `ChatView` callbacks (send, edit, delete, react, report, image tap, context-menu action…). Merged over the defaults. |
| `behaviors` | `ChatViewBehaviors?` | Override computed behaviors (mentions, reaction set, recording limits, read receipts…). Non-default fields win. |
| `appBarActions` | `List<Widget>?` | Trailing icons appended to the default app bar (e.g. refresh, overflow). Ignored when `appBarBuilder` is set. |
| `appBarBuilder` | `ChatAppBarBuilder?` | Replace the entire app bar: `(context, room, controller) => PreferredSizeWidget`. |
| `onAppBarTap` | `void Function(RoomListItem?)?` | Tap on the default app bar's title row (typically opens room/user info). |
| `onRoomLeft` | `VoidCallback?` | Invoked when the room is removed under the view. Defaults to `Navigator.maybePop`. |
| `contextMenuActionsResolver` | `ContextMenuActionsResolver?` | `(room, defaults) => Set<MessageAction>` — add/remove actions on top of the role-aware defaults. |
| `hydrateGroupMembers` | `bool` | Fetch + hydrate group members (default `true`). |
| `initialMessageId` | `String?` | Message to scroll to and highlight on mount (search / pinned-row target). |
| `reportReasonHint` | `String?` | Placeholder for the report dialog's reason field. |

Example — add a custom context-menu action and an image viewer while keeping
every default:

```dart
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  reportReasonHint: 'Why are you reporting this?',
  contextMenuActionsResolver: (room, defaults) =>
      {...defaults, MessageAction.replyInThread},
  appBarActions: [
    IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
  ],
  callbacks: ChatViewCallbacks(
    onTapImage: (message) => openImageViewer(message),
    onContextMenuAction: (message, action) {
      if (action == MessageAction.forward) openForwardSheet(message);
    },
  ),
)
```

#### ReportMessageDialog

The report flow uses `ReportMessageDialog` — a single free-text reason field
with a Cancel / Report pair (Report stays disabled until a non-empty reason is
typed). It is reusable on its own; `show` resolves to the trimmed reason or
`null` on cancel:

```dart
final reason = await ReportMessageDialog.show(context, theme: theme);
if (reason != null) {
  await chat.client.messages.report(roomId, messageId, reason: reason);
}
```

#### MessageInfoSheet

The "Message info" sheet (WhatsApp's long-press → Info) lists which members
**read** a message and which were only **delivered** it. `NomaChatView` wires
it automatically: `MessageAction.info` is in the default context-menu set and
appears only on the user's own (outgoing) messages. Reach for the widget
directly only in a custom chat screen:

```dart
MessageInfoSheet.show(
  context,
  message: message,
  currentUserId: chat.adapter.currentUser.id,
  loadReceipts: () async =>
      (await chat.adapter.messages.loadReceipts(roomId)).dataOrNull ?? const [],
  displayNameFor: chat.adapter.displayNameFor,
);
```

It classifies the room receipts (`getRoomReceipts`) against the message's
timestamp via the `readersFor` / `deliveredTo` helpers (read implies
delivered, so the "Delivered to" section lists only the not-yet-read
remainder). Pass `leadingBuilder` to render avatars next to each name.

### Core screens

| Widget | Purpose |
|---|---|
| `NomaChatView` | Drop-in single-room screen — app bar + `ChatView` + the seven room behaviors auto-wired (recommended) |
| `ChatView` | Full chat screen with input, bubble list, app bar |
| `RoomListView` | Paginated room list with unread badges, mute/pin/hide options |
| `GroupSetupPage` | Multi-step group creation flow |
| `GroupInfoPage` | Edit group name, avatar, add/remove/promote members |
| `ProfileSettingsPage` | User profile with avatar picker + crop |
| `MediaGalleryPage` | Scrollable gallery of all room attachments |
| `MessageSearchView` | Full-text message search with result highlighting |

### Message search — room-scoped vs global

`messages.search(query, roomId: roomId)` scopes full-text search to one room;
the client-side dartdoc on `ChatMessagesApi.search` states that omitting
`roomId` searches globally across every room the caller belongs to. The
`MessageSearchController` + `MessageSearchView` pair is **room-scoped only**
— its `searchFn` signature takes a `roomId` positionally, so it is built to
back the in-room search UI (long-press → "Search in chat"), not a global
search screen.

Room-scoped, via `MessageSearchView`:

```dart
final controller = MessageSearchController(
  searchFn: (query, roomId, {pagination}) =>
      chat.client.messages.search(query, roomId: roomId, pagination: pagination),
);

MessageSearchView(
  controller: controller,
  roomId: roomId,
  onMessageTap: (roomId, messageId) => jumpToMessage(roomId, messageId),
  senderNameResolver: chat.adapter.displayNameFor,
);
```

Global search has no dedicated controller or widget — call the sub-API
directly with `roomId` omitted and render the `ChatPaginatedResponse<ChatMessage>`
with your own list:

```dart
final res = await chat.client.messages.search('flutter'); // no roomId
switch (res) {
  case ChatSuccess(:final data):
    renderResults(data.items); // see caveat below before grouping by room
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

> **Caveat — no room correlation on hits.** The bundled
> `doc/chat-api-openapi.yml` now confirms the global form: `roomId` on
> `/messages/search` is optional, and omitting it spans every room the
> caller belongs to (scope resolved server-side from membership). However
> `ChatMessage` has no `roomId`/`conversationId` field, so a global-search
> response gives you no built-in way to tell which room each hit belongs
> to; a UI would need the backend to echo the room id in `metadata` to
> group results per-conversation. See `ISSUES.md`.

### Bubble types

`MessageBubble` dispatches to the appropriate sub-widget based on `ChatMessage.type`:

| Type | Widget |
|---|---|
| Text | `TextBubble` |
| Image | `ImageBubble` |
| Audio | `AudioBubble` |
| Video | `VideoBubble` |
| File | `FileBubble` |
| Link | `LinkPreviewBubble` |
| Location | `LocationBubble` (opens Google Maps by default) |

### Input area

`ChatView` renders a `MessageInput` that includes:
- Text field with @mention autocomplete
- Send button
- Attachment picker sheet (photos, videos, files, location, custom slots)
- Voice recorder with lock-to-record gesture and waveform preview

### Auxiliary widgets

| Widget | Purpose |
|---|---|
| `ChatRoomAppBar` | WhatsApp-style app bar with room title, subtitle, avatar and action menu |
| `QuickRepliesBar` | Horizontally scrollable chips for quick reply suggestions |
| `TypingIndicator` | Animated three-dot bubble |
| `PinnedMessagesBanner` | Tappable banner showing the latest pinned message |
| `ReactionBar` | Per-message emoji summary strip |
| `ReactionPicker` | Full emoji picker sheet |
| `SwipeToReply` | Swipe gesture that sets reply context on the input |
| `ThreadView` | Inline thread reply list |
| `DateSeparator` | Sticky date labels between message groups |
| `MessageStatusIcon` | Sent / delivered / read ticks |
| `UserAvatar` | Network image with fallback initials |

---

## Customization hooks

### isDmRoom

Controls which `oneToOne` rooms are treated as DMs (affects contact-to-room routing, typing indicators, and the lazy DM creation flow):

```dart
isDmRoom: (RoomDetail detail) =>
    detail.type == RoomType.oneToOne &&
    detail.custom?['type'] == 'dm',
```

Omit to use the default: any `RoomType.oneToOne` room is a DM.

### RoomTitleResolver

Controls what title is displayed in `RoomTile`, `ChatRoomAppBar` and anywhere
else that reads `RoomListItem.displayName`. It is a plain function —
`String? Function(RoomTitleContext context)` — passed directly to
`NomaChat.create`/`fromClient`, not a named-constructor object:

```dart
roomTitleResolver: (context) {
  if (context.isDm) {
    return context.otherMembers.firstOrNull?.displayName;
  }
  return context.detail?.name;
},
```

Return `null` to opt out for a given room and let the SDK apply its default
(other member's name for DMs, `room.name` for groups) — a resolver does not
have to handle every case itself.

Common use cases beyond the basic DM/group split:

```dart
roomTitleResolver: (context) {
  // 1. Nickname book — override the DM title with a locally-stored
  //    contact nickname when the user has set one, otherwise fall back
  //    to the SDK default.
  final otherId = context.otherMembers.firstOrNull?.userId;
  final nickname = otherId != null ? nicknameBook.get(otherId) : null;
  if (nickname != null) return nickname;

  // 2. Role-based titles in a support/contact-center style room —
  //    show the customer's name to agents, and "Support" to the
  //    customer, using room `custom` metadata set by the backend.
  final role = context.detail?.custom?['viewerRole'] as String?;
  if (role == 'agent') {
    return context.otherMembers.firstOrNull?.displayName ?? 'Customer';
  }
  if (role == 'customer') return 'Support';

  // 3. Group title before the member list resolves — RoomDetail may
  //    still be null right after a room is created; fall back to a
  //    provisional label instead of showing a blank tile.
  if (context.detail == null && !context.isDm) {
    return context.currentItem.name ?? 'New group';
  }

  return null; // opt out — let the SDK default apply
},
```

`context.currentItem` already carries whatever `name`/`subject` the row was
last hydrated with, so a resolver that only wants to override *some* rooms
can read it instead of returning `null` and losing the current value.

### RoomTile builders

`RoomListView` accepts per-slot builder overrides:

```dart
RoomListView(
  controller: controller,
  leadingBuilder: (context, room) => MyCustomAvatar(room),
  trailingBuilder: (context, room) => MyBadge(room.unreadCount),
  subtitleBuilder: (context, room) => MyPresenceRow(room),
  lastMessagePreviewBuilder: (context, message) => MyPreview(message),
  typingUserNameResolver: (userId) => contactBook.getName(userId),
)
```

### AttachmentPickerSheet — extra slots

Add custom options to the attachment picker:

```dart
ChatView(
  controller: controller,
  attachmentPickerExtraOptions: [
    AttachmentPickerOption(
      icon: Icons.location_on,
      label: 'Location',
      onTap: () => myLocationPicker(),
    ),
  ],
  onShareLocation: (context) => myLocationPicker(),
)
```

### ChatRoomOption factories

Build action menus from predefined factories or custom entries:

```dart
ChatView(
  controller: controller,
  roomOptions: [
    ChatRoomOption.muteRoom(controller),
    ChatRoomOption.pinRoom(controller),
    ChatRoomOption.searchMessages(controller),
    ChatRoomOption.mediaGallery(controller),
    ChatRoomOption.reportUser(controller, onReport: (userId) { ... }),
    ChatRoomOption.custom(
      label: 'Export chat',
      icon: Icons.download,
      onTap: () => exportChat(),
    ),
  ],
)
```

`ChatRoomOption.muteRoom` is duration-aware: it shows a `MuteDurationSheet`
(8h / 1 week / always) on tap and reports the chosen expiry. Wire it with the
two calls — the SDK owns the picker:

```dart
ChatRoomOption.muteRoom(
  l10n: l10n,
  muted: room.muted,
  onMute: (until) => adapter.rooms.mute(roomId, until: until),
  onUnmute: () => adapter.rooms.unmute(roomId),
);
```

`ChatRoomOption.archiveChat` / `unarchiveChat` map to `adapter.rooms.hide` /
`unhide`; archived rooms surface in the collapsible **Archived** section that
`RoomListView` renders automatically (see below).

### Starred messages

Per-user message bookmarks. `MessageAction.star` is in `NomaChatView`'s default
context menu; tapping it calls `adapter.messages.star(roomId, messageId)`.
Render the bookmarks with `StarredMessagesView`:

```dart
StarredMessagesView.fromAdapter(
  chat.adapter,
  onOpen: (s) => router.openRoom(s.roomId, highlight: s.messageId),
);
```

The `.fromAdapter` constructor loads `adapter.messages.loadStarred()`, resolves
room titles from the room list and unstars through the adapter. Use the primary
constructor (`load` / `onUnstar` / `onOpen` / `roomTitleFor` / `itemBuilder`) for
full control. Each entry is a lightweight `StarredMessage` (ids + `starredAt`).

### Mention badge & Archived chats

`RoomTile` shows an "@" badge when `RoomListItem.unreadMentions > 0` (populated
from the conversation listing and bumped in real time when an incoming message
tags the current user; cleared on read). `RoomListView` groups hidden rooms into
a collapsible **Archived** section automatically — no wiring needed beyond the
`hidden` pref. `RoomListController.archivedRooms` / `hasArchivedRooms` expose the
partition for custom layouts.

### Edit / delete windows

`ChatViewBehaviors.editWindow` (default 15 min) and `deleteWindow` (default 2
days) gate the edit / delete context-menu actions on the user's own messages —
once a message is older than the window the action is hidden (WhatsApp parity).
Pass `null` to disable a gate. The backend also enforces it: a late attempt that
slips through surfaces as a typed `EditWindowExpiredFailure` /
`DeleteWindowExpiredFailure` (subtypes of `ChatFailure`) so you can show a
tailored message instead of a generic "Forbidden".

### Location bubble

By default `LocationBubble` opens Google Maps when tapped. Override:

```dart
ChatView(
  controller: controller,
  onLocationTap: (lat, lng) => myMapSheet(lat, lng),
)
```

### MessageStatusIconBuilder

Replace the delivery-status icon (the WhatsApp-style ticks) per state. The
builder lives in `ChatBubbleTheme` and is consulted at both render sites:
the corner of outgoing bubbles and the last-message preview in the room
list.

```dart
typedef MessageStatusIconBuilder =
    Widget? Function(BuildContext context, MessageStatusIconData data);
```

`MessageStatusIconData` carries:

| Field | Type | Meaning |
|---|---|---|
| `state` | `MessageDeliveryState` | `sending` / `sent` / `delivered` / `read` / `failed` |
| `size` | `double` | Suggested icon height (14 in bubbles, 12 in the room-list preview) |
| `message` | `ChatMessage?` | The message the icon belongs to; `null` in room-list previews |

Return `null` to fall back to the SDK default for that state — partial
overrides are one switch case away:

```dart
theme: ChatTheme(
  bubble: ChatBubbleTheme(
    statusIconBuilder: (context, data) => switch (data.state) {
      MessageDeliveryState.read =>
          Icon(Icons.done_all, size: data.size, color: Colors.teal),
      MessageDeliveryState.failed =>
          Icon(Icons.sms_failed, size: data.size, color: Colors.orange),
      _ => null, // SDK default for sending / sent / delivered
    },
  ),
)
```

Notes:

- The failed icon keeps the bubble's tap-to-retry behavior even when
  overridden — the SDK wraps your widget with the retry gesture.
- Only `sent` / `delivered` / `read` reach the room-list preview
  (`sending` / `failed` are bubble-local states).
- Color-only tweaks don't need the builder: `statusColor`,
  `statusReadColor`, `statusPendingColor` and `failedIconColor` cover the
  default icons.

### AvatarStorage

Plug in your own storage backend for uploaded avatars:

```dart
NomaChat.create(
  ...
  avatarStorage: MyS3AvatarStorage(),
)
```

Implement `AvatarStorage` with `upload(Uint8List bytes) → Future<String>` (returns the public URL).

---

## Theming

Pass a `ChatTheme` to `ChatView` and `RoomListView`, or set it globally via your `MaterialApp`:

```dart
ChatView(
  controller: controller,
  theme: ChatTheme.branded(
    accent: Color(0xFF4F46E5),
    contrastingOnAccent: Colors.white,
  ),
)
```

### Factories

| Factory | Description |
|---|---|
| `ChatTheme.lightPreset()` | Full light theme with sensible defaults for every surface |
| `ChatTheme.darkPreset()` | Full dark theme |
| `ChatTheme.resolved(context)` | Picks light or dark based on `MediaQuery.platformBrightnessOf` |
| `ChatTheme.branded(accent:, contrastingOnAccent:)` | Derives ~12 accent slots (bubble, send button, badge, reply bar, audio cue…) from one colour |
| `ChatTheme.highContrast()` | WCAG-AAA preset — white-on-black with 7:1 minimum contrast |

### Sub-theme structure

```dart
ChatTheme(
  // Sub-themes
  bubble: ChatBubbleTheme(...),      // incoming/outgoing colors, radius, text style,
                                     // status tick colors (statusColor / statusReadColor /
                                     // statusPendingColor) + statusIconBuilder override
  input: ChatInputTheme(...),        // background, hint, send button, attachment icon
  roomList: ChatRoomListTheme(...),  // tile, unread badge, separator
  markdown: ChatMarkdownTheme(...),  // bold, italic, code, link styles

  // Cross-cutting flat slots
  backgroundColor: Color(...),
  primaryColor: Color(...),
  onPrimaryColor: Color(...),
  borderRadius: 12.0,
  // ... 140+ more fields
)
```

See the `ChatTheme` class documentation for the complete field reference.

---

## Localization

Seven locales ship out of the box:

```dart
MaterialApp(
  localizationsDelegates: const [
    ChatUiLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: [
    ...ChatUiLocalizations.supportedLocales,
    // your app locales
  ],
)
```

Supported: `en`, `es`, `fr`, `de`, `it`, `pt`, `ca`.

The SDK falls back to English when no delegate is registered. Widgets access strings through `ChatUiLocalizations.of(context)`.

### Custom strings

Register `ChatUiLocalizations.override(...)` in place of `delegate` to
customise individual strings while keeping the seven bundled locales. The
overrides layer on top of whichever locale is active:

```dart
localizationsDelegates: [
  ChatUiLocalizations.override(
    send: 'Submit',
    writeMessage: 'Write a message…',
  ),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
],
supportedLocales: ChatUiLocalizations.supportedLocales,
```

To scope overrides to a single language, pass `locale:` and chain the
default `delegate` so the other locales keep their bundled copy:

```dart
localizationsDelegates: [
  ChatUiLocalizations.override(locale: const Locale('en'), send: 'Submit'),
  ChatUiLocalizations.delegate, // es/fr/de/it/pt/ca use bundled copy
],
```

Any of the 225 string fields can be overridden; unspecified ones keep the
bundled translation. `copyWith` is also available if you build a
`ChatUiLocalizations` instance directly.

---

## Testing

Import the testing barrel in your test files:

```dart
import 'package:noma_chat/noma_chat_testing.dart';
```

### MockChatClient

`MockChatClient` is a pre-built mock (Mocktail-based) that stubs all sub-API calls:

```dart
final mockClient = MockChatClient();
final chat = NomaChat.fromClient(
  client: mockClient,
  currentUser: testUser,
);

// Stub a call
when(() => mockClient.rooms.list()).thenAnswer((_) async => [testRoom]);

// Inject fake events
mockClient.injectEvent(NewMessageEvent(message: testMessage));
```

To simulate delivery ticks, emit the cursor events the backend would send —
a single `messageDelivered` flips every own message at-or-before the cursor:

```dart
// Single gray tick: the server acked the send (carries the seq).
mockClient.emitEvent(
  const ChatEvent.messageAcked(roomId: 'r1', messageId: 'm2', seq: 2),
);

// Double gray tick: bob's delivered cursor reached m2 (covers m1 too).
mockClient.emitEvent(
  const ChatEvent.messageDelivered(
    roomId: 'r1',
    userId: 'bob',
    messageId: 'm2',
    seq: 2,
  ),
);

// Outbound confirmations are recorded for assertions:
expect(mockClient.messages.markRoomAsDeliveredCalls, isNotEmpty);
```

### Fake adapter

For widget tests that don't need the full facade:

```dart
final adapter = FakeChatUiAdapter(currentUser: testUser);
adapter.injectRoom(testRoom);
adapter.injectMessage(testMessage);

testWidgets('shows message bubble', (tester) async {
  final controller = ChatController.fromAdapter(adapter, roomId: testRoom.id);
  await tester.pumpWidget(ChatView(controller: controller));
  expect(find.text(testMessage.text!), findsOneWidget);
});
```

### Integration tests with real backend

For integration tests against a real CHT instance, wire a real `NomaChat` with a test-environment URL and a fixture JWT. See [TESTING.md](../TESTING.md) for the full setup.

---

## Troubleshooting

### `MissingPluginException` / `HiveError: not initialized` on startup

`NomaChat.create()` does **not** initialise Hive for you. Call
`WidgetsFlutterBinding.ensureInitialized()` and `await Hive.initFlutter()`
(from `hive_ce_flutter`) **before** `NomaChat.create()`, or disable the cache
with `enableCache: false`. `Hive.initFlutter()` is itself idempotent, so calling
it once at app start is safe even if other code initialises Hive too.

### WebSocket connects but events never arrive

CHT requires a JWT in the first `auth` frame. Verify `tokenProvider` returns a non-expired token. Enable logging to see the auth frame:

```dart
config: ChatConfig(logger: ChatConfig.debugOnlyLogger)
```

### `ChatAuthException` on every API call

Ensure `tokenProvider` **throws** when the token cannot be refreshed. If it returns a stale token instead, the SDK retries indefinitely without surfacing an error.

### Messages not persisting after a cold restart

The cache is on by default. Make sure you did **not** pass `enableCache: false`,
and that you called `await Hive.initFlutter()` at startup — without it the boxes
fail to open and the SDK falls back to a no-op in-memory store.

### `Invalid argument(s): path must not be null` on web

Call `await Hive.initFlutter()` before `NomaChat.create()` (the SDK does not do
it for you). Ensure `hive_ce_flutter` is in your `pubspec.yaml` dependencies.

### Voice recording returns `permissionDenied` on Web

Voice recording is not supported on Web in this release (the recorder stages audio on the local file system). Use `kIsWeb` to hide the record button, or open a feature request.

### `ChatResult` / `ChatSuccess` types not found

You are on `noma_chat` pre-1.0. These types were renamed in the 1.0 release cycle. See [MIGRATING.md](../MIGRATING.md).

### `MockChatClient` not found after upgrading

Mock classes moved to a dedicated barrel. Import `package:noma_chat/noma_chat_testing.dart` in test files.

### Room list shows duplicate DMs after reconnect

The adapter deduplicates `oneToOne` rooms on reconnect using its contact-to-room index. If you see duplicates, verify that `isDmRoom` is consistent (same predicate on every `NomaChat.create()` call in the same session) and that your backend returns the same `roomId` for the same DM pair.
