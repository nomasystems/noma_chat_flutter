# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/). From `1.0.0`
onwards, breaking changes require a **major version bump**.

## [0.10.1] - 2026-07-03

### Added

- **Cross-platform capability gating (`PlatformSupport`).** Attachment and
  avatar UI now degrade gracefully on platforms whose plugins do not cover
  every target: camera capture and image crop are offered on mobile (crop on
  mobile only), while downloaded files open natively on mobile and fall back to
  the OS default handler via `url_launcher` on desktop. Derived from `kIsWeb` +
  `defaultTargetPlatform` (never `dart:io`), so it resolves on web too, hiding
  controls a platform cannot honour instead of surfacing ones that silently
  fail.
- **Example app now builds for desktop and web** (Linux, macOS, Windows, web)
  in addition to Android and iOS.

### Changed

- **`ChatConfig` URL validation exempts loopback hosts from the release-mode
  HTTPS requirement.** `http://` to `localhost`, `127.0.0.0/8`, or `::1` stays
  allowed in release builds — loopback traffic never leaves the device and
  every platform treats it as a secure context — while every other host still
  requires `https://` (pentest M-10). The `127.` match is anchored to an IPv4
  literal so a DNS host such as `127.evil.com` is not mistaken for loopback.

## [0.10.0] - 2026-06-17

### Added

- **Global message search — `messages.search()` `roomId` is now optional.**
  `roomId` changed from a required to an optional named argument
  (`String? roomId`). Call `messages.search(query)` to search **globally**
  across every room the caller belongs to (the backend scopes results to the
  authenticated user's rooms); `messages.search(query, roomId: 'x')` keeps the
  single-room behaviour. The `roomId` query param is sent to
  `GET /messages/search` only when non-null. Non-breaking for existing
  single-room callers, who already pass `roomId:` by name. New `ChatMessagesApi`
  interface contract — see the migration note for custom implementers.
- **Unified room preferences — `rooms.patchPreferences()`.** New
  `rooms.patchPreferences(roomId, {muted?, muteUntil?, pinned?, hidden?})`
  sends a single partial `PATCH /rooms/{roomId}/preferences` and returns the
  merged server-side state as a new `RoomPreferences` model (`muted`,
  `pinned`, `hidden`, `muteUntil?`). Pass only the fields you want to change;
  a non-null `muteUntil` is sent as an ISO-8601 string for WhatsApp-style
  timed mutes. This is the single write path for room preferences on the data
  API. `ChatResult` gains a `discardValue()` helper (plus a matching
  `Future<ChatResult<T>>` extension) that drops a success value to
  `ChatResult<void>` while preserving the outcome. New `ChatRoomsApi` interface
  method — see the migration note for custom implementers.
- **Stable error tokens — `ChatFailure.errorToken`.** Every `ChatFailure` now
  exposes an optional `String? errorToken`: a stable snake_case symbolic code
  from the server's vocabulary (`room_not_found`, `edit_window_expired`,
  `blocked`, `rate_limited`, `cannot_delete_other_user`, …) surfaced alongside
  the existing `{code, detail}`. Host apps should branch and localize on the
  token instead of the English `message`. Well-known constants live on the new
  `ChatErrorTokens` holder; the field is a `String?` (not an enum) so a new
  server token never breaks the SDK. The token also rides on
  `OperationError.failure.errorToken`. Purely additive.
- **GDPR self-deletion — `users.deleteCurrentUser()`.** New method calling
  `DELETE /users/me`, the robust default for self-service account erasure (the
  server resolves the principal from the auth token, so it can't target the
  wrong account). New `ChatUsersApi` interface method — see the migration note
  for custom implementers.
- **Member-list `users` expansion — no more N+1 for group rosters.**
  `members.list` gains an `expand` param; passing
  `[RoomMemberExpand.users]` sends `?expand=users` and the backend embeds each
  member's `displayName` + `avatarUrl` straight in the row. `RoomUser` gains
  nullable `displayName` / `avatarUrl` (populated only on an expanded
  response). Rendering a group roster no longer needs a `GET /users/{id}` per
  member — one `list` call carries everything. The built-in `GroupMembersView`
  now requests this expansion and seeds the adapter user cache from the
  embedded fields, eliminating the per-member profile fetch out of the box.
  Backward-compatible: without `expand` the fields stay `null` and the
  user-cache fallback is unchanged. Purely additive.
- **Canonical reactions endpoint — `messages.addReaction()`.** New
  `messages.addReaction(roomId, messageId, emoji: '👍')` POSTs the dedicated
  `/rooms/{roomId}/messages/{messageId}/reactions` sub-resource (HTTP `201`)
  instead of synthesising a reaction-typed message via
  `send(messageType: MessageType.reaction)`. Modelling a reaction as a
  first-class sub-resource keeps it out of the timeline and the offline send
  queue. `messages.deleteReaction` gains an optional `emoji` — when supplied it
  sends `?emoji=…` so a specific reaction can be removed (omit it to clear the
  user's reaction wholesale, the historical behaviour). The built-in
  optimistic UI reacts and un-reacts through these canonical calls.
  `addReaction` / `deleteReaction` are the only supported reaction API; the SDK
  no longer sends reactions via `send(messageType: MessageType.reaction)`. New
  `ChatMessagesApi` methods — see the migration note for custom implementers.
- **Bidirectional opaque cursor pagination.** `ChatCursorPaginationParams`
  carries an opaque `cursor` (String) plus a `direction`
  (`ChatCursorDirection.older` / `.newer`, emitted as the `direction` query
  param; `null` lets the backend default to `newer`). `ChatPaginatedResponse`
  exposes two seq-based cursors: `prevCursor` (parsed from the response `prev`
  field, anchored on the oldest message of the page) and `nextCursor` (parsed
  from `next`, anchored on the newest). To load older history pass `prevCursor`
  with `direction: ChatCursorDirection.older`; to catch up on newer messages
  pass `nextCursor` with `direction: ChatCursorDirection.newer`. `hasMore`
  reports whether more pages exist in the requested direction. The cursors are
  seq-based, so paging never skips or replays messages that share an exact
  millisecond. The load-more, chat-export, media-gallery and polling/manual
  realtime paths all run on these cursors.
- **Signed attachment URLs — `attachments.signedUrl()` (primary download
  path).** New `attachments.signedUrl(attachmentId, roomId: ...)` returns an
  `AttachmentSignedUrl` whose `.url` is absolute, short-lived, and
  self-authorizing (HMAC signature + expiry + user baked in) — it drops
  straight into `Image.network` / `CachedNetworkImage` / a native viewer with
  no auth headers to re-attach. Hits
  `GET /attachments/{attachmentId}/signed-url?roomId=...`; the backend
  authorizes by room membership fail-closed. `attachments.download` gained an
  optional `roomId`: when present it takes this same signed-URL path under the
  hood (falling back to a `roomId`-scoped header request only if the backend
  returns no URL). New `ChatErrorTokens.notARoomMember` (`not_a_room_member`)
  is surfaced on the resulting `ForbiddenFailure.errorToken` when the caller
  isn't a member of the room. New `ChatAttachmentsApi.signedUrl` method — see
  the migration note for custom implementers.
- **Canonical managed-users list — `users.getManagedByParent()`.** New
  `users.getManagedByParent(parentId, {pagination})` calls
  `GET /users/{parentId}/managed-users`, the backend's canonical replacement
  for the old `GET /managed-users/{userId}` list path (operationId
  `getManagedUsersByParent`). Returns the paginated `{users, hasMore}` response
  shape. The only managed-users list method; it replaces the removed
  `getManaged` (see Removed). Wired through the `ChatUsersApi` interface, the
  REST implementation, and the mock client. See the migration note for custom
  implementers.

- **`NomaChatView` — drop-in chat-room screen.** Wraps `ChatRoomAppBar` +
  `ChatView` and auto-wires the seven per-room behaviors hosts used to
  reimplement by hand (history + pin load, unread divider, group member
  hydration, blocked / room-removed reactions, role-aware context menu, report
  dialog, reaction-user fetcher). Additive — `ChatView` is unchanged and stays
  available for fully custom screens. See the migration guide and the
  Developer Guide for the override slots. A matching quickstart was added to the
  README so the common case is `NomaChat.create(...)` + `NomaChatView(...)`,
  with the persistent Hive cache initialized automatically (default
  `enableCache: true` on `NomaChat.create` opens the store; no manual
  `Hive.initFlutter()` needed for the default path).
- **Group invite links — `members.joinWithToken` + `ChatInviteLink`.** Public
  / invitable rooms can be joined via a shareable link: build one from a room's
  `publicToken` with `ChatInviteLink(...).toUri(base)`, and self-join from an
  incoming deep link with `members.joinWithToken(roomId, token: …)` (a wrapper
  over `invite` with `inviteAndJoin` for the current user). `toUri` and
  `ChatInviteLink.tryParse` accept custom query-parameter names. Surfaced in
  the room menu via the new `ChatRoomOption.inviteViaLink` preset (copies the
  link to the clipboard by default). `joinWithToken` is a new
  `ChatMembersApi` interface method — see the migration note for custom
  implementers.
- **Export a chat — `adapter.messages.exportChat(roomId)`.** Returns a
  `ChatExport` whose `text` is the room's full history as a WhatsApp-style
  transcript; writing the file and sharing it is left to the host app (no new
  dependency). Surfaced via `ChatRoomOption.exportChat`.
- **"Message info" sheet — `MessageInfoSheet` + `MessageAction.info`.** Lists
  who read / was delivered a message. `NomaChatView` wires it automatically:
  `MessageAction.info` is in the default context-menu set and shows only on the
  user's own messages. (`MessageAction` gained an `info` value — affects
  exhaustive `switch`es on custom menus only.)
- **Idempotent sends — `clientMessageId`.** `messages.send` accepts an optional
  `clientMessageId` (≤128 chars); when set, the backend makes the send
  idempotent over `(roomId, sender, clientMessageId)` and a POST retry that
  replays the key returns the already-persisted message instead of a duplicate.
  The key round-trips inside the response `metadata.clientMessageId`, which the
  SDK reads back onto `ChatMessage.clientMessageId`. `NomaChatView` / the
  adapter generate one per optimistic message and the offline queue reuses it
  on every retry, so a send that actually landed before a network failure
  surfaced is never duplicated. Pass your own only for custom send flows.
- **Starred messages — `MessageAction.star` + `StarredMessagesView`.** Per-user
  bookmarks (WhatsApp-style). `messages.starMessage` / `unstarMessage` and the
  paginated cross-room `messages.listStarred` are new on `ChatMessagesApi`; the
  adapter exposes `star` / `unstar` / `loadStarred`. `MessageAction.star` is in
  the default context menu (wired in `NomaChatView`), and `StarredMessagesView`
  (or `.fromAdapter(adapter)`) renders the list.
- **Mute with a duration — `rooms.mute(roomId, until:)`.** Optional `until`
  (a `DateTime`); omit it for a permanent mute. `ChatRoomOption.muteRoom` is now
  duration-aware (`onMute(DateTime? until)` + `onUnmute()`) and the SDK presents
  a `MuteDurationSheet` (8h / 1 week / always) on tap. `RoomDetail`,
  `UnreadRoom` and `RoomListItem` gained a `muteUntil` field.
- **"@" mention badge + Archived section.** `UnreadRoom` / `RoomListItem`
  gained `unreadMentions`; `RoomTile` shows an "@" badge when it is `> 0`.
  `RoomListView` renders a collapsible **Archived** section for hidden rooms
  (backed by the existing `hidden` pref); `RoomListController` exposes
  `archivedRooms` / `hasArchivedRooms`, and `ChatRoomOption.archiveChat` /
  `unarchiveChat` map to `rooms.hide` / `unhide`.
- **Edit / delete windows + typed `403` failures.** `ChatViewBehaviors` gained
  `editWindow` (default 15 min) and `deleteWindow` (default 2 days):
  `NomaChatView` hides the edit / delete context-menu actions on the user's own
  messages once the window closes (`null` disables). A late attempt the backend
  rejects now surfaces as the typed `EditWindowExpiredFailure` /
  `DeleteWindowExpiredFailure` instead of a generic forbidden failure.
- **`ChatConfig.actAsUserId` (managed-user delegation).** Set it to act on
  behalf of a managed user — every REST request then injects
  `X-From-User-Id: <actAsUserId>`. The backend enforces the parent→managed
  relationship (`403` if not allowed). REST only; does not change the real-time
  identity.
- **`rooms.create(..., forceGroup: true)`.** By default a contacts room with a
  single other member collapses to a DM-style room; pass `forceGroup: true` to
  keep it a named group. Defaults to `false`, so existing calls are unchanged.
- **`members.invite` now reports per-user outcomes.** It returns
  `ChatResult<InviteResult>` (was `ChatResult<void>`) so callers can inspect
  the per-user result when the backend answers `207 Multi-Status` (some users
  banned / already members / etc.). The `userRole` parameter was removed (the
  backend never accepted a per-invite role) and an optional `token` parameter
  was added for public-room joins. See the migration guide for the before/after.
- **Cursor-based delivery ticks (WhatsApp-style).** The SDK now consumes the
  two new realtime events of the `1.0.0` backend: `message_acked` (the server
  durably persisted an own message — single gray tick; surfaced as
  `MessageAckedEvent` with the server-assigned `seq` and the message metadata
  echoed for client-side correlation) and `message_delivered` (a user's
  delivered cursor advanced — one event flips the double gray tick on every
  message at-or-before the cursor, for any author). Cursors are max-registers:
  duplicated or reordered events are harmless by construction.
- **`ChatMessagesApi.markRoomAsDelivered(roomId, lastDeliveredMessageId:)`** —
  consolidated delivered-cursor confirmation: one call per conversation covers
  any number of messages, via the new WebSocket `delivered` frame when
  connected and the receipts endpoint otherwise. Prefer it over
  `sendReceipt(status: delivered)` (legacy per-message path, rerouted
  server-side to the same cursor).
- **`ChatUiAdapter.autoConfirmDelivery`** (default `true`): the adapter
  confirms delivery automatically — on live messages in non-active rooms, on
  chat load, and on the post-login/reconnect room sync — coalesced per room
  (at most one confirmation in flight; a burst costs ≤2 calls). Turn it off to
  drive confirmation manually through `markRoomAsDelivered`.
- **`ReadReceipt` gains `lastDeliveredMessageId` / `lastDeliveredAt`**
  (additive, nullable). Receipt rehydration on chat open now restores
  delivered ticks too, and read coverage uses conversation order against
  `lastReadMessageId` instead of the over-marking timestamp comparison
  (kept only as fallback for whole-room reads).
- **`ChatBubbleTheme.statusIconBuilder`** — per-state override of the
  delivery-status icon, applied both at the bubble corner and next to the
  room-list preview. The builder receives a `MessageStatusIconData`
  (`MessageDeliveryState` — sending / sent / delivered / read / failed —
  plus the suggested size and, in bubbles, the message); returning `null`
  falls back to the SDK default for that state, so partial overrides are
  one switch case away. The default rendering is unchanged.
- **`ChatBubbleTheme.statusPendingColor`** — dedicated color for the
  pending clock shown while a message is in flight (falls back to
  `statusColor`, so existing themes look the same). The clock also gains
  a "Sending" semantics label (`ChatUiLocalizations.statusSending`).

> Compatibility: 0.9.x clients keep working against a backend that emits the
> new events (unknown types are ignored), but their live delivered tick stops
> updating — the backend emits `message_delivered` instead of the legacy
> `receipt_updated{status: delivered}`. Bubbles jump from sent to read; ticks
> in listings stay correct. Upgrade to 0.10.0 to restore live delivered ticks.

### Changed

- **`lastUnreadMessage` preview is now object-or-null only.**
  `RoomMapper.unreadRoomFromJson` reads the room preview exclusively from the
  nested `lastUnreadMessage` object; when it is `null` or absent the room has
  no unread preview (all `lastMessage*` fields stay null). The legacy flat
  `lastMessage*` fallback fields and the "magic 0" handling are gone. No public
  model change — `UnreadRoom` is unchanged.

- **Typed-failure routing is now token-first.** The exception mapper prefers
  the server's stable `error` token to choose the typed failure (e.g.
  `edit_window_expired` → `EditWindowExpiredFailure`, account-deactivation
  tokens → `AuthFailure`), keeping the legacy `detail` string-matching as a
  fallback for older servers. No behavior change against existing backends.
- **`users.delete(userId)` is own-account-only.** The backend tightened
  `DELETE /users/{userId}` to the caller's own id; a non-own id returns a 403
  that surfaces as a `ForbiddenFailure` carrying the
  `cannot_delete_other_user` token. Prefer `deleteCurrentUser()`.
- **`messages.send` now autogenerates a `clientMessageId` when omitted.** The
  server-side dedup is a partial unique index over messages that carry a
  `clientMessageId`, so a raw `send()` without one could be persisted twice if
  retried after a transient 429/5xx. `send()` now generates a UUID v4 when the
  caller doesn't pass `clientMessageId`, making retries safe for every consumer
  (the canonical UI path already passed one). Pass your own value only to
  correlate with an external id. The field is always sent now.
- **Certificate pinning documented honestly as not-yet-enforced.**
  `ChatConfig.certificatePins` and `CertificatePinningInterceptor` are an
  experimental skeleton: the native handshake hook is **not** wired, so no
  certificate is validated against the pins and there is no MITM protection
  today. `SECURITY.md`, the `certificatePins` dartdoc and the audit history were
  corrected to stop claiming otherwise, and the SDK now emits a `warn` log when
  pins are configured. No behaviour change — pinning was already a no-op.

- **`ChatConfig.ssePath` default changed from `/events` to `/eventsource`.**
  The old default never worked against CHT/NRTE; this is a fix, not a
  regression. Callers that override `ssePath` explicitly are unaffected.
- **Dropped `json_annotation` / `json_serializable` dependencies.** The SDK no
  longer uses these code-gen packages; they were never part of the public API
  and removing them has no consumer impact (add them to your own `pubspec.yaml`
  if you relied on them transitively).
- **Backend contract pinned to OpenAPI `1.0.0`.** The bundled spec
  (`doc/chat-api-openapi.yml`) now tracks the first stable version of the
  Nomasystems chat API (previously an internal `2.10.0` numbering that never
  shipped). The copy stays byte-identical to the backend source of truth.
- **Managed-user webhook config speaks the `1.0.0` wire format.** It is now
  serialized as `{ url, authMethod, authToken }` instead of the old nested
  `auth` object. The public `WebhookConfig` model is unchanged (bearer token,
  or basic username + password); basic credentials are sent as standard
  base64 `user:pass`. Legacy nested `auth{}` payloads are still parsed for
  resilience against stale servers or caches.

### Deprecated

- **Header-only attachment download.** Calling `attachments.download(id,
  metadata: ...)` *without* `roomId` (the `x-attachment-metadata`
  header-authorized flow) is deprecated. The backend now enforces room
  membership and requires a `roomId`; the header alone no longer authorizes a
  download and returns `403 not_a_room_member`. Pass `roomId` to take the
  signed-URL path, or use `attachments.signedUrl(...)` directly. See
  `MIGRATING.md`.

### Removed

- **Legacy XMPP sender/identity aliases.** The SDK no longer reads the
  deprecated `jid` / `fromJid` (and the secondary `id`) fallbacks.
  `UserMapper.contactFromJson` parses `userId` only and
  `RoomMapper.unreadRoomFromJson` parses the preview sender from `from` only
  (`EventParser` likewise drops the `fromJid` alias). Current backends emit the
  canonical fields, so this is a no-op against them; servers that emit only the
  dropped aliases are no longer supported.
- **`users.getManaged(userId)`.** Removed. Use
  `users.getManagedByParent(parentId)` (canonical
  `GET /users/{parentId}/managed-users`) — same arguments and response shape.
  Dropped from the `ChatUsersApi` interface, the REST implementation, and the
  mock. See `MIGRATING.md`.
- **Data-API room-preference toggles `rooms.mute` / `unmute` / `pin` /
  `unpin` / `hide` / `unhide`.** Removed from `ChatRoomsApi` (interface, REST
  implementation, and mock). Call `rooms.patchPreferences(...)` directly. The
  optimistic single-flag wrappers on the UI adapter
  (`adapter.rooms.mute/unmute/pin/unpin/hide/unhide`) are unchanged and now
  drive `patchPreferences` internally. The user-moderation
  `members.muteUser` / `unmuteUser` (a different endpoint) are unaffected. See
  `MIGRATING.md`.
- **Reaction-via-send path.** The SDK no longer issues reactions through
  `send(messageType: MessageType.reaction)`; `messages.addReaction` /
  `deleteReaction` are the only supported reaction API. The general
  `messages.send` still accepts `messageType` / `reaction` for other uses.
- **`ChatCursorPaginationParams.before` / `.after` (ISO-8601 timestamp
  paging).** Removed entirely. They no longer exist as fields, are no longer
  emitted as `before` / `after` query params, and the timestamp/id boundary
  dedup that backed them in the polling realtime engine is gone. All paging is
  now driven by the opaque `cursor` + `direction` (older/newer) against the
  `prevCursor` / `nextCursor` anchors. See `MIGRATING.md`.

### Fixed

- **User profile page now reflects the backend after its background refresh.**
  `UserInfoPage` paints from the user cache for an instant first frame, then
  always re-fetches the profile from the backend. The re-fetch wrote only local
  widget state, so a cache entry seeded by a roster / members endpoint (which
  may omit `bio`) kept shadowing the fresh record and the description never
  appeared. The fetched record is now fed back into the shared user cache, so
  the always-on refresh wins and the live `ListenableBuilder` repaints.
- **Polling could skip messages sharing an exact millisecond.** The REST
  polling/manual `RefreshEngine` tracked progress by last-seen timestamp plus a
  boundary id set. When the backend now returns an opaque `next` cursor the
  engine switches to seq-based cursor polling (and drops the timestamp dedup),
  eliminating the identical-timestamp skip. Old backends without `next` keep
  the timestamp path (soft degradation). Stale pagination state carried into a
  freshly built engine is purged on its first tick so the upgrade can't replay
  or skip across the scheme change.
- **Realtime parser hardened against off-contract payloads.** Several
  `EventParser` handlers read wire fields with raw `as String?` / `as int?`
  casts (and one non-nullable `as String` for `lastSeen`), so a backend that
  shipped a field with an unexpected type (e.g. a numeric `lastSeen`) threw an
  uncaught `TypeError` out of the WebSocket stream callback and could stop
  event delivery. Every field is now read through a safe type check and
  degrades gracefully (the field, or the event, is dropped). As defense in
  depth, `WsTransport` wraps event dispatch in a guard so no parser error can
  tear down the stream — matching the SSE path, which already guarded
  `parseNrte`. Re-enables and broadens the previously-skipped `FUZZ-BUG-2`
  regression group to cover every handler.
- **Quickstart room-list snippets now compile.** The README and Developer
  Guide examples referenced a non-existent `RoomListController(chat: chat)`
  constructor and omitted `currentUserId` (needed for own-message ticks and the
  group "You:" prefix). They now use `chat.roomListController` with
  `currentUserId`; the Developer Guide no longer shows a manual `dispose()` (the
  SDK owns the controller) or non-existent `onInvitation*` setters, using the
  real `RoomListView` `onAcceptInvitation` / `onRejectInvitation` callbacks.
- **Media gallery and DM/conversation history now paginate older pages.**
  `attachments.listInRoom`, `contacts.getDirectMessages` and
  `contacts.getConversationMessages` built their `ChatPaginatedResponse` without
  parsing the `next` / `prev` cursors from the response (a regression from the
  opaque-cursor migration), so `prevCursor`/`nextCursor` were always `null` and
  the "shared in this chat" gallery, DMs and conversation timelines stopped
  after the first page even when `hasMore == true`. They now parse `json['next']`
  / `json['prev']` like `messages.list` does.
- **Timestamps and day separators now render in the device's local time
  zone.** `DateFormatter.formatTime` / `formatSeparator` / `isSameDay` /
  `isToday` / `isYesterday` formatted the backend's UTC `DateTime` directly, so
  users outside UTC saw wrong clock times and could see a message land on the
  wrong calendar day. All helpers now call `.toLocal()` first, matching the
  export and starred-message formatters.
- **Group delivery ticks no longer stick on "read by all" during member
  hydration.** `ChatController` inferred 1:1-vs-group purely from
  `otherUsers.length`, which is 0–1 before the member list loads; a group whose
  members hadn't hydrated yet was treated as a 1:1, so a single peer's read flag
  flipped every message to the blue "read by all" tick permanently. The group
  flag is now pinned explicitly via `ChatController.setIsGroup(...)` (wired from
  `RoomListItem.isGroup` the moment the room opens), `_aggregateStatus` never
  collapses a known group to 1:1 (and stays at `sent` until members are known),
  and `setOtherUsers` recomputes receipts whenever the member count changes.
- **SSE reconnect / RefreshEngine re-entrancy races.** `SseTransport._doConnect`
  now cancels any armed reconnect timer and prior request before connecting
  (mirror of `WsTransport`), so a `connect()` racing a scheduled reconnect can no
  longer open two parallel streams that double-emit events. `RefreshEngine.tick`
  gained a `_ticking` re-entrancy guard (like `OfflineQueue`) so a fast poll
  interval or a mid-tick `refreshRoom` can't interleave cursor/snapshot mutations.

- **Direct message to a contact who has blocked you (HTTP 204) no longer yields
  a phantom message.** Per the `1.0.0` contract the backend silently drops it
  with an empty body (WhatsApp parity). The SDK now synthesizes a local `sent`
  message instead of an empty, id-less one, so the bubble shows as sent and
  never advances to delivered/read — exactly what a blocked sender sees.
- **`RateLimitFailure.retryAfter` is now populated against CHT.** CHT's `429`
  sends `X-RateLimit-Reset` (seconds until the window resets) and no
  `Retry-After`; the SDK now reads `X-RateLimit-Reset` as a fallback, so
  `retryAfter` (and the retry interceptor's back-off) reflect the real reset
  window instead of being `null`. No code change required.
- **Terminal auth close (`4005 too_many_auth_attempts`) suspends both
  transports.** It stops the WebSocket and prevents the SSE failover from
  reconnecting with the rejected token. The SDK emits a terminal
  `ChatAuthException` (`exception.terminal == true`) and stays in `error` until
  a fresh token is obtained and `connect()` is called again — listen for it to
  drive a re-authentication prompt.

### Confirmed

- `message_acked` / `message_delivered` WebSocket events (`MessageAckedEvent`
  / `MessageDeliveredEvent`) and `receipt_updated` (`ReceiptUpdatedEvent`) are
  parsed and dispatched by the SDK — documented in the event catalogue. No code
  change.

## [0.9.2] - 2026-05-29

### Docs

- Documented that the SDK targets a **Nomasystems chat backend** defined by a public **OpenAPI 3.0 contract**; any backend that implements the spec works. The README now links a rendered API reference (Redoc) and the source spec.
- Added the backend OpenAPI contract to the repository (`doc/chat-api-openapi.yml`, OpenAPI 3.0.1). Kept on GitHub and linked from the README; excluded from the published tarball via `.pubignore` (consumers don't need it in their pub cache).
- Noted that the Nomasystems chat backend is planned to be open-sourced but is not public yet; for commercial use contact `info@nomasystems.com`. Added the Nomasystems website.
- Renamed "UI Kit" to "UI components" across the README, dartdoc API docs and developer docs.
- Screenshots and the demo GIF now have transparent backgrounds so they render cleanly on pub.dev (light and dark themes).
- Fixed a broken README link (`INTEGRATING.md` → `INTEGRATION.md`).

## [0.9.1] - 2026-05-29

### Dependencies

- **Breaking (consumers)**: minimum SDK raised to **Flutter 3.44 / Dart 3.12**.
  Required by `record` 7, which dropped support for older SDKs.
- `record` bumped `^6.0.0` → `^7.0.0` (the audio recorder used by voice
  messages). The Dart API we use (`start`/`stop`/`pause`/`hasPermission`)
  is unchanged; record 7's breaking changes are native-only (Android
  background service, iOS `manageAudioSession`) and unused here.
- `file_picker` lower bound raised `>=9.0.0` → `>=11.0.0`. The attachment
  picker calls the `FilePicker.pickFiles` **static** API, which only exists
  from file_picker 11.0.0 (it was instance-based before) — the old `>=9.0.0`
  constraint let the package resolve to a version where the code did not
  compile.

### Docs

- README quick-start now pins `noma_chat: ^0.9.0` (was a stale `^1.0.0`).

## [0.9.0] - 2026-05-29

### Security

- HTTP debug logger (`enableHttpLog: true`) now redacts sensitive values
  in request/response bodies (`password`, `token`, `secret`,
  `authorization`, `api_key`, `otp`, `pin`, `credential` and common
  variants) and replaces binary payloads with a `<binary N bytes>`
  placeholder. Previously bodies were logged verbatim and could leak
  credentials to whichever sink the consumer wired (Sentry, file log,
  console). Opt-in flag and `logger` callback semantics are unchanged.

### Robustness

- `HiveChatDatasource` serializes per-room writes (`saveMessages`,
  `updateMessage`, `deleteMessage`, `clearMessages`) through an internal
  per-`roomId` lock. Concurrent saves to the same room can no longer
  leave the message-id index pointing to a key that was just removed.
  Cross-room writes still run in parallel.
- `RestClient` now exposes `cancelPending()` and the facade calls it on
  `disconnect`/`dispose`/`logout`, so in-flight HTTP requests are aborted
  instead of resurfacing as 401s through a stale `tokenProvider`.
- `BearerAuthInterceptor` token refresh resets the WebSocket reconnect
  attempt counter only on `auth_ok`, not on every `connect()` call —
  prevents a programmatic reconnect from clobbering an in-progress
  backoff schedule.
- `AutoFailoverTransport` re-arms the SSE fallback on every primary drop,
  not just the first one — connectivity recovers cleanly after a primary
  + fallback double failure.
- `RetryInterceptor` no longer retries non-idempotent verbs (POST, PATCH,
  DELETE) on transient connection errors by default. Opt back in with
  `options.extra['idempotent'] = true` per request when the caller can
  guarantee safe replay.
- Exponential backoff with jitter is now computed in a single helper
  (`computeBackoffMs`) used by WS, SSE and HTTP retry layers. Jitter is
  added before the cap so the maximum delay is honoured exactly.
- `AutoFailoverTransport.dispose()` now propagates to both the primary
  and fallback transports. Previously only streams and subscriptions
  were cleaned up; the inner transport event/state streams were never
  closed, leaking listeners across reconnect cycles.
- `WsTransport._onMessage` now wraps `jsonDecode` in a try/catch so a
  malformed frame (invalid JSON, non-UTF-8 bytes) is silently discarded
  rather than propagating an uncaught `FormatException` to the zone.
- `MessageDto.fromJson` no longer hard-casts `id`, `from`, and
  `timestamp` fields. Non-string values (e.g. integer ids from certain
  backends) are coerced via `toString()` instead of throwing
  `_TypeError`. Similarly `text_history` guards against non-List values.
- `PollingConfig.interval` below the 5 s floor is now clamped to 5 s with
  a warning instead of throwing `ArgumentError`. A bad value supplied by
  the consumer degrades the polling cadence rather than crashing
  `NomaChat.create` at login.

### Public surface

- **Breaking**: types prefixed for clarity. `Result` → `ChatResult`,
  `Success` → `ChatSuccess`, `Failure` → `ChatFailure*` (the existing
  failure hierarchy keeps its `ChatFailure` base name and the `Result`
  variant renames to `ChatFailureResult`), `PaginationParams` →
  `ChatPaginationParams`, `CursorPaginationParams` →
  `ChatCursorPaginationParams`, `PaginatedResponse` →
  `ChatPaginatedResponse`, `SortOrder` → `ChatSortOrder`. Reduces
  collisions with apps that already use `Result` / `Pagination` /
  `SortOrder` from other libraries.
- `ChatLocalDatasource` and `CachePolicy` moved out of `lib/src/_internal/`
  (which is meant to be opaque) into `lib/src/cache/`. The barrel export
  paths are unchanged.
- `MockChatClient` and its eight `Mock*Api` siblings moved from the
  primary `package:noma_chat/noma_chat.dart` barrel to a dedicated
  `package:noma_chat/noma_chat_testing.dart`. Production apps no longer
  see test scaffolding in autocomplete; tests `import` the testing
  barrel explicitly.
- `MetricCallback` exported from `package:noma_chat/noma_chat_advanced.dart`
  (was reachable only by path before).
- `ChatLogger` mentioned in earlier changelog drafts is renamed to the
  typedef it actually is (`void Function(String level, String message)`).
- `ChatRoomsApi.updateRoom` / `updateConfig` gains a `clearAvatar` flag.
  When `true` the SDK sends an explicit empty avatar so a group photo can
  be removed (the backend's merge-with-preserved config otherwise keeps
  the old one). Mutually exclusive with a non-null `avatarUrl`.
- `RoomDetail` and `RoomListItem` gain a `selfMuted` field (moderation
  mute: an admin/owner silenced the current user in the room, distinct
  from `muted` = the user's own notification preference). `isReadOnly`
  now also returns `true` when `selfMuted`, so the composer goes
  read-only.
- `UserInfoPage` added and exported — a read-only WhatsApp-style "user
  info" page for a DM peer (large avatar, display name, bio). The
  read-only twin of `ProfileSettingsPage`.
- `ChatConfig.eventBufferSize` default changed from `0` to `20`. Late
  subscribers (e.g. a second `ChatController`) now replay the last 20
  events on attach instead of none; set it back to `0` to opt out.

### UI

- Accessibility: composer send/attach/camera/voice and voice-recorder
  overlay buttons enlarged to ≥48 dp tap targets (WCAG AA). Status icon
  in message bubbles now exposes a `Semantics` label (`sent`,
  `delivered`, `read`, …) and the timestamp/status/reactions row is
  wrapped in `MergeSemantics` so screen readers announce the row once.
- `MessageList` typing-row branch no longer recomputes `isGroup` from
  `otherUsers.length`; reuses the host-provided `widget.isGroup` like the
  message branch already did. Fixes typing label/avatar regressions for
  callers that wire `isGroup` explicitly.
- Audio bubble migrated to `ValueListenableBuilder<Duration>` for the
  seek bar; the play button, speed button and status row no longer
  rebuild on every player tick.
- Cache: `CacheManager._timestamps` is persisted to a Hive meta box so
  cold-starts no longer always fall through `cacheFirst` to network for
  rooms/contacts.
- `chat_room_options_menu.dart` factory `blockUser` documented for
  parity with the others.

### Internal / tests

- `ChatUiAdapter` sub-API split: the 71 public methods now live in
  their five sub-controllers (`ChatMessagesController`,
  `ChatRoomsController`, `ChatContactsController`, `ChatProfileController`,
  `ChatDmController`) instead of in the adapter itself. Each controller
  is a `part of '../chat_ui_adapter.dart'` and accesses the adapter's
  state through a single `_a` reference. The adapter retains a thin
  pass-through for every method (`adapter.sendMessage(...)` ⇒
  `adapter.messages.send(...)`), so existing callers and tests work
  unchanged. `chat_ui_adapter.dart` drops from 2591 → 1706 LOC (-34%).
  See `plans/split_chat_ui_adapter.md` for the sessions journal.
- `chat_ui_adapter` further decomposed: `RoomListMutator` and
  `MemberEventHandler` extracted as standalone collaborators. Adapter
  drops from ~2960 LOC to ~2300 LOC.
- `MessageInput` voice-recorder gesture machine extracted to
  `MessageInputVoiceController` (ChangeNotifier) — composer state is no
  longer entangled with drag/lock/overlay logic.
- `ChatTheme.copyWith` (~250 manual lines) replaced with the Freezed
  generator; adding a slot is now a one-line edit.
- `MessageList`, `MessageBubble`, `TextBubble` and `ChatView` `build`
  methods broken into `_build*` helpers (no behaviour change, just
  legibility).
- 31 cross-barrel self-imports inside `lib/src/*` replaced with relative
  paths. The symbolic cycle (`lib/noma_chat.dart` exporting files that
  import `package:noma_chat/noma_chat.dart`) is gone.
- `lib/src/_internal/util/backoff.dart` added (shared helper, see above).
- `test/cache/hive_chat_datasource_test.dart` and
  `test/sdk/api/api_repositories_test.dart` split into smaller per-entity
  files.
- CI now also runs `flutter analyze` / `flutter test` over `example/` so
  breaking the public API can no longer go undetected through the demo
  app.

### Docs

- `CHANGELOG`: the long-standing `[Unreleased]` summary cut into this
  `0.9.0` entry. Covers changes since the 2026-05-26 `0.6.0` audit.
- `ARCHITECTURE.md` and the auto-generated dartdoc strings cleaned of
  refactor history (`"Promoted from part of"`, `"Extracted from"`,
  `"since 0.3.0"`) — historical context lives here in the changelog.

## [0.6.0] - 2026-05-26

### Architecture

- **Three-layer package** — `ChatClient` (REST + real-time + cache-aware
  sub-APIs), `HiveChatDatasource` (persistent local cache, opt-in but on by
  default), `ChatUiAdapter` (bridges SDK events to per-room controllers and
  drives the UI Kit).
- **`Result<T, ChatFailure>` everywhere on the public surface.** No
  `throw` leaks out of the SDK; the `Result` sealed type with
  `Success` / `Failure` cases is pattern-matchable. Helpers:
  `dataOrThrow`, `failureOrThrow`, `castFailure<R>()`, `getOrElse`,
  `mapFailure`, `fold`.
- **`ChatFailure` hierarchy** — sealed `AuthFailure`,
  `NotFoundFailure`, `NetworkFailure`, `ValidationFailure`,
  `ConflictFailure`, `CacheFailure`, `UnknownFailure`. Each carries a
  cause when available.
- **Models are Freezed.** All 17 SDK models and the `RoomListItem` UI
  model use Freezed for `copyWith` / `==` / `hashCode` / `toString`.
  Identity-equality preserved on entities that need it
  (`ChatMessage`, `ChatRoom`, `ChatUser`, `ChatContact`, `RoomUser`,
  `InvitedRoom`, `ScheduledMessage`, `ChatPresence`,
  `BulkPresenceResponse`) via `@Freezed(equal: false)` + manual `==`.

### Theming

- **Cohesive sub-themes** — `ChatBubbleTheme`, `ChatInputTheme`,
  `ChatRoomListTheme`, `ChatMarkdownTheme`. Each groups the slots that
  belong together (e.g. `bubble.outgoingColor`,
  `input.backgroundColor`, `roomList.unreadBadgeColor`,
  `markdown.boldStyle`).
- **Flat slots for cross-cutting surfaces** — `backgroundColor`,
  `avatarBackgroundColor`, `presenceAvailableColor`,
  `audioPlayButtonColor`, `videoBorderRadius`,
  `linkPreviewBackgroundColor`, `reactionTextStyle`, the context menu,
  attachment picker and image viewer colours, etc., remain top-level
  on `ChatTheme` itself.
- **Factories** — `ChatTheme.lightPreset()` and
  `ChatTheme.darkPreset()` set rich defaults across every visible
  surface; `ChatTheme.resolved(BuildContext)` picks one based on the
  platform brightness; `ChatTheme.branded({accent,
  contrastingOnAccent})` derives ~12 accent slots from a single
  colour; `ChatTheme.highContrast()` returns a WCAG-AAA-friendly
  preset.

  ```dart
  final theme = ChatTheme(
    bubble: ChatBubbleTheme(outgoingColor: Colors.green),
    input: ChatInputTheme(backgroundColor: Colors.white),
    markdown: ChatMarkdownTheme(
      boldStyle: TextStyle(fontWeight: FontWeight.w800),
    ),
    roomList: ChatRoomListTheme(
      nameStyle: TextStyle(fontSize: 16),
    ),
  );
  ```

### Localization

- **Seven shipped locales** — `en`, `es`, `fr`, `de`, `it`, `pt`, `ca`.
  All user-facing strings (system messages, action labels, attachment
  type names, voice message templates, deleted-message placeholders)
  live in `ChatUiLocalizations`.
- **`LocalizationsDelegate`** — `ChatUiLocalizations.delegate`
  integrates with Flutter's standard l10n flow:

  ```dart
  MaterialApp(
    localizationsDelegates: const [
      ChatUiLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      // …
    ],
    supportedLocales: ChatUiLocalizations.supportedLocales,
  );
  ```

  Widgets call `ChatUiLocalizations.of(context)`; the SDK falls back
  to English when no delegate is registered (handy in tests and
  quick demos).

### Real-time transports

`ChatConfig.realtimeMode` chooses how live updates arrive:

| Mode                     | What it does                                                                 |
| ------------------------ | ---------------------------------------------------------------------------- |
| `auto` *(default)*       | WebSocket primary, automatic SSE fallback when WS connect/upgrade fails.     |
| `webSocketOnly`          | WS only; disconnects surface as errors instead of falling back.              |
| `serverSentEventsOnly`   | SSE only; useful on networks that drop WebSockets.                           |
| `polling`                | REST polling diff. Configurable interval; no typing/presence events.         |
| `manual`                 | No background work. The host app calls `chat.refresh()` to pull updates.     |

All transports emit events onto the same `chat.client.events` stream.
SSE has a client-side idle watchdog (`ChatConfig.sseIdleTimeout`,
default 60 s) that reconnects on long silence to mitigate zombie
streams.

### Cache

- **Hive CE backend** (`HiveChatDatasource`), opt-in via `cache:` on
  `NomaChat.create` (a default instance is wired up automatically).
- **Per-API `CachePolicy`** — `cacheFirst`, `networkOnly`,
  `cacheOnly`, `cacheThenNetwork` — surfaces explicitly on read
  methods.
- **Eviction policy** — FIFO with configurable per-room cap +
  per-entry TTL. Tunable via `CacheConfig`.
- **Schema migration** — `CacheSchemaMigrator` runs step-by-step
  migrations between recorded schema versions, falling back to a
  wipe-and-rebuild only when no path is registered.
- **Avatar storage** — pluggable `AvatarStorage` interface; the
  default delegates to `client.attachments.upload`.

### Offline queue

- **Sealed `PendingOperation`** with nine concrete subclasses
  (`SendMessage`, `EditMessage`, `DeleteMessage`, `SendReaction`,
  `DeleteReaction`, `MarkAsRead`, `PinMessage`, `UnpinMessage`,
  `ToggleRoomFlag`). Each carries its own `Map<String, dynamic>
  toJson()` so serialization stays cohesive with the type.
- **Exponential backoff** with a configurable ceiling
  (`OfflineQueue.maxBackoffSecs`).
- **Drain runs through an injected `PendingOperationExecutor`** so
  the queue stays decoupled from `ChatClient`.

### UI Kit

- **Message bubbles** for text, image, video, audio, file and
  location, with a shared `BubbleMetadataRow` that handles the
  `timestamp + receipt-status` corner consistently.
- **Composer** (`MessageInput`) with mentions, replies, edits,
  attachments, voice recording (slide-to-cancel, lock-to-keep),
  link preview, send-on-Enter on desktop.
- **Room list** with unread badges, mute / pin / hide / archive
  affordances, WhatsApp-style last-message previews
  (`📷 Photo`, `🎤 Voice message (0:14)`, etc.) and `Tú:` /
  `You:` prefix in groups.
- **Reactions** — long-press to pick, double-tap to react, picker
  sheet, aggregated badges under the bubble.
- **Group flows** — `MemberPickerSheet` → `GroupSetupPage` →
  `GroupInfoPage`. Avatar pipeline: `AvatarPickerSheet` →
  `AvatarCropPage` (square crop with pinch + pan + rotate).
- **Profile** — `ProfileSettingsPage` for display name + avatar +
  optional bio/email.

### Observability

- **Pluggable logger** — `ChatConfig.logger:
  void Function(String level, String message)?`. Levels are
  `debug`/`info`/`warn`/`error`. Propagated to interceptors, transports,
  cache datasource and offline queue; the consumer passes their own
  implementation to forward to telemetry.
- **`OperationError` stream** — the adapter publishes
  `(OperationKind, ChatFailure, roomId/messageId/userId)` for every
  mutation failure, so a host app drives a single global banner
  instead of wrapping each call site.
- **`LinkPreviewFetcher.cacheStats`** — entries, capacity, in-flight,
  hits, misses, failure retries, evictions, hit rate. Useful for
  debug overlays.

### Utilities

- **`Result<T, ChatFailure>`** + helpers (above).
- **`PaginatedResult<T>`** with `nextCursor` / `hasMore` for SDK
  pagination.
- **`MimeClassifier`** (`MimeKind { image, gif, video, audio, file }`
  + `classifyMime(String?)`) — single source of truth for "what
  kind of attachment is this".
- **`DateFormatter`** — context-aware "12:34", "Yesterday",
  weekday name, full date.
- **`MarkdownParser`** — inline-only (`**bold**`, `*italic*`,
  `~~strike~~`, `` `code` ``); the parser's scope and the deliberate
  non-support (block markdown, links) are documented in the file.

### Platform support

`pubspec.yaml` declares all six Flutter targets — `android`, `ios`,
`macos`, `linux`, `windows`, `web`. Production-tested: Android and
iOS. Voice recording on web is disabled (the controller stages
recordings on the local filesystem before sending); calling
`startRecording()` returns `permissionDenied` instead of crashing.
See the README "Platform support" table for the breakdown.

### Lints & tests

- `analysis_options.yaml` enables `strict-casts`,
  `strict-inference`, `strict-raw-types` plus the canonical
  `prefer_const_*` / `prefer_final_*` ruleset.
- Suite size: **1710 tests passing**, 2 skipped. Coverage > 90% on
  every leaf module. Golden tests for the seven non-network bubbles
  in light + dark themes (19 baselines), plus the five outgoing
  status icons.

## [0.3.1] - 2026-05-14

Pana-score patch. No public API or behaviour change; consumers on
`^0.3.0` pick this up automatically.

### Fixed

- **Pana static analysis (40/50 → 50/50)**: the four `chat_ui_adapter_*`
  part files introduced by the 0.3.0 SRP refactor had drifted from the
  Dart formatter. `dart format --set-exit-if-changed` failed on pana's
  side, dropping the static-analysis score by 10 points. Now formatted.
- **Stale dartdoc reference**: `ChatUiAdapter.presenceFor` referenced
  the private `_bootstrapPresence` symbol that was relocated to
  `_PresenceManager.bootstrap` in 0.3.0; the comment now describes the
  bootstrap source without naming an internal symbol.

### Changed

- **`VoiceRecordingController` no longer imports `dart:io` or
  `path_provider` directly.** The filesystem helpers
  (`getTemporaryDirectory()`, `File`, `Directory`, `FileSystemException`)
  live in `_voice_recorder_io.dart` with a Web stub in
  `_voice_recorder_io_web.dart`; the controller picks them up via a
  conditional import (`if (dart.library.js_interop)`).

  This is a step towards full WASM compatibility but does **not** move
  the pana platform-support score by itself (the remaining WASM
  blocker is in `audioplayers` → `path_provider`). A future
  WASM-compatible audio backend would now drop the package straight to
  160/160 with no further changes on our side.

### Notes

- Pana on pub.dev for the (still-published) 0.3.0 reports 140/160 —
  this 0.3.1 lifts it to 150/160 once published, matching the local
  measurement.

## [0.3.0] - 2026-05-13

Quality + architecture release. No public API breaking changes; the audio
backend migration is transparent to consumers.

### Changed

- **Audio backend**: migrated from `just_audio` to `audioplayers ^6.1.0`.
  Same feature surface (play / pause / seek / playback rate / state stream)
  but `audioplayers` ships implementations for all six Flutter targets,
  unblocking Linux and Windows. `pubspec.yaml` `platforms:` now lists
  android / ios / macos / linux / windows / web; see README "Platform
  support" for the production / best effort breakdown.
- **`ChatClient` interface**: `set onOfflineMessageSent` is now part of the
  abstract contract (was concrete-only on `NomaChatClient`). The UI adapter
  no longer needs an `as NomaChatClient` cast. `MockChatClient` and any
  custom `ChatClient` impl in tests implement the setter (no-op is fine).
- **`ChatUiAdapter` internal SRP refactor** (no API change): the 2272-line
  monolith was split into four `part of` collaborators —
  `_PresenceManager`, `_ChatEventRouter`, `_RoomEnricher`,
  `_OptimisticHandler`. The facade is now ~1500 lines and the
  responsibilities are obvious from the file layout.
- **`MockChatClient.rooms`** now emits `RoomUpdatedEvent` after each
  successful `mute` / `unmute` / `pin` / `unpin` / `hide` / `unhide` to
  match the real client's event semantics. Tests that count events should
  expect one per mutation.
- **Models**: every public value-object class in `lib/src/models/` and
  `lib/src/ui/models/` is now annotated `@immutable`. No runtime
  difference; the analyzer now flags accidental subclassed mutability.

### Fixed

- `loadRooms()` and `_enrichAndSetRooms` guard `_disposed` after every
  long await so they cannot write to a disposed `ValueNotifier` or
  `RoomListController`.
- `rejectInvitation` now restores the room on network failure (previously
  it dropped the invitation permanently if the request errored out).
- `sendThreadReply` no longer double-emits to `operationErrors`: both
  `OperationKind.sendMessage` and `OperationKind.sendThreadReply` used to
  fire for a single failure. `sendMessage` accepts an optional
  `operationKind` override and the thread-reply path uses it to emit a
  single, more specific kind.
- `loadMoreMessages` wraps its body in `try/finally` so
  `controller.setLoadingMore(false)` runs even if the SDK call leaks an
  exception past the `Result` wrapper.
- `VoiceRecordingController.startRecording()` early-returns with
  `StartRecordingResult.permissionDenied` on Web (it was crashing on
  `dart:io` / `path_provider`). A MediaRecorder-backed Web flow is on
  the roadmap.
- `LinkPreviewFetcher` retries cached failures after a configurable TTL
  (default 5 min) instead of caching `null` forever. Transient network
  glitches no longer poison the per-session preview cache.
- Hardcoded English Semantics labels in `ImageBubble`, `VideoBubble` and
  `ScrollToBottomButton` are now routed through `theme.l10n`. A new
  `scrollToBottom` localisation key was added across all seven shipped
  locales (en / es / fr / de / it / pt / ca).
- Dark + high-contrast themes now ship explicit `markdownCodeStyle` and
  `markdownLinkStyle` overrides; the previous defaults bled light-mode
  values into the dark UI and failed WCAG AA contrast for inline links.
- A handful of dark-theme accent colours (`reactionBackgroundColor`,
  `audioPlayButtonColor`, `audioListenedIconColor`,
  `audioUnlistenedIconColor`, `linkPreviewBackgroundColor`) are now
  overridden in `ChatTheme.dark` instead of inheriting light defaults.
- Voice upload progress `ValueNotifier`s detached after a completed
  upload are now tracked and disposed during `adapter.dispose()` (they
  used to outlive the adapter when the optimistic bubble held a
  reference).
- `_resolveDmContact` rewritten from a `Future.sync().then().catchError()`
  chain to `async`/`await` + `try`/`catch` with an explicit `unawaited()`
  so the fire-and-forget intent is visible at the call site.

### Documentation

- README `Platform support` table rewritten to reflect the audioplayers
  migration (six platforms supported via the new backend; voice
  recording on Web is documented as "Limited" with the reason).
- `RELEASING.md` updated for the now-live automated publishing flow,
  including the three pub.dev configuration toggles and the four
  failure modes a maintainer might hit.
- `TESTING.md` test counts refreshed to reflect the current suite size
  (1474+) and the 80% coverage gate enforced in CI.
- `markdown_parser.dart` dartdoc now lists the supported inline syntax
  and the deliberate non-support (`[label](url)`, block markdown).

### Tests

- 1485 tests passing on Linux (CI), + 4 skipped. On macOS the 19 golden
  bubble diffs fail by ~1% pixel-diff because the baselines are
  generated on Linux for CI; regenerate locally with
  `flutter test --update-goldens` if needed.
- Coverage 80.55% (8248/10239), enforced ≥80% in CI.

## [0.2.1] - 2026-05-13

Post-publish polish driven by the pub.dev scoring report. No behavioural
changes; consumers on `^0.2.0` pick this up automatically.

### Fixed

- **Static analysis**: 17 stale `*.freezed.dart` files were left behind from
  an earlier migration of plain models off Freezed. `dart analyze` ignored
  them locally (excluded via `analysis_options.yaml`) but pana ran a
  separate analysis that surfaced 1 176 errors against them. The files are
  now deleted; the remaining `admin_models.freezed.dart` is genuinely
  generated and stays.
- **`hive_ce` lower bound**: bumped from `^2.7.0` to `^2.19.0`. Older
  versions did not yet expose `package:hive_ce/hive_ce.dart`, so a
  consumer with `dart pub downgrade` would fail to compile.
- **`just_audio` constraint**: bumped from `^0.9.42` to `^0.10.0` so the
  package tracks the current stable line.

### Changed

- `pubspec.yaml` now declares `platforms:` explicitly. Supported targets
  are **android, ios, macos, web**. Windows and Linux are excluded because
  `just_audio` (transitive, used for voice playback) does not support them.
- README has a new **Platform support** section documenting which
  platforms are production-tested vs best-effort vs unsupported, with the
  exact transitive-dep blocker for Windows/Linux.

## [0.2.0] - 2026-05-13

First public release. The SDK has been used internally for several months and
the API surface, UI Kit, persistent cache and adapter are considered stable
enough for external evaluation; the pre-1.0 versioning keeps room for breaking
changes informed by real-world feedback before committing to a 1.0 contract.

### Added

- **Message search** end-to-end: `MessageSearchController`,
  `MessageSearchView` with case-insensitive query highlighting, and
  `ChatView.initialMessageId` to scroll-and-highlight a target message after
  navigating back from results.
- **Read receipts**: blue double-check in `MessageStatusIcon` (default
  `messageStatusReadColor` shipped in `ChatTheme.defaults`) and automatic
  `ReadReceiptAvatars` row in group rooms when receipts are available.
  Public helper `readersFor(ChatMessage, List<ReadReceipt>)` for custom
  derivations.
- **Optimistic UI** across the adapter: every mutating operation
  (`sendMessage`, `editMessage`, `deleteMessage`, `sendReaction`,
  `deleteReaction`, `muteRoom`/`unmuteRoom`, `pinRoom`/`unpinRoom`,
  `pinMessage`/`unpinMessage`, `hideRoom`, …) updates local state first and
  rolls back on failure.
- **Operation errors stream**: `ChatUiAdapter.operationErrors` — a broadcast
  `Stream<OperationError>` carrying `OperationKind`, the original
  `ChatFailure` and `roomId`/`messageId`/`userId` context for every adapter
  failure. Designed for global snackbars and telemetry without wrapping each
  call site.
- **Pinned messages** state in `ChatController`
  (`pinnedMessages` + `addPin`/`removePin`/`setPins`/`clearPins`/`isPinned`).
  `adapter.loadPins(roomId)` now seeds it too.
- **Dark theme** shipped as `ChatTheme.dark` and `ChatTheme.highContrast`.
- **Example app** with four pages (home, chat room, message search, pinned
  messages) and a `GlobalErrorBanner` that subscribes to `operationErrors`.
- Comprehensive dartdoc across all public APIs (entry points, sub-APIs,
  models, controllers, theme, l10n, every widget and bubble).

### Tests

- 1156 tests passing + 4 skipped in the full suite.
- Golden tests for the seven non-network bubbles in light and dark themes
  plus the five outgoing message status icons (19 baselines).
- Integration tests exercising the full adapter flow against
  `MockChatClient`.
- Performance regression guard for `HiveChatDatasource` on 10k messages.
- Accessibility audit using `meetsGuideline` (Android/iOS tap target,
  labeled tap target, text contrast).
- System-message l10n parity across the seven shipped locales
  (`en`, `es`, `fr`, `de`, `it`, `pt`, `ca`).

### Known limitations

- Golden tests for `ImageBubble` and `LinkPreviewBubble` are skipped:
  `CachedNetworkImage` pulls in `flutter_cache_manager` →
  `sqflite` + `path_provider`, which is impractical to mock in plain widget
  tests without an extra dependency such as `sqflite_common_ffi`.
- Push notifications integration is not part of this release.
- `ChatEvent` does not yet emit `MessagePinnedEvent` / `MessageUnpinnedEvent`,
  so cross-client pin synchronisation requires a manual `loadPins` refresh.

## [0.1.0] - Unreleased

Initial development version. Used internally during the SDK's design and
not published to pub.dev.
