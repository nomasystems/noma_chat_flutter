# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/). From `1.0.0`
onwards, breaking changes require a **major version bump**.

## 0.21.0 - 2026-08-15

Minor bump, not a patch on `0.20.0`: the enum addition below is a source break
for hosts that switch over it exhaustively, the camera stops sending on its
own, and the package gains a `video_player` dependency.

### Added

- **A confirmation step between the shutter and the send.** `CameraCapturePage` no
  longer hands a capture back the moment the finger lifts: what the shutter produces
  lands on `CameraCaptureReview` (exported, and usable on its own — a plain widget
  with no routing baked in) with exactly three ways out. **Send** is the only one that
  returns the capture; **Retake** deletes the file and goes back to the live
  viewfinder; **Discard** leaves the camera with nothing. The system back gesture on
  the review is a retake, not a silent exit. A capture nobody confirmed is deleted on
  teardown — including the case where the host pops the route out from under the
  review — because nothing else collects the camera's cache directory. Three new
  strings (`cameraRetake`, `cameraDiscard`, `pausePreview`) in every locale that
  already translated the `camera*` family; `send`, `playPreview` and `close` are
  reused.
- `video_player` is now a dependency, used by exactly one widget:
  `CameraVideoPreview`, the review step's playable clip (tap to play, tap to pause, a
  finished clip restarts from the first frame; a container the platform decoder cannot
  open degrades to a static placeholder so the capture stays sendable). Hosts that
  would rather not ship a second video stack replace it wholesale — through
  `CameraCapturePage(videoPreviewBuilder: …)` when they push the screen themselves, or
  through the new `ChatViewBuilders.videoPreviewBuilder` for the flow `NomaChatView`
  opens from the composer's Camera row. With the slot wired, nothing the SDK renders
  touches `video_player`.
- `ChatTheme.cameraCaptureSendButtonColor` and `ChatTheme.cameraCaptureReviewActionStyle`
  — the review step's Send button fill (defaults to `DefaultPalette.cameraCaptureSendButton`,
  the same green as the composer's send button) and its Retake label style (falls back
  to `cameraCaptureHintStyle`, then to the capture screen's own white-on-black).
- 14 flat `ChatTheme` slots for the in-room search screen, so it stops looking
  stock-Material inside a themed app: `messageSearchBackgroundColor`,
  `messageSearchFieldFillColor`, `messageSearchFieldTextStyle`,
  `messageSearchFieldHintStyle`, `messageSearchFieldCursorColor`,
  `messageSearchFieldBorderColor`, `messageSearchFieldBorderRadius`,
  `messageSearchFieldIconColor`, `messageSearchResultTitleStyle`,
  `messageSearchResultSnippetStyle`, `messageSearchResultHighlightStyle`,
  `messageSearchResultTimestampStyle`, `messageSearchEmptyTextStyle`,
  `messageSearchProgressColor`. The split of responsibilities is unchanged — the host
  still owns the `Scaffold` and `AppBar` around `MessageSearchView`, the SDK themes
  what it paints inside. Every slot is `null` by default and an unthemed host renders
  exactly as before; all four presets (`lightPreset`, `darkPreset`, `branded`,
  `highContrast`) now fill them, so the search screen follows a preset like every
  other surface. No new strings.
- `ChatTheme.galleryBackgroundColor` — the surface behind the media gallery's
  media / documents / links tabs, which until now inherited the `Scaffold` default and
  read as a stray grey panel under a host that tints its own pages. Falls back to
  `galleryAppBarBackgroundColor`, then to the `Scaffold` default. Deliberately not
  `backgroundColor`: that one is the chat wallpaper.
- `AttachmentPolicy.deniedExtensions`, defaulting to
  `AttachmentPolicy.defaultDeniedExtensions` — 20 OS-executable and script-dropper
  extensions (`exe`, `msi`, `bat`, `cmd`, `com`, `scr`, `pif`, `cpl`, `msc`, `apk`,
  `dex`, `sh`, `ps1`, `vbs`, `vbe`, `jse`, `wsf`, `wsh`, `reg`, `jar`). It is a
  constructor default, so every existing policy inherits it, including
  `AttachmentPolicy.unrestricted` and `NomaChatView.defaultAttachmentPolicy`. The
  point is the stance it makes safe: a chat can now be **default-allow** — send any
  file type, except the dangerous ones — instead of reaching for `allowedMimeTypes`
  and rejecting every uncommon-but-safe extension (`.xyz`, `.log`, a proprietary
  export) as collateral. Only a trailing token shaped like an extension (≤ 8 ASCII
  alphanumerics) is matched, so a prose tail (`report.final version`) is not an
  extension; a name whose tail spells a denied one (`newsletter-acme.com`) is
  refused on purpose. Narrow, widen or disable it with
  `copyWith(deniedExtensions: {...})` — `{}` turns the check off entirely.
- `AttachmentPolicy.validate` takes an optional `fileName`, and `deniesFileName`
  answers the extension question on its own. Both `AttachmentPickers.pickFile` and
  `ChatMessagesController.sendAttachment` now pass it, so the floor holds on the
  upload path a host reaches directly (web drag-and-drop, a share-intent handler),
  not only behind the pickers. The image/video pick paths are unchanged — they pass
  no `fileName` and behave exactly as before.

### Changed

- **Breaking (behaviour):** the in-app camera does not auto-send any more. Tapping the
  shutter or releasing a hold-to-record now opens the review step described above
  instead of resolving `CameraCapturePage.show()`. The signature is unchanged — it
  still returns `CameraCaptureResult?` — but `null` now also means "the user discarded
  the take on the review", not only "cancelled before capturing". Hosts that treat
  `null` as a cancellation need no changes; hosts that assumed a non-null result
  followed every shutter press do. `NomaChatView` handles this itself: its Camera row
  only ever sees captures the user confirmed.
- `ChatTheme.videoHeight` is a **maximum**, not a fixed height. The video bubble's
  poster frame is painted at the clip's own aspect ratio, scaled down to fit the bubble
  width and this ceiling, so a portrait clip is no longer stretched into a landscape
  strip. The default is now 250 (was an exact 180), matching `imageMaxHeight` so a clip
  and a photo of the same shape take the same room. States with no real frame to size
  from — pending download, upload and failure placeholders, a missing thumbnail — keep
  the previous full-width / 180 look. A host that set `videoHeight` to pin a row height
  gets a shorter bubble for a landscape clip than before.
  `RoomDefaults.videoThumbnailMaxWidth` follows it from 480 to 720: on a portrait clip
  the long edge is now the height, and 480 left the poster frame visibly soft on a
  dense screen. It is still tens of kilobytes at `videoThumbnailQuality`.
- `ChatBubbleTheme.uploadProgressColor` falls back to `statusReadColor` before
  `statusColor` (and only then to `DefaultPalette.uploadProgressColor`). The ring and
  the read tick mark the same thing — the message made it — so a host that themes its
  read ticks now gets the ring for free; the old chain painted it in the muted grey of
  a *pending* tick, which reads as the opposite of progress. Hosts that theme
  `statusColor` but not `statusReadColor` are unaffected.
- The search screen's query field defers to the app's own `InputDecorationTheme` where
  its slots are unset: it no longer passes an explicit `filled: false` (which
  overrode an ambient `filled: true`), and `messageSearchFieldBorderRadius` set
  *without* `messageSearchFieldBorderColor` now reshapes the outline the ambient theme
  draws — border, enabled *and* focused — instead of replacing it (a radius alone
  previously discarded the ambient `border` slot specifically, painting the SDK's own
  outline over whatever shape the host had drawn there). And with
  `messageSearchFieldBorderColor` set — as all three colour presets now do — the
  focused state is no longer a repaint of the enabled one: it widens and, when the
  theme also carries `messageSearchFieldCursorColor`, tints towards it, so a focused
  query field keeps a visible ring instead of looking identical to an idle one. A host
  that themes the ambient `InputDecorationTheme.focusedBorder` directly still wins
  verbatim over this heuristic.
- **Breaking (source):** `AttachmentPolicyViolationKind` gains a third value,
  `extensionDenied`. Exhaustive `switch`es over it stop compiling until the case is
  added. `AttachmentRejectReason` is deliberately **not** touched: a denied extension
  is reported as `mimeNotAllowed`, reusing the existing
  `ChatUiLocalizations.attachmentTypeNotAllowed` string in every locale, so hosts
  switching on a rejection's `reason` (and their l10n) need no changes at all.

## 0.20.0

### Added

- `ChatRoomsController.hydrate({type})` — the disk half of `rooms.load()`, callable on its own.
  Returns the `RoomHydrationStatus` it published on `roomHydrationNotifier`. It never emits a
  request, and it is safe **before** `connect()` and before the user exists server-side: nothing it
  reads is set up by either. Until now `loadAll` was the only door to the cache, so a host could not
  paint from disk without first paying for a handshake — a cache-first SDK handing its cached rows
  out behind a network round-trip. Concurrent calls share a single pass, and it deliberately does
  **not** mark the list initialized: `initializedNotifier` and `onRoomsLoaded` still mean "a network
  pass completed".
- `ChatMembersApi.list` accepts `cachePolicy`, and the roster is now persisted locally under
  `members:$roomId` with a new `CacheConfig.ttlMembers` (12 h, matching `ttlRooms`). The cache path
  is deliberately narrow: it applies **only** when `pagination` is `null` **and** `expand` is empty.
  Any other shape goes straight to the network in both directions — one record per room cannot answer
  "page 3", and serving a bare cached roster to a caller that asked for `expand: [users]` would blank
  every name and avatar it was about to render. Naming **no** `cachePolicy` keeps the pre-cache
  semantics exactly: the call goes to the network and a failed fetch is a `ChatFailureResult`, never
  the roster on disk. Deferring to `CacheConfig.defaultReadPolicy` (`networkFirst`) instead would have
  flipped every existing caller's `fold(showError, render)` into "render a stale roster, never show an
  error" without a line of their code changing. The answer is still written through to the cache
  either way, so a `CachePolicy.cacheOnly` reader — the SDK's own disk-only hydration pass, or yours —
  finds it there. Opt into the offline fallback by naming the policy you want.
- `ChatLocalDatasource.saveRoomMembers` / `getRoomMembers` / `deleteRoomMembers`, with default no-op
  implementations so a third-party datasource keeps compiling and keeps working. `getRoomMembers`
  keeps "nothing stored" (`ChatSuccess(null)`) apart from "the store could not be read"
  (`ChatFailureResult`), the same distinction `getUserRooms` documents. `HiveChatDatasource` stores
  them in a new `chat_room_members` box, cascaded from `deleteRoom`, from room eviction and from
  `clear()`; no schema bump is needed (a box that does not exist opens empty).

### Changed

- `ChatUiAdapter.connect()` now hydrates the room list from disk before opening the socket, when the
  host has not already called `rooms.hydrate()` itself. A host that does nothing gets its cached rows
  ahead of the handshake instead of after it. The cost is local I/O in front of the connection; a
  store that throws is logged and skipped, because an unreadable cache must never stop a connection.
  `signOut()` / `dispose()` rearm it, so the next session hydrates again; `disconnect()` does not, so
  a background→foreground cycle will not overwrite rows that realtime events already advanced.
- **A cold start now names its DM rows from disk.** The cache pass of `loadAll` resolves DM contacts
  again — with `CachePolicy.cacheOnly` threaded through both `members.list` and the peer's
  `users.get`, so it still emits nothing. Before, a device that had never resolved a DM *in this
  session* painted it anonymous (no title, no avatar) until the network pass landed, and with no
  connectivity, forever — even with the peer's profile sitting on disk. The session's in-memory
  replay added in 0.19.0 only ever covered a warm reopen.
- **Reverses a 0.19.0 behaviour note**: the cache pass collapses duplicate DM rooms for the same
  contact again, now that it can tell they share a peer without emitting anything. It still never
  *persists* the loser's eviction — only an authoritative (network) pass does that.
- The cached roster is invalidated by every local mutation that can change it (`invite`, `remove`,
  `leave`, `updateRole`, `ban`, `unban`; `invite` / `remove` / `leave` also drop `roomDetail:$roomId`
  because they move `memberCount`) and by every remote roster event, through the single
  `ChatUiAdapter.notifyRoomMembersChanged` chokepoint. `UserRoleChangedEvent` now goes through that
  chokepoint too — it did not before, and a role travels *in* the cached row, so a promotion to admin
  would otherwise have rendered stale for a whole TTL. `muteUser` / `unmuteUser` deliberately do not
  invalidate: the mute flag does not ride on `RoomUser`.

### Fixed

- `CachePolicy.cacheOnly` no longer reaches the network on a client built without a cache.
  `users.get`, `rooms.getUserRooms`, `rooms.get`, `members.list`, `contacts.list`, `messages.list`
  and `messages.getReactions` all fell through to their network branch when there was no store to
  read, so the one policy whose contract is that it emits nothing issued a request per call — one
  per conversation on the disk-only hydration pass. They now answer the same miss `CacheManager`
  answers for an empty store: `NetworkFailure('No cached data available')`. If you pass `cacheOnly`
  on a cache-less client expecting data, name the policy you actually want.
- On a client that *has* a cache, `messages.getReactions` resolved under
  `CacheConfig.defaultReadPolicy` (`networkFirst`) instead of the policy passed, so an explicit
  `cacheOnly` still fetched.

### Breaking

- `ChatMembersApi.list` gained an optional named `CachePolicy? cachePolicy`. Callers are unaffected;
  any class that `implements ChatMembersApi` and declares `list` explicitly must add the parameter.
  Fakes that fall back to `noSuchMethod` keep compiling. See `MIGRATING.md`.

## 0.19.0

### Added

- `ChatUiAdapter.roomHydrationNotifier`, a `ValueListenable<RoomHydrationStatus>` reporting what the
  disk pass of the room load could contribute: `pending`, `unavailable`, `empty` or `hydrated`, plus
  how many rows were painted and which listing they came from. It updates once per `loadRooms`, as
  soon as the cache pass has written to the room list and **before** any network pass is attempted,
  so a host can pick its first frame — skeleton, empty state or list — without guessing. Nothing else
  answered this: `roomListController` stays silent when `mergeRooms` changes nothing (the warm-reopen
  case), and `onRoomsLoaded` only fires after a network pass. It is a `ValueListenable` rather than a
  stream on purpose, so a widget that subscribes late still reads the outcome. `RoomHydrationStatus`
  and `RoomHydrationOutcome` are exported from `package:noma_chat/noma_chat.dart`.
- `RoomListController.unreadRoomCount()` and `unreadArchivedRoomCount()`: how many conversations carry
  unread messages in the main list and in the archive, using the same predicates as `rooms` and
  `archivedRooms` (`hidden` + `deletedRoomIds`) but independent of the active text filter. Both take
  `includeMuted` (default `false`, WhatsApp parity: a muted room should not feed a badge that alerts).
  They replace the hand-written filter over `allRooms` that every consumer was rewriting to paint a
  tab badge or an archive header.
- `DeliveredConfirmationCoordinator.reset()` to forget confirmed delivery cursors on sign-out or user
  switch, plus `confirmedCursorCount` for diagnostics. `PresenceRegistry` and
  `DeliveredConfirmationCoordinator` both accept an optional
  `ValueListenable<ChatConnectionState> connectionState`; without it their behaviour is unchanged.

### Changed

- The cache pass of `loadAll` — the instant-from-disk startup — no longer emits any network request:
  no `GET /presence`, no `members.list` per DM, no `users.get`, no delivery confirmations, no sender
  hydration. It previously issued 1 awaited request plus 2N + M + K more right in front of the first
  paint, and with no connectivity the awaited `presence.bootstrap()` put a full timeout ahead of it.
- The room list no longer flashes blank on a warm reopen. The cache pass now rebuilds a DM's identity
  — peer, title, avatar, presence — from the session's in-memory state instead of overwriting the
  enriched row and buying it back with a `members.list`.
- DM contact resolution reads the peer profile with an explicit `CachePolicy.cacheFirst` instead of
  falling through to the default `networkFirst`, so a peer already on disk stops costing a
  `GET /users/{id}` per DM per cold start. `CacheConfig.ttlUsers` still applies (6 h by default), so a
  renamed peer refreshes on its own.
- **Behaviour change worth noting**: the cache pass no longer collapses duplicate DM rooms for the
  same contact, because doing so requires `members.list`, which has no cache path. If the backend
  holds two rooms for one contact and the device has not reconciled them yet, both rows show until the
  network pass collapses them and evicts the loser.
- `ChatRoomsApi.getUserRooms` now tells an empty cache apart from an unreadable one. A local cache that
  reads cleanly and holds no rooms resolves to `ChatSuccess(UserRooms(rooms: [], invitedRooms: []))`
  rather than a cache miss — the SDK stating "this device knows you have no rooms", which is what lets
  a host paint an honest empty state instead of a spinner. Only a cache that could not be read (I/O
  error, corrupt store) counts as a miss, and under `CachePolicy.cacheOnly` that is the only thing
  surfacing as a `ChatFailureResult`. Cache read failures are now logged at `warn` instead of being
  silent.
- A failed network pass is no longer masked when the cache answered "you have zero rooms". Masking now
  applies only when the cache had something to paint, so a failed load stops presenting itself as a
  successful empty one. Behaviour for a cache with rooms is unchanged.
- `ChatUiAdapter.signOut()` routes through `ChatClient.logout()`, so client-owned session state is torn
  down along with the adapter's — chiefly the offline queue. An attachment or message parked there by a
  connectivity failure carries no record of who queued it and drains on the next connection, whichever
  account that connection authenticates as. Clearing the persistent cache, all `signOut()` did before,
  only wiped the queue's stored copy: the in-memory queue survived, re-persisted on the next enqueue,
  and replayed the signed-out account's upload under the next user. It now also clears the client's
  permanently-failed operation ids, its cache-manager TTL timestamps and its confirmed delivery
  cursors, all of which belong to the account leaving. `disconnect()` is unchanged and still preserves
  the offline queue — it remains the teardown for background/foreground transitions.
- `ChatUiAdapter.cancelAttachmentUpload` now aborts a voice note in flight and removes its bubble;
  previously it was a no-op for voice, which `sendVoice` did not register a cancel token for. A host
  wiring a single cancel control to every pending row will now cancel recordings it did not cancel
  before.
- `disconnect(clearRooms: true)` aborts in-flight uploads along with the rest of the connection state.
- `forward()` mints its temp id from a per-adapter sequence instead of appending the target room key,
  so `ChatMessage.id` and the `clientMessageId` sent to the server no longer carry that suffix. Two
  sends in the same microsecond used to collide on all three registries keyed by it.

### Fixed

- `attachmentUploadCancellableFor` and `voiceUploadProgressFor` no longer hand back a listenable the
  SDK later destroys. Both registries flip the value and release the notifier instead of disposing it,
  so a host that resolves one and subscribes itself keeps a usable object after the send ends or after
  a `signOut()`. Previously its next `addListener` threw
  `A ValueNotifier was used after being disposed`.
- An attachment or voice upload whose transport raises, instead of returning a failure, now lands in
  the same visible state as a returned failure: the row is marked failed with a retry affordance, its
  cached copy is persisted as failed, and the bytes are offered to the offline queue. It used to strand
  the optimistic row pending forever. `sendAttachment` and `sendVoice` honour their
  `Future<ChatResult<ChatMessage>>` signature and answer with a `ChatFailureResult` carrying the
  original error in `UnexpectedFailure.originalError` rather than propagating it. Such a failure is
  deliberately not replayed by the offline queue: a raise does not prove the bytes never reached the
  server, and re-uploading one that did would bill a duplicate blob.
- A voice note whose upload failed is marked failed on the optimistic row again, instead of staying
  pending forever while its cached copy and the offline queue both treated it as failed.
- Delivery confirmations are no longer sent twice per room list sync. The same `markRoomAsDelivered`
  fired once on the cache pass and again on the network pass, and once more on every background
  revalidation. Only successes are remembered, so a failure is still retried.
- An attachment upload that throws after the bytes have landed no longer leaves the progress ring and
  its cancel control wired forever, and no longer leaks the progress notifier.
- `LinkPreviewFetcher.fetch` keeps working for a host that narrows its return type. The `.timeout`
  call site reified the narrowed type, so `onTimeout: () => null` threw a `_TypeError` at the call
  boundary before subscribing.
- Ending a session no longer leaves a stale user-cancelled mark behind.
- A deleted row no longer exposes a "cancel upload" action to screen readers.

## 0.18.0

### Added

- **The camera lives in the SDK.** `CameraCapturePage.show(context:, theme:)` opens a capture screen
  and returns a `CameraCaptureResult`; `NomaChatView` wires it as the default camera action, and a
  host can still override it through `ChatViewCallbacks.onPickCamera`. It ships pinch-to-zoom, a
  shutter that only changes colour while recording, a lens switch that recovers the previous camera
  when a bind fails, and a permission flow that tells a plain refusal apart from one the OS will not
  prompt for again — offering a route to Settings for the second. Consumers no longer hand-roll a
  preview, a shutter and a permission dance to send a photo from a chat.

  `platforms:` still declares all six targets. `camera` and `permission_handler` cover mobile and
  web; `PlatformSupport.supportsInAppCameraCapture` hides the screen where the plugin has no
  implementation, and the picker falls back to `image_picker` there, so the Camera option never
  disappears. **Android hosts:** the camera plugin merges `<uses-feature android:name=
  "android.hardware.camera.any" />` into your manifest with `android:required` defaulting to true,
  and Play then hides the app from camera-less devices. `README.md` and `INTEGRATION.md` §2b carry
  the four declarations needed to lift that filter — note `android:required` is OR-merged, so a
  plain `false` loses silently.

- **Videos carry a poster frame.** `VideoThumbnailer` is the seam, with a working default, so the
  frame extractor can be swapped in one file. The frame is generated after the clip's upload
  succeeds, bounded by a deadline, and never blocks the send: a failure degrades to a preview-less
  video. Its blob gets its own attachment id, which is what the bubble, the quote preview and the
  media gallery fetch — they were previously handed the clip's id, so rendering a 40×40 thumbnail
  downloaded the whole video.

- **An upload can be cancelled while it is in flight.** The progress ring fills for real, and its
  centre cancels. `ChatUiAdapter.attachmentUploadCancellableFor` reports whether that is still
  possible, separately from progress, and `NomaChatView` wires it by default.

- **`NomaChatView.attachmentPolicy`** applies one size and type limit across the camera, gallery and
  file paths, to the pre-check and to the send alike. Rejections surface instead of being dropped.

- **`ChatConfig.metricCallback` reaches image processing.** One `image_metadata_strip` metric per
  call, carrying an outcome and a reason code — no bytes, no names, no paths, and nothing at all
  when the callback is null. `TELEMETRY.md` documents every value.

### Changed

- **Images are rebuilt, not edited.** The metadata stripper used to walk JPEG markers and keep a
  whitelist; three independent adversarial reviews each found a new way through it, the last one
  proving GPS riding through under a relabelled marker and two working channels inside the colour
  profile the whitelist deliberately kept. Images are now decoded to pixels and encoded again, so
  nothing from the source container survives because nothing from it is read: marker laundering,
  EXIF, GPS, XMP, Motion Photo and MPO trailers, JUMBF, thumbnails and comments all go, including
  the frame and table bodies previously documented as an inherent limit. Orientation survives as
  pixels rather than as a tag. PNG gets the same treatment; formats that cannot be rebuilt are
  reported rather than silently passed. An image that cannot be processed is still sent as-is so a
  rare odd-but-valid photo stays sendable, and the metric says so.

  Rebuilding drops the colour profile, which would make every Display-P3 photo arrive
  oversaturated. Rather than carry the source profile back in, the colour space is identified and a
  fresh profile is emitted, built from this package's own constants — its colorants and transfer
  curves come out byte-identical to the system profile they replace, derived from the primaries
  alone. sRGB stays untagged, which already means sRGB to every receiver. Adobe RGB and Rec. 2020
  are still converted by the receiver as sRGB, as before, but the metric now names it.

- **`pickFile` re-encodes a JPEG or PNG picked as a generic file.** That path preserved bytes
  before; it is now lossy, in exchange for the guarantees above.

- **Default attachment limits.** Video drops from 100 MB to 32 MB and gallery and file picks rise
  from 25 MB to 32 MB, so one ceiling governs every path. Hosts set their own through
  `NomaChatView.attachmentPolicy`.

- **Upload progress lives until the row has a real state.** It used to be retired the moment the
  bytes landed, which left a window where a rebuild painted a broken photo with a live play button
  and a tap that opened an empty URL.

### Fixed

- **Upload progress moves.** The payload was handed to the HTTP client as a single chunk, so the
  progress callback fired once, at the end — the ring span the whole upload without filling. It is
  now streamed in bounded pieces over views of the same buffer, with no second copy of a
  hundred-megabyte clip.
- **A quoted image renders its own preview** instead of being handed the referenced video's, which
  is what made replying to a clip download the clip.
- **A cancelled upload removes its message** rather than leaving it failed, and is told apart from a
  genuine network failure, so backgrounding mid-upload still queues offline as before.
- **A send abandoned by a logout** no longer writes into a cleared cache or posts under the session
  that just ended.
- **A failure a retry cannot clear** — the bytes never reached the server — shows an error rather
  than a retry arrow that does nothing.
- **The recording gate** cannot be left armed by a start that resolves after an interruption, and a
  clip lost that way says so.
- **A lens switch** cannot be raced by the shutter into disposing the controller it is rebinding,
  and a teardown failure during the switch is no longer reported as a failed switch.
- **A permission plugin that throws** no longer leaves the camera screen on a spinner forever.
- **A capture is measured on disk** before it is read into memory, and its file is deleted whether
  it was sent or refused.

### Removed

- **`VideoBubble.attachmentRef`** — renamed to `thumbnailRef`. It resolves the poster frame, never
  the clip; the rename is what makes the old mistake unrepresentable.
- **`ReplyPreview.attachmentRef`** — replaced by `roomId`. The widget resolves the blob it needs, so
  no caller can hand it the wrong one.

### Known limitations

- HEIC is not rebuilt — no pure-Dart decoder exists. The picker paths are unaffected because
  `image_picker` transcodes to JPEG on iOS; a raw `.heic` chosen through `pickFile` passes through
  untouched and is reported as such.
- An image whose decoder rejects it is returned unchanged, by design, and reported as not stripped.
- Camera capture and poster frames are mobile-only; the gates in `PlatformSupport` say where.

## 0.17.0

### Security

- **A URL that came in a message is launched only when it is `http` or `https`.** Three places hand
  a message's URL to the platform launcher: the tap handler `ChatView` installs when the host wires
  no `onTapLink`, the OpenGraph card `LinkPreviewBubble` paints, and the Links tab of the media
  gallery. None of them looked at the scheme. Message *text* is filtered upstream — the markdown
  parser only ever linkifies `http://` and `https://` — but the preview card is not: its `url` is
  read from the message `metadata`, which the transport copies through verbatim from whoever sent
  the message. A third party could therefore send an ordinary-looking card, with a title and a
  domain line of their choosing, whose tap opened `javascript:`, `file:`, `intent://…` or a deep
  link into the host app. The SDK passed the string to `url_launcher` as it arrived.

  All three now resolve the URL through one allowlist: `http` and `https` only, a bare domain read
  as `https`, everything else refused. A refused URL launches nothing and says nothing — at the tap
  site a hostile scheme is indistinguishable from a typo, and a warning dialog on every miss only
  teaches people to dismiss warnings. `LinkPreviewBubble` goes one step further and paints no card
  at all for a URL it would refuse to open: the whole card is a tap target whose title, description
  and domain line are chosen by the sender, so leaving it on screen would be an affordance that
  lies about where it goes. Ordinary web links are unaffected — every link the parser has ever
  produced is one, as is every preview card built from a real page. Hosts that pass their own
  `onTapLink` are unaffected too, and own the filtering of whatever they choose to open.

### Fixed

- **A failed attachment or voice send keeps the blob it already uploaded.** `sendAttachment` and
  `sendVoice` upload first and post the message second. When the upload landed but the post did
  not — the room not settled yet and answering 404 is the common case, right after a DM is created
  — the optimistic bubble was marked failed still holding the placeholder it was painted with: an
  empty `attachmentUrl`, no `attachmentId`, and metadata without either. `retrySend` re-posts that
  row verbatim, so retrying a failed photo, file, camera capture or voice note published a message
  pointing at nothing, and the sender saw it as delivered. Hosts that noticed had to fall back to
  re-picking the file, which uploads a second copy of the same bytes.

  Both methods now patch the row with the URL, the `attachmentId` and the enriched metadata the
  upload resolved, in the controller and in the pending-message cache alike. The cached copy is
  written as soon as the upload resolves, *before* the send is attempted, so a process killed with
  the send in flight still rehydrates a row that carries the blob and can be retried without
  uploading the bytes again. Retrying re-posts the blob that is already on the server under the
  original `clientMessageId`, so a retry can neither re-upload nor duplicate the message —
  including a retry that fails again and is retried once more. Nothing changes when the send
  succeeds, and an upload that itself failed has nothing to patch — see the entries below for what
  happens to that bubble.

- **Retrying an attachment or voice bubble whose upload never landed no longer publishes an empty
  media message.** The bubble painted for a failed *upload* holds no blob at all, and the bundled
  chat view offers a retry on every failed bubble. Taking it re-posted the row verbatim, so an
  attachment or voice message pointing at nothing landed in the room, shown as delivered to the
  sender and impossible to take back. `messages.retrySend` now refuses that row: it posts nothing,
  leaves the bubble failed and returns a `ValidationFailure` whose `errors['reason']` is
  `attachment_never_uploaded`.

  A row counts as having a blob when *any* of `attachmentUrl`, `attachmentId` or the
  `attachmentUrl` / `attachmentId` keys of `metadata` carries a non-empty value — `metadata` is
  where `sendVoice` puts them, and where a host driving `messages.send` itself may put them, so
  those rows keep retrying as they did in 0.16.0. An empty string counts as absent.

  **What the user can actually do about it**: pick the file again. Nothing else recovers that
  bubble on its own, and this release deliberately narrows the one path that used to look like it
  did (see the offline-queue entry below). Automatic replay happens only when the host configured
  a cache — no `cacheConfig`, no offline queue — *and* the upload failed in a way that proves the
  bytes never left the device. Every other upload failure ends with a failed bubble whose retry is
  refused. The bundled chat view now says so out of the box: `NomaChatView` mounts an
  `OperationFeedbackListener` over `adapter.operationErrors` itself (see **Changed**), so the
  refusal reaches the user as a localized snackbar with no host wiring. Hosts with their own
  `errorLabelBuilder` should route that `reason` to a "pick the file again" message of their own.

- **An upload whose 2xx carries neither an id nor a url is reported as a failure.** `POST
  /attachments` was parsed leniently: a response body with no `attachmentId`/`id` and no
  `getUrl`/`url` produced an `AttachmentUploadResult` with an empty id and a null url, and
  `sendAttachment` / `sendVoice` then posted a perfectly ordinary-looking media message pointing at
  nothing — no retry needed, first attempt. `attachments.upload` now returns a `ServerFailure` for
  that body, which routes the bubble through the existing upload-failure branch instead.

- **An attachment or voice send that reached the server without answering no longer paints a
  second bubble.** The optimistic rows of `sendAttachment` and `sendVoice` were built without the
  `clientMessageId` that text sends carry, and that key is the only way the authoritative
  `new_message` event can recognise the row it belongs to. When the send landed but its response
  did not — a `receive`-phase timeout, a 5xx after persistence, or an `ack_mode=async` provisional
  echo — the event found nothing to reconcile and added a bubble of its own: the same photo or
  voice note twice, one of them stuck in its failed or sending state for good. Both rows now
  carry the key, so the event replaces the optimistic bubble exactly as it already did for text.

  **Known limitation, and it is new in this release.** The same key now also reaches the
  cold-start rehydration path, which still decides whether a cached pending row was superseded by
  comparing message *text* within a timestamp window — media rows carry no text, so a stale
  **failed** media row still sitting in the pending cache is not recognised as superseded.
  Precisely because it now carries the `clientMessageId`, re-adding it resolves onto the
  authoritative message and repaints an already-delivered message as failed until the next
  reload; 0.16.0 painted a second, duplicate bubble in that same situation. The heuristic
  predates this release, the symptom does not. Tracked in `ISSUES.md` under *"Pending-row
  rehydration matches on text + timestamp, not the idempotency key"*, together with the fix
  (match on the key before the heuristic), deliberately left out of a release scoped to the send
  path.

- **An upload that timed out after the bytes were on the wire is no longer replayed by the offline
  queue.** `POST /attachments` carries no idempotency key and the server mints a fresh
  `attachmentId` on every call, so replaying an upload that may already have landed leaves a
  duplicate blob behind. The queue now accepts an upload failure only when it proves the bytes
  never arrived — a `NetworkFailure`, or a `TimeoutFailure` whose `kind.isPreResponse` — the same
  predicate the equally non-idempotent text send has always applied.

  **The trade-off, stated plainly**: a `receive`-phase or `unknown` timeout on an upload — the
  common shape of a bad network dropping while waiting for the `201` — now has no automatic
  recovery at all. It marks the bubble failed, it is not queued, and `retrySend` on it is refused
  because nothing was uploaded to re-post. The user has to pick the file again; the bundled UI
  tells them so. The alternative was replaying an upload that may already have landed, which
  leaves an orphan blob on the server for every attempt. That stands until `POST /attachments`
  takes an idempotency key.

- **Every link in every message was dead — tapping a URL in a bubble now opens it.** The markdown
  parser has always painted a bare `http://` / `https://` URL blue and underlined, the universal
  "this is tappable" affordance, and it attaches the tap recognizer only when it is handed an
  `onTapLink`. `ChatView` has always built one (`callbacks.onTapLink ?? _defaultOpenLink`, which
  opens the URL in the system browser via `url_launcher`), and `MessageList` has always forwarded
  it — but `MessageBubble` never passed it on to the `TextBubble` it builds. The handler existed,
  was correct, and died one line short of its destination, so no link in any message has ever been
  tappable, in any host, with or without custom wiring. The bubble now forwards it.

  **This is visible to every host on upgrade and needs no wiring**: URLs in message text become
  tappable and open in the system browser. A host that already passes its own
  `ChatViewCallbacks.onTapLink` — in-app webview, deep-link router, confirmation dialog — keeps
  winning: the default is only the `??` fallback, and it is now actually reachable. Hosts that
  want links to stay inert pass an `onTapLink` that does nothing. Link *styling* is unchanged —
  the blue underline was already painted and still is, so goldens do not move. This covers the
  message timeline; untouched, and each tracked in `ISSUES.md`: the reply bubbles inside
  `ThreadView`, which build their own `MessageBubble` and accept no `onTapLink`, and `@mentions`,
  which the parser still paints as tappable with no callback anywhere in the public API.
  `LinkPreviewBubble` and the links tab of the media gallery had working taps already.

- **Registering `ChatUiLocalizations.delegate` now translates the chat UI.** The delegate, `of` and
  `override` resolved the right instance for the active locale and no widget consulted them: every
  widget read `ChatTheme.l10n`, whose default is English. A host that followed the guide to the
  letter — delegate registered, `supportedLocales` set, app locale in Spanish — got a chat in
  English with no clue why. Widgets now resolve through `ChatTheme.l10nOf(context)`, which returns
  the instance the host put on `ChatTheme.l10n` and otherwise reads the `Localizations` ancestor,
  so both routes work and the ancestor route follows app-locale changes at runtime.

  **Hosts that already pass `l10n` through the theme see no change** — an explicit instance still
  wins. The one case that moves is a host whose app locale is not English and whose theme carries
  the canonical `ChatUiLocalizations.en` verbatim (including `forLanguageCode('en')`,
  `forLanguageCode(null)` and any unsupported code, which all return that instance): that theme
  reads as "not set" and now follows the ancestor. Passing `ChatUiLocalizations.en.copyWith()`
  pins English. The limitation is documented on `ChatThemeL10n` and tracked in `ISSUES.md`.

- **A membership banner is no longer stuck in the language it was written in.** "Alice joined",
  "You removed Bob" and the role-change notice are composed by the adapter — which has no
  `BuildContext` — and then *persisted*, so the sentence stayed in whatever language the session
  had when the event arrived: switching the app to Spanish left every old banner in English, on
  every device, forever. The row now carries the ingredients that produced it (`event`, the two
  user ids, the display names resolved at the time, and whether the local user is the subject or
  the actor — see `SystemMessageMetadataKeys`), and `MessageBubble` rebuilds the sentence on every
  paint with the localizations it is rendering with. Display names stay as they were resolved: they
  are proper nouns, and re-resolving them per paint would cost a user lookup to change nothing.

  **Rows written by earlier versions keep their stored text**, since they carry ids but no names —
  re-localizing them would put raw user ids on screen, which is worse than an English banner. The
  new public helper `localizedSystemMessageText(message, l10n)` is what the bubble calls and is
  exported, so a host with its own system-message rendering can call it too. A host
  `systemMessageTextResolver` still wins over both, unchanged.

- **The chat list was the one screen the delegate could not reach, and now it is not.** A row's
  preview — "📷 Photo", "🎤 Voice message (0:14)", "Forwarded", the deleted marker, "Alice reacted
  👍 to …" — was composed once, by the adapter, in whatever language the session had when the
  message landed, and then stored on the row and cached. Registering the delegate and switching the
  app to Spanish translated every screen except the one users spend the most time on, and no
  amount of host wiring fixed a row already written. Worse, one shape came out wrong in *any*
  language: a photo with no caption stored the generic "📎 Attachment" in the very slot the
  renderer reads captions from, so the row read "📷 📎 Attachment" instead of "📷 Photo", on
  every host, forever.

  Nothing is composed into a row any more. `RoomListItem.lastMessage` now holds the sender's own
  text and nothing else — `null` when they wrote none — and the row carries what the preview needs
  instead: the type, the mime type, the file name, the voice duration, the deleted flag, and, new
  in this release, `lastMessageReactionTargetText` / `lastMessageReactionTargetType` for the
  message a reaction was aimed at. `RoomTile` builds the sentence from those on every paint, with
  `theme.l10nOf(context)`, so the list follows the app locale live like every other widget and the
  "📷 📎 Attachment" row is gone. **Text a person wrote is never rewritten**, because nothing
  rewrites anything: the only string kept is theirs.

  **Two host-visible changes.** `RoomListItem.lastMessage` (and `UnreadRoom.lastMessage`, which
  feeds it) no longer carries a label for a captionless photo, voice note, forward, reaction or
  deletion — read the row's structured fields, or call the exported `buildLastMessagePreview`, to
  render one. And the room-list search filter, which matches on that field, now matches what people
  typed rather than the SDK's own labels. Rows cached by an older version keep the label they were
  written with until the next `loadRooms` or the next message in that room refreshes them.

- **`ChatUiAdapter.l10n` is settable, and registering the delegate is now enough on its own.** It
  was a `final` field, so the strings the adapter composes where no `BuildContext` is in reach were
  pinned to the language the session connected with, and the only documented way to move them was
  to dispose the adapter and build a new one. That made a language change cost a disconnect and a
  full reconnect, and a reconnect that fails leaves a host with no chat at all until the app
  restarts — a heavy and failure-prone price for re-reading a few strings.

  It is now a property whose setter every handler reads through on each use, so assigning a new
  bundle re-points the whole adapter in place: no teardown, no reconnect, no await, nothing that
  can fail. With the previews gone from the row, one string is left that a widget cannot recompute
  for itself because it is stored there rather than derived at paint time — the self-chat title —
  and the setter re-stamps it, touching only a row whose title is exactly what the outgoing bundle
  would have produced.

  **The SDK now assigns it for you.** `NomaChatView`, and `RoomListView` when handed the new
  optional `adapter:`, push the localizations their subtree resolved into the adapter as their
  dependencies settle, with the same precedence `ChatTheme.l10nOf` uses: an explicit
  `ChatTheme.l10n` first, the `Localizations` ancestor otherwise. **A host that assigns
  `adapter.l10n` itself — or passes a non-default `l10n:` to the constructor or to
  `NomaChat.create` — keeps full control and is never pushed to**, so existing wiring such as WB's
  `ChatService.updateLanguage` behaves exactly as before. Reading `adapter.l10n` is unchanged.

- **`ChatUiLocalizations.override(...)` reaches every string.** It declared 237 of the 274 fields
  and forwarded 236 of those: `attachmentUploadingTemplate` was accepted and silently dropped, and
  37 more — `retry`, `messageInfo`, `readBy`, `deliveredTo`, `starredMessages`, the `mute*` and
  `presence*` sets, `archived`, `loadMore`, `error`, `reason`, `avatar`, `email`, `searchEmoji`,
  the `*Failed` toasts and the rest — could not be overridden at all. The parameter list now
  mirrors `copyWith` one for one and forwards all of it.

### Changed

- **`NomaChatView` mounts the bundled `OperationFeedbackListener` itself.** The listener has
  shipped with the package for a while, but nothing inside the package mounted it: a host that
  rendered `NomaChatView` — the drop-in path this package advertises — got no snackbar for a
  moderation rejection, and none for the refused retry described above. The retry button did
  nothing and said nothing, whatever the docs claimed. The view now wraps its own subtree in the
  listener, fed from `adapter.operationSuccesses` and `adapter.operationErrors` and localized with
  the very `theme` it is already rendering with, so the feedback works with zero host wiring.

  **Wrapping the view by hand still gives exactly one snackbar.** A host that already wraps it in
  an `OperationFeedbackListener` wired to both streams keeps that one and only that one: the view
  reads what the listener above it delivers and adds nothing, so those integrations are untouched
  and need no edit. What the view checks is what the wrapper *shows*, not that a wrapper exists —
  `errors` is optional on that widget, and a listener mounted for successes only would otherwise
  have silenced the very failures this release exists to surface. In that case the view mounts a
  failures-only listener underneath: the wrapper keeps its success confirmations, the failures get
  said once, and neither is announced twice. A listener mounted with `enabled: false` still claims
  the whole subtree — silencing your own listener is a request for silence, and that switch would
  be dead if the view spoke over it.

  A host that routes the two streams into feedback UI that is *not* this widget — a global error
  banner, an analytics-driven toast — decides: pass
  `ChatViewBehaviors(showOperationFeedback: false)` when that UI already speaks for the same
  events, or leave the default on and let the SDK cover the ones it does not. The same flag is the
  switch for a layout with two chat views on screen where only one should speak.

  **What actually changes for a host with no feedback wiring at all**: pinning, unpinning and
  deleting now confirm themselves with a snackbar, and moderation rejections and refused retries
  now explain themselves. Forwarding confirms itself too, for the hosts that wire it — see the
  entry below on why it is no longer in the default menu. Every string comes from
  `ChatUiLocalizations` through the view's own theme, so it is already translated, already
  overridable, and an empty string still suppresses its snackbar.

- **`MessageAction.forward` is no longer in `NomaChatView`'s default context menu.** The tile was
  painted on every long-press with its icon and its label, and tapping it closed the sheet and did
  nothing at all: neither `ChatView` nor `NomaChatView` had a branch for it, and the only remaining
  exit was `ChatViewCallbacks.onContextMenuAction`, which a drop-in host does not pass. Choosing
  the target rooms is a product decision the package cannot make on a host's behalf, so it now
  leaves the action out instead of offering a dead control.

  **Hosts that already wire forwarding must add the action back** — one line, and the behaviour is
  exactly what it was:

  ```dart
  NomaChatView(
    roomId: roomId,
    adapter: adapter,
    contextMenuActionsResolver: (room, defaults) =>
        {...defaults, MessageAction.forward},
    callbacks: ChatViewCallbacks(
      onContextMenuAction: (message, action) {
        if (action == MessageAction.forward) openForwardSheet(message);
      },
    ),
  );
  ```

  Nothing else about forwarding changed: `MessageForwardSheet`, `adapter.messages.forward` and the
  `feedbackForwarded` confirmation are untouched, and the bundled feedback listener still shows
  that confirmation once the host's own sheet completes the operation.

- **A video bubble no longer paints a play button nobody answers.** `VideoBubble` drew its 56×56
  play overlay unconditionally whenever no upload was in flight, but the tap travels to
  `ChatViewCallbacks.onTapVideo`, which — unlike `onTapImage` and `onTapFile` — has no default in
  `NomaChatView`: the package bundles no video player. A host that wired nothing showed a
  thumbnail with a large, obvious play button that did absolutely nothing when tapped. The overlay
  is now painted only when a handler is wired, so an unwired video reads as a still. Wire
  `onTapVideo` to get the affordance back; the upload-in-progress state is unchanged (placeholder
  and progress ring, no overlay, taps ignored).

- **The default app bar's title row is tappable only when `onAppBarTap` is wired.** `NomaChatView`
  always handed `ChatRoomAppBar` a non-null closure — `() => onAppBarTap?.call(room)` — so the
  `InkWell` behind the avatar, title and subtitle was permanently live: it painted a Material
  splash and swallowed the tap while the default `onAppBarTap` of `null` made the closure a no-op.
  Opening a room or user profile is navigation, and the package has no screen it can route to on a
  host's behalf, so the callback is now propagated as it arrives: `null` in, no ripple, no consumed
  tap. Wire `onAppBarTap` — `GroupInfoPage` and `UserInfoPage` ship with the package — to get the
  affordance back, exactly as before. Hosts with their own `appBarBuilder` were never affected.

- **`RoomListView` no longer opens a room context menu it cannot answer.** Every tile handed its
  `InkWell` a non-null `onLongPress`, so a long press always opened `RoomContextMenu`, and with
  `contextMenuActions` left at its default that sheet painted every action it knows for the row:
  Mute or Unmute, Pin or Unpin, Mark as read when the row had unread messages, and Delete on every
  row without exception. Picking one closed the sheet and called
  `onContextMenuAction`, which a drop-in host does not pass — a full modal sheet of dead tiles,
  Delete included, opened by the package without the host ever asking for it. Unlike the bubble
  menu, this view takes a `RoomListController` and no adapter, and that controller is a pure
  view-model: it can mutate the in-memory list but cannot mute, pin, mark read or delete a room on
  the server. There is no subset of those actions with a working default to keep, so the long press
  is now wired only when something can answer it — `onContextMenuAction`, `onLongPressRoom`, or a
  `contextMenuBuilder` that owns the sheet outright. Wire any of the three and the menu behaves
  exactly as it did.

- **An invitation row paints "Accept" and "Reject" only when they are wired.** `RoomTile` drew both
  buttons on every `room.isInvitation` row and handed each one a nullable callback. A button with
  no handler behind it registers no tap recognizer, so the touch did not stop there: it fell
  through to the tile's own `InkWell` and opened the conversation. Pressing "Reject" on an
  invitation therefore entered it — the wrong action rather than no action, on the only control the
  row offers for answering at all. Each button is now painted only when its own handler exists
  (`RoomListView.onAcceptInvitation` / `onRejectInvitation`, forwarded per row), so a tap always
  lands on the thing it says it does, and a row with neither wired falls back to the ordinary
  last-message preview. Hosts that already answer both buttons see no change.

- **`ChatRoomsApi.updateCachedRoomPreview` replaces the whole last-message block when it is told
  the type.** Every field it takes describes one message, but each was merged with `??` against
  what the row already held, so a plain text message landing after a photo inherited the photo's
  mime type and rendered as one, and a reaction's quoted snippet outlived the reaction. A call
  that passes `lastMessageType` now states the row's new last message outright and the rest of the
  block is replaced, `null`s included; a call that omits it still patches a single field (a
  receipt, a deletion) and leaves the block alone. Two optional parameters were added for the
  reaction fields (see **Added**); a custom UI that calls this method itself needs no edit unless
  it wants them.

### Added

- **`RoomListItem.lastMessageReactionTargetText` / `.lastMessageReactionTargetType`**, mirrored on
  `UnreadRoom`, persisted in the preview cache, and settable through
  `ChatRoomsApi.updateCachedRoomPreview` — the text (or, failing that, the type) of the message a
  reaction was aimed at, so "Alice reacted 👍 to …" can be rebuilt at paint time in the reader's
  own language instead of being frozen when the reaction landed. All optional; nothing to wire.

- **`RoomListView.adapter`** — optional, and the only reason to pass it is localization: the view
  hands the adapter the bundle its subtree resolved, so a host that registers
  `ChatUiLocalizations.delegate` gets the strings composed off-screen in the app's language with
  no assignment of its own. The view stays adapter-free for everything else it renders, and a host
  that sets `ChatUiAdapter.l10n` itself is never overridden.

- **`ChatViewBehaviors.showOperationFeedback`** — opts the chat view out of mounting the bundled
  `OperationFeedbackListener` (default `true`, see **Changed**). Optional named parameter with a
  default, like every other knob on that class.

- **`OperationFeedbackListener.coverageAbove` and `OperationFeedbackCoverage`** — what a listener
  mounted above a given context already delivers: `none`, `successesOnly` (mounted without an
  `errors` stream, so failures reach nobody through it) or `everything`. This is how `NomaChatView`
  decides what to mount, and it is public so a host composing its own feedback widgets can make the
  same call. Nothing to wire for the drop-in path.

- **`ChatUiLocalizations.attachmentNeverUploaded`** — "That file was never uploaded — pick it
  again to send it." (translated in `es`, `fr`, `de`, `it`, `pt` and `ca`; English elsewhere).
  The listener `NomaChatView` mounts shows it as a soft snackbar when `retrySend` is refused with
  `errors['reason'] == 'attachment_never_uploaded'`, so the bundled retry button explains itself
  instead of doing nothing. Override it like any other string, with `copyWith` on the
  `ChatUiLocalizations` you put on `ChatTheme.l10n`, or through
  `ChatUiLocalizations.override(...)`. The field has a default, so nothing has to change to
  upgrade.

- **`MockAttachmentsApi.uploadCount`** (`package:noma_chat/noma_chat_testing.dart`) — how many
  times `upload` has been called, failures included. Lets a test assert that a path which re-posts
  an already-uploaded blob, such as `retrySend` on an attachment whose send failed, does not
  upload the bytes a second time.

### Removed

- **`packages/noma_chat_otel/` — the OpenTelemetry companion is gone from the repo and from the
  published archive.** Its documented install route was a git dependency on this repository
  (`path: packages/noma_chat_otel`), and it also travelled inside `noma_chat`'s own tarball; both
  stop resolving from this version on. It was under a hundred lines turning
  `ChatConfig.metricCallback` into one instantaneous span per event, and its span naming could not
  be customized without rewriting the callback anyway — which is the whole adapter:

  ```dart
  config: ChatConfig(
    metricCallback: (metric, data) =>
        tracer.startSpan('noma_chat.$metric', attributes: attrs(data)).end(),
  ),
  ```

  `attrs` is your own map-to-attributes conversion for whichever OTel binding you use, and the
  span names are now yours to choose. `ChatConfig.metricCallback` itself is unchanged, and
  `TELEMETRY.md` still documents every metric name, its fields and when it fires.

- **`benchmark/` — the micro-benchmark scripts are gone from the repo and from the published
  archive.** Three standalone `dart run` programs (event parser, message mapper, offline queue)
  plus their README, used to compare throughput before and after a change on a maintainer's
  machine. They were never public API and were never importable as a library, but they did travel
  inside the archive; a consumer running them out of their pub cache no longer finds them.

### Docs

- **The localization guide describes the two routes that now work.** The class documentation,
  `doc/DEVELOPER_GUIDE.md` and the `LocalizationsDelegate` bullet of the 0.6.0 entry below said the
  widgets resolve the active instance through `Localizations`; between 0.6.0 and this release they
  did not, and a host that registered the delegate got an English chat with no clue why. Both
  routes are real as of the **Fixed** entry above, and the docs now spell out the precedence
  between them, the runtime-locale behaviour, and the one case where an explicit English theme
  loses to the ancestor:

  ```dart
  // Route 1 — explicit, wins over the ambient locale.
  NomaChatView(
    roomId: roomId,
    adapter: adapter,
    theme: ChatTheme.defaults.copyWith(
      l10n: ChatUiLocalizations.forLanguageCode(code),
    ),
  );

  // Route 2 — register the delegate, leave the theme alone.
  MaterialApp(
    localizationsDelegates: const [ChatUiLocalizations.delegate, /* … */],
    supportedLocales: ChatUiLocalizations.supportedLocales,
    home: NomaChatView(roomId: roomId, adapter: adapter),
  );
  ```

## 0.16.0

### Security

- **The local cache is now namespaced per user.** Every Hive box the SDK opens is prefixed with a
  digest of the signed-in user's id — `u_` followed by 32 hex characters — so two accounts on the
  same device get two disjoint stores. Until now they shared one: signing out and signing in as
  somebody else left the previous user's rooms, contacts, display names and message history in
  place, and the new session read them as its own. `NomaChat.create()` passes `currentUser.id` for
  you — **nothing to do if you use it**. If you build the datasource yourself, pass the id:
  `HiveChatDatasource.create(userId: userId)`. Omitting it selects the old device-wide layout,
  which is still shared by every account that opens it.

  The id is digested rather than spelled out, so **no box on disk carries a user's id in its
  name**: a host that hand-deletes box files on logout, or goes looking for the boxes belonging to
  a given user, will not find them. Clear a user's cache through the datasource's own `clear()`.

  One consequence to check before upgrading: the id now derives the store's name, so
  `NomaChat.create()` and `HiveChatDatasource.create()` **throw `ArgumentError` for a blank or
  whitespace-only id**. In 0.15 the id never reached the cache and such a session opened normally.
  If your host builds a session before the id is known, pass `enableCache: false` for it.

- **A cache that turns out to belong to another account is destroyed before it is read**, and when
  it cannot be destroyed the session is refused: `create()` throws a `StateError` rather than
  returning a datasource that would serve the surviving boxes to the signed-in user. Nothing is
  claimed on that path, so the next launch tries the destruction again. It takes a store whose
  namespace two ids somehow share — a host that respells its ids between releases, a backup
  restored from another device — plus a write failure on top, so no ordinary install reaches it;
  handle it like any other cache failure and retry, or open that session with
  `enableCache: false`.

### Added

- **`adoptUnscopedCacheFor` — opt in to carrying the pre-0.16 local history over.** A device
  upgrading from an earlier version still holds the old device-wide store, and by default **nothing
  is adopted from it**: the store carries no record of whose it is, so the SDK will not guess. It is
  left untouched and reclaimed from disk after 30 days (`unscopedCacheRetention`), and the user
  re-fetches their history from the server on first open — visible as an empty room until the
  network answers, and as the permanent loss of anything the server no longer serves.

  If your app can never have had a second account signed in on the same install, you can say so and
  the old store is moved into that user's namespace:

  ```dart
  final chat = await NomaChat.create(
    /* ...required params... */
    currentUser: ChatUser(id: userId, displayName: name),
    adoptUnscopedCacheFor: userId,
  );
  ```

  This is an assertion, not a hint. **If it is wrong, the named user inherits the other person's
  rooms, contacts and message history and sees it as their own** — the exact leak the scoping above
  closes, re-opened by hand. It is refused when it names anyone other than the signed-in user (the
  old store is then left on disk, still adoptable by whoever it belongs to), and refused when the
  store's own owner stamp disagrees with it.

  Whatever the answer, it is written into that user's store as a migration record, and that record
  is what stops the question being asked a second time — not the `cacheOwner` stamp, which answers
  a different question (*whose* a store is, so that one found stamped for somebody else is
  destroyed rather than served). The one exception is deliberate: a refusal taken while you were
  passing nothing is reopened when you start passing the parameter, so shipping the scoping in one
  release and the assertion in the next still carries the history over, as long as the retention
  window has not expired.

  On that reopen path the old store can be a release older than the one adopting it, so **adoption
  fills gaps and never writes over live state**. Two consequences: contacts and invited rooms are
  stored as lists rather than keyed by id, so each is carried over whole or not at all — and not at
  all once the user has a list of their own; and the queue of unsent operations is never carried
  over, because it holds instructions rather than state and nothing in it records how old they are.

  An adoption interrupted before it completes — the process killed mid-move — resumes on the next
  launch instead of stranding what was left behind. The old store's own meta box is the last thing
  removed, so for as long as anything of it remains, it is still there to be found.
- `unscopedCacheRetention` and `orphanGracePeriod` are now reachable from `NomaChat.create()`
  (30 and 7 days by default), not only from `HiveChatDatasource.create()`.
- `HiveChatDatasource.purgeUnscopedCache()` deletes the old device-wide layout on demand, for hosts
  that would rather reclaim the space than wait out the retention window. Pass the same
  `encryptionCipher` your store uses: the per-room boxes are found by reading room ids out of the
  global ones, and without the right cipher they are silently left on disk.

### Fixed

- **A double tick never turns back into a single one.** Receipt state is now monotonic: it only ever
  advances. Three paths used to walk it backwards — a REST row (which carries no receipt at all)
  replacing a message already acked over the event stream, a room reclassified between 1:1 and
  group, and a re-aggregation under a roster that had shrunk. The fourth way in, an out-of-order
  frame, was already guarded in 0.15. Every path that replaces a message row — the server echo
  that confirms an optimistic send included — now defers to that same comparison, held in one
  place, so the lower value is discarded instead of being written.
- **A group's read ticks survive re-entering the app.** The aggregate for a group is "read once
  every other member has read", which needs the member list as the divisor. When the controller was
  rebuilt before its roster had hydrated, that divisor was zero and the aggregate reported `sent`,
  downgrading every already-read message in the room. An empty roster on a group is now treated as
  "not derivable yet" and leaves the existing state alone.
- **Receipts survive the app being killed.** They arrive as events and were never written anywhere,
  so every ✓✓ died with the process and the room re-opened showing single ticks. Advanced receipts
  are now mirrored onto the message rows and persisted, and a cached row's receipt is merged rather
  than overwritten when a receipt-less network row replaces it.
- **Re-opening a room recovers the ticks the event stream missed.** The rehydration that replays the
  server's read cursor only applied its `lastReadMessageId` when that message was inside the loaded
  window, and fell back to the timestamp comparison only when the backend had sent no id at all — so
  a room re-opened on its most recent page, where the cursor has usually paginated out, matched
  neither branch and left every older bubble on one tick. The fallback now also covers the
  paginated-out case — **as far as the local cache can carry it**: the cursor message is placed in
  conversation order by its own timestamp, looked up in the cache, and a cursor the cache does not
  hold either still marks nothing rather than guess. That is a fresh install, the first open after
  `clear()` — where the cache holds only the page just loaded — and any session running with
  `enableCache: false`. Such a room opens on single ticks until a receipt event or a later launch
  fills them in. What the fallback recovers **from a cursor** is written to the cache, so the next
  cold start renders from it instead of repeating the round trip. A whole-room read — the shape the
  backend sends with no `lastReadMessageId` at all — is applied to the screen but deliberately never
  written: a stored tick can only ever move up, and there is no cursor behind that one to justify
  making it permanent.
- **A message that failed to send is no longer filed away as delivered and read.** A peer's receipt
  advances every older message of yours at once, and optimistic rows sat in that range, so a failed
  send picked up the tick of a later successful one — and, new in this release, was written into the
  message history carrying it. Two things followed on the next cold start: the failed message
  rendered as delivered and read, and once you retried it successfully the room showed it twice.
  Unsent rows now take no receipt at all, and one that already carried a receipt has it revoked the
  moment the send is declared pending or failed.
- **A cold start no longer wipes the message history of rooms this device only joined.** The orphan
  sweep destroyed the message box of any room absent from the `chat_rooms` box — but `saveRooms` has
  a single caller in the SDK, the room-creation path, so on any install that joined its rooms
  instead of creating them that box is empty and every room looked orphaned. The sweep now needs
  positive proof of deletion: a room must be missing from two authoritative room listings, spread
  over a grace period (`orphanGracePeriod`, 7 days by default), and unattested by every local source
  that knows about rooms. An install that is offline, or that has not loaded its room list yet,
  produces no candidates at all and loses nothing.

### Changed

- **The per-room receipts list is pinned to network-first** rather than following whatever read
  policy the consumer configured. `networkFirst` is already the default, so this changes nothing
  unless you set `defaultReadPolicy: CachePolicy.cacheFirst` — under which a peer reading while the
  app is not running leaves no local signal that could invalidate the stored copy, and a long
  message TTL pinned the room's ticks to a stale snapshot for as long as that TTL ran. The cached
  rows still render instantly on open, and receipts only advance, so the round trip costs no
  perceived latency and cannot regress what is on screen. The cache remains the offline fallback.
  Sending a read receipt, and any receipt-bearing event, now also expires the freshness entry
  behind that list, so the next read goes to the network; the stored rows themselves are kept and
  keep serving offline reads.
- **`clear()` now removes the pending and reaction boxes of every room it knows about**, not only
  the message boxes it had opened. A logout that cleared the cache used to leave unsent drafts and
  reactions on disk for any room the session had not visited, where nothing would ever read them
  again and nothing would delete them either. It also deliberately preserves two keys it wrote
  itself — the store's owner and the record of whether the pre-0.16 cache was adopted — so clearing
  a cache does not make the next launch re-ask a question that was already answered.

## 0.15.0

### Changed

- **A voice message starts recording the moment the finger touches the mic button**, instead of
  after a half-second hold. Everything that follows is unchanged: slide up to lock, slide left to
  cancel, release to send.
- **BREAKING — `StartRecordingResult` lost `permissionJustGranted` and gained `aborted`.** Code that
  `switch`es exhaustively over the enum will no longer compile. `permissionJustGranted` existed only
  to feed a heuristic that timed `hasPermission()` and guessed whether the OS permission dialog had
  been shown, dropping that first recording; it is gone, and a first grant now records like any
  other. `aborted` is returned when the touch that asked for the recording is already over before
  the platform recorder gets armed. Migration: delete the `permissionJustGranted` branch — the
  `started` branch covers what it used to — and treat `aborted` like `alreadyRunning`, i.e. as a
  non-event with no message for the user.

### Fixed

- **The mic button no longer steals gestures from the rest of the composer.** The recorder listened
  through a `GestureDetector` wrapping the whole composer, so its long-press recognizer competed in
  the gesture arena with everything underneath it. It is now a plain `Listener`, which observes the
  pointer stream without ever claiming it, and the mic button's own rectangle is what decides
  whether a touch starts a recording.
- **A tap on the mic no longer flashes the recording row.** Capture starts on touch down, so a
  stray tap used to swap the composer to the recording UI and straight back. The recording state is
  now announced to listeners only once the touch outlives a short window
  (`VoiceRecordingController.revealDelay`, 120 ms); the capture itself is untouched, so audio from
  the first millisecond still ends up in the message.
- **A tap too short to be a recording no longer opens the platform audio session.** Arming the
  recorder activates the shared audio session, and on iOS that interrupts whatever the user is
  listening to. When the finger lifts before the recorder is armed, the start is now abandoned and
  the recorder is never touched.
- **An interrupted touch discards the recording.** A pointer cancelled by the system (an incoming
  call, a parent scrollable taking the gesture over) reached no handler at all, leaving the
  recording running with no finger left to end it. Cancelled touches now drop it; a locked
  recording, which no longer depends on the finger, is left running.

## 0.14.2

### Fixed

- **Picked photos no longer carry their EXIF metadata**, and with it the GPS coordinates of where
  they were taken, which until now travelled to every room member who downloaded the original file.
  `requestFullMetadata: false` already covered iOS, but it does nothing on Android:
  `image_picker_android` copies EXIF from the source file unconditionally whenever it resizes, and
  offers no flag to suppress it. Picked bytes now go through `JpegMetadataStripper`, which drops the
  EXIF, XMP/IPTC and comment segments of a JPEG without adding an image-processing dependency.
  Non-JPEG picks, and any JPEG that cannot be parsed with full confidence, are returned untouched —
  corrupting a photo would be a worse outcome than leaving metadata on it. Covers both the image
  pickers and the generic file picker.

## 0.14.1

### Fixed

- **Image bubbles size to their content.** A portrait photo left wide empty
  margins on both sides of the bubble instead of the bubble following the
  image.
- **The full-screen image viewer loads authenticated images.** Tapping an
  attachment opened a viewer that fetched the URL without the bearer token,
  so it answered 401 and the image never appeared. `onTapImage` now defaults
  to a loader that carries the session.
- **Attachment uploads have their own timeout.** They inherited the 30 second
  timeout meant for small JSON calls, which a photo or a video over a slow
  connection does not fit in; since the upload is a POST, the retry
  interceptor deliberately excludes it, so the send just failed.
- **Photos no longer ship their EXIF location.** A picked image carried the
  GPS coordinates of wherever it was taken, so anyone who downloaded it
  learned where the sender had been. Not requested on iOS any more; on
  Android `image_picker` still copies EXIF when it resizes, so that half is
  still open.
- **The chat is usable with a screen reader.** The message bubble excluded its
  own semantics and declared no actions, so a reader could read a message and
  reach nothing else: no context menu to reply, react, forward, delete, pin or
  copy, no retry on a failed send, no way to open an attachment or enter a
  thread.
- **Consumer behaviours merge onto the defaults** instead of replacing them
  wholesale, so enabling one thing no longer switches the rest off.
- **The room cache evicts the least recently used room**, not the first one
  alphabetically.
- Close buttons in the media viewer and the attachment sheet are labelled.

## 0.14.0

### Breaking changes

- **`ChatClient` gained two members: `pendingOperationCount` and
  `flushPendingOperations()`.** Anything that `implements ChatClient` and
  spells out every member explicitly — in practice, hand-written test fakes
  with no `noSuchMethod` fallback — stops compiling until both are added.
  `NomaChatClient` and `MockChatClient` already implement them, so only your
  own fakes are affected; in this repository the change broke 13 test files,
  and a consumer with a similar fake will see the same. The patch is two
  lines per fake — see [MIGRATING.md](./MIGRATING.md).
- **The five `ChatUiAdapter` sub-controllers are `interface class` instead
  of `final class`**: `ChatRoomsController`, `ChatMessagesController`,
  `ChatDmController`, `ChatContactsController` and `ChatProfileController`.
  This only *widens* what callers may do — nothing that compiled against
  `0.13.x` stops compiling — but it is the change that makes them mockable
  from outside the package, so it belongs here: a mock declared as
  `extends Mock implements ChatRoomsController` now compiles in your own
  test suite. While they were `final`, mocking the adapter meant reaching
  for the `@internal` pass-throughs on `ChatUiAdapter` (`adapter.loadRooms()`,
  `adapter.openDirectMessageDraft()`, `adapter.draftRoutingKey()`, …) and
  silencing `invalid_use_of_internal_member`. That workaround can go: move
  those call sites to `adapter.rooms.*` / `adapter.dm.*` and delete the
  ignore.

### Behaviour changes

Neither of these breaks compilation, but both change *when* something
happens. Read them before upgrading.

- **The offline queue drains on the first connection of a session, not only
  after a reconnect.** The drain used to be gated on having connected at
  least once already, so anything queued during a cold start — the classic
  "the user sends a message while the socket is still coming up" — sat in
  the queue until the connection dropped and came back. It now goes out as
  soon as the first `connected` event lands. If any part of your app quietly
  depended on that delay (a screen that assumed it could still cancel a
  queued send, say), those sends now leave earlier. Missed-unread catch-up is
  deliberately *not* affected: it still runs only after a real
  disconnect→reconnect cycle, because a session that never dropped has
  nothing to catch up on.
- **WebSocket close code `4002` (`auth_failed`) now invalidates the cached
  token, like `4003`/`4004`, and repeated rejections stop the reconnect
  loop.** On `4002` the transport used to reconnect with the very token the
  server had just refused, so a stale credential turned into an endless
  connect → `4002` → reconnect cycle. The cached token is now dropped, which
  forces the next attempt to fetch a fresh one; and after **3** consecutive
  token-rejecting closes (`4002`/`4003`/`4004`) with no successful
  authentication in between, the transport terminates the session — it stops
  reconnecting and emits a terminal `ChatAuthException` — instead of looping
  forever. A successful auth, or an explicit `connect()`, resets the counter.
  A host that hand-rolled a "watch for the error state, refresh the token,
  reconnect" patch to work around this can delete it.

### Added

- `ChatClient.pendingOperationCount` — how many operations are sitting in the
  offline queue right now (`0` on a client configured without one), so a
  "N pending" badge no longer needs the host to shadow-count sends itself.
- `ChatClient.flushPendingOperations()` — forces an immediate drain attempt
  instead of waiting for the next connection. The queue already drains on
  every connect, so this is for an explicit "retry sending" affordance, not
  for normal operation.
- **Duplicate-submission guard on room and member operations.**
  `rooms.create`, `rooms.updateConfig`, `members.invite` (and therefore
  `members.joinWithToken`, which delegates to it) and `members.remove` now go
  through a single-flight registry: a second call with an identical payload
  while the first is still in flight — a double-tap on "Create group", or a
  caller invoking the method twice before the first future resolves — shares
  the first call's result instead of issuing a second request. Each of the
  four also sends a deterministic `Idempotency-Key` header, derived from the
  canonical request content so the same logical request always derives the
  same key, whatever order the payload was built in.

  **What this does not buy you:** the backend does not read
  `Idempotency-Key` yet — verified against `chat_engine`, whose only real
  server-side dedup is the `clientMessageId` body field on message sends. So
  this protects against duplication that originates in the client (a double
  tap, a local retry of a request that never left) and nothing more. A retry
  whose original request *did* reach the server and was applied before the
  client saw the failure — a timeout after the server committed, a connection
  dropped post-commit — will still duplicate server-side. This is not
  end-to-end idempotency; the header is forward-looking and starts paying off
  the day the backend honours it.
- **The resilience primitives are now public surface**, exported from the
  advanced barrel (`package:noma_chat/noma_chat_advanced.dart`):
  `computeBackoffMs`, `CircuitBreaker` / `CircuitState` and
  `CircuitBreakerRegistry` — the same pieces the SDK's own `RetryInterceptor`
  uses internally. If your app calls the backend outside the bundled HTTP
  client, reuse these instead of reimplementing a weaker backoff (the jitter
  is applied *before* the cap, so a retry never overshoots the maximum delay
  agreed with the server — an easy detail to get wrong by hand).

### Fixed

- Attachments that failed to download when the backend handed back a signed
  URL relative to the API base (`/v1/…` rather than an absolute `https://…`).
  The URL reached the HTTP layer verbatim and never resolved, so the download
  errored out. It is now resolved against the configured base URL first. The
  legacy header-only fallback, used when the backend returns no signed URL at
  all, is unchanged.
- Tapping an image bubble now opens the full-screen `ImageViewer` out of the
  box, wired to the same authenticated media loader the bubbles render
  through. `NomaChatView` previously forwarded `onTapImage` with no default
  at all, so opening the viewer was left to the host — and a host that
  handed `ImageViewer` only a URL got the broken-image fallback, because
  attachment downloads are Bearer-protected and `CachedNetworkImage` never
  sends that header. A host-supplied `onTapImage` still wins. **Hosts that
  build an `ImageViewer` themselves must pass `mediaLoader` and
  `attachmentRef`** (`adapter.defaultAttachmentMediaLoader`) or drop their
  override and take the default.
- Image bubbles no longer stretch to the full bubble width when the picture
  is taller than it is wide. The bubble now sizes itself to the shape the
  photo is actually painted at — its aspect ratio scaled down to fit the
  available width and `ChatTheme.imageMaxHeight` (250 by default) — instead
  of leaving a wide empty margin beside a portrait photo. The metadata row
  is aligned within the picture's width rather than the bubble's, with a
  floor so a very narrow image cannot squeeze the timestamp.
- **`MessageBubble` was unreachable with a screen reader beyond the plain
  text label** — TalkBack/VoiceOver could hear a message but had no way to
  open the long-press context menu (reply/react/forward/delete/pin/copy),
  retry a failed send, open an image/video/file attachment, or view a
  thread's replies: all of it lived inside the bubble's `excludeSemantics`
  subtree with no equivalent action on the outer node. The context menu and
  retry are now exposed as a `longPress` action and a `Retry` custom action
  on the bubble itself (same pattern as `MapButton`: keep `excludeSemantics`,
  re-declare the callback on the same node); opening an image/video/file
  attachment is the bubble's `tap` action. Reactions and the thread
  reply-count row keep their own un-excluded `Semantics` nodes instead of
  being swallowed by the bubble's — fixing this exposed a latent duplicate-
  announcement bug in `ReactionBar` (`"👍 1, 👍 1"`), also fixed alongside
  it. **Known gap**: audio play/pause stays unreachable — the toggle is
  private to `AudioBubble`, with no callback the bubble can surface as an
  action.
- **No screen-reader announcement when a new message arrives** while a chat
  is open — `MessageList` had no live region for message content, unlike
  `TypingIndicator`/`ConnectionBanner`, which already announce their own
  state changes. Incoming messages (not your own outgoing sends, and not
  loading older history via pagination) now update a `liveRegion` label with
  `"{sender}: {preview}"`, reusing the same WhatsApp-style preview text
  `RoomTile` shows for a room's last message.
- **Photos sent through the chat kept their full EXIF, including GPS
  coordinates and capture timestamp** — every recipient who downloaded the
  original file could see where and when it was taken. `pickImageFromCamera`
  / `pickImageFromGallery` / `pickMultipleMedia` now request
  `requestFullMetadata: false` from `image_picker`, which drops the
  GPS/EXIF block on iOS. **This is an iOS-only mitigation**:
  `image_picker`'s Android implementation copies EXIF from the source file
  unconditionally whenever it resizes (which every picker here triggers via
  `imageQuality: 85`), with no equivalent flag — closing that gap needs
  either an image-processing dependency this package doesn't carry, or a
  server-side strip on upload.

### Changed

- `CachePolicy` is no longer marked `@experimental`. It is a core, stable
  concept of the cache API, and the annotation forced an
  `// ignore: experimental_member_use` on every consumer that named a policy
  explicitly. Those ignores can go.

## 0.13.1

### Added

- `DeliveryReceiptClient` (`confirmMessageDelivered`) — a standalone,
  lightweight REST entry point that confirms a message as *delivered*
  without a full `NomaChatClient`. It takes a `ChatConfig`, an auth token,
  a room id and a message id and issues the delivery receipt over REST only
  (no WebSocket, cache, or DI), so it can run from a background push isolate.
- `AuthenticatedAttachmentLoader` — media bubbles, the media gallery, the
  full-screen viewer and the reply preview now load attachment bytes through
  the authenticated client instead of fetching the signed download URL
  directly.

### Fixed

- Image, audio and video attachments that silently failed to display when
  the signed download URL was fetched without the auth header (a `401` that
  degraded to a fallback). Media is now loaded via the authenticated client
  and renders reliably.
- `setActiveRoom`'s optimistic unread-count clear is deferred to a microtask
  so it never notifies the room list mid-build, which could otherwise surface
  as a build-phase error in a consumer that also listens to the room list.
- `exportChat` now includes the room title in the exported header.

### Changed

- The media gallery page picks up the chat theme (new AppBar/TabBar theme
  fields), and the message input can autofocus when a chat opens.

## 0.13.0

### Added

- **Structured logging pipeline.** `ChatLogTag`/`ChatLogLevel`/`ChatLogRecord`,
  pluggable `ChatLogSink` (`ConsoleChatLogSink`, `CallbackChatLogSink`,
  `BufferChatLogSink`, `MultiChatLogSink`) and `ChatLogExporter.exportToFile`
  for a one-tap shareable log file. `ChatConfig` gains `logSink`/`logLevel`/
  `logTags`/`logMessageContent` and a `logs` getter every subsystem logs
  through; the existing `logger` callback keeps working unchanged
  (`CallbackChatLogSink` bridges it when `logSink` is left `null`).
- `ChatMessage.attachmentId` — the stable id an attachment was uploaded
  under, propagated through the full send path (REST, cache, offline
  queue, WS-ack synthetic echo) so the recipient (and the sender, on
  re-open) can re-mint a fresh signed download URL instead of trusting a
  persisted one that may have expired.
- `SignedAttachmentUrlResolver` / `AttachmentUrlResolver` / `AttachmentRef`
  (`ui/services/attachment_url_resolver.dart`): re-mints signed URLs on
  expiry, wired as the default `ChatViewBuilders.attachmentUrlResolver` by
  `NomaChatView`. `AudioBubble`/`ImageBubble`/`VideoBubble` gain
  `attachmentRef`/`urlResolver` params and retry once via the resolver on
  a load error; `MessageBubble` gains `roomId`/`attachmentUrlResolver`.
- `AttachmentPickers` methods gain `onRejected` (`AttachmentRejection`,
  `AttachmentRejectReason`) — a policy violation or unreadable file is no
  longer a silent drop with just a `warn` log line.
- `ChatMessagesController.sendAttachment` now paints an optimistic bubble
  with live upload progress (`ChatUiAdapter.attachmentUploadProgressFor`)
  before the upload even starts, and leaves it visibly failed on error —
  parity with `sendVoice` instead of a blank bubble for the whole upload.
- `ChatUiLocalizations` gains `attachmentTooLarge` / `attachmentTypeNotAllowed`
  / `attachmentUnreadable`, translated for en/es/fr/de/it/pt (other locales
  fall back to English).
- `ChatMessagesController.sendAttachment`/`sendVoice` enter the offline retry
  queue on a connectivity-flavored upload failure instead of requiring a
  manual retry — `ChatClient.enqueueOfflineAttachment` (**Breaking**: new
  required interface method; `NomaChatClient` and `MockChatClient` both
  implement it, defaulting to a no-op when no offline queue is configured)
  queues the bytes + metadata as a `PendingSendAttachment` and replays the
  whole upload+send on reconnect, reconciling the optimistic bubble via the
  existing `onOfflineMessageSent` hook (same tempId).
- `ImageBubble`/`VideoBubble`/`FileBubble` gain `uploadProgress` and show a
  placeholder + upload-progress ring while non-null — parity with
  `AudioBubble.uploadProgress` for the attachment types that previously
  showed a broken-image icon (or nothing) for the whole upload.
  `ChatViewBuilders`/`MessageList` gain `attachmentUploadProgressFor`,
  defaulted by `NomaChatView` to `ChatUiAdapter.attachmentUploadProgressFor`
  so the ring shows up without the host wiring anything.
- `ChatRoomsController.open()` fast-fails with a typed `NetworkFailure`
  instead of waiting out the full `requestTimeout` when the client already
  knows the realtime channel is `disconnected`.
- `RoomListItem.lastSeen` — mirrors `ChatPresence.lastSeen`, kept in sync by
  `PresenceRegistry.update`/`bootstrap`. `ChatRoomAppBar` now renders a
  "last seen …" subtitle for an offline 1:1 peer instead of leaving the
  subtitle blank (`ChatUiLocalizations.lastSeenTemplate`, translated for
  en/es/fr/de/it/pt).
- **WS pong watchdog (dead-peer detection).** `WsTransport` now arms a
  timeout (`ChatConfig.wsPongTimeout`, default 10s) on every ping
  (`wsPingInterval`, default 30s) and forces a reconnect if the matching
  `pong` never arrives — previously a "zombie" socket (stuck half-open
  after a NAT timeout or mobile network handoff) never surfaced as an
  `onError`/`onDone` close and silently stopped delivering realtime
  events. Toggle with `wsPongWatchdogEnabled` (default `true`; verified
  safe — the backend always answers `ping` with `pong`). Reconnect backoff
  gains explicit tunables: `wsMaxReconnectDelay` (default 60s) and
  `wsReconnectJitterMs` (default 1000). `RealtimeTransport` gains
  `lastPongAge`.
- **`ChatConnectionState.authenticating`** — emitted between the socket
  opening and the server confirming `auth_ok` (previously indistinguishable
  from `connecting`). `isWorking` now includes it. **Breaking** for any
  exhaustive `switch` over the enum (see Changed below).
- **SDK-owned app lifecycle.** `ChatUiAdapter` (and `NomaChat.create` /
  `.fromConfig` / `.fromClient`) gain `manageAppLifecycle` (default `true`)
  and `lifecyclePolicy` (`ChatLifecyclePolicy.standard()` by default,
  `.pushOptimized()` also provided). When enabled, the adapter registers
  its own `WidgetsBindingObserver` and reconnects on resume / optionally
  disconnects after a grace period on pause — the host no longer needs a
  separate `AppLifecycleService` for chat. Registration is best-effort: it
  silently no-ops if no Flutter binding is available yet (e.g. a
  `ChatUiAdapter` built in a plain unit test), so it never crashes a host
  or a test that doesn't expect it.
- `ChatUiAdapter.resync()` — a full reconnect resync (room list
  `forceNetwork: true` + the foregrounded room's messages, backfilling
  anything missed while disconnected). A no-op until the adapter's first
  `loadRooms` has ever completed (`initializedNotifier`) — there is
  nothing to resync for a session that hasn't bootstrapped its room list
  yet, and firing early could race the host's own initial load. Triggered
  automatically on every fresh reconnect via `enableReconnectResync`
  (default `true`, adapter constructor param), debounced to at most once
  every 5 seconds so a flappy connection or a resume racing an in-flight
  reconnect can't double-resync. Centralized in the adapter's existing
  reconnect hook — no second "did we just reconnect" detection point.
- **Cache-first room list, with a self-healing background revalidation.**
  `RoomListController.mergeRooms(incoming, {required authoritative})` —
  upserts rows in place instead of clear-then-refill. A non-authoritative
  merge (a cache read, or a best-effort background pass) never drops a
  row it can't vouch for, so a partial/empty response can't blank the
  list; an authoritative merge (a full server snapshot) reconciles fully,
  same end state as `setRooms`, but without ever exposing listeners to an
  empty list in between. `RoomEnricher.loadAll` no longer hard-skips the
  network pass when realtime is already trusted — it now fires a
  background revalidation (`mergeRooms(authoritative: true)`) instead, so
  a stale or partial cache snapshot self-heals without the caller ever
  seeing an empty screen. Guarded per `type` so repeated `loadRooms()`
  calls (e.g. a screen re-opening) never fan out into overlapping network
  passes for the same request.
- `ChatRoomsController.open(roomId, {fetchIfMissing = true})` — opens a
  room by id, fetching its detail from the server when it isn't already
  known to `roomListController` (the deep-link case: a push notification
  or shared link pointing at a room the local list/cache hasn't synced
  yet). Returns a ready `ChatController` on success, or a typed
  `ChatFailure` the host can branch on instead of collapsing every case
  to "this chat doesn't exist": `NotFoundFailure` (really gone / not a
  member), `AuthFailure` / `ForbiddenFailure` (session/permission — NOT
  the same as not-found), or `NetworkFailure` / `TimeoutFailure`
  (transient — retry, don't tell the user the chat is gone).

### Fixed

- **Room list flicker between refreshes for duplicate DM rooms (root
  cause of part of S1).** The duplicate-DM tie-break used to fall back to
  "whichever room was already bound wins" when neither candidate had
  history (or both shared the exact same `lastMessageTime`) — but which
  one that was depended on which of the two async DM resolutions
  happened to complete first, which flips from refresh to refresh under
  normal scheduling. The tie-break is now a deterministic `roomId`
  comparison, independent of resolution order: the same pair of
  duplicate rooms always resolves to the same winner.
- A **non-authoritative (cache) pass of the duplicate-DM dedupe no
  longer evicts the losing room from the persistent cache** — it now
  only suppresses it from the visible list. Only an authoritative
  (network) pass persists the eviction (drops the cached room/detail and
  disposes its `ChatController`). Previously a cache-only guess could
  permanently destroy state a later authoritative pass might still have
  needed to reconcile correctly.
- `ChatUiAdapter.logs` now propagates `logLevel` and `logMessageContent` —
  both were silently clamped to `warn` + redacted regardless of what the
  host passed, so sub-manager `debug` lines (presence bootstrap, signed
  attachment re-mint, optimistic send) never reached a `logLevel: debug`
  host, and message text stayed redacted even with `logMessageContent:
  true`. `ChatUiAdapter` (and `NomaChat.create`/`fromConfig`/`fromClient`)
  now accept `logLevel`/`logMessageContent` and forward them, mirroring
  `ChatConfig.logs`.
- `PresenceRegistry.bootstrap` now applies every changed DM room via a
  single `RoomListController.mergeRooms` call instead of one `updateRoom`
  per room — a reconnect with N one-to-one rooms used to re-sort +
  re-index + notify the whole list N times (O(n² log n)); it's now one
  pass.
- `ChatView` no longer flashes the empty state for a room with no cached
  history: `ChatController.isLoadingInitial` (set while
  `ChatMessagesController.load`'s cache+network phases are in flight)
  now gates the empty state, matching the loading/empty split
  `RoomListView` already had. A brand-new draft DM (which never runs
  `load`) still renders its empty composer immediately.
- Opening a room now clears its room-list unread badge immediately,
  client-side (`ChatUiAdapter.setActiveRoom`), instead of waiting for
  `markAsRead`'s network round-trip — matches the bubble-level receipt
  behavior and avoids the badge visibly lagging on a slow connection.
- `ChatUiAdapter.dispose()` now disposes `blockedUsersListenable` — it was
  the only one of the adapter's four broadcast notifiers left out,
  leaking a `ChangeNotifier` and its listeners on every teardown.
- `RoomEnricher`'s background room-list revalidation (fired on every
  cache-fresh `loadRooms`, e.g. every screen reopen) is now debounced
  per `type` (default 5s, same window as reconnect-resync) — the
  in-flight guard alone only stopped *concurrent* passes, so a rapid
  open/close/reopen still re-ran the full network fetch + per-DM
  enrichment pass each time.
- **Offline queue self-duplication on a failed drain.** Replaying a queued
  `send`/`delete`/`addReaction`/`deleteReaction`/`pinMessage`/
  `unpinMessage`/`starMessage`/`unstarMessage` (and DM `sendDirectMessage`)
  from the drain loop went back through the same enqueue-on-failure
  decorator that queued it in the first place — a failed retry left BOTH
  a fresh copy (from the decorator) and the backoff-requeued original (from
  `OfflineQueue._drainWith`) in the queue. `OfflineQueuedMessagesApi`/
  `ContactsApi` gain `enqueueOnFailure` (default `true`; the drain replay
  path passes `false`), so `_drainWith`'s backoff is the single place that
  re-enqueues a retried op.
- `ChatRoomsController.open()` (deep-link fetch of a room not yet known
  locally) now fast-fails with a typed `NetworkFailure` when
  `ChatClient.connectionState` is already `disconnected`, instead of
  waiting out the full `requestTimeout` (default 30s) on a REST call very
  unlikely to succeed.
- `RoomListController.mergeRooms` no longer drops a locally created room
  it hasn't heard back about yet: an authoritative snapshot older than a
  room's own creation/edit timestamp can't vouch for its absence, so that
  row is now spared instead of evicted. An authoritative *empty* snapshot
  that does carry a capture time still clears every row that predates it,
  so a genuinely empty room list (no rooms left) no longer leaves a
  phantom row behind.
- `ChatUiAdapter.resync()` no longer silently drops a reconnect that
  lands while a previous resync is still in flight — it's coalesced into
  a follow-up pass instead of being swallowed by the debounce window. Its
  debounce seal is now per-attempt (a late failure can't clobber a newer
  attempt's seal) and is also reverted when the resync throws, not only
  when it returns a typed failure.
- The room list's per-row receipt tick and `ChatController`'s aggregated
  per-message receipt now both apply a monotonic rank guard
  (`sent < delivered < read`) — a `receipt_updated` event that arrives
  out of order (e.g. a queued `delivered` landing after a live `read` for
  the same message) can no longer regress the tick backwards.
- `PresenceRegistry.bootstrap` no longer lets a stale REST snapshot
  overwrite a live `PresenceChangedEvent` that arrived while the snapshot
  request was still in flight — the fresher live update wins regardless
  of which one resolves first.
- **Background room-list revalidation could wipe a healthy list on a
  transient blip (regression reopening S1).** `RoomEnricher.loadAll`'s
  self-healing background pass (see "Cache-first room list" above) reused
  the same fully-authoritative, row-dropping merge as an explicit
  pull-to-refresh — a single short/empty network response on an
  automatic, invisible background refresh was enough to drop real rooms
  from the list. `RoomListController.mergeRooms` gains an
  `allowRoomRemoval` path so the background pass can still reconcile
  DM-dedupe/kicked-room state authoritatively without ever being allowed
  to delete a row.
- **The reconnect-triggered `ChatUiAdapter.resync()` was still fully
  authoritative and reopened the same S1 regression the fix above closed
  for the background pass.** `resync()` goes through `loadRooms(forceNetwork:
  true)` — the very same foreground path an explicit pull-to-refresh uses —
  so the `allowRoomRemoval` guard above never reached it, and a reconnect is
  exactly the moment network is flakiest (the best-effort backend read
  behind `getUserRooms` can fail closed to a short/empty page). `loadAll` /
  `loadRooms` / `ChatRoomsController.load` now thread an explicit
  `allowRoomRemoval` parameter (independent of `forceNetwork`, which both
  callers set) down to the foreground network merge; `resync()` passes
  `false`, matching `_backgroundRevalidate`. Only an explicit, user-initiated
  pull-to-refresh (the default `allowRoomRemoval: true`) still prunes rooms
  the server no longer returns. Defense in depth: `RoomListController
  .mergeRooms` also hardened so a totally empty incoming snapshot is now
  *always* a no-op, even when `authoritative` and `snapshotAt` are set — a
  full wipe is indistinguishable, over the wire, from the same fail-closed
  blip, and is never how a genuine room removal actually arrives (those
  come one at a time, via realtime events or a partial authoritative
  snapshot).
- **Offline attachment queue had no size cap and re-encoded the whole
  queue to base64 on every mutation.** `enqueueOfflineAttachment` now
  rejects an attachment over `CacheConfig.offlineQueueMaxAttachmentBytes`
  (default 10 MB) via the existing `onOperationDropped` callback
  (`'attachment_too_large'`) instead of queueing it and running out of
  memory later, and `PendingSendAttachment`'s base64 payload is memoized
  per byte buffer so persisting the queue no longer re-encodes every
  pending attachment's bytes on each `enqueue()`/drain pass.
- **A resumed app could reconnect onto a zombie WebSocket and never
  recover realtime (regression reopening S3/S5).** `WsTransport.connect()`
  is a no-op while the transport already believes it's `connected` — but
  after an OS-suspended socket dies without a proper close, that belief is
  wrong, so app resume silently did nothing. Transports gain
  `verifyLiveness()`: on resume, a connected `WsTransport` sends an
  immediate ping and arms the existing pong watchdog instead of trusting
  its own state; a timeout forces the real reconnect (`Disconnected` +
  `Connected` events), which in turn re-triggers presence bootstrap and
  `resync()`. `AutoFailoverTransport.connect()` now probes the primary's
  liveness instead of unconditionally resetting `_primaryHasConnected`
  when the primary is already connected, fixing a related failover
  regression where a resume could delay promoting the SSE/polling
  fallback after a subsequent blip.

### Changed

- `ChatUiAdapter.disconnect()` gains `{bool clearRooms = false}`. The new
  default is cache-first and resumable: the room list, the currently
  foregrounded room's `ChatController` and the DM contact↔room binding all
  survive a `disconnect()` — the list never flashes empty across a
  background/reconnect cycle, and a subsequent `resync()` can backfill the
  open conversation. Pass `clearRooms: true` for the previous eager-wipe
  behavior (also what `signOut()` / `dispose()` use internally — logout is
  unaffected).
- `ChatConnectionState` adds `authenticating` (see Added above) — any
  exhaustive `switch` over the enum in host code must add a case for it
  (the SDK's own `ConnectionBanner` and `AutoFailoverTransport` already do,
  mapping it to the same treatment as `connecting`).

### Notes

- `enableReconnectCatchUp` (`NomaChatClient`, unread catch-up on reconnect,
  default `false`, not activated by WB) is a pre-existing, distinct
  reconnect mechanism one layer below the new `ChatUiAdapter.resync()` /
  `enableReconnectResync`. Left untouched this release; the two can overlap
  if a consumer enables both — not merged here.
- `logMessageContent` defaults to `false`. Message/caption text passed to
  `ChatLogger.content()` is redacted unless explicitly enabled — intended
  for a temporary diagnostics build, not for production.
- `ChatMessage.attachmentId` closing S6 (audio/photo URL re-mint) for a
  **received** message additionally requires the backend to echo
  `attachmentId` on reads (`getRoomMessages`, `new_message`,
  `sendRoomMessage`) and to persist the stable slot URL rather than a
  TTL-bound signed one — see the `chat_engine` 0.13.0-train changes. The
  SDK falls back to parsing an id out of the URL (`attachmentIdFromUrl`)
  when the backend hasn't rolled the field out yet.

## 0.12.1 - 2026-07-17

### Removed

- Internal audit notes are no longer part of the repository, and maintainer
  docs (`ISSUES.md`, `CONVENTIONS.md`) are excluded from the published
  package tarball.

## 0.12.0 - 2026-07-17

### Fixed

- **DM typing indicators now work over an active WebSocket connection.**
  `contacts.sendTyping()` used to emit a WS `typing` frame addressed by
  `contactId` while realtime was connected — but the backend's `typing`
  frame is room-scoped (it requires `roomId` and answers
  `{"error":"typing","reason":"missing_roomId"}`), so the peer never saw
  the indicator; only the REST fallback used when realtime was down
  actually worked. DM typing is now ALWAYS routed through
  `POST /contacts/{id}/activity`, which the peer receives as a
  `DmActivityEvent`. The dead `sendDmTyping` WS path was removed from the
  internal transport interface and every implementation. Room typing
  (`messages.sendTyping()`) is unaffected.
- **WS close code `4006` (`transport_disabled`) is now handled.** The
  server emits it when the WebSocket transport is disabled at runtime;
  the SDK used to treat it as a generic drop and reconnect in a loop
  against a server that closes every socket the same way. On `4006` the
  WS transport now suspends its reconnect loop and marks itself
  unavailable for the session, and `RealtimeMode.auto` promotes the
  SSE/polling fallback immediately (even when WS never connected once).
  The cached token is untouched — this is a transport condition, not an
  auth one. A later `connect()` (e.g. after re-login or app restart)
  tries WS again.
- `nomaChatSdkVersion` (the `X-Noma-Chat-Version` / `User-Agent` constant)
  was left at `0.10.1` by the `0.11.0` release; synced to the package
  version, un-breaking the `version_sync_test` gate.

### Changed

- **`send()` / `sendDirectMessage()` results are provisional under the
  backend's `ack_mode = async` (an opt-in deployment mode; the backend
  default is `sync`).** The `201` echo is built
  before persistence: its `id` does NOT match the stored message. The SDK
  now detects that case and returns the message with the new
  `ChatMessage.isProvisional` flag set and `clientMessageId` stamped
  (the authoritative `new_message` event carries the same key). All SDK
  stores reconcile by `clientMessageId`: `ChatController` replaces the
  optimistic/pending row with the event message (no duplicates, no row
  stranded under the provisional id), the message cache never persists a
  provisional echo, and the bundled UI keeps the bubble in the *sending*
  state until the event confirms it.
  **Migration note for consumers:** do not use the `id` returned by
  `send()` / `sendDirectMessage()` for immediate follow-ups (react /
  edit / delete / pin). Check `isProvisional`; when `true`, wait for the
  `NewMessageEvent` whose `clientMessageId` matches and use that
  message's `id`. `sendViaWs()`'s synthetic ack message is now also
  flagged `isProvisional` and carries its `clientMessageId`.
- **`contacts.sendDirectMessage()` now always sends a `clientMessageId`**
  (auto-generated when omitted — a new optional parameter lets callers
  supply their own), so DM sends are idempotent under retries and
  offline-queue drains, matching `messages.send()`.

### Docs

- Bundled OpenAPI contract (`doc/chat-api-openapi.yml`) resynced with the
  backend: room preferences consolidated under
  `PATCH /rooms/{id}/preferences` (the room-level `/hidden`, `/mute` and
  `/pin` endpoints no longer exist — message pin/unpin endpoints are
  untouched), `DELETE /users/me` self-deletion alias, machine-readable
  `error` tokens on error bodies, async-ACK provisional echo semantics,
  WS close codes `4006`/`4007`, and `roomId` on `/messages/search` now
  documented as optional (global search across the caller's rooms
  confirmed — closes the spec-drift item in `ISSUES.md`; the "no room id
  on hits" caveat remains).
- README installation snippet bumped to `noma_chat: ^0.11.0`.

## 0.11.0 - 2026-07-06

### Removed

- **BREAKING: Certificate pinning removed.** `ChatConfig.certificatePins`
  (and the corresponding `certificatePins` parameter on `NomaChat.create`)
  no longer exists, along with the internal pinning interceptor, its
  platform adapters and the public `CertificatePinningException` type. The
  SDK now relies solely on the platform's standard TLS validation against
  the operating system's CA trust store. Consumers that were passing
  `certificatePins` must delete the argument; those that need pinning should
  enforce it outside the SDK (an OS-level network security config, HSTS +
  Certificate Transparency logs at the deployment layer, or a custom `Dio`
  HTTP adapter). the internal audit item ALTA-001 is closed as
  RESOLVED-BY-REMOVAL.
- **`package:crypto` dependency.** Its only consumer was the pinning
  interceptor removed above; no other code in the SDK used it.

### Fixed

- **Cache invalidation race on message writes (`send`/`update`/`delete`/
  `markRoomAsRead`).** `CachedMessagesApi` now invalidates the `messages:*`
  and `rooms:all`/`rooms:unread` TTL keys **before** writing the mutation to
  the local cache, not after. Previously a concurrent `cacheFirst` reader
  landing between the cache write and the invalidation call could observe a
  "still fresh" TTL paired with stale data. Added `CacheManager.invalidateKeys`,
  a batch primitive that invalidates several keys as one step instead of
  several separate `invalidate()` calls.
- **`rooms.updateConfig()` no longer leaves a stale avatar/name in the
  cached room list.** The cached `UnreadRoom` entry for the room is now
  patched in place with the new `name`/`avatarUrl` (or cleared, for
  `clearAvatar: true`) at the same time the `roomDetail`/`rooms:all`/
  `rooms:unread` TTL keys are invalidated — previously the room list would
  keep rendering the old avatar/name from the cached `UnreadRoom` until the
  next full rooms refetch replaced it.
- **`HiveChatDatasource` now logs the concrete reason a cached record was
  discarded** (missing field, invalid timestamp, etc.) for every skipped
  entry, not just the first one in the batch. The aggregated `"Skipped N
  corrupted records"` warning is still emitted alongside the per-record
  detail.
- **Example app: `enableHttpLog` is now gated on `kDebugMode`** instead of
  hardcoded to `true`, so a release build of the example never ships with
  HTTP body logging on.
- **Offline queue no longer risks a duplicate send on an ambiguous-phase
  timeout.** The pre-response gate now explicitly documents (and tests)
  that `TimeoutKind.unknown` — the defensive default when the timeout
  phase can't be determined — is treated like a `receive` timeout for
  non-idempotent operations, not like a pre-response one. `send()` was
  already correct in practice; this closes the gap between the intended
  contract and its test coverage.
- **`NomaChatClient.connect()` is now safe to call twice in quick
  succession.** A repeated `connect()` fired before the first call
  resolves now awaits the same in-flight `Future` instead of racing it —
  previously both calls could observe the same non-null internal event
  subscription, cancel it twice, and reassign it out of order, leaking a
  transport subscription.
- **Offline queue drain no longer spins through the whole queue when the
  front operation is still in backoff.** Previously a `drain()` call
  would re-queue every remaining still-backing-off operation one by one
  (O(queue length) work for no effect); it now stops at the first
  operation whose `nextRetryAt` hasn't elapsed yet and leaves the rest of
  the queue untouched and in order.
- **`RestClient.post()` validates the response body type** like `get()`
  already did: a 2xx body that is not a JSON object (e.g. an array) now
  surfaces as a typed `ChatApiException` instead of an unhandled cast
  error.
- **Rate-limit back-off is clamped to `[1 s, 5 min]`.** A `Retry-After` /
  `X-RateLimit-Reset` of zero or negative seconds (server clock skew) no
  longer produces an immediate-retry stampede, and an absurdly large value
  no longer stalls the client for hours.
- **WebSocket close codes 4003/4004 now explicitly close the client-side
  sink** before a reconnect is scheduled, releasing the half-closed socket
  instead of leaking it alongside the fresh connection.
- **`WsTransport.dispose()` latches a disposed flag synchronously** and
  every emit checks it, so late callbacks from in-flight reconnect timers
  or channel teardown can no longer race the controllers being closed.

### Added

- **`ChatMessage.silentlyDropped`.** `contacts.sendDirectMessage()` returns
  success with a synthesized `ReceiptStatus.sent` message when the backend
  answers `204 No Content` (recipient has blocked the sender) — this new
  field is `true` on that synthesized message so callers can distinguish
  "accepted but never delivered" from a normal send instead of showing
  "sent" with no further explanation. Persisted through the local cache
  round-trip. Additive, defaults to `false` everywhere else.
- **`addReaction`, `pinMessage`, `unpinMessage`, `starMessage` and
  `unstarMessage` now retry through the offline queue** on a
  `NetworkFailure` or pre-response `TimeoutFailure`, matching the
  existing `send`/`delete` behaviour. Previously a network drop while
  reacting to, pinning, or starring a message failed silently with no
  retry once connectivity returned.
- **`NomaChatClient.onOperationDropped`.** Fires when the offline queue
  gives up on a pending operation (queue full, TTL expired, or max
  retries exhausted). Defaults to recording the operation id, queryable
  via the new `isOperationPermanentlyFailed(id)` /
  `permanentlyFailedOperationIds` so a host app can show a "delivery
  failed" indicator without wiring anything itself; still fully
  overridable with a custom closure.
- **`ws_auth_timeout` metric + structured `warn` log** when the WebSocket
  auth handshake exceeds `ChatConfig.authTimeout`, tagged with the
  configured timeout and the current reconnect attempt.
- **Token-refresh circuit breaker in `BearerAuthInterceptor`.** Consecutive
  401s that survive a token refresh are counted (metric
  `auth_refresh_retry_failure`); after 3 of them further 401s skip the
  refresh entirely (metric `auth_circuit_open`) and go straight to
  `onAuthFailure`, so a revoked account cannot hammer the token endpoint.
  A successful retry — or `invalidateCache()` with fresh credentials —
  closes the circuit. `ChatConfig.metricCallback` is now forwarded to the
  bearer interceptor.
- **`NomaChat.fromConfig({required config, required currentUser, ...})`.**
  New factory that builds the SDK from a pre-assembled `ChatConfig` without
  re-stating `baseUrl`/`realtimeUrl`/`tokenProvider`. `NomaChat.create` and
  `fromClient` are unchanged.
- **UI customization hooks.** `ChatViewBuilders.batchUserFetcher` (batch user
  resolution, removes the reaction-sheet N+1), `ChatViewBuilders.statusIconBuilder`
  (override the delivery-status tick), `RoomListView.selectedRoomId` /
  `onSelectionChanged` (master-detail selection), `AttachmentSheetOption.previewBuilder`,
  `AudioBubble.initialPlaybackSpeed` / `onPlaybackSpeedChanged` (persist playback
  speed across sessions), `ForwardedBubble.sourceTimestamp`, and
  `GroupMembersView.pageSize` (paginated member lists).
- **Platform-support gates.** `PlatformSupport.supportsVoiceRecording`,
  `supportsFilePicker` and `supportsLocalStorage`, plus
  `StartRecordingResult.unsupported` and `VoiceRecorderGesture.onUnsupported` —
  voice recording on Web now reports "unsupported" instead of a misleading
  "permission denied".
- **5 new locales** (`sv`, `no`, `da`, `pl`, `cs`; 12 total) and
  `ChatUiLocalizations.loadMore`.
- **`LinkPreviewFetcher.cancel(url)` / `cancelAll()`.** Aborts the in-flight
  link-preview HTTP request (via Dio `CancelToken`) on URL change, dismiss or
  dispose, releasing the socket promptly.
- **`example/android` target** generated so the sample app builds on Android.

### Docs

- **`TELEMETRY.md`** (new). Full metric-by-metric reference for every event
  emitted through `ChatConfig.metricCallback` / `CacheManager.onMetric` /
  `HiveChatDatasource.onMetric` — name, fields, and firing condition for
  cache, offline-queue, HTTP, auth and WebSocket metrics. Referenced by
  `CONVENTIONS.md` §10.3 and `SECURITY.md`, which previously pointed at a
  file that did not exist.
- **`ISSUES.md`** (new). Tracks the golden-test `sqflite` skip workaround,
  the `golden_toolkit` → `alchemist` migration plan (not executed — needs a
  session with `pubspec.yaml` in scope), the `/messages/search` spec/dartdoc
  mismatch on global search, and the non-customizable `noma_chat_otel` span
  naming.
- **`doc/DEVELOPER_GUIDE.md`** gained worked examples for scheduled messages
  (`schedule`/`listScheduled`/`cancelScheduled`), an end-to-end
  `actAsUserId` delegation walkthrough, `ForwardInfo` (plus a no-E2EE note
  on forwarding), room- vs global-scoped message search,
  `AttachmentPolicy` MIME/size filtering, three `RoomTitleResolver` use
  cases (nickname book, role-based titles, pre-hydration fallback), and a
  new "Observability" section covering `ChatConfig.metricCallback` and the
  `noma_chat_otel` companion package.
- **21 stale golden baselines regenerated** (`test/golden/goldens/*.png`,
  `bubbles_dark_test.dart` + `bubbles_light_test.dart` +
  `message_status_test.dart`) via `flutter test --update-goldens
  test/golden/` — no widget code changed; the prior baselines predated
  unrelated visual changes elsewhere in this audit-remediation pass.
  `TESTING.md`'s skipped-golden count corrected from a stale "4" to the
  actual "2" (`ImageBubble` only; `LinkPreviewBubble` was never skipped,
  just rendered without its optional OG image).

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
