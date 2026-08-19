# Analytics

`noma_chat` never phones home. Every event below only exists as an argument
to the `ChatAnalyticsSink` the host app wires through `ChatConfig
.analyticsSink` **or** directly into `ChatUiAdapter`'s constructor. If
neither is wired (the default), nothing is collected, stored, or sent
anywhere.

This file is the human-readable counterpart to the `ChatAnalyticsEvent`
doc comments in `lib/src/models/chat_analytics_event.dart`: the sealed
union is the machine-readable contract, this table is what each event
means and when it fires. Update this file in the same change that adds or
changes an emission site.

```dart
typedef ChatAnalyticsSink = void Function(ChatAnalyticsEvent event);
```

## This is not `TELEMETRY.md`

The SDK has **two** separate observability channels, and they exist apart
from each other on purpose:

| | `MetricCallback` (`TELEMETRY.md`) | `ChatAnalyticsSink` (this file) |
|---|---|---|
| Carries a room/message id? | **Never** — forbidden by `CONVENTIONS.md` §10.3 | **Yes**, on every event |
| Shape | `(String metric, Map<String, dynamic> data)` — free-form counters | A closed `freezed` union of 4 typed events |
| What it's for | SRE-shaped signals: cache hit rate, HTTP error rate, WS disconnects, queue depth | Product-shaped signals: did the user open a room, receive a message, play a voice note, did a send land |
| Wired via | `ChatConfig.metricCallback` only | `ChatConfig.analyticsSink` **and** `ChatUiAdapter`'s constructor |

A single channel carrying both shapes would force every consumer of
`MetricCallback` to filter room/message ids back out (easy to forget, and
the forgetting is a PII leak), or force `ChatAnalyticsSink` payloads down
to string-keyed maps (losing the sealed-union exhaustiveness check on the
consumer side). Keeping them apart makes the PII boundary a type, not a
convention someone has to remember.

## Why `ChatUiAdapter`'s constructor, not only `ChatConfig`

`ChatConfig.analyticsSink` is the sink `NomaChat.create` / `NomaChat
.fromConfig` mirror onto the adapter for you. A host that builds
`ChatUiAdapter` directly — bypassing those two entry points, e.g. to wire a
custom `ChatClient` or to share one `ChatClient` across adapters — would
never reach a sink that only lived on `ChatConfig`. `WB/mobile` does
exactly this (`WB/mobile/lib/features/chat/chat_service.dart` builds
`ChatUiAdapter` by hand and never calls `NomaChat.create`), which is why
the constructor parameter is not optional plumbing — for that class of
consumer it is the *only* way in.

## Events

| Event | Emission site | Fields | Fires when |
|---|---|---|---|
| `roomOpened` | `ChatUiAdapter.setActiveRoom` | `roomId`, `isGroup` | The user enters a room (`setActiveRoom(roomId)` with a non-null id). Once per entry — there is no `roomClosed` counterpart; `setActiveRoom(null)` is lifecycle plumbing, not a product moment. Skipped for an unmaterialized DM draft (see below). |
| `messageReceived` | `ChatEventRouter._onNewMessage` | `roomId`, `messageId`, `kind` (`MessageType`), `isGroup` | A message from **another** user lands in a room. Never fires for the local echo of a message this device sent — the router's `message.from == currentUser.id` guard gates this emission too. Does fire for a system message, and fires again if the server redelivers the same `messageId` (see below). |
| `voicePlayed` | `AudioBubble._togglePlayPause`, threaded up through `MessageBubble` → `MessageList` → `ChatViewCallbacks.onVoicePlayed` → `NomaChatView` | `roomId`, `messageId`, `durationMs`, `firstListen` | An incoming voice message starts playing on the edge that flips the bubble's "listened" badge. `firstListen` is always `true` from this emission site today, and means "first play of this bubble's current on-screen life" (see below). |
| `sendOutcome` | `OptimisticHandler.sendMessage` | `roomId`, `kind` (`MessageType`), `success`, `failureKind` | A send through the optimistic send path — `messages.send()`, and therefore `messages.sendThreadReply()` and any host call that hands it an already uploaded `attachmentUrl` — resolves. `failureKind` is the failed `ChatFailure`'s `errorToken` when the server provided one, else its class name (`'NetworkFailure'`, `'ServerFailure'`, …) — **never** `failure.message`, which can echo server- or user-provided text. `null` when `success` is `true`. |

### Known limits of the four events

These are coverage gaps and rough edges of the current emission sites, not
design choices to build a funnel on top of unknowingly.

- **`roomOpened` skips an unmaterialized DM draft.** A virgin DM is routed
  by the synthetic key `draft:<otherUserId>`, not a room id: emitting it
  would put the *peer's user id* on this channel in a field consumers read
  (and hash) as a room, and the same visit would report a second open once
  the draft materializes and the host re-points `setActiveRoom` at the real
  room. So the visit reports one `roomOpened` — the real room's, on the
  first send — or none, if the user never sends.
- **`messageReceived` counts system messages** (membership changes and the
  like, rendered as a centred notice rather than a bubble). The event
  carries no flag to tell them apart, so a "messages received" funnel
  cannot exclude them from this event alone today.
- **`messageReceived` does not de-duplicate.** A message the server
  delivers twice emits twice with the same `messageId`; de-duplicate in the
  sink if that matters.
- **`voicePlayed.firstListen` is per-bubble, not per-message.** It is
  seeded from `AudioBubble.isListened`, which the SDK's own message list
  does not persist, so scrolling the bubble out of view and back, leaving
  and re-entering the room, or restarting the app arms it again — while a
  replay in between emits nothing at all. De-duplicate on `messageId` for a
  true once-per-message signal.
- **`sendOutcome` covers one send path.** It is **not** wired for
  `messages.sendAttachment()` (upload-then-send, its own flow in
  `MessagesController`), `messages.sendVoice()` (same),
  `messages.sendDirect()` (contact-addressed, calls
  `client.contacts.sendDirectMessage` directly),
  `messages.forwardMessage()` (calls `client.messages.send` directly),
  `messages.retrySend()`, or the contact-addressed fallback a DM draft
  takes when its room cannot be materialized. Sends down those paths
  produce no event at all — neither success nor failure.
- **A send blocked between the two users reports `success: true`.** The
  sender is never told (WhatsApp parity), and the event reports what the
  user was shown rather than what the server stored.

## Rules every emission site follows

- **No message content, ever.** No text, no display name, no attachment
  file name — only identifiers, a type discriminator, and numbers. If a
  field could plausibly carry user-authored text, it is not on this union.
- **Identifiers travel unhashed.** This SDK does not transform `roomId` /
  `messageId` before handing them to the sink — no hashing, no truncation.
  A consumer that needs hashed identifiers (`WB` does: every outbound
  analytics event is hashed by a sanitizer that runs unconditionally)
  applies its own transform on the way out. A second transformation point
  *inside* the SDK would just be a second place for that mapping to drift
  from the consumer's — one source of truth for "how do we hash a room id"
  beats two that have to agree.
- **No sampling, no batching, no dropping.** Every emission reaches the
  sink synchronously, one call per occurrence, in the order it happened —
  the SDK never coalesces two occurrences into one or holds one back.
  (That is a statement about the channel, not a de-duplication promise:
  see "Known limits" above.) Rate-limiting a noisy stream (e.g. capping
  `messageReceived` volume in a very active group) is the consumer's call,
  made in the sink itself — the SDK does not make it for you.
- **A throwing sink is caught and dropped.** Every emission goes through
  `ChatUiAdapter.emitAnalyticsEvent`, which wraps the call in a `try/catch`
  — the same pattern the SDK already uses for every other user-supplied
  callback (`onAdminMessage`, `onBroadcast`, …). Analytics never decides
  whether a message sends, a room opens, or the chat stays usable.

## The sealed union and forward compatibility

`ChatAnalyticsEvent` is a `freezed` sealed union with four variants today.
Adding a fifth is an **additive, minor-version-compatible** change under
this package's semver policy (see `CHANGELOG.md`'s header) — the same
policy that already governs `MessageType` and `ChatFailure`. A consumer
`switch`
that lists every variant that exists today and has no wildcard branch
**will stop compiling** the moment the SDK ships a new one. Always keep a
trailing case:

```dart
void forward(ChatAnalyticsEvent event) {
  switch (event) {
    case ChatAnalyticsRoomOpened(:final roomId, :final isGroup):
      analytics.log('chat_room_opened', {'room': hash(roomId), 'group': isGroup});
    case ChatAnalyticsMessageReceived(:final roomId, :final messageId):
      analytics.log('chat_message_received', {
        'room': hash(roomId),
        'message': hash(messageId),
      });
    default:
      // voicePlayed, sendOutcome, and anything added in a future release
      // fall through here until handled explicitly.
      break;
  }
}
```

`test/ui/adapter/chat_analytics_test.dart` exercises this contract
directly: a `switch` that names three variants and keeps a wildcard routes
the unnamed one (`sendOutcome`, standing in for a variant that test
predates) to the fallback case instead of failing to compile.

## Wiring example

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
  // MetricCallback: SRE-shaped counters, no identifiers, ever.
  metricCallback: (metric, data) => statsd.increment(metric, tags: data),
  // ChatAnalyticsSink: product-shaped events, identifiers included —
  // hash them yourself before they leave the device.
  analyticsSink: (event) => switch (event) {
    ChatAnalyticsRoomOpened(:final roomId, :final isGroup) =>
      productAnalytics.log('chat_room_opened', {
        'room': sanitizer.hash(roomId),
        'is_group': isGroup,
      }),
    ChatAnalyticsMessageReceived(:final roomId, :final messageId, :final kind) =>
      productAnalytics.log('chat_message_received', {
        'room': sanitizer.hash(roomId),
        'message': sanitizer.hash(messageId),
        'kind': kind.name,
      }),
    ChatAnalyticsVoicePlayed(:final roomId, :final messageId, :final durationMs) =>
      productAnalytics.log('chat_voice_played', {
        'room': sanitizer.hash(roomId),
        'message': sanitizer.hash(messageId),
        'duration_ms': durationMs,
      }),
    ChatAnalyticsSendOutcome(:final roomId, :final success, :final failureKind) =>
      productAnalytics.log('chat_send_outcome', {
        'room': sanitizer.hash(roomId),
        'success': success,
        'failure_kind': failureKind,
      }),
    // Keep the wildcard: a variant added in a future minor release lands
    // here instead of breaking this build.
    _ => null,
  },
);
```

For a host that builds `ChatUiAdapter` directly instead (bypassing
`NomaChat.create`/`fromConfig`), pass `analyticsSink` to the adapter's
constructor the same way — see the "Why `ChatUiAdapter`'s constructor, not
only `ChatConfig`" section above.

## Adding a new event

1. Add the `const factory` to `ChatAnalyticsEvent` in
   `lib/src/models/chat_analytics_event.dart` and re-run `dart run
   build_runner build --delete-conflicting-outputs`.
2. Emit it through `ChatUiAdapter.emitAnalyticsEvent` (or a collaborator's
   `analyticsEmit` dependency, which already routes there) — do not add a
   second sink.
3. No message content, ever — see "Rules every emission site follows"
   above.
4. Add a row to the table above in the same change.
5. Add or extend a test in `test/ui/adapter/chat_analytics_test.dart`
   covering the new emission site.
