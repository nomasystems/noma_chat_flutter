# Migration guide

## 0.11.x → next release

### Behavioural: the id returned by `send()` can be provisional

Backends running `ack_mode = async` (an opt-in deployment mode; the backend default is `sync`) answer
`POST /rooms/{id}/messages` and `POST /contacts/{id}/messages` with `201`
and an echo built **before** persistence — its `id` does not correspond to
the stored message. The SDK now surfaces this instead of pretending the id
is final:

- `ChatMessage.isProvisional` (new flag) is `true` on such echoes, and
  `ChatMessage.clientMessageId` is always populated on them.
- The authoritative message arrives via `NewMessageEvent` carrying the same
  `clientMessageId`; the SDK's controller and cache reconcile by that key
  automatically (no duplicates, nothing stranded under the provisional id).

**Do not use the id returned by `send()` / `sendDirectMessage()` for
immediate follow-ups** (react / edit / delete / pin). When
`isProvisional == true`, wait for the matching `NewMessageEvent` and use its
`id`:

```dart
final res = await chat.client.messages.send(roomId, text: 'hi');
final sent = res.dataOrNull;
if (sent != null && sent.isProvisional) {
  // Correlate later: event.message.clientMessageId == sent.clientMessageId
}
```

No action is needed if you only render through the bundled `ChatUiAdapter`
/ `NomaChatView` — the bubble stays in the *sending* state until the event
confirms it, then swaps to the authoritative message.

### Non-breaking additions

- `contacts.sendDirectMessage()` gained an optional `clientMessageId`
  parameter (auto-generated when omitted) and now always sends the key, so
  DM retries are idempotent. Custom `ChatContactsApi` implementers must add
  the parameter to their override.
- DM typing (`contacts.sendTyping()`) is now always sent over REST; the
  broken contact-addressed WS `typing` frame was removed (the backend only
  accepts room-scoped frames).
- WS close code `4006` (`transport_disabled`) now suspends WS for the
  session and `RealtimeMode.auto` fails over to SSE/polling immediately.

## 0.9.x → 0.10.0

### Breaking: message pagination is now bidirectional opaque cursors

`ChatCursorPaginationParams.before` and `.after` (the ISO-8601 timestamp
fields) were **removed entirely** — they no longer exist, are no longer emitted
as `before` / `after` query params, and the timestamp/id boundary dedup that
backed them in the polling realtime engine is gone.

`messages.list` (and `getDirectMessages` / `getConversationMessages`) now page
with the opaque, seq-based cursors the backend returns on every page:

- `ChatPaginatedResponse.prevCursor` — anchored on the **oldest** message of
  the page. Pass it back as `cursor` with `direction: ChatCursorDirection.older`
  to load **older history**.
- `ChatPaginatedResponse.nextCursor` — anchored on the **newest** message.
  Pass it back with `direction: ChatCursorDirection.newer` (the backend
  default) to **catch up** on newer messages.

`hasMore` reports whether more pages exist *in the requested direction*. The
cursors are seq-based, so paging never skips or replays messages that share an
exact millisecond.

**Before:**

```dart
// Load older history by oldest-timestamp
final res = await chat.client.messages.list(
  roomId,
  pagination: ChatCursorPaginationParams(before: oldest.timestamp.toIso8601String()),
);
```

**After:**

```dart
final first = await chat.client.messages.list(roomId);
final older = await chat.client.messages.list(
  roomId,
  pagination: ChatCursorPaginationParams(
    cursor: first.dataOrThrow.prevCursor,
    direction: ChatCursorDirection.older,
    limit: 30,
  ),
);
```

If you implement `ChatMessagesApi` yourself, parse the response `prev` field
into `ChatPaginatedResponse.prevCursor` (alongside `next` →`nextCursor`).

### Breaking: `members.invite` now returns `InviteResult`

`members.invite` used to return `ChatResult<void>` — a `ChatSuccess` meant the
HTTP call worked, but said nothing about whether each user was actually added.
It now returns `ChatResult<InviteResult>` so you can inspect the per-user
outcome (the backend answers `207 Multi-Status` when some users succeed and
others fail — banned, already a member, etc.).

The `userRole` parameter was **removed** (the backend never accepted a
per-invite role; assign roles afterwards with `updateRole`). A new optional
`token` parameter was added for joining a public room by invitation token.

**Before:**

```dart
final result = await chat.client.members.invite(
  roomId,
  userIds: ['user-123', 'user-456'],
  userRole: MemberRole.member, // removed
);

switch (result) {
  case ChatSuccess():
    showOk(); // assumed everyone was added — not necessarily true!
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

**After:**

```dart
final result = await chat.client.members.invite(
  roomId,
  userIds: ['user-123', 'user-456'],
  // token: publicRoomToken, // optional: public-room join by token
);

switch (result) {
  case ChatSuccess(:final data) when data.hasFailures:
    for (final f in data.failed) {
      showError('${f.userId}: ${f.detail ?? 'failed'} (${f.code})');
    }
  case ChatSuccess(:final data):
    showOk('${data.succeeded.length} invited'); // data.allSucceeded == true
  case ChatFailureResult(:final failure):
    // Every user failed (non-2xx) or a transport error.
    showError(failure);
}
```

`InviteResult` exposes `results` (a `List<InviteUserResult>` with
`userId` / `success` / `code?` / `detail?` each), plus the derived
`succeeded`, `failed`, `hasFailures` and `allSucceeded`. To roughly preserve
the old "did the call work" check, branch on `data.allSucceeded`.

### Deprecated: header-only attachment download — use signed URLs

Attachment download moves to a **signed-URL** primary path. The backend now
authorizes attachment access by room membership (fail-closed) and exposes
`GET /attachments/{attachmentId}/signed-url?roomId=...`, which returns a
short-lived, self-authorizing URL (HMAC signature + expiry + user baked in).
That URL drops straight into `Image.network` / `CachedNetworkImage` / a native
viewer.

The legacy header-only flow (`GET /attachments/{attachmentId}` authorized by
the `x-attachment-metadata` header alone) is **deprecated**. It now also
requires a membership-checked `roomId`; without one the backend returns
`403` with the `not_a_room_member` token (exposed as
`ChatErrorTokens.notARoomMember`).

In the SDK:

- New `attachments.signedUrl(attachmentId, roomId: ...)` →
  `ChatResult<AttachmentSignedUrl>` (the `.url` is absolute and ephemeral).
- `attachments.download` gained an optional `roomId`. **Pass it** — when
  present the SDK takes the signed-URL path automatically. Calling
  `download(id, metadata: ...)` *without* `roomId` is the deprecated path and
  will now 403.

**Before:**

```dart
final res = await chat.client.attachments.download(
  attachmentId,
  metadata: storedMetadata,
);
```

**After:**

```dart
// Display / cache: resolve a signed URL.
final res = await chat.client.attachments.signedUrl(
  attachmentId,
  roomId: roomId,
);
final url = res.dataOrNull?.url; // -> Image.network(url) / CachedNetworkImage

// Raw bytes: pass roomId so download takes the signed-URL path.
final bytes = await chat.client.attachments.download(
  attachmentId,
  roomId: roomId,
);
```

**For custom `ChatAttachmentsApi` implementers:** the interface gained
`signedUrl(...)` (a new method you must implement) and `download` gained the
optional `roomId` parameter. The bundled `MockChatClient` already implements
both.

### Behaviour change: `ChatConfig.ssePath` default is now `/eventsource`

The default SSE path changed from `/events` to `/eventsource`. The old default
never worked against CHT/NRTE, so this is a fix, not a regression. **If you
override `ssePath` explicitly, you are unaffected.** If you relied on the old
default and pointed a custom backend at `/events`, set it back:

```dart
config: ChatConfig(ssePath: '/events'),
```

### New: `ChatConfig.actAsUserId` (managed-user delegation)

Set `actAsUserId` to act on behalf of a managed user — every REST request then
injects `X-From-User-Id: <actAsUserId>`. The backend enforces the
parent→managed relationship (`403` if not allowed). REST only; it does not
change the real-time identity.

```dart
config: ChatConfig(actAsUserId: managedUserId),
```

### New: `rooms.create(..., forceGroup: true)`

`rooms.create` gained an optional `forceGroup` flag. By default a contacts room
with a single other member collapses to a DM-style room; pass `forceGroup:
true` to keep it a named group. Existing calls are unchanged (`forceGroup`
defaults to `false`).

```dart
await chat.client.rooms.create(
  name: 'Team Alpha',
  audience: RoomAudience.contacts,
  members: [otherUserId],
  forceGroup: true,
);
```

### Note: `presence.update(statusText:)` is not persisted

`presence.update` accepts a `statusText:` argument, but the backend currently
**ignores** it — a custom status string will not round-trip to other users.
The parameter is reserved for future backend support; do not rely on it yet.

### Recommended: render rooms with `NomaChatView`

A new `NomaChatView` widget is the recommended drop-in for a chat-room screen.
It wraps `ChatRoomAppBar` + `ChatView` and auto-wires the seven room behaviors
(history + pin load, unread divider, group member hydration, blocked /
room-removed reactions, role-aware context menu, report dialog, reaction-user
fetcher) that hosts previously had to reimplement.

This is **additive** — `ChatView` is unchanged and remains available for fully
custom screens. Migrating is optional, but typically deletes a lot of
boilerplate:

```dart
// Before: ChatView composed by hand (controller, app bar, callbacks, unread
// snapshot, member hydration, report dialog… all wired manually).

// After:
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  onRoomLeft: () => Navigator.of(context).maybePop(),
)
```

See the [Developer Guide — NomaChatView](./doc/DEVELOPER_GUIDE.md#nomachatview)
for the full list of override slots.

### Internal: dropped `json_annotation` / `json_serializable` deps

These code-gen dependencies were removed from the package — the SDK no longer
uses them. **No consumer impact:** they were never part of the public API. If
you depended on them transitively through `noma_chat`, add them to your own
`pubspec.yaml`.

### New: `members.list(expand:)` — embed names + avatars, kill the roster N+1

`members.list` gains an optional `expand` param. Pass
`expand: const [RoomMemberExpand.users]` and the SDK sends `?expand=users`,
making the backend embed each member's `displayName` + `avatarUrl` in the row.
`RoomUser` gains nullable `displayName` / `avatarUrl`, populated only on an
expanded response. Rendering a group roster no longer needs a
`GET /users/{id}` per member — one `list` call carries it all.

```dart
final res = await chat.client.members.list(
  roomId,
  expand: const [RoomMemberExpand.users],
);
// res.dataOrNull.items each carry m.displayName / m.avatarUrl (or null).
```

Backward-compatible: omit `expand` and the fields stay `null`, exactly as
before. The bundled `GroupMembersView` already opts in and seeds the adapter
user cache from the embedded fields, so the group screen renders names +
avatars with no extra fetches. See the
[Developer Guide — listing members](./doc/DEVELOPER_GUIDE.md#listing-members--list-and-the-users-expansion).

> **Custom `ChatMembersApi` implementers:** `list` gained an
> `List<RoomMemberExpand> expand = const []` parameter. It is optional with a
> default, so existing implementations keep compiling; add the param to your
> override to forward the expansion (and honour it server-side).

### New: unified room preferences — `rooms.patchPreferences()`

Room preferences (mute / pin / hide) now funnel through one endpoint:
`rooms.patchPreferences(roomId, {muted?, muteUntil?, pinned?, hidden?})` sends
a partial `PATCH /rooms/{roomId}/preferences` and returns the merged
server-side state as a new `RoomPreferences` model (`muted`, `pinned`,
`hidden`, `muteUntil?`). Pass only the fields you want to change; a non-null
`muteUntil` is sent as an ISO-8601 string for WhatsApp-style timed mutes.

```dart
final res = await chat.client.rooms.patchPreferences(
  roomId,
  pinned: true,
  hidden: false,
);
// res.dataOrNull -> RoomPreferences(muted, pinned, hidden, muteUntil?)
```

**Breaking — the six data-API toggles are removed.** `chat.client.rooms.mute`
/ `unmute` / `pin` / `unpin` / `hide` / `unhide` no longer exist. Call
`patchPreferences` directly:

```dart
// Before:
await chat.client.rooms.mute(roomId);
await chat.client.rooms.mute(roomId, until: someInstant);
await chat.client.rooms.unmute(roomId);
await chat.client.rooms.pin(roomId);
await chat.client.rooms.hide(roomId);

// After:
await chat.client.rooms.patchPreferences(roomId, muted: true);
await chat.client.rooms.patchPreferences(roomId, muteUntil: someInstant);
await chat.client.rooms.patchPreferences(roomId, muted: false);
await chat.client.rooms.patchPreferences(roomId, pinned: true);
await chat.client.rooms.patchPreferences(roomId, hidden: true);
```

The single-flag convenience wrappers **with optimistic UI updates** remain on
the UI adapter — `adapter.rooms.mute/unmute/pin/unpin/hide/unhide` are
unchanged and now drive `patchPreferences` internally — so consumers using the
adapter API need no changes.

> **Custom `ChatRoomsApi` implementers:** the interface no longer declares the
> six toggles. Implement only
> `Future<ChatResult<RoomPreferences>> patchPreferences(String roomId, {bool? muted, DateTime? muteUntil, bool? pinned, bool? hidden})`
> against `PATCH /rooms/{id}/preferences`.

### Breaking: managed-users list — only `users.getManagedByParent()`

Listing the users a parent manages is served by a single canonical method.
`users.getManagedByParent(parentId, {pagination})` calls
`GET /users/{parentId}/managed-users` (operationId `getManagedUsersByParent`)
and returns the paginated `{users, hasMore}` response.

```dart
// Before (removed):
final res = await chat.client.users.getManaged(parentId);

// After:
final res = await chat.client.users.getManagedByParent(parentId);
// res.dataOrNull -> ChatPaginatedResponse<ChatUser>
```

**`users.getManaged(userId)` is removed.** It previously targeted the legacy
`GET /managed-users/{userId}` route; replace every call with
`getManagedByParent`, which takes the same arguments and returns the same shape.
`deleteManaged` / `searchManaged` / `createManaged` are unchanged.

> **Custom `ChatUsersApi` implementers:** the interface no longer declares
> `getManaged`. Implement only
> `Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManagedByParent(String parentId, {ChatPaginationParams? pagination})`,
> pointed at `GET /users/{parentId}/managed-users`.

### Breaking: contact / last-unread sender ids read the canonical field only

The SDK now reads **only** the canonical sender/identity field; the legacy XMPP
aliases are no longer accepted. `ChatContact` parses `userId` only (the `jid`
and `id` fallbacks are gone), and `UnreadRoom`'s last-message preview parses
`from` only (the `fromJid` fallback is gone). This is a no-op against a current
backend, which already emits the canonical fields. A server that emits *only*
the dropped `jid` / `fromJid` aliases will now surface an empty sender id — such
servers are no longer supported.

### Note: SDK spec mirror corresponds to the `user` audience bundle

The SDK ships a mirror copy of the backend OpenAPI spec at
[`doc/chat-api-openapi.yml`](./doc/chat-api-openapi.yml) for reference and codegen. The
backend source spec now annotates every operation with an `x-audience` tag
(`user` / `admin` / `internal`) and a Redocly config that generates three
audience-scoped bundles. The SDK only needs the **`user`** surface: the mirror
corresponds to that `user` audience bundle and can be regenerated from the
backend source where Redocly is available (e.g.
`npx @redocly/cli bundle user@v1 --config redocly.yaml`). Admin- and
internal-only operations are intentionally absent from the SDK surface.

### New: global message search — `messages.search()` `roomId` is now optional

`messages.search` used to require a `roomId` and only ever searched one room.
The argument is now optional (`String? roomId`): omit it to search **globally**
across every room the caller belongs to (the backend scopes results to the
authenticated user's rooms), or keep passing `roomId:` to scope to a single
room.

```dart
// Global: search across all of the caller's rooms
final all = await chat.client.messages.search('invoice');

// Single room (unchanged)
final inRoom = await chat.client.messages.search('invoice', roomId: roomId);
```

No call-site changes are required: existing single-room callers already pass
`roomId:` by name, and that keeps working. The `roomId` query param is sent to
`GET /messages/search` only when non-null.

> **Custom `ChatMessagesApi` implementers:** the `search` signature changed
> from `search(String query, {required String roomId, ...})` to
> `search(String query, {String? roomId, ...})`. Make `roomId` nullable in your
> override and forward it only when non-null (the bundled `RestMessagesApi`
> omits the `roomId` query param when it is `null`).

### New: canonical reactions endpoint — `messages.addReaction()`

Reactions now have a dedicated sub-resource endpoint instead of riding on the
message-send path. `messages.addReaction(roomId, messageId, emoji: '👍')` POSTs
`/rooms/{roomId}/messages/{messageId}/reactions` (HTTP `201`), and
`messages.deleteReaction` gains an optional `emoji`:

```dart
// React (the only supported way)
await chat.client.messages.addReaction(roomId, messageId, emoji: '👍');

// Un-react: omit `emoji` to clear the caller's reaction wholesale...
await chat.client.messages.deleteReaction(roomId, messageId);
// ...or pass it to remove a specific one (DELETE …/reactions?emoji=👍)
await chat.client.messages.deleteReaction(roomId, messageId, emoji: '👍');
```

Modelling a reaction as a sub-resource keeps it out of the message timeline and
the offline send queue. The built-in optimistic UI (`ChatView` / `NomaChatView`)
already reacts and un-reacts through these calls — **no UI consumer changes are
required**.

**Breaking — reactions no longer ride on the send path.** The SDK no longer
sends reactions via `send(messageType: MessageType.reaction)`; `addReaction`
(and `deleteReaction`) is the only supported reaction API. The general
`messages.send` still accepts `messageType` / `reaction` for any other purpose,
but if your code constructed reaction messages by hand, switch to
`addReaction`.

> **Custom `ChatMessagesApi` implementers:** two interface members changed.
> `addReaction(String roomId, String messageId, {required String emoji})` is
> **new** — add an override (POST the `{emoji}` body to the reactions
> sub-resource). `deleteReaction` gained an optional `String? emoji` parameter —
> forward it as the `?emoji=` query param when non-null. The bundled
> `RestMessagesApi` / `CachedMessagesApi` show the reference shape.

### New: group invite links — `members.joinWithToken` + `ChatInviteLink`

Public / invitable rooms can now be joined via a shareable link. Build one
from a room's `publicToken` with `ChatInviteLink(...).toUri(base)`, and
self-join from an incoming deep link with
`members.joinWithToken(roomId, token: …)` (a wrapper over `invite` with
`inviteAndJoin` for the current user). Both `toUri` and
`ChatInviteLink.tryParse` accept custom query-parameter names. Surface it in
the room menu with the new `ChatRoomOption.inviteViaLink` preset (copies the
link to the clipboard by default). Additive — see the
[Developer Guide — invite links](./doc/DEVELOPER_GUIDE.md#invite-links--joinwithtoken--chatinvitelink).

> **Custom `ChatMembersApi` implementers:** `joinWithToken` is a new interface
> method. If you implement `ChatMembersApi` directly (rather than using the
> bundled client / `MockChatClient`), add it — delegating to your `invite`.

### New: export a chat — `adapter.messages.exportChat`

`adapter.messages.exportChat(roomId)` returns a `ChatExport` whose `text` is
the room's full history as a WhatsApp-style transcript. No new dependency —
writing the file and sharing it is left to your app. Surface it with
`ChatRoomOption.exportChat`.

### New: "Message info" sheet — `MessageInfoSheet` + `MessageAction.info`

`MessageInfoSheet` lists who read / was delivered a message. `NomaChatView`
wires it automatically: `MessageAction.info` is now in the default
context-menu set and shows only on the user's own messages.

> **Exhaustive `switch` on `MessageAction`:** the enum gained an `info` value.
> A non-default `switch` over `MessageAction` will need a new branch (or a
> `default`). The bundled menu handles it; only custom menus are affected.

### Behaviour: WebSocket close 4005 suspends both transports

A terminal auth close (`4005 too_many_auth_attempts`) now stops the WebSocket
**and** prevents the SSE failover from reconnecting with the rejected token.
The SDK emits a terminal `ChatAuthException` (`exception.terminal == true`) and
stays in `error` until you obtain a fresh token and call `connect()` again.
Listen for it to drive a re-authentication prompt.

### New: idempotent sends — `clientMessageId`

`messages.send` accepts an optional `clientMessageId` (≤128 chars). When set,
the backend makes the send idempotent over `(roomId, sender, clientMessageId)`:
a POST retry that replays the same key returns the already-persisted message
(the same `201` as a fresh send, no duplicate). The key round-trips inside the
response `metadata.clientMessageId`, which the SDK reads back and surfaces on
`ChatMessage.clientMessageId`. **You usually don't pass it yourself**:
`NomaChatView` / the adapter generate one per optimistic message and the offline
queue reuses it on every retry, so a send that actually landed before a network
failure surfaced is never duplicated. Pass your own only for custom send flows on
unreliable networks.

### Behaviour: `RateLimitFailure.retryAfter` now populated on CHT

CHT's `429` sends `X-RateLimit-Reset` (seconds until the window resets) and no
`Retry-After`. The SDK now reads `X-RateLimit-Reset` as a fallback, so
`RateLimitFailure.retryAfter` (and the retry interceptor's back-off) reflect the
real reset window instead of being `null`. No code change required.

### New: starred messages — `MessageAction.star` + `StarredMessagesView`

Per-user message bookmarks (WhatsApp-style). `messages.starMessage` /
`unstarMessage` and `messages.listStarred` (paginated, across all rooms) are new
on `ChatMessagesApi`; the adapter exposes `adapter.messages.star/unstar/
loadStarred`. `MessageAction.star` is in the default context menu (wired in
`NomaChatView`), and `StarredMessagesView` (or `.fromAdapter(adapter)`) renders
the list. **Exhaustive switches on `MessageAction` must add a `star` case.**

### New: mute with a duration — `rooms.mute(roomId, until:)`

The UI-adapter `adapter.rooms.mute` takes an optional `until` (a `DateTime`);
omit it for a permanent mute. (On the data API this maps to
`patchPreferences(roomId, muteUntil: …)`.) `ChatRoomOption.muteRoom` is now
duration-aware — its
`onToggle` callback was replaced by `onMute(DateTime? until)` + `onUnmute()`,
and the SDK presents a `MuteDurationSheet` (8h / 1 week / always) on tap:

```dart
ChatRoomOption.muteRoom(
  l10n: l10n,
  muted: room.muted,
  onMute: (until) => adapter.rooms.mute(roomId, until: until),
  onUnmute: () => adapter.rooms.unmute(roomId),
);
```

`RoomDetail`, `UnreadRoom` and `RoomListItem` gained a `muteUntil` field.

### New: "@" mention badge + Archived section

`UnreadRoom` / `RoomListItem` gained `unreadMentions`; `RoomTile` shows an "@"
badge when it is `> 0`. `RoomListView` now renders a collapsible **Archived**
section for hidden rooms (backed by the existing `hidden` pref);
`RoomListController` exposes `archivedRooms` / `hasArchivedRooms`, and
`ChatRoomOption.archiveChat` / `unarchiveChat` map to `rooms.hide` / `unhide`.

### New: edit/delete windows + typed 403 failures

`ChatViewBehaviors` gained `editWindow` (default 15 min) and `deleteWindow`
(default 2 days): `NomaChatView` hides the edit / delete context-menu actions on
your own messages once the window closes (pass `null` to disable). A late
attempt the backend rejects now surfaces as the typed `EditWindowExpiredFailure`
/ `DeleteWindowExpiredFailure` (instead of a generic `ForbiddenFailure`).

### New: stable error tokens on `ChatFailure` — `errorToken`

Every `ChatFailure` now exposes a `String? errorToken`: a stable, snake_case
symbolic code from the server's vocabulary (e.g. `room_not_found`,
`edit_window_expired`, `blocked`, `rate_limited`, `cannot_delete_other_user`).
Branch and localize on the token instead of the English `message`, which was
never contractual. The token is `null` on older servers or when no token
applies — never the empty string.

This is **purely additive** — no existing API changed. The SDK already routed
edit/delete-window 403s to typed failures by string-matching the `detail`
field; it now prefers the stable token when present and keeps the string match
as a fallback for older servers, so nothing breaks either way.

**Before** (branching on English prose — fragile):

```dart
result.fold(
  (failure) {
    if (failure.message.contains('window')) showEditTooLate();
    else showGenericError();
  },
  (data) => render(data),
);
```

**After** (branching on the stable key):

```dart
result.fold(
  (failure) {
    final label = switch (failure.errorToken) {
      ChatErrorTokens.editWindowExpired => l10n.editTooLate,
      ChatErrorTokens.blocked => l10n.youAreBlocked,
      ChatErrorTokens.rateLimited => l10n.slowDown,
      ChatErrorTokens.cannotDeleteOtherUser => l10n.cannotDeleteOther,
      _ => l10n.genericError, // unknown / older server / no token
    };
    showSnackBar(label);
  },
  (data) => render(data),
);
```

The well-known tokens live on `ChatErrorTokens` (a constants holder), but the
field is a `String?` (not an enum) on purpose: a new server token arrives
verbatim and never breaks the SDK. The same token rides on
`OperationError.failure.errorToken`, so a global `operationErrors` listener can
localize centrally.

### New: GDPR self-deletion — `users.deleteCurrentUser()`

The backend tightened account deletion to **own-account-only**. There is now a
dedicated `DELETE /users/me`, exposed as `client.users.deleteCurrentUser()`:

```dart
final res = await client.users.deleteCurrentUser();
res.fold(
  (failure) => showError(failure),
  (_) async {
    await chat.dispose();
    goToOnboarding();
  },
);
```

Prefer it for self-service erasure — it resolves the principal from the auth
token and so can never target the wrong account.

`users.delete(userId)` still exists, but **`userId` must be the caller's own
id**. Passing any other id returns a 403 that surfaces as a `ForbiddenFailure`
carrying `errorToken == ChatErrorTokens.cannotDeleteOtherUser`. Migrate
self-service flows from `delete(myId)` to `deleteCurrentUser()`.

### Confirmed: `message_delivered` / `message_acked` WS events supported

No migration needed — calling this out for completeness: the SDK parses and
dispatches the backend's `message_acked` and `message_delivered` events
(`MessageAckedEvent` / `MessageDeliveredEvent`) plus `receipt_updated`
(`ReceiptUpdatedEvent`). See the event catalogue in the developer guide.

## 0.5.x → 0.6.x

### Breaking: type renames

Several types were prefixed with `Chat` to avoid collisions with types from
other packages (`result_dart`, `dartz`, pagination helpers, etc.).

| Before (0.5.x)              | After (0.6.x)                 |
| --------------------------- | ----------------------------- |
| `Result<T>`                 | `ChatResult<T>`               |
| `Success<T>`                | `ChatSuccess<T>`              |
| `Failure`                   | `ChatFailureResult`           |
| `PaginationParams`          | `ChatPaginationParams`        |
| `CursorPaginationParams`    | `ChatCursorPaginationParams`  |
| `PaginatedResponse<T>`      | `ChatPaginatedResponse<T>`    |
| `SortOrder`                 | `ChatSortOrder`               |

`ChatFailure` (the sealed base class for all domain-specific failures) keeps
its name — only the `Failure` result-wrapper type that was distinct from it
was renamed to `ChatFailureResult`.

**Before:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final Result<PaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: PaginationParams(limit: 20, sortOrder: SortOrder.desc),
  );

  switch (result) {
    case Success(:final value):
      // use value.items
    case Failure(:final failure):
      // handle failure
  }
}
```

**After:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final ChatResult<ChatPaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: ChatPaginationParams(limit: 20, sortOrder: ChatSortOrder.desc),
  );

  switch (result) {
    case ChatSuccess(:final value):
      // use value.items
    case ChatFailureResult(:final failure):
      // handle failure
  }
}
```

**Cursor pagination:**

```dart
// Before
final params = CursorPaginationParams(cursor: lastCursor, limit: 50);
// After
final params = ChatCursorPaginationParams(cursor: lastCursor, limit: 50);
```

### Breaking: mock classes moved to a testing barrel

`MockChatClient` and its eight `Mock*Api` siblings were removed from the
primary `package:noma_chat/noma_chat.dart` barrel. Import the dedicated
testing barrel in test files:

```dart
// Before
import 'package:noma_chat/noma_chat.dart'; // exposed MockChatClient

// After
import 'package:noma_chat/noma_chat_testing.dart'; // all Mock*Api siblings
```

The primary barrel is unchanged for production imports.

### Behaviour change: RetryInterceptor

Non-idempotent verbs (POST, PATCH, DELETE) are no longer retried on transient
connection errors by default. If you have a POST endpoint that is safe to
replay (e.g. because it is idempotent on your backend), opt in per request:

```dart
await chat.client.messages.sendCustom(
  roomId: roomId,
  payload: myPayload,
  extra: {'idempotent': true}, // opt-in replay for this call
);
```

### New: `ChatConfig.developerLogger` / `debugOnlyLogger`

Two ready-made logger callbacks are now available as static helpers on
`ChatConfig` — no need to wire `dart:developer` manually:

```dart
// Before
import 'dart:developer' as dev;
final chat = await NomaChat.create(
  // …
  logger: (level, msg) => dev.log(msg, name: 'noma_chat'),
);

// After
final chat = await NomaChat.create(
  // …
  logger: ChatConfig.debugOnlyLogger, // silent in release, developer.log in debug
);
```

### New: `MetricCallback` (observability)

Wire a metric sink to capture SDK-emitted telemetry events:

```dart
final chat = await NomaChat.create(
  // …
  metricCallback: (name, data) => myAnalytics.record(name, data),
);
```

See [TELEMETRY.md](./TELEMETRY.md) for the full event catalog.
