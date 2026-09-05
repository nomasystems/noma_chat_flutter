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

  // How long the cache waits before reclaiming disk (defaults shown):
  orphanGracePeriod: const Duration(days: 7),        // rooms the server stopped listing
  unscopedCacheRetention: const Duration(days: 30),  // see Per-user scoping
);
```

`orphanGracePeriod` is how long a room must stay missing from authoritative room
listings before the cache destroys its local message history. Lengthen it if
your backend can omit rooms it still serves; the cost of shortening it is
history destroyed for a room that was only temporarily unlisted.

#### Per-user scoping

Every box the bundled cache opens is namespaced with a digest of
`currentUser.id`, so two accounts signing in on the same device get two disjoint
stores and a logout may keep the cache without leaking the previous user's
rooms, names or messages. Nothing to configure — `NomaChat.create()` passes the
id for you.

If you build the datasource yourself, pass it explicitly:

```dart
localDatasource: await HiveChatDatasource.create(userId: userId),
```

Omitting `userId` selects the pre-0.16 device-wide layout, which every account
on the device shares.

The box name carries `u_` plus a 32-character digest of the id, never the id
itself — an id has to be folded to fit a box name, and every fold merges
distinct ids (`a.b@x.com` and `a_b@x_com`; `Alice` and `alice`, since Hive
lower-cases box names), which would be one account handed another's store. The
practical consequence for a host: **no file on disk is named after a user**, so
deleting box files by hand on logout will not find them. Use the datasource's
own `clear()`.

Because the id derives the store's name, a blank or whitespace-only id is
rejected — both constructors throw `ArgumentError`. In 0.15 the id never reached
the cache and such a session opened normally. If you build a session before the
id is known, pass `enableCache: false` for it.

A store that turns out to belong to another account — the same namespace reached
by two ids, through a host that respelled its ids between releases or a backup
restored from another device — is destroyed before a single box of it is read.
If the destruction cannot be completed, `create()` throws a `StateError` instead
of returning a datasource that would serve the survivors to the signed-in user.
Nothing is claimed on that path, so a later launch tries again; treat it as any
other cache failure and retry, or open that one session with
`enableCache: false`.

##### Carrying the old local history over

A device upgrading from a pre-0.16 build still holds that device-wide store, and
**by default nothing is adopted from it**: the store carries no record of whose
it is, so the SDK will not guess. It is left untouched and reclaimed from disk
after `unscopedCacheRetention` (30 days); the user re-fetches their history from
the server.

If your app can never have had a second account signed in on the same install,
you can assert who that cache belongs to and it is moved into that user's
namespace:

```dart
final chat = await NomaChat.create(
  /* ...required params... */
  currentUser: ChatUser(id: userId, displayName: name),
  adoptUnscopedCacheFor: userId,   // "this device's old cache is userId's"
  unscopedCacheRetention: const Duration(days: 30),  // how long the old store waits
);
```

This is an assertion, not a hint. **If it is wrong, the named user inherits the
other person's rooms, contacts and message history and sees it as their own.**
Only pass it when the promise holds; the cost of omitting it is one re-fetch.

Resolution, given the `cacheOwner` stamp the store carries and your assertion:

| Stamp | `adoptUnscopedCacheFor` | Result |
|---|---|---|
| absent | omitted | not adopted, reclaimed after the retention window |
| absent | current user id | **adopted** |
| absent | another user id | not adopted, kept on disk for that user to adopt |

Those three rows are the whole decision in practice, because **the stamp is
always absent here**. Only a per-user store is ever stamped; nothing writes an
owner into the device-wide layout, in this release or any before it, so a device
upgrading from any build arrives at this table unstamped. The SDK does resolve
the stamped cases — a stamp naming the current user adopts, one naming somebody
else refuses, and it refuses even against an assertion that says otherwise,
because evidence written by the store outranks a declaration about it — but no
store a released build can leave on disk reaches them.

Whatever the answer, it is written into that user's own store as a migration
record, and **that record** is what stops the question being asked twice. The
`cacheOwner` stamp is a different thing: evidence of *whose* a store is, written
by every scoped store at creation and checked on every open — a store found
stamped for somebody else is destroyed rather than served. Neither is a
substitute for the other; a store can be stamped and still have never been
through the migration.

Starting to pass `adoptUnscopedCacheFor` in a later release is the one exception
to the once-only rule: a refusal recorded while you were passing nothing is
reopened when you start passing it, so a host that ships the scoping first and
the assertion second does not lose the history of everyone who launched in
between, as long as the retention window has not expired.

That reopen is also why **adoption merges rather than restores**. It runs
against a per-user store that has been live for a whole release, so the old
store fills in what the new one does not have and never writes over what it
does. Two consequences worth knowing:

- Contacts and invited rooms are stored as lists, not keyed by id, so each is
  carried over whole or not at all — and not at all once the user has a list of
  their own. Both are write-through caches of a server fetch, so nothing is
  lost that the next fetch does not restore.
- **The queue of unsent operations is never carried over.** Every other box
  holds state, which is merely stale when it is old; that one holds
  instructions, and nothing in an entry records when it was enqueued. Adopting
  it would hand a month-old send straight to the transport.

An adoption killed part-way through resumes on the next launch. The old store's
own meta box is the last thing the move removes, so for as long as any of it is
still on disk it is still findable — nothing is left stranded between the two
layouts.

Call `HiveChatDatasource.purgeUnscopedCache()` to reclaim the old layout
immediately instead of waiting the retention window out. If your store is
encrypted, pass the same cipher — the per-room boxes have no fixed names and are
found by reading room ids out of the global ones, so a missing or wrong cipher
silently leaves them on disk:

```dart
await HiveChatDatasource.purgeUnscopedCache(
  encryptionCipher: HiveAesCipher(key32),   // the one the old store was written with
  onWarning: (m) => debugPrint(m),          // the only signal a purge was partial
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
    localDatasource: await HiveChatDatasource.create(userId: userId),
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

### Observability — `metricCallback`

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

That one sink is also the whole OpenTelemetry story: an adapter is a few
lines you write against your own tracer, and writing it yourself is what
keeps the span naming yours.

```dart
config: ChatConfig(
  metricCallback: (metric, data) =>
      tracer.startSpan('noma_chat.$metric', attributes: attrs(data)).end(),
),
```

`attrs` is your own conversion from the event's `Map<String, dynamic>` to
whatever attribute type your OTel binding takes. Note what the shape
implies: these are instantaneous, point-in-time spans — started and ended
in the same statement, so start and end timestamps are identical. They are
observations, not measured durations; a metric that carries a duration
reports it as a field, which lands as an attribute.

> An earlier `noma_chat_otel` companion package did exactly this mapping
> with a fixed name table. It was removed in 0.17.0 — see the CHANGELOG —
> because it saved a handful of lines while making the names impossible to
> change without rewriting the callback anyway.

### Structured logging — `logSink` / `ChatLogger`

`ChatConfig.logSink` is an opt-in structured pipeline that sits alongside the
plain `logger` callback — wiring one does not disturb the other, and if you
never touch either, nothing is collected. Every subsystem (transports, cache,
attachments, presence, receipts, lifecycle, auth) logs through the shared
`ChatLogger` at `config.logs`, tagged with a `ChatLogTag` and leveled with
`ChatLogLevel` (`debug < info < warn < error`; default minimum is `warn`).

```dart
final buffer = BufferChatLogSink();
final config = ChatConfig(
  // ...baseUrl/realtimeUrl/tokenProvider...
  logSink: MultiChatLogSink([const ConsoleChatLogSink(), buffer]),
  logLevel: ChatLogLevel.info,
  logTags: {ChatLogTag.ws, ChatLogTag.connection, ChatLogTag.attachments},
);
```

Built-in sinks: `ConsoleChatLogSink` (routes to `debugPrint`, no-op in
release), `CallbackChatLogSink` (bridges to the legacy `logger` callback —
used automatically when `logSink` is left `null` and `logger` is set),
`BufferChatLogSink` (in-memory ring buffer, `capacity` records, oldest
dropped first) and `MultiChatLogSink` (fans out to several sinks; a
throwing sink never blocks its siblings).

**Exporting a shareable log file** — the classic "send me your logs" support
flow:

```dart
final path = await ChatLogExporter.exportToFile(buffer);
// hand `path` to a share sheet (share_plus, Share.shareXFiles, ...) —
// the SDK writes the file, the host presents the share UI.
```

**Message content is redacted by default.** `ChatConfig.logMessageContent`
defaults to `false`; call sites that would otherwise log raw message/caption
text go through `logs.content(text)`, which returns `<redacted:N chars>`
unless you explicitly opt in:

```dart
config: ChatConfig(
  logSink: buffer,
  logMessageContent: true, // only for a temporary diagnostics build (e.g. QA) — never production
),
```

Bring your own sink by implementing `ChatLogSink` (`add`/`flush`/`close`) —
e.g. to forward records to Crashlytics/Sentry/Datadog breadcrumbs.

**The UI adapter's own logger.** `ChatUiAdapter` (presence, signed
attachment re-minting, optimistic send, …) logs through its own `logs`
getter rather than `config.logs` — it bridges the plain `logger` callback
the same way, but respects its own `logLevel`/`logMessageContent`
constructor params. `NomaChat.create`/`fromConfig` forward `config.logLevel`
/ `config.logMessageContent` automatically, so a single `ChatConfig` still
governs both the SDK core and the UI adapter. `NomaChat.fromClient` (no
`ChatConfig` in scope) and a directly-constructed `ChatUiAdapter` take
`logLevel`/`logMessageContent` as their own parameters, defaulting to
`ChatLogLevel.warn` / `false` like `ChatConfig` does.

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

### App lifecycle — the SDK manages it by default

`ChatUiAdapter` (and therefore `NomaChat.create` / `.fromConfig` /
`.fromClient`, which all forward the params) registers its own
`WidgetsBindingObserver` and drives reconnect/disconnect on foreground/
background transitions — `manageAppLifecycle` defaults to `true`. Nothing to
configure for the WhatsApp-like default (stay connected in background,
reconnect + resync on resume):

```dart
final chat = await NomaChat.create(
  // ...
  // manageAppLifecycle: true is the default — omit it entirely for the
  // WhatsApp-like behavior below.
);
```

Pass `lifecyclePolicy: const ChatLifecyclePolicy.pushOptimized()` if your
push pipeline suppresses notifications while a realtime connection is open
and you want that suppression to lift promptly after backgrounding — it
disconnects `pauseGracePeriod` (default 3s) after pause instead of the
default `ChatPauseAction.keepAlive`:

```dart
final chat = await NomaChat.create(
  // ...
  lifecyclePolicy: const ChatLifecyclePolicy.pushOptimized(),
);
```

**If your app already has its own lifecycle/reconnect logic for chat,
remove it** — running both means two managers racing to `connect()` /
`disconnect()` the same adapter. To opt out entirely and keep driving
connect/disconnect yourself, pass `manageAppLifecycle: false`. Registration
is best-effort: it silently no-ops with no Flutter binding available (e.g.
an adapter built in a plain `test()`), so it never breaks a host or an
existing test suite.

#### `resync()` — backfilling after a reconnect

`adapter.resync()` does a full post-reconnect catch-up: room list
`forceNetwork: true` plus the foregrounded room's messages. It is a no-op
until the adapter's first `loadRooms` has completed (nothing to resync for
a session that hasn't bootstrapped yet), and it fires automatically on
every fresh reconnect when `enableReconnectResync` is `true` (the
`ChatUiAdapter`/`NomaChat.create` default), debounced to at most once every
5 seconds so a flappy connection can't double-resync. Call it yourself only
if you disabled `enableReconnectResync` and want to drive resync from your
own connectivity signal:

```dart
await chat.adapter.resync();
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

#### Deep-linking a room — `adapter.rooms.open`

Use `adapter.rooms.open(roomId)` instead of `adapter.getChatController(roomId)`
when the room might not be in the local list yet — a push notification or a
shared link pointing at a room that hasn't synced locally. Unlike
`getChatController` (which never fails but also never fetches), `open` hits
the network when the room is unknown and returns a typed failure your host
can branch on:

```dart
final result = await adapter.rooms.open(roomId);
switch (result) {
  case ChatSuccess(:final data):
    openChatScreen(data); // ready ChatController
  case ChatFailureResult(failure: NotFoundFailure()):
    showChatGoneMessage(); // really gone, or not a member
  case ChatFailureResult(failure: AuthFailure() || ForbiddenFailure()):
    promptReauth(); // session/permission — NOT "gone"
  case ChatFailureResult(failure: NetworkFailure() || TimeoutFailure()):
    showRetry(); // transient — don't tell the user the chat doesn't exist
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

Pass `fetchIfMissing: false` to restrict the lookup to the local list only
(no network round-trip; returns `NotFoundFailure` if absent).

When the client already knows the realtime channel is `disconnected`,
`open` fast-fails with a `NetworkFailure` instead of waiting out the full
`requestTimeout` (default 30s) on a REST call very unlikely to succeed —
`connecting`/`reconnecting`/`authenticating` still attempt the network
call, since a REST request can succeed independently of the WS state.

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

Each queued operation retries exactly once per drain, with exponential
backoff (capped, plus jitter) between attempts — the queue itself owns
re-enqueuing a failed retry; nothing else in the SDK enqueues a second copy
of the same logical send.

A photo/video/audio/file attachment enters the same queue when the
**upload** step fails with a failure that proves the bytes never arrived —
a `NetworkFailure`, or a `TimeoutFailure` whose `kind.isPreResponse`,
checked by `NomaChatClient.enqueueOfflineAttachment`, which is the same
predicate the equally non-idempotent text send applies. The queue only
exists when the host configured a cache (`cacheConfig`); without one there
is nowhere to persist the bytes and nothing is queued. `sendAttachment`/
`sendVoice` still mark the optimistic bubble failed immediately (nothing
changes visually), but the bytes + metadata are queued and the whole
upload+send is replayed automatically on reconnect. The bubble flips from
failed to sent via the same `onOfflineMessageSent` reconciliation as a
queued text send, keyed by the original `tempId`. A permanent failure
(validation, auth, forbidden, …) is never queued — there is nothing a
retry would fix. Neither is a `receive`-phase or `unknown` timeout:
`POST /attachments` carries no idempotency key and the server mints a
fresh `attachmentId` per call, so replaying an upload that may already
have landed would leave a duplicate blob behind. That bubble has no
automatic recovery left: it stays failed, `retrySend` on it is refused
(there is no blob to re-post), and the only way forward is the user
picking the file again.

When the upload lands but the **send** that follows it fails, the bubble is
marked failed carrying the blob that is already on the server:
`attachmentUrl`, `attachmentId` and the enriched metadata are written onto
the row (and onto its cached pending copy, which is updated as soon as the
upload resolves — before the send is even attempted, so a process killed
mid-send rehydrates a row that still knows its blob) before the failure
returns. A `messages.retrySend` on that bubble therefore re-posts the
uploaded attachment under the original `clientMessageId` — no second
upload, no orphan blob, and no duplicate message however many times it is
retried.
This is what makes a "retry the first message once the room exists" policy
safe on the four upload paths (voice, file, gallery, camera), not just on
text.

When the **upload** is what failed there is no blob to repost, and
`messages.retrySend` refuses the row rather than publishing an attachment
or voice bubble pointing at nothing — a message nobody can take back once
it is in the room. The call returns a `ValidationFailure` with
`errors['reason'] == 'attachment_never_uploaded'` and leaves the bubble
failed. A row counts as carrying a blob when any of `attachmentUrl`,
`attachmentId` or the `attachmentUrl`/`attachmentId` keys of `metadata`
holds a non-empty value, so a media message posted through
`messages.send` with the reference only in `metadata` still retries
normally.

The only way out of a refused row is picking the file again, and the
bundled UI says so by itself: `NomaChatView` mounts an
`OperationFeedbackListener` over `adapter.operationErrors`, which turns
that failure into a soft snackbar reading
`ChatUiLocalizations.attachmentNeverUploaded` in the view's own theme
language — a host rendering `NomaChatView` needs no wiring at all. A host
that wraps the view in its own listener and passes it `errors:` keeps that
one and only that one (the view sees the failures are covered and mounts
none); a host driving `ChatView` or `messages.retrySend`
directly reads the returned `ValidationFailure`, or routes the same
`reason` through its own `errorLabelBuilder`. Do not document it to the
user as "recovered automatically": that only happens for the queued case
above (a cache configured *and* a failure proving the bytes never left),
and there the queue replays the whole upload + send by itself, without the
user touching anything.

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

##### Caching the roster — one shape only

`members.list` also takes `cachePolicy`, but it is honoured **only for the
bare shape**: no `pagination` and no `expand`. Every other shape goes
straight to the network in both directions, whatever you pass — it is
neither read from nor written to the cache. One record per room cannot
answer "page 3" of a large group, and serving a bare cached roster to a
caller that asked for `expand: [users]` would blank every name and avatar it
was about to render.

So a "participants" screen that paginates or expands keeps behaving exactly
as before, while a plain roster read becomes instant on a warm start:

```dart
// Cached under `members:$roomId`, TTL `CacheConfig.ttlMembers` (12 h).
final res = await chat.client.members.list(
  roomId,
  cachePolicy: CachePolicy.cacheFirst,
);
```

The key is dropped on every local membership mutation (`invite`, `remove`,
`leave`, `updateRole`, `ban`, `unban` — not `muteUser`, whose flag does not
ride on `RoomUser`) and, when you use `ChatUiAdapter`, on every remote
`user_joined` / `user_left` / `user_role_changed` event.

##### Naming no policy is not the same as naming the default

`members.list` without a `cachePolicy` behaves exactly as it did before the
roster cache existed: it fetches from the network, and a failed fetch is a
`ChatFailureResult` — never the roster on disk. It deliberately does **not**
fall back to `CacheConfig.defaultReadPolicy` (`networkFirst`); that would
have turned every existing `fold(showError, render)` into "render a stale
roster, never show an error" without a line of your code changing.

The response is written through to the cache either way, so the disk-only
readers still find it there: the SDK's own hydration pass, and any
`CachePolicy.cacheOnly` read of your own. The offline fallback is one
argument away when you want it:

```dart
// Pre-cache semantics: the network answers, or the call fails.
final res = await chat.client.members.list(roomId);

// Opt in to the fallback: network first, disk when the network is down.
final res = await chat.client.members.list(
  roomId,
  cachePolicy: CachePolicy.networkFirst,
);
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

#### Sending to someone who blocked you

A block is invisible to the blocked sender, WhatsApp-style: they must not be
able to tell a rejected send from an ordinary one. The library owns that, and
the host must not undo it by painting a state of its own.

Every send path through the UI layer — `messages.send`, the first message of
a draft DM (both when creating the 1:1 room is refused and when the
contact-addressed fallback is), `messages.retrySend`, `sendAttachment`,
`sendVoice` and `forward` — swallows the server's `403 blocked` and returns
**success**. The row keeps `ReceiptStatus.sent`, no `OperationError` is
emitted, and the message is written to the local cache so it is still there
after a cold start. It is also pinned: no delivery cursor, fan-out or
per-user ack can ever advance it to ✓✓, because nobody received it.

Such a row carries `ChatMessage.silentlyDropped == true`. That flag is for
the library's own bookkeeping (and for hosts that need to reason about local
history) — **do not render a distinct state from it**. Showing "not
delivered", a warning icon or a retry affordance on those bubbles tells the
sender exactly what the product decided they must not learn.

The same applies one level down: `contacts.sendDirectMessage()` answers
`204 No Content` when the recipient blocks the sender, and the SDK
synthesizes a local `ChatMessage` with `ReceiptStatus.sent` and
`silentlyDropped: true` so the composer clears normally.

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
// Upload a file and send in one step (adapter helper — paints an
// optimistic bubble with live upload progress before the upload starts).
await chat.adapter.messages.sendAttachment(
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

#### Caption and reply — a photo answers like a text message does

`sendAttachment` takes a `caption` (published as the message text, painted
under the media by `ImageBubble` / `VideoBubble` / `FileBubble`) and a
`referencedMessageId` (the message being answered). `sendVoice` takes the
same `referencedMessageId`. Pass the composer's pending reply and close it
once the send resolves — read it *before* opening the picker, so a picker
the user cancels leaves the reply preview where it was:

```dart
final chatController = chat.adapter.findChatController(roomId);
final replyTo = chatController?.replyingTo?.id;

final pick = await AttachmentPickers.pickImageFromGallery();
if (pick == null) return; // the reply preview stays open

final sent = await chat.adapter.messages.sendAttachment(
  roomId,
  bytes: pick.bytes,
  mimeType: pick.mimeType,
  fileName: pick.fileName,
  caption: 'at the top of the hill',
  referencedMessageId: replyTo,
);
if (sent.isSuccess) chatController?.setReplyTo(null);
```

`NomaChatView` already does all of this on its own gallery, file, camera
and voice-note paths — the snippet is for a host that drives the pickers
itself. A quoted attachment paints the same quote strip a text reply does,
above the media; a voice note recorded with the reply preview open carries
the quote through `VoiceMessageData.referencedMessageId`.

An attachment that fails on a connectivity error and is replayed from the
**offline queue** keeps its quote too, not just its caption:
`ChatClient.enqueueOfflineAttachment` takes an optional
`referencedMessageId`, `PendingSendAttachment` (the queued operation)
carries it, and the replay path sends it when present — the same as a
manual `retrySend` on the failed bubble already did. Call it right after
the upload failure, passing the same `referencedMessageId` the failed
`sendAttachment`/`sendVoice` call was given:

```dart
client.enqueueOfflineAttachment(
  roomId: roomId,
  bytes: bytes,
  mimeType: mimeType,
  causeFailure: uploadFailure,
  referencedMessageId: replyTo,
);
```

#### Reviewing before sending — `AttachmentReviewPage`

The system picker confirms a *selection*, not a publication. Between the
picker and the send, `AttachmentReviewPage` shows what was chosen at full
size with a caption field under it and two ways out: back, which sends
nothing, and send, which returns every attachment with its own caption.
Multi-selection is paged, one caption per attachment.

```dart
final picks = await AttachmentPickers.pickMultipleMedia();
final reviewed = await AttachmentReviewPage.show(
  context: context,
  attachments: picks,
  theme: chatTheme,
);
if (reviewed == null) return; // the user backed out

for (final item in reviewed) {
  await chat.adapter.messages.sendAttachment(
    roomId,
    bytes: item.attachment.bytes,
    mimeType: item.attachment.mimeType,
    fileName: item.attachment.fileName,
    caption: item.caption,
  );
}
```

`NomaChatView` inserts this step by itself on the gallery and file rows.
The in-app camera has its own review step, `CameraCaptureReview`, which now
carries the same caption field (`allowCaption`, on by default):
`CameraCapturePage.show` returns a `CameraCaptureSubmission` with the
`capture` and the `caption`. The caption field's placeholder is the
`attachmentCaptionHint` string of `ChatUiLocalizations`, and both review
steps expose `chat_attachment_review_caption` /
`chat_attachment_review_send` / `chat_attachment_review_back` for UI tests.

#### `attachmentId` and re-minting an expired signed URL

`ChatMessage.attachmentId` is the stable id an attachment was uploaded
under. It travels through the full send path (REST, cache, offline queue,
WS-ack synthetic echo), so both the sender and the recipient can re-mint a
fresh signed download URL later instead of trusting a persisted one that
may have expired (`AttachmentPolicy`'s signed URLs are short-lived — see
"Downloading / displaying" above).

`SignedAttachmentUrlResolver` does this re-minting for you: it caches a
signed URL per `(roomId, attachmentId)` and re-mints when the cached entry
is close to expiring, falling back to `ChatMessage.attachmentUrl` (via
`attachmentIdFromUrl` for legacy messages predating this field) when no id
is available. `NomaChatView` wires it in **by default** — nothing to
configure for the common case:

```dart
NomaChatView(
  adapter: chat.adapter,
  roomId: roomId,
  // builders.attachmentUrlResolver defaults to
  // adapter.defaultAttachmentUrlResolver (a SignedAttachmentUrlResolver) —
  // override only for a custom CDN/proxy.
)
```

`AudioBubble` / `ImageBubble` / `VideoBubble` retry once through the
resolver on a load error (e.g. the persisted URL expired between render and
tap), so a received attachment self-heals without the host doing anything.

#### Upload progress — `ImageBubble` / `VideoBubble` / `FileBubble`

`ImageBubble`, `VideoBubble` and `FileBubble` each take an `uploadProgress`
(`ValueListenable<double>?`); while non-null they show a placeholder +
progress ring instead of resolving the (not-yet-usable) attachment URL, and
disable tap-to-open — the same contract `AudioBubble.uploadProgress`
already had. `NomaChatView` wires this **by default**: `ChatViewBuilders
.attachmentUploadProgressFor` defaults to
`ChatUiAdapter.attachmentUploadProgressFor` (the same registry
`sendAttachment`/`sendVoice` register into), so a photo/video/file upload
shows the ring out of the box — nothing to configure for the common case.
Supply your own `attachmentUploadProgressFor` on `ChatViewBuilders` only if
you need a different resolver (it wins over the default).

The ring itself is determinate and fills in
`ChatBubbleTheme.uploadProgressColor` (falls back to `statusReadColor`, then
`statusColor`, then to the same green as the send button / unread badge — the
read tick first, since both mark "it made it"), with an X centered on
top that cancels the upload — never the retry arrow, which only ever
belongs to a message that has actually failed (see below). `NomaChatView`
wires the X **by default** too: `ChatViewCallbacks.onCancelAttachmentUpload`
defaults to `ChatUiAdapter.cancelAttachmentUpload(messageId)`. Cancelling
removes the provisional bubble entirely — the user chose to abort, so
there's nothing to retry — rather than leaving it behind marked failed.
Supply your own `onCancelAttachmentUpload` only to change what cancelling
does; leaving it `null` on a bare `ImageBubble`/`VideoBubble`/`FileBubble`
(used outside `ChatView`) renders the ring without a tappable X instead of
a dead button.

The X and the ability to cancel share one lifetime: both end the instant
the bytes land. The **ring** does not — it stays up through everything a
send still has to do after that (a video's poster frame, then the message
itself), because until the send resolves the row carries no attachment URL
and a bubble out of the ring would resolve an empty one: a broken image, or
a video placeholder with a live play button that opens nothing.

Those are two signals, and `ChatViewBuilders` has one resolver for each:

| Resolver | Answers | Ends when |
|---|---|---|
| `attachmentUploadProgressFor` → `ValueListenable<double>?` | how full is the ring | the row has a real final state (sent, or failed) |
| `attachmentUploadCancellableFor` → `ValueListenable<bool>?` | is the X tappable | the bytes land — `cancelAttachmentUpload` can no longer abort anything |

`NomaChatView` defaults **both**, to `ChatUiAdapter.attachmentUploadProgressFor`
and `ChatUiAdapter.attachmentUploadCancellableFor` respectively — nothing to
configure for the common case. Override either on `ChatViewBuilders` (each
wins over its default independently) when you need your own resolver.

Cancellability is a *listenable* rather than a plain `bool` on purpose: it
flips in the middle of a ring's life, with nothing else changing that would
rebuild the row. Returning `null` from a wired resolver means "no send in
flight", the same as `attachmentUploadProgressFor`. A bare
`MessageBubble`/`ImageBubble` used outside `ChatView` that leaves
`attachmentUploadCancellable` unset keeps its `onCancelAttachmentUpload`
exactly as wired.

A failed upload does not render inside the ring at all: `uploadProgress`
becomes `null` once the upload settles. For `ImageBubble`/`VideoBubble`
that swaps the ring for `AttachmentFailedPlaceholder` — the same
blurred-media stand-in, now centered on `AttachmentRetryIcon` instead of
the progress ring. `FileBubble` has no separate media area, so it swaps its
leading file-type icon for the same `AttachmentRetryIcon` instead. Tapping
the arrow calls the bubble's `onRetry` — `MessageBubble` forwards the exact
callback the status-row icon already used,
which `NomaChatView` wires by default through
`ChatViewCallbacks.onRetryMessage` to `adapter.messages.retrySend`. There
is no second retry path: the arrow fires the same retry a screen reader's
"Retry" custom action already triggers.

Uploading and failed are mutually exclusive, so the arrow can never appear
mid-upload. It also only appears when a retry can actually get anywhere.
`retrySend` refuses a media row whose bytes never reached the server — it
retains none, so there is nothing to re-drive and the only way forward is
picking the file again — and `MessageBubble` mirrors that rule: such a row
gets the same failed placeholder with a **static error glyph** instead of
the retry arrow, and keeps its metadata-row failed icon, whose tap surfaces
the localized "that file was never uploaded" notice through
`OperationFeedbackListener`. Passing `onRetry: null` to a bare
`ImageBubble`/`VideoBubble`/`FileBubble` does the same thing. Only when the
media does paint a **working** arrow does `MessageBubble` suppress the
metadata row's small failed-message icon, so the two never duplicate the
same tap target. Text and audio messages have no media area to paint an
arrow over, so they keep the status-row icon as their only retry
affordance.

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
// `onRejected` turns what used to be a silent drop (just a `warn` log
// line) into something the UI can react to.
final pick = await AttachmentPickers.pickImageFromGallery(
  policy: imagesAndDocsOnly,
  logger: (level, msg) => myLogger.log(level, msg), // logs the violation
  onRejected: (rejection) => showSnackBar(rejection.message),
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
policy for small tweaks.

##### Dangerous extensions — `deniedExtensions`

The generic "File" picker (`AttachmentPickers.pickFile`, wired to
`NomaChatView`'s File row) is **default-allow**: with no `allowedExtensions`
passed to the system picker, a user can pick anything, including a file
whose extension nobody thought to whitelist (`.xyz`, `.log`, `.md5`, a
proprietary export, …). What keeps that from also letting through an
OS-executable dropper is `AttachmentPolicy.deniedExtensions` — checked by
`validate()` ahead of `allowedMimeTypes` and the size cap, and applied at
both pick time and send time (`sendAttachment` re-validates by file name
too, so a host that builds `bytes` itself instead of going through
`AttachmentPickers` still gets the same floor).

```dart
// Defaults to AttachmentPolicy.defaultDeniedExtensions — exe, msi, bat,
// cmd, com, scr, pif, cpl, msc, apk, dex, sh, ps1, vbs, vbe, jse, wsf,
// wsh, reg, jar — every AttachmentPolicy (including `unrestricted` and
// `whatsappLike`) carries it unless a host opts out.
const noApks = AttachmentPolicy(
  deniedExtensions: {...AttachmentPolicy.defaultDeniedExtensions, 'ipa'},
);

// Disables the deny-list entirely — the host takes on the risk itself.
const noExtensionCheck = AttachmentPolicy(deniedExtensions: {});
```

A denied extension is reported through the same `onRejected` callback as
any other policy violation, under `AttachmentRejectReason.mimeNotAllowed`
(there is no separate reason — see the enum's dartdoc for why), so no host
`switch` over `AttachmentRejectReason` needs a new case to keep compiling.

Only a trailing token that looks like an extension is matched — up to eight
ASCII letters or digits — so `report.final version` carries no extension as
far as the deny-list is concerned. A file name whose tail *spells* a denied
extension without being one (`newsletter-acme.com`) is refused all the same:
nothing in the name separates a TLD from a DOS executable, and Windows runs
`.com` through `PATHEXT` whatever the bytes hold. Hosts that would rather
take that trade the other way drop the entry:
`copyWith(deniedExtensions: {...AttachmentPolicy.defaultDeniedExtensions}..remove('com'))`.

#### Surfacing a rejected pick — `onRejected`

#### Photo metadata is stripped for you

Every picked image is rebuilt from its pixels before it becomes an
`AttachmentPickResult`, so the **GPS coordinates and capture timestamp of a
photo never reach the other members of a room**. You do not have to opt in,
and there is no flag to keep them.

Two passes are needed because neither platform is covered by the other:

- `requestFullMetadata: false` is passed to every still-image pick. On iOS
  this skips fetching the source `PHAsset` and the JPEG comes back
  re-encoded without its EXIF block. On Android it changes nothing:
  `image_picker_android` copies EXIF from the source file unconditionally
  whenever it resizes (any `imageQuality < 100`), with no flag to suppress it.
- `ImageMetadataScrubber` then decodes the picked bytes and encodes a fresh
  file from the pixel buffer alone. Not one byte of the container the user
  picked reaches the output, which is what makes the guarantee structural
  rather than a list of segments somebody remembered to drop: EXIF, XMP,
  IPTC, JUMBF/C2PA, the ICC profile, embedded thumbnails, comments, and the
  MP4 a Motion Photo appends past the end of the picture are all absent for
  the same reason — they were never copied.

The rotation is baked into the pixels, so no orientation tag is written and
none is needed.

Colour is carried across the same way: as a value, never as bytes. The decoder
is not colour managed, so a Display P3 capture keeps its P3 numbers and needs a
profile for the receiver to read them by — and forwarding the source's would
reopen the channel the rebuild exists to close. So the source profile is parsed
only far enough to name the space, dropped with everything else, and the output
gets a profile the SDK **builds from published constants** (chromaticities, a
white point, a Bradford matrix, five transfer-curve parameters). What comes out
is a function of those constants and one enum value, and nothing else.

- A **Display P3** source is re-issued as a canonical 512-byte Display P3
  profile, which costs 530 bytes on a JPEG and about 310 on a PNG. Its
  colorant and tone-curve tags reproduce the profile Apple ships bit for bit.
- An **sRGB** source is left untagged, because untagged already means sRGB to
  every receiver and a redundant half-kilobyte on the most common photo in the
  world buys nothing.
- **Anything else** — Adobe RGB, Rec. 2020, ProPhoto, or a profile too
  malformed to read — is left untagged and **reported as such**. Those pixels
  are read as sRGB and reach the receiver oversaturated, the same as before;
  converting them would need a colour engine the SDK does not carry. Watch
  `colour_profile` in the metric if that matters to you.

**JPEG is re-encoded**, at quality 90 with 4:2:0 chroma — a second lossy
generation over whatever the picker already wrote, for roughly 20% more bytes
than a same-quality pass would cost.

Only JPEG and PNG are rebuilt; they are the two formats that can be written
back in the format they arrived in. A HEIC, WebP, GIF, video or PDF comes back
**untouched** under `unsupported_format`. So does a file the decoder cannot
read: corrupting someone's photo is a worse outcome than leaving metadata on
it, so a rare odd-but-valid picture stays sendable.

Untouched means the metadata is still on the file, so that outcome is not
silent. Every pass emits one `image_metadata_strip` metric on
`ChatConfig.metricCallback` — `outcome: stripped | not_stripped |
unsupported_format`, plus the format, the reason, and `colour_profile` saying
what the output actually carries. Wire the callback
(`NomaChat.create(metricCallback: …)`) and a photo that could not be cleaned
stops looking exactly like one that was. See
[TELEMETRY.md](../TELEMETRY.md). Nothing is collected when it is `null`, and a
callback that throws can never fail the send.

The work runs on a background isolate everywhere except web, where `compute`
has no isolate to move it to.

This applies to `pickFile` too, so a photo attached through the generic file
picker is covered as well, and to the avatar picker — pass
`AvatarPickerField(onMetric: …)` to see its outcome, which matters most on
desktop, where there is no native cropper to re-encode the pick afterwards.

Every `AttachmentPickers` method (`pickImageFromCamera`,
`pickImageFromGallery`, `pickVideoFromGallery`, `pickMultipleMedia`,
`pickFile`) takes an optional `onRejected: void Function(AttachmentRejection
rejection)`. It fires for a policy violation (`reason:
AttachmentRejectReason.tooLarge` / `.mimeNotAllowed`) as well as an
unreadable file (`.unreadable` — the plugin/platform failed to read it, a
distinct case from the user simply cancelling the picker, which still
returns `null`/an empty list with no callback at all). `rejection.message`
is a ready-to-show English string; a localized UI should instead build its
own from `rejection.reason` plus `ChatUiLocalizations.attachmentTooLarge` /
`.attachmentTypeNotAllowed` / `.attachmentUnreadable`.

`NomaChatView`'s built-in Camera/Gallery/File rows call `AttachmentPickers`
with `NomaChatView.defaultAttachmentPolicy` (or `NomaChatView.attachmentPolicy`
when you set it) and an `onRejected` that shows the rejection in a
`SnackBar` via `ChatUiLocalizations`, so a rejected pick is never silent
even with zero extra wiring. If your app wants a different policy (or a
different rejection UI), override the picker callbacks (they replace the
built-in row's action entirely, not just its icon):

```dart
NomaChatView(
  adapter: chat.adapter,
  roomId: roomId,
  callbacks: ChatViewCallbacks(
    onPickGallery: () async {
      final pick = await AttachmentPickers.pickImageFromGallery(
        policy: imagesAndDocsOnly,
        onRejected: (r) => showSnackBar(r.message),
      );
      if (pick != null) {
        await chat.adapter.messages.sendAttachment(
          roomId,
          bytes: pick.bytes,
          mimeType: pick.mimeType,
          fileName: pick.fileName,
        );
      }
    },
    // onPickCamera / onPickFile follow the same pattern.
  ),
)
```

There is no separate "attachment builder" hook for the sheet's layout —
extra picker entries (e.g. a location share button) are added via
`ChatViewBehaviors.attachmentExtraOptions`, documented under "Customization
hooks → AttachmentPickerSheet — extra slots" below; `AttachmentPolicy` only
governs validation.

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

### Dead-peer detection — the WS pong watchdog

A WebSocket left half-open by a NAT timeout or a mobile network handoff
("zombie" socket) never surfaces as an `onError`/`onDone` close, so nothing
tells the transport to reconnect — realtime events just silently stop
arriving. `WsTransport` guards against this: every `ping` (interval
`ChatConfig.wsPingInterval`, default 30s) arms a `ChatConfig.wsPongTimeout`
(default 10s); if the matching `pong` never arrives, the transport forces a
reconnect. It's on by default and verified safe against this backend (it
always answers `ping` with `pong`) — turn it off only against a backend you
know doesn't:

```dart
config: ChatConfig(
  wsPongWatchdogEnabled: false, // only if your backend never answers ping
),
```

Reconnect backoff after any WS drop (watchdog-triggered or not) is tunable
too — `wsMaxReconnectDelay` (default 60s, the backoff ceiling) and
`wsReconnectJitterMs` (default 1000, random jitter added to each attempt so
a fleet of clients reconnecting after an outage doesn't hit the backend in
lockstep). `RealtimeTransport.lastPongAge` exposes how long it's been since
the last pong, if you want to surface connection health in a debug overlay.

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
> needed to drive WhatsApp-style ticks. Frames attributed to the current user
> — the echo of their own `markAsRead`, fanned out to every one of their
> connections — never reach the tick: they say what *this* user read, not what
> anyone received. Their only effect is clearing the room's unread badge, so a
> read on one device converges on the others. The exception is a room with no
> members besides the user — the "message yourself" conversation
> (`ChatController.isSelfConversation`) — where they are the audience, so their
> own read is what turns the tick blue. Recognising such a room takes positive
> evidence that nobody else is in it — either a member list that was fetched and
> came back empty, or a room row reporting a single member — *and* a row that
> names no peer of its own: signing out or deleting an account drops that user
> from the room's member lists, so an ordinary DM the other side walked out of
> reports a single member too, and only the peer the row still remembers tells
> the two apart. `NomaChatView` pins both facts on open so the exception also
> holds for a host that opens rooms with `hydrateGroupMembers: false` and never
> lists members at all. That
> mark is rendered but never cached — it rests on the room being empty, and a
> stored receipt can never be lowered — so re-opening the room re-derives it
> from the user's own read cursor instead.

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

### What the SDK already surfaces for you

`NomaChatView` mounts an `OperationFeedbackListener` over both streams, so
a host that renders it gets the SDK's own snackbars with no wiring at all:
the pin / unpin / delete confirmations, plus the two failures a failed
bubble cannot express by itself — a moderation rejection, and a `retrySend`
refused because the file was never uploaded. Forwarding is confirmed the
same way for hosts that wire the action (it is not in the default context
menu — see `NomaChatView` below). Every string comes from
`ChatUiLocalizations` through the view's `theme`, so it is translated and
overridable; setting one to `''` suppresses that snackbar alone.

Two ways to take it over — either keeps you at exactly one snackbar per
event:

```dart
// Wrap the view in your own listener and the SDK mounts none.
OperationFeedbackListener(
  successes: chatAdapter.operationSuccesses,
  errors: chatAdapter.operationErrors,   // omit and the view covers failures
  theme: theme,                          // pass the same theme as the view
  labelBuilder: (context, event, theme) => myStrings.forKind(event.kind),
  child: NomaChatView(roomId: roomId, adapter: chatAdapter, theme: theme),
);

// Or switch it off and drive the streams from your own pipeline.
NomaChatView(
  roomId: roomId,
  adapter: chatAdapter,
  behaviors: const ChatViewBehaviors(showOperationFeedback: false),
);
```

`errors` is optional on that widget, and the view accounts for it: what it
checks is what your listener *shows*, not that it exists. Wrap the view
with both streams and the view mounts nothing; wrap it with `successes`
only and the view mounts a failures-only listener underneath, so your
success labels stay yours and the failures still get said — once. If you
want silence instead, that is `enabled: false` on your listener (it claims
the whole subtree) or `showOperationFeedback: false` on the view.

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
datasource with `HiveChatDatasource.create()` — the only constructor there is —
and wire it as `localDatasource`. **Pass the signed-in user's id**: `NomaChat.create()` does it
for you, but on this path nothing does, and a datasource built without one opens
the device-wide layout every account on the device shares.

```dart
final ds = await HiveChatDatasource.create(
  userId: userId,                             // scopes every box to this account
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
final ds = await HiveChatDatasource.create(userId: userId);
final chat = await NomaChat.create(/* ...required... */, localDatasource: ds);

final snapshot = await ds.exportData(); // Map<String, dynamic>
await ds.importData(snapshot);          // replaces the current cache contents
```

### Host user directory cache

Names resolved through `userDirectoryResolver` (see
[Customization hooks](#userdirectoryresolver--host-user-directory)) are
persisted so the very first frame after a cold start already has the names
it had yesterday, instead of a blank screen until the resolver answers
again. `HiveChatDatasource` implements the separate `HostUserStore`
interface (`saveHostUsers` / `getHostUsers` / `getHostUser` /
`clearHostUsers`, each keyed by `CachedHostUser(user: HostUser, updatedAt:
DateTime)`) in a Hive box scoped to the signed-in user, alongside the boxes
`Backup and restore` above covers.

A custom `ChatLocalDatasource` gets this for free by also implementing
`HostUserStore` — the adapter checks `cache is HostUserStore` at runtime and
persists only when it answers; one that does not implement it still works,
it just resolves names fresh from `userDirectoryResolver` every session
instead of caching them.

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

#### Cache-first loading — `mergeRooms`, and why the list never flashes empty

The adapter's own `loadRooms()` renders the local cache first, then
revalidates against the network in the background — you don't opt into
this, it is simply how `NomaChat.create()` behaves. The mechanism behind it
is `RoomListController.mergeRooms(incoming, {required authoritative})`, an
upsert-in-place alternative to `setRooms` (clear-then-refill):

- **Non-authoritative** (a cache read, or a best-effort background
  revalidation) only adds/updates rows — it never drops one it can't vouch
  for, so a partial or empty response can't blank a list that already has
  content.
- **Authoritative** (a full server snapshot) reconciles fully — drops rows
  missing from `incoming`, same end state as `setRooms` — but without ever
  exposing listeners to an empty list in between.
- **A totally empty `incoming` is always a no-op**, even when
  `authoritative` is `true` and `snapshotAt` is set — `mergeRooms` never
  clears a non-empty list from an empty response. A full wipe is,
  over the wire, indistinguishable from a transient backend blip that
  fails closed to an empty page rather than an outright error, and that's
  far likelier mid-session than the user genuinely losing every room at
  once. Genuine removals always arrive one at a time: a realtime event
  (`RoomLeft` / `RoomDeleted`), or a *partial* authoritative snapshot
  (non-empty `incoming` that omits some previously known rows).

`RoomEnricher.loadAll` (and, through it, `ChatUiAdapter.loadRooms` /
`ChatRoomsController.load`) additionally accepts `allowRoomRemoval`
(default `true`) to opt a caller *out* of the drop pass entirely, even on
its own foreground network response — used by the automatic
`_backgroundRevalidate` pass and by `resync()` (see below), both of which
run without the user having asked for a refresh and must never be the
thing that deletes a room on a flaky read. Only an explicit,
user-initiated pull-to-refresh keeps the default `true` and stays fully
authoritative.

Most hosts never call `mergeRooms` directly (the adapter uses it
internally); it's public for a host that maintains its own
`RoomListController` outside the adapter.

This is also why `adapter.disconnect()` defaults to `clearRooms: false` —
the room list, the foregrounded room's `ChatController`, and the DM
contact↔room binding all survive a disconnect, so backgrounding or a
connection blip never flashes the list empty; a subsequent `resync()` (see
above) backfills anything missed. Pass `disconnect(clearRooms: true)` for
the old eager-wipe behavior — `signOut()` / `dispose()` still always do the
full wipe internally.

#### `adapter.isTearingDown` — telling a wipe apart from a removal

A room list that goes empty looks, to a listener, exactly like "every room
you were in has just been removed". `adapter.isTearingDown` is the explicit
signal that says which one it was: it is `true` for the whole of a
`disconnect(clearRooms: true)` / `signOut()` / `dispose()` wipe — every
notification the wipe emits, not only the one that empties the list, because
a teardown keeps clearing (and notifying) after that — and `false` otherwise.

Read it *inside* the notification. For `disconnect(clearRooms: true)` and
`signOut()` the signal is only raised across the wipe itself and is `false`
again by the time the call returns, because the adapter deliberately stays
reusable — the next user can sign in on the same instance. `dispose()` is the
exception: there it stays `true` for good.

Anything that reacts to a room disappearing — leaving the room, popping its
route, showing "this conversation is no longer available" — must check it
first and stay put while it is `true`. `NomaChatView` already does, so
`onRoomLeft` never fires for a logout; a host that watches
`roomListController` itself has to do the same, or a sign-out will strand a
dialog on top of whatever screen it navigated to.

A view that was open when the wipe ran does not come back: the wipe disposes
the `ChatController` behind it, so `NomaChatView` records the teardown and
renders its neutral placeholder from then on rather than repainting against a
dead controller. Hosts navigate away on logout anyway; one that keeps the
route alive gets a spinner, not an exception.

It is a declared signal rather than an inference from the list going empty
on purpose: being removed from the only room you had empties the list too,
and that one is a real removal the host still has to hear about.

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
4. **Blocked + room-removed reactions** — rebuilds when the blocked-user set changes and pops (or calls `onRoomLeft`) when the room is removed under it (local user left/blocked, or the peer deleted the room). A session teardown that empties the room list is not a removal and does not leave — see `adapter.isTearingDown`.
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
| `onAppBarTap` | `void Function(RoomListItem?)?` | Tap on the default app bar's title row (typically opens room/user info). Left unset, the row is not a tap target at all — no ripple, no swallowed tap. |
| `onRoomLeft` | `VoidCallback?` | Invoked when the room is removed under the view. Never fires for a session teardown — `disconnect(clearRooms: true)`, `signOut()`, `dispose()` — including a leave already scheduled when the teardown starts (see `adapter.isTearingDown`). Defaults to `Navigator.maybePop`. |
| `contextMenuActionsResolver` | `ContextMenuActionsResolver?` | `(room, defaults) => Set<MessageAction>` — add/remove actions on top of the role-aware defaults. |
| `hydrateGroupMembers` | `bool` | Fetch + hydrate group members (default `true`). |
| `initialMessageId` | `String?` | Message to scroll to and highlight on mount (search / pinned-row target). |
| `reportReasonHint` | `String?` | Placeholder for the report dialog's reason field. |

Example — add context-menu actions and an image viewer while keeping every
default:

```dart
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  reportReasonHint: 'Why are you reporting this?',
  contextMenuActionsResolver: (room, defaults) =>
      {...defaults, MessageAction.replyInThread, MessageAction.forward},
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

> **`MessageAction.forward` is not one of the defaults**, which is why the
> example adds it explicitly. Choosing the target rooms is yours to decide,
> so the SDK leaves the tile out rather than painting one that closes the
> sheet and does nothing. Add it back as above and answer it in
> `onContextMenuAction` — typically with `MessageForwardSheet` and
> `adapter.messages.forward`, whose confirmation snackbar the bundled
> feedback listener then shows for you.

> **You rarely need `onTapImage`.** Left unset, `NomaChatView` already opens
> the built-in full-screen `ImageViewer` wired to the authenticated media
> loader. Attachment downloads are Bearer-protected, so an `ImageViewer`
> built from a URL alone renders the broken-image fallback — if you do
> override the callback, pass `mediaLoader` and `attachmentRef` too:
>
> ```dart
> ImageViewer(
>   imageUrl: message.attachmentUrl!,
>   mediaLoader: chat.adapter.defaultAttachmentMediaLoader,
>   attachmentRef: AttachmentRef(
>     roomId: roomId,
>     attachmentId: message.attachmentId,
>     fallbackUrl: message.attachmentUrl!,
>   ),
> )
> ```

> **`onTapVideo` is the one tap callback with no default.** The package
> bundles no video player, so playback is yours to provide — and until you
> do, the video bubble paints no play overlay: a thumbnail with a play
> button that swallows the tap is worse than a thumbnail. Wire the callback
> (`video_player`, a full-screen route, an external app — your call) and the
> overlay comes back. Re-mint the URL through
> `chat.adapter.defaultAttachmentUrlResolver` before handing it to a player,
> for the same expiry reason as `ImageViewer` above. The still behind the
> overlay is handled for you — see [VideoThumbnailer](#videothumbnailer).

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

**The hours, and why most rows have none.** The backend keeps a read cursor
and a delivered cursor per member, not a stamp per message: a row says "this
member's read cursor sits on message X, and it moved at T". So `T` is that
member's time *for the inspected message* only when their cursor points at
that very message — for anything older it is an upper bound and nothing
more. The sheet prints an hour exactly in that provable case; every other
row reads `No exact time` ("Sin hora exacta") rather than borrowing the
cursor's clock.

| Parameter | Default | What it does |
|---|---|---|
| `receiptTimeFormatter` | `HH:mm`, prefixed by the day when older than today | `String Function(BuildContext, DateTime)` |
| `receiptSubtitleBuilder` | `null` | Replaces the line under a name; return `null` to keep the default for that row |
| `showApproximateReceiptTimes` | `false` | Prints the honest upper bound ("By 10:05 at the latest") on the non-provable rows instead of the "no exact time" wording |

`MessageReceiptDetail` is what those overrides receive: `userId`, `kind`
(`MessageReceiptKind.read` / `.delivered`), `cursorAt` (the member's cursor
time) and `isExact` — plus `exactAt`, which is `cursorAt` only when it is
this message's own time and `null` otherwise. Print `exactAt`, never
`cursorAt`, unless the copy states the bound.

Strings: `receiptNoExactTime` and `receiptAtLatestTemplate` (`{time}`) on
`ChatUiLocalizations`.

#### DeliveryStatusLegendSheet

The consultable "what the checks mean" legend for the delivery ticks. The
natural entry point is the room menu, which lives in the host app, so the
SDK ships the surface and the host wires the entry:

```dart
ListTile(
  title: Text(ChatUiLocalizations.of(context).deliveryStatusLegendTitle),
  onTap: () => DeliveryStatusLegendSheet.show(
    context,
    theme: myChatTheme,
    isGroup: room.isGroup,
  ),
);
```

| Parameter | Default | What it does |
|---|---|---|
| `theme` | `ChatTheme.defaults` | Pass the chat's own theme so the glyphs in the legend are the glyphs on the bubbles (`bubble.statusIconBuilder` overrides are honoured) |
| `isGroup` | `false` | Appends the footnote spelling out that in a group both double-check states are claims about every member |
| `states` | sending → sent → delivered → read → failed | Which states to explain, in render order |
| `entryBuilder` | `null` | Replaces one row; return `null` to keep the default for it |
| `title` | `l10n.deliveryStatusLegendTitle` | Sheet title |

Embed `DeliveryStatusLegendSheet` directly for a different container (a
settings page, a dialog). Rows are named for drivers with
`deliveryStatusLegendSemanticsId(state)` →
`chat_delivery_legend_<state>`.

Strings: `deliveryStatusLegendTitle`, `statusSendingDescription`,
`statusSentDescription`, `statusDeliveredDescription`,
`statusReadDescription`, `statusFailedDescription` and
`deliveryStatusLegendGroupNote`. The row titles reuse the existing
`statusSending` … `statusFailed`, which is also what `MessageBubble` speaks
aloud in its semantic label.

### Core screens

| Widget | Purpose |
|---|---|
| `NomaChatView` | Drop-in single-room screen — app bar + `ChatView` + the seven room behaviors auto-wired (recommended) |
| `ChatView` | Full chat screen with input, bubble list, app bar |
| `RoomListView` | Paginated room list with unread badges; the long-press menu (mute/pin/mark read/delete) opens only once `onContextMenuAction` is there to answer it |
| `GroupSetupPage` | Multi-step group creation flow |
| `GroupInfoPage` | Edit group name, avatar, add/remove/promote members |
| `ProfileSettingsPage` | User profile with avatar picker + crop |
| `MediaGalleryPage` | Scrollable gallery of all room attachments |
| `CameraCapturePage` | The SDK's own camera (tap for a still, hold for a clip) with a WhatsApp-style review step before anything is sent |
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

#### Theming the search screen

`MessageSearchView` is a plain body widget — the host owns the `Scaffold`
and the `AppBar` around it, and themes those with its own design system.
Everything the SDK paints inside reads from `ChatTheme`'s flat
`messageSearch*` slots:

| Slot | Applies to | Falls back to |
|---|---|---|
| `messageSearchBackgroundColor` | Surface behind field + results | transparent (the host `Scaffold`) |
| `messageSearchFieldFillColor` | Query field fill (also turns `filled` on) | unfilled |
| `messageSearchFieldTextStyle` | Typed query text | ambient Material |
| `messageSearchFieldHintStyle` | "Search messages" placeholder | ambient Material |
| `messageSearchFieldCursorColor` | Caret | ambient `TextSelectionTheme` |
| `messageSearchFieldBorderColor` | Outline colour, idle and enabled. Focused widens the stroke and tints towards `messageSearchFieldCursorColor` (when set) so the ring stays visible | ambient input decoration |
| `messageSearchFieldBorderRadius` | Outline radius, stamped onto whichever border is in play — themed colour or the ambient one | Material default (4) |
| `messageSearchFieldIconColor` | Magnifier + clear button | ambient icon theme |
| `messageSearchResultTitleStyle` | Result row sender name | 14 / w600 |
| `messageSearchResultSnippetStyle` | Non-matching snippet text | 13 / grey 600 |
| `messageSearchResultHighlightStyle` | Matching substrings | the snippet style made bold |
| `messageSearchResultTimestampStyle` | Trailing timestamp | 11 / grey 500 |
| `messageSearchEmptyTextStyle` | "No results" copy | `emptyStateTitleStyle`, then 16 / grey 500 |
| `messageSearchProgressColor` | First-page spinner | `input.sendButtonColor` |

Every slot is `null` by default, so a host that themes none of them keeps
the look the widget has always had — and an unset slot really does defer to
the app: the query field never forces `filled: false` over an ambient
`InputDecorationTheme.filled`, and a radius set without a colour reshapes
whichever border your `InputDecorationTheme` already draws for that state
(idle, enabled, focused) instead of repainting it black or replacing its
shape. Setting `messageSearchFieldBorderColor` gives every state that
colour, *except* focused, which is deliberately not a repaint of enabled: it
draws a wider stroke and, when `messageSearchFieldCursorColor` is also set,
tints towards it — otherwise a themed border reads as "always the same
colour, never focused". Theming the ambient `InputDecorationTheme.focusedBorder`
directly still wins verbatim over this heuristic, for a host that wants
exact control over the focus ring.

The four built-in presets (`ChatTheme.lightPreset()`, `darkPreset()`,
`branded()`, `highContrast()`) already fill these slots, so the search
screen follows a preset the same way every other surface does. `branded`
tints only the accent-carrying ones (caret, match highlight, spinner) and
leaves the surfaces on the fallback chain.

```dart
MessageSearchView(
  controller: controller,
  roomId: roomId,
  theme: myTheme.copyWith(
    messageSearchBackgroundColor: Colors.white,
    messageSearchFieldFillColor: const Color(0xFFF5F5F5),
    messageSearchFieldBorderColor: const Color(0xFFE0E0E0),
    messageSearchFieldBorderRadius: BorderRadius.circular(12),
    messageSearchResultHighlightStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFFEA6D28),
    ),
  ),
);
```

#### Empty states of the search screen

`MessageSearchView` has three distinct empty states, each with its own
instrumentation identifier so a host (or an E2E suite) can tell them apart:

| Identifier | When | Copy |
|---|---|---|
| `chat_search_prompt` | Nothing typed yet | `ChatUiLocalizations.searchPromptEmpty`, or the `emptyPromptText` override |
| `chat_search_too_short` | Something typed, but shorter than `minQueryLength` | `ChatUiLocalizations.searchPromptTooShort(minQueryLength)`, or the `tooShortPromptText` override |
| `chat_search_empty` | A dispatched query returned nothing | `ChatUiLocalizations.noResults` |

`searchPromptTooShort` takes the minimum as an argument and substitutes it
into `searchPromptTooShortTemplate` (`'Type at least {count} characters'`),
so a host that raises `minQueryLength` gets copy that matches — never
hard-code the number into a translation. With `minQueryLength: 1` the
too-short state is unreachable by construction and never renders.

`GroupSetupPage` gates its member search the same way, on
`minSearchQueryLength` (default `RoomDefaults.minSearchQueryLength`), and
below that minimum it renders the same copy under the identifier
`chat_group_search_too_short` instead of silently falling back to the
contact suggestions.

#### Empty states of "Shared in this chat"

`MediaGalleryView`, `DocsListView` and `LinksListView` each render an
`EmptyState` with a title *and* a second line naming what will eventually
fill the tab — `noMediaSubtitle`, `galleryNoDocsSubtitle` and
`galleryNoLinksSubtitle`. The subtitle is styled with
`ChatTheme.emptyStateSubtitleStyle`; override any of the strings through
`ChatUiLocalizations.copyWith` or `ChatUiLocalizations.override`.

Translation coverage follows each title: `noMediaSubtitle` ships in all
twelve bundled locales, the docs and links subtitles in the seven whose
titles are translated (en/es/fr/de/it/pt/ca) — a translated subtitle under
an English title would read worse than neither.

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

### Keyboard behaviour

The SDK's own pages split into two groups, and the split is fixed — there is
no flag for it, because the two halves need opposite things:

| Page | `resizeToAvoidBottomInset` | Why |
|---|---|---|
| `StarredMessagesPage` | `false` | Nothing to type on the page |
| `MediaGalleryPage` | `false` | Nothing to type on the page |
| `ImageViewer` | `false` | Nothing to type on the page |
| `UserInfoPage` | `false` | Read-only profile |
| `CameraCapturePage` | `false` | No field; a shrinking viewfinder is never wanted |
| `GroupSetupPage` | default | Name / description / member search sit low in a scrollable form |
| `ProfileSettingsPage` | default | Name / about / email sit low in a scrollable form |
| `GroupInfoPage` | default | Inline name / description editing, at a scroll position the user chose |
| `NomaChatView` (room) | default | The composer is anchored to the bottom edge |

The first group draws the keyboard **on top**: the body keeps its full height,
so the content the reader is looking at is covered rather than squeezed into a
strip. The second keeps the Material default so the caret stays visible while
typing.

Hosts that embed the SDK's *views* (`ChatView`, `RoomListView`,
`StarredMessagesView`, `MediaGalleryView`, `MessageSearchView`,
`BlockedUsersView`) own the surrounding `Scaffold` and therefore own this
choice themselves. The same rule of thumb applies: pass
`resizeToAvoidBottomInset: false` unless the screen has a field below its
midpoint. When one single element has to clear the keyboard on an otherwise
fixed page, pad just that element — the pattern the SDK's own sheets use:

```dart
Padding(
  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
  child: confirmButton,
)
```

### Text selection & the iOS context menu

Every editable `TextField` the SDK owns — the composer, the message search
fields, the group/profile name and description fields, the report-message
reason field, the attachment caption — and the selectable body of a text
bubble render the Flutter-drawn `AdaptiveTextSelectionToolbar` for copy /
cut / paste / select-all, not the platform's native `SystemContextMenu`.

On iOS, `SystemContextMenu` can only be shown while the field's text input
connection is live. A route pushed, or a sheet opened, over a focused field
tears that connection down while the menu is still mounted, and the menu
then asserts on every subsequent frame — the screen keeps painting but stops
answering any gesture at all. Long-pressing a message while the composer
below it is focused is the everyday way to trigger this. Because every SDK
field sets its own `contextMenuBuilder` (see
`lib/src/ui/utils/text_selection_menu.dart`), none of them can ever build
`SystemContextMenu`, regardless of `MediaQuery.supportsShowingSystemContextMenu`.

One consequence: on iOS 16+, Apple's native Writing Tools entry — which only
ever appears inside `SystemContextMenu` — never shows up on an SDK field.
Copy, cut, paste, select-all and look-up remain available through the
Flutter toolbar.

A host that fully replaces an SDK field (e.g. a custom composer passed to
`ChatView`) is outside this guarantee and should apply the same
`contextMenuBuilder` if it can be focused underneath a pushed route or a
long-press sheet.

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

### membershipBannerFilter

Vetoes the SDK's own membership banners — "Alice joined", "Alice left",
"Alice is now an admin" — per room and per event:

```dart
membershipBannerFilter: (roomId, eventType) => isDirectMessage(roomId),
```

The predicate runs when a `user_joined` / `user_left` / `user_role_changed`
event arrives, just before the banner is composed. Returning `false` drops
that banner completely: it is not shown and, unlike a `systemMessageBuilder`
that renders nothing, it is not written to the local cache either, so it does
not reappear the next time the room is opened.

Omit it to keep every banner — that is what every consumer got before this
hook existed.

**When you need it.** Some backends post their own membership message into
the room, as a real message from the server. Those hosts render two rows for
one event: the server's and the SDK's. The filter turns the SDK's off exactly
where the server speaks, which is why it takes the room id: the same app
usually wants the banner kept in a one-to-one room, where nothing else
announces the change.

**Already-written rows stay.** The filter only decides what is minted from
now on. Banners cached before you turned it on are still in the local
database and still render; to see the effect, use a room the device has not
cached yet or clear the cache.

**What it does not switch off.** Suppressing the banner does not skip the
rest of the membership handling — the roster still refreshes and a room the
list did not know about is still added.

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

A string returned by `lastMessagePreviewBuilder` is taken as a finished
sentence: it is painted as-is, with no `"Alice: "` / `"You: "` sender prefix
in front of it. Name the actor inside your own text when the event calls for
it, and return `null` whenever you want the default WhatsApp-style preview
(prefix included) back.

### RoomTile swipe actions

Dragging a row sideways reveals a strip of buttons — a second, visible way
into the conversation actions, next to the long press (which keeps working
exactly as before). `RoomListView` builds the strip per row:

```dart
RoomListView(
  controller: controller,
  swipeActionsBuilder: (context, room) => [
    RoomSwipeAction(
      icon: room.muted
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      label: room.muted ? 'Unmute' : 'Mute',
      identifier: 'chat_row_swipe_mute',
      onPressed: () => toggleMute(room),
    ),
    RoomSwipeAction(
      icon: Icons.archive_outlined,
      label: 'Archive',
      backgroundColor: Colors.indigo,
      foregroundColor: Colors.white,
      onPressed: () => archive(room),
    ),
  ],
)
```

A bare `RoomTile` takes the same list directly as `swipeActions:`, so a host
that builds its own rows does not need `RoomListView` to get the gesture.

What the widget guarantees:

- **The swipe reveals, it never fires.** No action runs until its button is
  tapped — muting or archiving a conversation by brushing past it would be
  the wrong trade. The row closes on its own before `onPressed` runs, so the
  callback is free to push a route or open a sheet.
- **No actions, no change.** `swipeActionsBuilder` returning `null` or an
  empty list (and `RoomTile` built without `swipeActions`) yields the widget
  tree the row had before this existed: no gesture recognizer, no extra
  layer, no hit-test difference.
- **`side` defaults to `RoomSwipeSide.end`** — the trailing edge. `start` and
  `end` resolve against the ambient `Directionality`, so both sides mirror
  in RTL.
- **Leading-edge guard.** A drag born within 24 logical pixels of the
  leading edge — the left edge in LTR, the right one in RTL, which is where
  the platform back gesture lives — never pulls that side's actions into
  view. It can still close an open row and still open the other side. This
  is the reason the default side is the trailing one.
- **`identifier`** sets the button's semantics identifier, so integration
  drivers address it by name instead of by coordinates. It survives a host
  that wraps the tile in `MergeSemantics`.

`backgroundColor`/`foregroundColor` fall back to the ambient
`ColorScheme.secondaryContainer`/`onSecondaryContainer`. Each button is 76
logical pixels wide and its label is a single ellipsized line: pass a short
caption (`'Unmute'`, not `'Turn notifications back on'`).

### AttachmentPickerSheet — extra slots

Add custom options to the attachment picker:

```dart
NomaChatView(
  adapter: chat.adapter,
  roomId: roomId,
  behaviors: ChatViewBehaviors(
    attachmentExtraOptions: [
      AttachmentSheetOption(
        icon: Icons.location_on,
        label: 'Location',
        onTap: () => myLocationPicker(),
      ),
    ],
  ),
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

Once the mute is on, the expiry is read out, not just implied by the bell
icon: `RoomTile` adds a **"Muted until 01/01 18:30"** line under the preview
and `ChatRoomAppBar` appends it to its subtitle, both driven by
`RoomListItem.muteUntil` and localized through
`ChatUiLocalizations.mutedUntilTemplate` (`'Muted until {date}'`). A permanent
mute carries no expiry and renders the icon alone, as before. The deadline
travels in UTC and is printed in the device's zone.

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

### Unread counting excludes system messages

`RoomListItem.unreadCount` is server-authoritative: `GET` rooms returns
`unreadMessages` and the `UnreadUpdatedEvent` WS frame (`roomId`, `count`)
carries live deltas, both reconciled into the room list as-is. The client
only adds to that count locally, between reconciliations, when a `NewMessageEvent`
arrives for a room the user isn't currently viewing — and it skips that
local bump entirely for a message with `ChatMessage.isSystem == true`
(plan lifecycle notices, membership changes, …), so a room whose only
unseen activity is system messages never shows unread. The Messaggi-tab
badge (`RoomListController.unreadRoomCount`) and the row badge both read
`unreadCount`, so they inherit this for free. `NomaChatView`'s "N new
messages" divider (`resolveUnreadBoundary`) applies the same exclusion
independently, since it derives its own boundary from the loaded message
list rather than from `unreadCount`.

The very first event for a room the device doesn't know yet takes a
different path: `RoomEnricher.addFromDetail` fetches the room detail and
builds a brand-new `RoomListItem` around it, rather than updating an
existing one. That fresh row applies the same exclusion when seeding its
initial `unreadCount` — an unknown room's first message being a system
notice does not seed the row with a badge that the next reconciliation
would then have to clear.

This is a two-sided contract: the backend's own `unreadMessages` /
`UnreadUpdatedEvent.count` must already exclude system messages (messages
carrying `metadata.system == true` / `type == "system"`) for the two halves
to agree once `loadRooms` reconciles the server value. A backend that still
counts system messages will show a badge that briefly clears (the client's
local skip) and then reappears on the next room-list refresh.

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

### VideoThumbnailer

A video bubble needs a poster frame, and the backend is a pure blob store —
it never samples an uploaded clip. So the sending client is the only place
one can come from: `sendAttachment` extracts a frame, uploads it as a
**second, small blob with its own attachment id**, and stamps that id into
the message metadata. The receiving bubble downloads it through the same
authenticated media loader it uses for photos.

The default `NativeVideoThumbnailer` uses the platform decoder
(`MediaMetadataRetriever` / `AVAssetImageGenerator`) and is wired for you —
nothing to pass. Override it to route generation elsewhere:

```dart
NomaChat.create(
  ...
  videoThumbnailer: MyServerSideThumbnailer(),   // or const NoVideoThumbnailer()
)
```

```dart
class MyServerSideThumbnailer implements VideoThumbnailer {
  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) async {
    final jpeg = await myPipeline.posterFrame(videoBytes);
    return jpeg == null ? null : VideoThumbnailData(bytes: jpeg);
  }
}
```

Contract worth knowing before you plug something in:

- **Return `null`, never throw.** Generation is an enrichment: a video that
  arrives without a preview is a degraded success, one that fails to send
  because its preview failed is a bug. Every failure — unsupported platform,
  unreadable container, a failed thumbnail upload, or the whole step
  exceeding `RoomDefaults.videoThumbnailTimeout` — sends the clip anyway.
- **It runs only after the clip's own upload succeeded**, so a cancelled or
  failed send never reaches it, and the visible upload ring tracks the clip
  alone — the poster frame's few tens of kilobytes are deliberately outside
  it. The cancel X is already gone by the time generation starts; the ring
  itself stays, full, until the send resolves. See "Upload progress" above.
- **One budget, spent two ways.** `RoomDefaults.videoThumbnailTimeout`
  covers generation and the poster frame's upload together, but generation
  cannot observe a cancel token — a wedged platform decoder is only
  escapable by walking away from it — so it is bounded by abandoning it,
  while the upload is bounded by cancelling it. An upload that settles
  anyway, in the instant the deadline fires, is *used* rather than
  discarded: throwing away a POST that already succeeded is precisely how a
  blob nothing references gets created. A `signOut()`/`dispose()` in that
  window cancels the same token before the send is reached at all.
- **Android / iOS only by default** (`PlatformSupport.supportsVideoThumbnails`).
  Elsewhere the built-in returns `null` and bubbles keep the placeholder +
  play button; a host-supplied implementation is free to work everywhere.
- **Videos sent before this existed have no poster frame and never will** —
  they render exactly as they always did.

---

### In-app camera capture — the review step

On Android and iOS the composer's Camera row opens `CameraCapturePage`, the
SDK's own viewfinder (tap the shutter for a still, hold it for a clip).
`image_picker`'s system camera cannot do both from one entry point, which is
why this screen exists; `PlatformSupport.supportsInAppCameraCapture` gates
it and everywhere else falls back to `image_picker`.

**The shutter never sends.** Whatever it produces lands on
`CameraCaptureReview` — the still full-screen, the clip playable — with
three ways out:

| Control | What it does |
|---|---|
| **Send** (filled circle, bottom right) | Pops the capture back to the caller. The only path that sends. |
| **Retake** (bottom left) | Deletes this take and returns to the live viewfinder, camera still bound so the next shot is immediate. |
| **Discard** (✕, top left) | Deletes the take and leaves the screen, resolving `null` exactly like cancelling did. |

The system back gesture on the review is a **retake**, not an exit: backing
out of a take you just shot should not also close the camera.

Nothing on the page needs wiring — `NomaChatView` gets the review step with
zero configuration, and `_captureAndSend` only ever sees confirmed captures.
Unconfirmed ones are deleted by the page itself: the camera plugins write
into the app cache and nothing else ever collects it.

If you drive the screen yourself, `CameraCapturePage.show()` resolves to a
`CameraCaptureSubmission?` — the confirmed capture plus the caption typed on
the review step — `null` covering both "the user discarded it" and "the user
cancelled":

```dart
final submission = await CameraCapturePage.show(context: context, theme: myTheme);
if (submission == null) return;         // cancelled, or discarded on review
final shot = submission.capture;
await chat.adapter.messages.sendAttachment(
  roomId,
  bytes: await shot.file.readAsBytes(),
  mimeType: shot.mimeType,
  fileName: shot.fileName,
  caption: submission.caption,
);
```

**Swapping the clip preview.** Playback is `video_player`, wrapped in
`CameraVideoPreview` (tap to play, tap to pause, a finished clip restarts).
Replace it when your app already ships a player, or to avoid a second video
stack entirely:

```dart
CameraCapturePage.show(
  context: context,
  theme: myTheme,
  videoPreviewBuilder: (context, file, theme) => MyPlayer(path: file.path),
);
```

The builder only has to paint the clip — Send / Retake / Discard stay the
SDK's. It is never consulted for a still. A clip the platform decoder cannot
open falls back to a static placeholder rather than blocking the step, so a
capture whose preview failed can still be sent or thrown away.

Inside `NomaChatView` — which opens this screen itself from the composer's
Camera row — the same seam is `ChatViewBuilders.videoPreviewBuilder`:

```dart
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  builders: ChatViewBuilders(
    videoPreviewBuilder: (context, file, theme) => MyPlayer(path: file.path),
  ),
)
```

Wire it and nothing the SDK renders touches `video_player`; leave it unset
and `CameraVideoPreview` is used. A bare `ChatView` ignores the slot: it
never opens the camera.

**Theming and strings.** The review reads the same `cameraCapture*` slots as
the viewfinder, plus two of its own: `cameraCaptureSendButtonColor` (fill of
the Send button, default the send-green) and
`cameraCaptureReviewActionStyle` (the Retake label, falling back to
`cameraCaptureHintStyle`). Its labels are `ChatUiLocalizations.send`,
`.cameraRetake` and `.cameraDiscard`; the clip preview announces
`.playPreview` / `.pausePreview`.

### userDirectoryResolver — host user directory

Chat only knows the ids it was handed — a room's member list is a list of
opaque strings. Most hosts already have a users table of their own (name,
avatar, whether the account still exists), and `userDirectoryResolver` lets
that table answer instead of chat's own profile:

```dart
final chat = await NomaChat.create(
  ...
  userDirectoryResolver: (ids) async {
    final users = await myUsersApi.getByIds(ids);
    return {
      for (final u in users) u.id: HostUser(id: u.id, displayName: u.name, avatarUrl: u.photoUrl),
      for (final id in ids.difference(users.map((u) => u.id).toSet()))
        id: HostUser.missing(id), // no such user in our directory
    };
  },
  userDirectoryTtl: const Duration(hours: 12), // default
);
```

Contract: `userDirectoryResolver` is called in batches (several ids the SDK
needs at once, not one call per id); the map you return is keyed by the same
ids you were asked about. An id you leave out of the map is asked again
later — return `HostUser.missing(id)` instead when you have looked and there
really is nobody behind it, so the SDK stops asking. An exception is treated
as a transport failure and retried like any other lookup.

Names resolved this way feed the room title (`RoomTitleContext` for a DM
without its own name), the sender prefix on a bubble, avatars, and
membership banners — anywhere `ChatUiAdapter.displayNameFor` is the source.
Leave `userDirectoryResolver` unset and the SDK falls back to chat's own
profile store exactly as it always did.

**No id is ever painted as a name.** When neither the host directory nor
chat's own profile has a name for someone, every one of those surfaces
renders a blank instead of the raw id — a room full of UUIDs is worse than a
room full of blanks. A host that wants something in that gap (an initial, a
generic "Unknown") supplies it itself, from `displayName == null` or `''`.

Answers are cached to disk (see [Cache](#cache)) so the very first frame
after a cold start already has yesterday's names, and refreshed once
`userDirectoryTtl` elapses.

### bootstrapCurrentUser

`false` by default. When `true`, `connect()` asks chat for the signed-in
user's own profile (`users.get(currentUser.id)`) right after connecting and,
only if the answer is `NotFoundFailure`, creates it (`users.create()`). Any
other failure is logged and does not abort the connection. Turn it on for a
host whose backend never provisions the chat profile out of band; leave it
`false` — the 0.33 behaviour — for one that already does.

### sendRetryPolicy — retrying the first send after a draft materializes

A message typed into a brand-new 1:1 conversation is sent against a
client-side draft key before the room exists on the server; very
occasionally the send races the room's own creation and comes back
`NotFoundFailure` a moment too early. `sendRetryPolicy` re-polls the room
and retries that one send automatically:

```dart
NomaChat.create(
  ...
  sendRetryPolicy: const SendRetryPolicy.firstSendOnly(), // default
  // sendRetryPolicy: const SendRetryPolicy.none(), // 0.33 behaviour
)
```

`SendRetryPolicy.firstSendOnly()` backs off over three attempts (400ms,
900ms, 1500ms by default, configurable via `delays:`) and only ever applies
to a send whose destination was a draft key and whose failure was
"room not found" — an upload failure, a moderation rejection or any other
error is left for the user to retry by hand. The retry reuses the failed
row's own `tempId` as the idempotency key, so a first send that actually did
land on the server is never delivered twice; the bubble shows `pending`
while the retry runs and only flips to `failed` once every attempt in the
policy is exhausted.

### attachmentShrinker — outgoing image reduction

Every `AttachmentPickers` entry point (`pickImageFromCamera`,
`pickImageFromGallery`, `pickVideoFromGallery`, `pickMultipleMedia`,
`pickFile`) and the in-app camera shrink an outgoing image before it
uploads, so a full-resolution shot leaves the device as a few hundred KB
instead of a few MB:

```dart
AttachmentPickers.pickImageFromGallery(
  policy: const AttachmentPolicy(
    shrinkEnabled: true,             // default
    shrinkSteps: AttachmentPolicy.defaultShrinkSteps, // 3072px@85 … 1280px@60
  ),
  // shrinker: const DefaultAttachmentShrinker(), // the picker default
)
```

`AttachmentPolicy.shrinkEnabled` (default `true`) turns shrinking off for a
policy entirely — nothing is re-encoded, and an injected `AttachmentShrinker`
is never consulted. `AttachmentPolicy.shrinkSteps` (default
`AttachmentPolicy.defaultShrinkSteps`, five steps from 3072px/quality 85
down to 1280px/quality 60) is the ladder the default engine tries, largest
dimension first, stopping at the first result that fits the policy's byte
cap; a source already under the cap, a non-image mime type, or a step ladder
that runs out are all `null` — the contract for "send the bytes untouched".

The engine is pluggable through the abstract `AttachmentShrinker` interface
(`Future<ShrunkAttachment?> fit(bytes, {mimeType, maxBytes, fileName})`):

- `DefaultAttachmentShrinker` — the SDK's own engine, built on
  `package:image`, running on a background isolate where the platform
  supports one. It is the default for the five public pickers above.
- `NoAttachmentShrinker` — sends exactly the bytes picked; pass it as
  `shrinker: const NoAttachmentShrinker()` to a picker, or
  `AttachmentPolicy(shrinkEnabled: false)`, to opt out.
- `ChatUiAdapter(attachmentShrinker: ...)` sets the engine `NomaChatView`
  hands to every attachment path it drives itself (camera, gallery, multiple
  media, generic file). It defaults to `DefaultAttachmentShrinker` too, so a
  host that mounts `NomaChatView` and never touches this parameter still
  reduces outgoing images; pass `const NoAttachmentShrinker()` to opt the
  whole view out.
- A custom engine that wants `AttachmentPolicy.shrinkSteps` to drive its own
  ladder implements `PolicyConfigurableShrinker.withShrinkSteps(steps)`; one
  that does not implement it keeps its own fixed presets untouched by the
  policy.

Re-encoding always produces `image/jpeg` under a `.jpg` name — `mimeType`
and `fileName` on the returned `ShrunkAttachment` change together, since a
backend that stores a blob under a content type its own bytes contradict is
the failure mode this exists to avoid. `AttachmentPolicy` measures what the
file *is* (mime type, denied extensions) against the original pick and what
it *weighs* against the shrunk payload, with the original mime type's cap —
a PDF a shrinker declines to touch is never judged as if it were the JPEG
some other file became.

### ReadOnlyNoticeBuilder — why a room is read-only

A room can be read-only for three independent reasons, and a host that
customizes the notice usually wants to say which one applies:

```dart
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  builders: ChatViewBuilders(
    readOnlyNoticeBuilder: (context, reason) => switch (reason) {
      ReadOnlyReason.ownerOnly => MyClosedBanner(),
      ReadOnlyReason.selfMuted => MyMutedBanner(),
      ReadOnlyReason.announcement => MyAnnouncementBanner(),
    },
  ),
)
```

`ReadOnlyReason` is `announcement` (an announcement channel and the viewer
is not the owner), `selfMuted` (an admin silenced this member specifically —
distinct from the room's own notification mute), or `ownerOnly` (the room's
backend-set `RoomConfig.writePolicy` is `ownerOnly` and the viewer is not the
owner). Return `null` — the default — to keep the SDK's own notice, which
carries the semantic identifier `chat_read_only_notice` for drivers
(`Semantics(identifier: 'chat_read_only_notice')` plus a matching `ValueKey`).

`RoomWritePolicy` (`members`, the default, or `ownerOnly`) travels in the
room's own config — `RoomConfig.writePolicy` on `RoomDetail`, mirrored on
`RoomListItem.writePolicy` for the list — and is read-only from the SDK's
side: it is set server-side, never here. An absent field, a value from a
newer backend, or the wrong type all resolve to `members` (fails open, so a
spelling mismatch never locks a room nobody meant to close). `RoomListItem`
and `RoomDetail` both expose `isReadOnly` (`true` for any of the three
reasons); `readOnlyReason` — the most specific cause that applies, or `null`
when the room is writable — lives on `RoomListItem` only, and is what feeds
`ChatViewBehaviors.readOnlyReason` and therefore a host's
`readOnlyNoticeBuilder`.

### ParticipantNameResolver & recordRoomRoster — searching the room list by member

`RoomListController`'s text filter matches a room's resolved title
(`displayName`) and its last message by default. `participantNameResolver`
extends that to the people in the room, so typing a contact's name finds the
1:1 or group they are in even when the room's own title does not mention
them:

```dart
final controller = chat.roomListController
  ..setParticipantNameResolver(
    (room) => myContactDirectory.namesFor(room.id),
  );
```

`RoomListController.matchedParticipantFor(roomId)` returns the name that
made a row match when the title/last-message did not, or `null` otherwise;
`RoomListView`'s own `RoomTile` already paints it as a second line under the
room name (`RoomTile(matchedParticipant: ...)`) whenever it is not given a
custom `tileBuilder`. Call `notifyMembersChanged()` after your own directory
fills in a name so the active filter re-evaluates.

`ChatUiAdapter` wires a default resolver of its own — `displayNameFor` over
each 1:1's other member and whoever sent the room's last message — so
searching by name works out of the box for anyone the SDK has already had a
reason to name. It does not track full room membership on its own; feed it
with `ChatUiAdapter.recordRoomRoster(roomId, userIds, {complete: true})`
whenever your own code learns who is in a room (the SDK already calls this
when a group chat, its info page, or a page of `GroupMembersView` loads), and
read back what is known with `roomRosterOf(roomId)`. `complete: false` adds
to what is already known instead of replacing it, for a paginated roster.
Calling `setParticipantNameResolver` replaces the adapter's default outright
rather than layering on top of it — call `recordRoomRoster` instead if you
just want to widen what the default already finds.

For tests, `MockChatClient.seedRoomMeta(roomId, writePolicy: ...)` seeds the
write policy on both the room detail and the listing, so a suite (or
`example/`) can exercise an owner-only room without a real backend.

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

Twelve locales ship out of the box: `en`, `es`, `fr`, `de`, `it`, `pt`, `ca`,
`sv`, `no`, `da`, `pl`, `cs`.

Every widget resolves its strings through `theme.l10nOf(context)`, which
honours two wiring routes. Pick either.

**Route 1 — through the theme.** Put the instance you want on the theme you
hand to the view; an explicit instance always wins:

```dart
NomaChatView(
  roomId: roomId,
  adapter: adapter,
  theme: ChatTheme.defaults.copyWith(
    l10n: ChatUiLocalizations.forLanguageCode(languageCode),
  ),
)
```

This is what the example app does (`example/lib/pages/chat_room_page.dart`).

**Route 2 — through Flutter's `Localizations`.** Register the delegate and
leave `ChatTheme.l10n` at its default; the widgets read the ancestor
themselves and follow app-locale changes at runtime:

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
  home: NomaChatView(roomId: roomId, adapter: adapter),
)
```

With neither, the UI renders the English defaults.

One caveat on route 1: "the host set `l10n`" is detected by identity against
the canonical `ChatUiLocalizations.en` constant, so a theme carrying that
exact instance — including `forLanguageCode('en')`, `forLanguageCode(null)`
and any unsupported code, which all return it — reads as "not set" and falls
through to route 2. To pin English against a non-English app locale, pass a
distinct instance: `ChatUiLocalizations.en.copyWith()`.

**Room-list previews follow routes 1 and 2 like any other widget string.**
`RoomTile` builds every one of them at paint time from the structured
`RoomListItem` fields and `theme.l10nOf(context)`: the deleted marker, "📷
Photo" / "📹 Video" / "📄 report.pdf" / "🎵 song.mp3", "🎤 Voice message
(0:14)", "📍 Location", "Forwarded", and the reaction sentence ("Alice
reacted 👍 to …", rebuilt from `lastMessageReactionEmoji`,
`lastMessageSenderName` and `lastMessageReactionTargetText` /
`lastMessageReactionTargetType`). `RoomListItem.lastMessage` holds only the
text the sender wrote, so nothing on a row is ever frozen in the language it
arrived in and nothing a person typed is ever rewritten. Membership system
banners ("Alice joined", "You removed Bob") work the same way, rebuilt from
the metadata the SDK persists with them (`localizedSystemMessageText`); only
banners written before 0.17.0, which carry no display names, keep the
language they were stored in.

`ChatUiAdapter.l10n` is a third surface, and a small one: the strings the
adapter composes where no `BuildContext` is in reach — the self-chat title
and the membership banners at the moment they are minted.

**You do not normally have to set it.** `NomaChatView` — and `RoomListView`
when you pass it the optional `adapter:` — hand the adapter the bundle their
own subtree resolved, with the same precedence as `l10nOf`, so registering
the delegate covers this surface too:

```dart
RoomListView(
  controller: chat.roomListController,
  adapter: chat.adapter,
)
```

**Assign it yourself and you own it from then on.** `ChatUiAdapter.l10n` is
settable and read on every use, so a host that drives the chat language from
its own settings screen writes `adapter.l10n =
ChatUiLocalizations.forLanguageCode(code)` — no teardown, no reconnect. Once
you have assigned it (or passed a non-default `l10n:` to `NomaChat.create` or
to the constructor) the SDK stops pushing the ambient bundle in, so the two
routes never fight. The self-chat title on rows already written is re-stamped
by the setter; the membership banners already written keep their sentence, as
described above.

### Custom strings

Any of the 274 string fields can be overridden with `copyWith`; unspecified
ones keep the bundled translation:

```dart
theme: ChatTheme.defaults.copyWith(
  l10n: ChatUiLocalizations.forLanguageCode(languageCode).copyWith(
    send: 'Submit',
    writeMessage: 'Write a message…',
  ),
)
```

`ChatUiLocalizations.override(...)` builds a delegate that applies the same
overrides on top of whichever locale Flutter resolves. It reaches the chat UI
through route 2, so leave `ChatTheme.l10n` at its default when you use it:

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

As of `0.13.0` the dedupe tie-break is deterministic (a stable `roomId`
comparison, independent of which room's resolution completes first), so
the row no longer flickers between the two ids across refreshes. It also
no longer evicts the losing room from the persistent cache during a
cache-only pass — only an authoritative network pass does, so a stale
guess can never destroy state a later reconciliation still needs.
