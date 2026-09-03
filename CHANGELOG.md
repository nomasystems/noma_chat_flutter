# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/). From `1.0.0`
onwards, breaking changes require a **major version bump**.

## 0.32.2 - 2026-09-03

A WebSocket connection attempt is now bounded end to end, and tearing the
transport down no longer waits on a handshake that will never answer.

### Fixed

- **`connect()` can no longer stall forever on a socket that never finishes opening.** `WsTransport` awaited `WebSocketChannel.ready` with no bound. A socket that opens at TCP level but never completes its upgrade — a captive portal, a proxy that blackholes the handshake — left that future pending indefinitely, and the transport latched at `connecting`, the one state where every later `connect()` is guarded out as a no-op. The wait is now bounded by `authTimeout`, so the attempt fails, surfaces a `ChatTimeoutException`, and the normal reconnect path takes over.
- **`disconnect()` / `dispose()` abort the auth handshake in flight instead of leaving its timer armed.** Teardown cancelled the reconnect and ping timers but not the handshake's `authTimeout` timer, so a transport disposed mid-handshake kept a timer alive for up to ten seconds and only then resolved the pending `connect()`. Teardown now cancels that timer and unblocks the caller immediately, and the failure of the socket it abandoned is no longer reported as an application error — the caller already drove the transport to its final state.

### Changed

- **The test suite is bounded: no test may run longer than two minutes.** `dart_test.yaml` sets a global `timeout`, so a test waiting on something that never arrives fails on its own instead of stalling the run with no output. Alongside it, the WebSocket transport tests no longer depend on real-time waits: the fake channel used to hand `auth_ok` to a broadcast stream before the transport had subscribed, which dropped the frame and made every one of those tests sit out the full ten-second auth timeout. The fake now queues frames delivered before there is a listener, cutting that file from two and a half minutes to five seconds.

## 0.32.1 - 2026-09-03

A chat room could stop answering gestures after a long press on a message.

### Fixed

- **The chat room no longer freezes after a long press on a message.** On iOS the composer used the framework default selection toolbar, which is the platform's own `SystemContextMenu`. That menu can only be displayed while a text input connection is live, and asserts from its `build` once the connection is gone with the menu still mounted — which is exactly what opening the long-press sheet over the focused composer does. The assertion then fired on every frame, so the room kept painting but answered no touch at all. The composer and the selectable body of a text bubble now build `AdaptiveTextSelectionToolbar` instead, which carries the same buttons and needs no connection, and opening the message menu dismisses any selection toolbar still on screen.
- **An attachment upload the server refuses for its size (413) now maps to its own failure instead of a generic server error.** The client-side `AttachmentPolicy` pre-flight check already screens uploads before the bytes leave the device, but the two can disagree — a HEIC that grows on its way to JPEG, a re-encode step run between pick and upload — and a 413 used to fall through to the same catch-all `ChatApiException`/`ServerFailure` as any other unmapped status code. `RestClient` now maps a 413 to `ChatAttachmentTooLargeException`, and `exception_mapper` to a new `AttachmentTooLargeFailure` (`ChatErrorTokens.attachmentTooLarge`), so a host app can show the exact same "attachment too large" message the pre-flight rejection already uses instead of a generic upload failure.
- **Every other SDK text field is sealed against the same iOS system context menu freeze, not only the composer and a text bubble.** The forward-to and in-room search fields, the report-message reason field, the attachment caption, and the group/profile name, description and email fields now all build `AdaptiveTextSelectionToolbar` too, through the same shared helper. A new test walks every one of them and asserts none ever builds `SystemContextMenu`.

## 0.32.0 - 2026-09-03

Attachments and voice notes gain a caption and can answer a message, with a
new review step between the picker and the send. Message bubbles announce
their timestamp and delivery state to screen readers. Unread counters no
longer count system messages, and two logging/UI leaks that reached a
release build are closed.

### Added

- **Message bubble accessibility label now includes the timestamp and always announces the delivery state.** The semantic label, read by screen readers, now matches what the screen paints: `You: <text>, HH:mm, Sent|Delivered|Read`. For incoming messages, the sender prefix and timestamp are always present. Deleted messages announce no timestamp or state.

- **`FileBubble` paints its caption.** A document sent with a caption
  (`sendAttachment(caption: ...)`) already carried it as the message text,
  but only `ImageBubble`/`VideoBubble` painted it — a captioned PDF or ZIP
  showed the file name and nothing else. `FileBubble` gained the same
  `caption` field, painted below the file name.

- **An attachment can carry a caption and answer a message.**
  `ChatMessagesController.sendAttachment` takes `caption` (published as the
  message text, painted under the media by `ImageBubble` / `VideoBubble`)
  and `referencedMessageId`; `sendVoice` takes `referencedMessageId`.
  `VoiceMessageData` carries the quote it was recorded under
  (`referencedMessageId`, `asReplyTo`). A quoted attachment paints the same
  quote strip a text reply does, above the media, and `MessageBubble`
  announces it in the bubble's accessibility label. Thread replies (plain
  text carrying `referencedMessageId`) and reactions are unaffected.

- **`AttachmentReviewPage` — the step between the picker and the send.**
  What was chosen at full size, a caption field under it, and two ways out:
  back sends nothing, send returns every attachment with its own caption
  (`ReviewedAttachment`). Multi-selection is paged, one caption per
  attachment. `AttachmentCaptionField` is exported so a host can reuse the
  same field. `CameraCaptureReview` gains that field too (`allowCaption`,
  on by default). New localized string `attachmentCaptionHint` in the seven
  bundled locales; new UI-test identifiers
  `chat_attachment_review_media` / `_back` / `_caption` / `_send` /
  `_thumb_<n>`.

### Changed

- **Breaking — `CameraCapturePage.show` resolves to a
  `CameraCaptureSubmission`** (the `capture` plus the `caption` typed on the
  review step) instead of a bare `CameraCaptureResult`, and
  `CameraCaptureReview.onSend` is a `ValueChanged<String?>` instead of a
  `VoidCallback`. Hosts that pushed the capture screen themselves read
  `submission.capture` where they used to read the result.

- **`NomaChatView` reviews before it sends.** Its gallery and file rows now
  open `AttachmentReviewPage` between the picker and the upload, and every
  non-text path it drives (gallery, file, camera, voice note) carries the
  composer's pending reply and closes the reply preview once the send is
  away — and only if the user has not started answering something else in
  the meantime.

### Fixed

- **System messages (plan lifecycle notices, membership changes, …) no
  longer count as unread.** They still render in the room like any other
  message, but `ChatEventRouter` stops bumping the per-room unread counter
  and mention badge for them, and `resolveUnreadBoundary` excludes them
  both when counting how many messages sit below the "N new messages"
  divider and when choosing where to anchor it — a room whose only unseen
  activity is system messages now shows no divider at all. `RoomEnricher`
  applies the same rule the first time a device learns about a room from an
  incoming message: a system message never seeds the fresh row with an
  unread badge. The Messaggi tab badge and the row badge, both derived from
  the per-room counter, follow automatically. This assumes the server-side
  unread count applies the same exclusion; see the developer guide for the
  contract. A server that now labels these messages with `messageType:
  "system"` maps to `MessageType.regular` in `MessageMapper` — it no longer
  logs a spurious "unknown messageType" warning for every one of them;
  `ChatMessage.isSystem` (from `metadata.system`) remains the source of
  truth for how a message renders.

- **Every non-text send ignored the pending reply and left it in the
  composer.** Sending a photo, a video, a document, a location or a voice
  note while the reply preview was open published it with no quote and left
  the preview standing, so the *next* text message went out quoting a
  message the user had already answered. The whole send path now carries
  the quote, and the composer's reply preview closes with the send it
  belonged to. This also covers the offline-queue replay: an attachment or
  voice note that fails to upload and is later replayed automatically on
  reconnect now keeps its quote too — `ChatClient.enqueueOfflineAttachment`
  takes `referencedMessageId` and the queued operation carries it through
  the replay, the same as a manual `retrySend` on the failed bubble already
  did.

- **`uiDebugLog` and `ConsoleChatLogSink` printed to the release console.**
  Both routed through `debugPrint`, which Flutter documents as logging to
  console even in release builds — the opposite of what their own
  docstrings claimed. Message metadata and attachment URLs from ~39 call
  sites across the UI layer were reaching the device's system log on a
  release build. Both now gate the call behind `kDebugMode` themselves, so
  nothing is printed outside a debug build; `ChatConfig`'s default sink
  selection was already `kDebugMode`-gated and needed no change.

- **The search clear button stays in the tree when the field is empty.**
  `MessageSearchView` and `RoomSearchBar` hid the clear `IconButton` with
  `Visibility(maintainState: true)`, which keeps it mounted (offstage)
  rather than removing it, so a driver's dump still lists
  `chat_search_clear` / `room_search_clear` with an empty field. Both now
  build `const SizedBox.shrink()` while the field is empty and only build
  the `Semantics(identifier: ..., button: true, child: IconButton(...))`
  once there is text to clear, so the control unmounts for real. The
  `Tooltip` that used to carry the accessible label is gone with it — the
  label now lives on the `Semantics` node, which the a11y sweep already
  required — so there is no `TooltipState` left to dispose from inside its
  own `onPressed`. The pattern (`isEmpty ? SizedBox.shrink() :
  Semantics(...)`) is the one to repeat anywhere else in the host app that
  shows the same "X" affordance.

## 0.31.0 - 2026-09-01

Round 6 of QA on the host app, chat side. Nine defects landed here rather than
in the app around them, plus two more whose report pointed at the app but whose
root turned out to live in this package, plus the two UX changes that belonged
to the chat surfaces. Two of the fixes in this round are for regressions that
the round's own earlier fixes introduced; both are described below, because a
consumer upgrading from `0.30.0` never saw them and should not have to wonder.

### Fixed

- **The reaction row can be used on a tall bubble** (`D99`). With a bubble of
  roughly 376 pt or more the floating row was laid out inside the status bar,
  where the system swallows every tap: all seven buttons were unreachable, so
  reacting was impossible. The row is now placed against the safe area, and the
  anchor test asserts a bubble top that fails if the inset is reverted — the
  previous assertion passed with the broken value.
- **The reaction row no longer lands on top of the long-press menu** (`D124`).
  It shared the anchoring maths with `D99`, so both are fixed together, and the
  row is re-placed when the viewport changes instead of once.
- **Sending a message stops marking every own bubble as read** (`D125`). The
  echo of the sender's own read cursor was applied to the whole room instead of
  the message it names, so the room turned green on send and the conversation
  list agreed with it. The self-conversation ("message yourself") keeps its own
  double check, which is what the first version of this fix had broken.
- **A 1:1 whose peer left is not mistaken for a self-conversation** (`D125`).
  When a peer signs out or deletes their account the backend drops them from the
  room lists, leaving `memberCount == 1`; the exemption above then read that as
  the user's own room and stopped filtering the echo, which reproduced the very
  symptom it was written to fix. The exemption now also requires the absence of
  a remembered peer.
- **A group the user is alone in is not mistaken for a self-conversation
  either** (`D125`). Room facts are re-pinned when the detail arrives, but the
  group-ness was not, so a freshly created plan room opened cold — by deep link
  or push, before its detail landed — reported `isGroup: false` and took the
  same wrong branch.
- **Ordinary words are no longer painted as links** (`D115`). Any word with a
  dot and more than eight characters was treated as a URL and opened the
  browser. The detector now carries a table of cases that must and must not
  match, with the reported ones inside it.
- **A control no longer tears itself down under its own press** (`D132`). An
  icon button with a tooltip that unmounts inside its own press notification
  drags its `RawTooltipState` with it; that state registers a global pointer
  route in `initState` and only removes it in `dispose`, so while the element is
  deactivated-but-not-disposed **every pointer event in the whole app** enters
  its handler and throws. The result was a hundred-line log and an unresponsive
  bottom bar. Fixed in both search fields, in the group info and group creation
  pages, in the member lists, in starred messages and in blocked contacts: the
  rows hide instead of dropping.
- **The full emoji picker uses the sheet surface** (`D138`) instead of a colour
  of its own, in both brightnesses.
- **Several surfaces are legible on a dark host** (`D144`). The message info
  sheet, the "you blocked someone in this chat" strip (3.07:1 over the
  background WB paints in dark, now 10.93:1), the shared-media, documents and
  links tabs, the member role labels and the pinned-message bar all nailed their
  colours to fixed greys. They now come from the ambient `ColorScheme`, and each
  one has an assertion that fails if its line is reverted.
- **The delivery legend agrees with the icon it documents** (`D144`). The legend
  had been moved to theme colours and the bubble's own status icon had not, so
  the two drifted apart.
- **A session teardown is no longer read as an eviction** (`D119`). Tearing the
  session down empties the room list, and the view took the room's
  disappearance for "you were removed", firing the leave path and leaving an
  orphan dialog over the login screen. The adapter now declares the teardown
  explicitly — a signal, not a guess at cardinality, so being evicted from the
  only room you had still behaves correctly — and the view stops rebuilding
  against a disposed controller.

### Added

- **Semantic identifiers across the composer and the bubbles** (`D152`). The
  camera and voice buttons of the composer had none, and neither did a dozen of
  their siblings. Identifiers are published for the composer row, the voice
  overlay, quick replies, reaction removal, the attachment upload controls and
  the media bubbles, and they are documented under **Test identifiers**.
- **Accessibility gates** under `test/a11y/`: an identifier sweep that fails on
  an interactive control without one, an ambient-contrast sweep that fails on a
  hard-coded text colour, and a navigation-surface sweep. They exist so the next
  round finds the eighteenth site rather than the seventeenth.
- **Clearer empty states in the chat surfaces** (`U152`, `U154`). Searching
  inside a room with a single character now says so instead of reporting no
  results, and the shared-files tabs explain what will appear there.
- **The keyboard sits over the content screens** instead of shrinking them, on
  the package screens with no field in the lower half. The chat room keeps its
  current behaviour: its composer *is* a field in the lower half, and shrinking
  is what keeps it visible. `doc/DEVELOPER_GUIDE.md` records which embeddable
  views expect the host to own that decision.

### Changed

- **The member role badge follows the ambient theme.** Owner reads
  `ColorScheme.tertiary` and admin `ColorScheme.primary`, where both were a
  hard-coded orange and blue that belonged to nobody's palette. Visible change
  for any consumer of `MemberListView`.
- `MemberListView` becomes a `StatefulWidget` so it can keep the slot history
  its rows need. Its constructor and parameters are unchanged.
- `UrlDetector.extraTlds` matches case-insensitively, as its documentation
  already claimed; `add('Barcelona')` used to fail silently.

### Known issues

- **The attach and send buttons of the composer have been reported as
  unresponsive inside a room** (`D153`), and the mechanism is not demonstrated.
  Nothing was changed on a guess: a plausible fix with no mechanism behind it is
  worse than a known issue.
- A read receipt that was granted under an exemption and then had the exemption
  withdrawn keeps its tick until the controller is discarded. The window is
  narrow and one of its two paths predates this round.

## 0.30.0 - 2026-08-31

Round 5 of QA on the host app, chat side: `D61`, `D78`, `D79`, `D89`, `D90`,
`D91`, `U88`, `U89`, `U90` and `U94`. Every one of them belonged in this
package rather than in the app around it, plus one thing the fixes turned up
on the way.

### Fixed

- **Deleting a message no longer un-deletes it half a second later** (`D78`).
  The `message_deleted` event paints the tombstone and then re-fetches the
  message so a moderator's `adminDeleted` flag can reach the client. There is
  no server-side unit GET, so that fetch resolves against the id-indexed local
  cache — which still held the message ALIVE, because the DELETE response had
  not purged it yet. The live row was written back over the tombstone and
  stamped "edited" on a message nobody had edited, and the same row went into
  the cache, so it survived a re-open. The refresh now knows which event it is
  reacting to: on the delete path a row that comes back alive is stale by
  definition and is dropped, while a row confirming the deletion is still
  applied (that is the one carrying `adminDeleted`). The cache purge also runs
  before the refresh rather than after it. Every participant was affected, not
  just the person who deleted.

  The edit path shared the same helper and the same stale read: a
  `message_updated` event without an inline row re-fetched the PRE-edit text
  and tagged it "edited". A row identical to the one already on screen is now
  dropped there too.

  A deleted bubble also reads to a screen reader what it actually paints —
  "You deleted this message", "Deleted by admin" — instead of the
  sender-agnostic "This message was deleted".

- **Sending from halfway up the history takes you back to your message**
  (`D79`). WhatsApp behaviour, and it sits at the list rather than on the
  composer's send button, so it covers text, attachments, camera photos,
  voice notes, locations and forwards at once, since they all land in the
  same list. An incoming message still does not steal the viewport, loading
  older history does not move it, and an anchored open (a search hit, a
  tapped quote) keeps the scroll position it asked for.

- **The "back to the bottom" button can appear in short rooms, and its badge
  counts** (`D79`). The button was gated on scrolling more than a fixed
  200 px, so a room whose entire history measured 192 px could never show it;
  the threshold is now the fixed one OR a share of the scrollable extent, with
  a small floor so a stray drag does not flash it. Its unread badge — a
  parameter the button has always accepted and never been given — is finally
  wired, and wired to something that moves: the messages that have landed
  BELOW the viewport since the user was last at the bottom, not the open-time
  snapshot the "{n} new messages" divider freezes. That snapshot is 0 in
  precisely the case the button exists for, someone reading history while the
  conversation carries on underneath them. Reaching the newest row clears the
  count and spends the open-time one, so scrolling back up does not resurrect
  a number about messages already read.

- **A reply's quote says who it quotes, and jumping to the original works**
  (`D91`). The quote strip took its author name from the resolver that returns
  null for the local user on purpose (your own bubble must not be labelled
  with your name), so a reply to yourself was unattributed; the composer's
  strip was never given a name at all, in any room or language. Both now name
  the quoted author, with the localised "You" for your own messages and no
  name for a blocked one. Tapping the quote used to do nothing when the target
  sat outside the viewport, and nothing visible when it was already on screen;
  it now reuses the same machinery as an anchored open (build the loaded rows,
  paginate until the target arrives, retry) and always highlights the target.
  The bubble's accessibility label announces the quote, which the semantics
  exclusion around the strip had been erasing.

- **A system notice in the room list carries no delivery tick** (`D61`). A
  notice about a plan reaches the row with `from` set to the plan's owner,
  which made "is this my last message?" true for a sentence nobody typed, and
  the row painted a sent/delivered tick in front of "The plan has started".
  The tick and the sender prefix are the same claim made twice — "you wrote
  this" — so both now hang on one getter and cannot diverge again. System
  notices, reactions and tombstones carry neither.

- **Links are detected the way people write them** (`D89`). Only schemed URLs
  were, so `www.example.com`, a bare `example.com/path`, an e-mail address and
  a phone number all stayed dead text. All four are now found and tappable,
  with the trailing punctuation of the sentence left out of the match, a
  minimum length so a two-letter word before a two-letter "TLD" is not a link,
  and an explicit guard so the two halves of `maria.jose@example.com` are not
  mistaken for hosts of their own. Tapping a schemeless host opens it over
  `https`.

- **A message that is nothing but emoji is painted large** (`D90`). Up to
  three glyphs, the WhatsApp baseline: past that the enlarged emoji stop being
  a gesture and become a wall. They land on the chat background with no bubble
  around them, because enlarging the glyph inside the coloured rectangle only
  produces a taller rectangle. Family and flag sequences count as one emoji;
  one letter, digit or punctuation mark anywhere and the message is ordinary
  text again.

- **Your own voice note shows your photo, not your initials** (`U90`). The
  portrait inside your own bubble read `controller.currentUser`, the snapshot
  taken when the room opened and never touched again, while every other
  sender went through the live resolver — so a picture set (or simply
  fetched) after that first open existed only in the second. Your own bubble
  now takes the same route as everyone else's. And because a host that sets
  the profile photo through its own backend never pushes it into
  `currentUser` at all, opening a room now asks the chat backend for it once
  when there is no photo to show; see `ensureCurrentUserAvatar` below.

  The portrait stays where it is in every other respect, including alongside
  the small leading avatar on a group's incoming voice note: WhatsApp shows
  both there too, and WhatsApp is the baseline.

- **Reacting costs two gestures instead of three** (`U88`). The row of quick
  reactions used to live behind the sheet's "React" entry. It now comes up
  WITH the sheet, still anchored over the bubble, in the root overlay rather
  than a route of its own — two stacked modal routes means the top barrier
  eats the taps meant for the other. "React" leaves the sheet, since the row's
  own "+" already opens the full picker. Tapping an emoji closes both.

- **The action sheet stops covering the message it is acting on — without
  taking it off the top of the screen** (`U88`). Its height is not knowable in
  advance, since a host can replace the content wholesale through
  `contextMenuBuilder`, so it is measured once laid out and the list reserves
  room at its bottom, which lifts the conversation. What it reserves is now
  measured against the bubble instead of being the sheet's whole height plus a
  fixed margin: enough to clear the sheet, never more than the headroom the
  quick-reaction row needs above the bubble, and nothing at all when the
  bubble already sits clear. The fixed lift moved every bubble whether it
  needed it or not, and one that was not already at the bottom of the list
  left the screen through the top — the sheet stopped covering it by taking
  it away.

- **"Message info" says when the message was sent** (`U89`). In both branches:
  "Sent · 18:51" above the "Read by" / "Delivered to" sections, and "Sent at
  18:53. Nobody has received it yet." in place of the bare "No read or
  delivery info yet". The one screen dedicated to a message was the only place
  that did not state its hour.

- **The chat's bottom sheets look like the host app's** (`U89`). Every one of
  them. They passed no background colour, so Material derived
  `surfaceContainerLow` — which under a warm seed comes out cream — and they
  hard-coded a 16 corner radius one call site at a time, against the 15 host
  design systems round at. All fifteen call sites now go through
  `ChatSheetPresentation.showSheet` (below), so "one bottom sheet for the
  whole app" holds by construction rather than by fifteen of them agreeing,
  and a host that declares `ThemeData.bottomSheetTheme` reaches the lot at
  once. The long-press menu, the room menu, the attachment picker, the forward
  and member pickers, the reaction detail, the emoji picker, the mute-duration
  and avatar pickers and the delivery-status legend all keep the drag handle,
  scroll control and navigator they had.

- **A room opened by id is not abandoned before the room list catches up.**
  The view read "this room is not in the list" as "I have been removed from
  it" and walked out — and the room list is notified by every avatar or
  display name the SDK learns, so an unrelated cache write was enough to eject
  a user who had arrived from a push notification or a deep link. Leaving now
  requires the room to have been in the list at some point.

### Added

- `ChatSheetPresentation`, an extension on `ChatTheme` carrying
  `showSheet<T>()`, `sheetBackgroundColor(context)` and `sheetShape(context)`:
  the single door every SDK bottom sheet goes through. Both values defer to
  the host's own `ThemeData.bottomSheetTheme` when it declares one — the
  standard Material lever, and the way to make every SDK sheet match an app's
  design system in one place — and otherwise fall back to
  `colorScheme.surface` and `kChatBottomSheetCornerRadius` (15, the radius
  host design systems round at, against the 16 the sheets used to hard-code).
  `showSheet` also takes `showDragHandle` and a `backgroundColor` override for
  the one sheet that already exposed its own (`fullEmojiPickerBackgroundColor`).

- `chatHighlightSpans(text, query, baseStyle:, matchStyle:)`, the highlight the
  in-room message search has always painted its results with, now part of the
  package's surface. A host building a row of its own — a chat list telling
  the reader WHY a room matched — no longer needs a second copy of it to keep
  in step with the theme. Matching is case-insensitive and literal, so a query
  containing `.`, `(` or `*` highlights those characters instead of throwing.

- `ChatUiAdapter.ensureCurrentUserAvatar()`, which fills in the local user's
  own avatar from the backend when the snapshot the host handed over at
  sign-in carries none. At most one request per adapter, and none at all once
  there is a photo. `NomaChatView` calls it after the first frame of a room.
  `refreshCurrentUser()` remains the unconditional version, for a host that
  has just written the profile itself.

- `MessageInput.displayNameResolver`, the resolver behind the "replying to X"
  line of the composer's reply strip. Same contract as
  `MessageList.displayNameResolver`; `ChatView` wires it from
  `ChatViewBuilders.displayNameResolver`, so a host that already sets that one
  gets it for free.

- `MessageList.viewportBottomInset`, space reserved below the newest message.
  The list is `reverse: true` and bottom-anchored, so it lifts the
  conversation instead of hiding under it. `ChatView` uses it to keep the
  long-press sheet off the message it is acting on.

- `kChatEmojiOnlyFontSize` and `ChatEmojiOnlyPresentation.emojiOnlyTextStyle`,
  the size and style an emoji-only message is painted at. A host that sets a
  13pt body does not thereby ask for 13pt emoji, so the size is deliberately
  not derived from the bubble text style's own `fontSize`.

- `DetectedUrl` — the slice as the sender typed it, where it ends, and the
  absolute form to hand a launcher — returned by the widened `UrlDetector`.

- New localised strings: `messageSentAtTemplate`,
  `messageSentNoReceiptsTemplate`, `replyQuoteSemanticsTemplate` and
  `replyQuoteSemanticsNoSenderTemplate`, with `messageSentAt`,
  `messageSentNoReceipts` and `replyQuoteSemantics` to read them. Translated
  into all twelve shipped locales — en, es, fr, de, it, pt, ca, sv, no, da, pl
  and cs — rather than only the six that carry the full set.

## 0.29.1 - 2026-08-26

Patch. One fix, and a note on where it came from.

### Fixed

- **The camera page's permission warning goes away on its own again.**
  `SnackBar` defaults `persist` to `action != null`, and a persisting bar
  makes `Scaffold` skip its own timeout — so offering the "open settings"
  shortcut had the side effect of leaving the warning on screen until the
  user dismissed it by hand, over the camera and over every screen they
  moved to afterwards. It now sets `persist: false` with an explicit
  duration, longer when the permission is permanently blocked because that
  wording has to be read *and* tapped.

### Note on 0.29.0

The archive published as `0.29.0` already contains this change, but the
`v0.29.0` tag does not: the fix landed in the working tree after the release
commit and `pub publish` packages the working tree rather than `HEAD`. This
release exists so that what is on pub.dev corresponds to a reviewed commit.
Prefer `0.29.1`.

## 0.29.0 - 2026-08-26

Minor bump. Two of the fixes change what an existing call site *answers*
without changing what it compiles to, so read *Breaking (behaviour)* before
upgrading: deleting a chat now reports a failed write instead of swallowing
it, and the three deleted-room markers propagate their datasource's result
rather than collapsing it to success. Everything else is additive — two
local-write methods on the client surface, a veto over the membership
banners, and a subtitle slot on `RoomTile` that composes instead of
replacing.

The two headline fixes share a shape worth naming, because it is the one
that made both defects invisible: **a local write that failed was reported
as if it had landed**. A message the server refused was shown as sent and
then vanished on reopen; a chat the user deleted came straight back with
its old preview. In both cases the row on screen and the row in the store
disagreed, and the code had no way to notice.

### Added

- **`ChatClient.saveLocalMessage(roomId, message)`** — writes a message into
  the local store with no server round-trip. The pure-local twin of
  `setLocalClearedAt`, for the rows the server will never hand back. It sits
  on the client surface, not on the adapter cache, for the same reason
  `markRoomDeleted` does: the row has to survive a `ChatUiAdapter` built
  without its own `cache:` argument, which is how WB builds it. A no-op that
  never throws when the client has no local datasource.

- **`ChatClient.hideLocalMessage(roomId, messageId)`** — records a message as
  hidden for this user ("delete for me"). The backend keeps no per-user hide
  state, so without a durable marker the row — usually a tombstone — comes
  straight back on the next list fetch.

- **`MembershipBannerFilter`, on `ChatUiAdapter` and on the facade** — a host
  veto over the SDK's own membership banners, asked per room *and* per event
  flavour (`user_joined`, `user_left`, `user_role_changed`) just before the
  banner is composed. Return `false` and the row is neither shown nor
  cached, so it does not reappear on the next open. The per-room argument is
  the point: a host whose own backend posts a membership message into group
  rooms wants the SDK quiet there and still wants the banner in a
  one-to-one room, where nothing else announces it. `null` — the default —
  keeps every banner, which is what every consumer had before this existed.

- **`RoomTile.subtitleHeaderBuilder`** — a slot *above* the preview line
  instead of in place of it. `subtitleBuilder` was the only way in, and it
  replaced the whole subtitle, so a host that wanted one extra line lost
  typing, the sender prefix and its system-notice guard, the delivery
  receipt and the blocked-sender pruning, and had to rebuild all four by
  hand. This one composes: the host adds its line and keeps the tile's.

### Fixed

- **A message the server rejected with 403 no longer disappears from the
  thread.** Sending to someone who blocked you is meant to look like it
  worked, and it did — until you left the room and came back, at which point
  the message was gone from the thread while the chat list still previewed
  it. Nothing persisted it: every read path that could restore a message is
  fed by the server, and the server had refused this one. It is now written
  through `saveLocalMessage` at the moment it is pinned as sent.

- **"Delete chat" persists.** The conversation came back on the next list
  build with its last message intact. The durable marker was written through
  a path that swallowed its own failure, and the empty set returned by a
  *failed* read is indistinguishable from "this user never deleted
  anything" — so the room-list build had nothing to filter on and repainted
  the row. Both halves now fail closed, in all three layers that touched
  them, and the read-modify-write on the deleted-id set is serialized.

- **An identity swap on the same adapter no longer leaks deleted-room ids.**
  Now that a list build merges the mirror instead of replacing it wholesale,
  the outgoing user's ids would have kept hiding rooms for the incoming one.
  `signOut` and `dispose` clear it; a `disconnect` deliberately does not.

- **A participant's arrival is no longer announced twice** in hosts that post
  their own membership message — see `MembershipBannerFilter` above. The
  guard sits on `addSystemMessage`, the single chokepoint the router reaches
  for all three event flavours, so it covers a kick as well (it travels as
  `user_left` with an actor).

- **A system notice in the chat list no longer gets a sender put in front of
  it** in the composed subtitle, closing the other half of the fix 0.28.0
  started in `RoomTile`.

### Breaking (behaviour)

- **`ChatRoomsController.delete` now returns a failure when the durable
  deleted marker could not be written, and leaves the row on screen.** It
  used to drop the row and answer success regardless. A row dropped without
  its marker reappears on the next build with its old preview, which is
  worse than a delete that visibly did nothing. A host that shows a
  confirmation should key it off this result. A lost *cutoff* is reported
  but not acted on: the row is gone either way, and only prior history could
  resurface.

- **`markRoomDeleted`, `clearRoomDeleted` and `getDeletedRoomIds` propagate
  the datasource's `ChatResult`** instead of collapsing it into success or
  into the empty set. Direct callers that treated these as infallible will
  now see failures they were previously blind to.

## 0.28.0 - 2026-08-25

Minor bump, but read *Changed* before upgrading: part of it breaks a build,
and the rest changes what an existing screen does without touching what it
compiles to. Breaking: the composer's send and edit slots, and
`ThreadView`'s reply slot, now *answer* whether the request was taken, so a
refusal hands the wording back instead of losing it; and `RoomListItem` and
`UnreadRoom` gain a field in the middle, which shifts every positional
Freezed callback written against them and adds a parameter to
`ChatRoomsApi.updateCachedRoomPreview`. Silent underneath a call site that
still compiles — and not only in the two the list flags as **Breaking
(behaviour)**: `withRoomState` no longer re-opens a composer the host
deliberately closed, and `RoomTile.lastMessagePreviewBuilder` no longer
gets a sender prefix put in front of it. *Changed* also holds the
connection banner's red band back for eight seconds instead of flashing it
on the first dropped socket, clears the stored draft when a message goes
out, reopens the composer on more kinds of refused edit, freezes
`silentlyDropped` at "sent", stops prefixing a sender onto a system notice
in the chat list, renames the attach button, formats file sizes and
rewrites the delivery legend. The additive part runs longer than it looks:
swipe actions on the chat list, a "muted until" line that says when the
silence ends, a veto the host can put in front of the mic button, and
several smaller hooks besides — the full list is under *Added*.

The headline fix asks nothing of a host. It arrives with an API of its own
— `confirmSent(pinnedAsSent:)`, a failure injector for tests — and it
freezes what `silentlyDropped` may render as, but none of that has to be
adopted for the fix to hold. Sending to someone who blocked you was only
invisible on the plain-text path. On every other one — attachment, voice
clip, forward — and on every 1:1 room that had to be created first, it
surfaced as a red failed bubble, which is exactly the tell a block is
supposed to hide.

### Added

- **A chat-list row can be swiped.** `RoomSwipeAction` describes one button
  — `icon`, `label`, `onPressed`, plus `side`, `backgroundColor`,
  `foregroundColor` and an `identifier` for drivers — and `RoomSwipeSide`
  says which edge it is revealed from, resolved against the ambient
  `Directionality`. Wire a list of them through
  `RoomListView.swipeActionsBuilder(context, room)`, or hand them to a bare
  `RoomTile` as `swipeActions:`.

  The swipe *reveals* the buttons, it never fires one: nothing destructive
  happens on a gesture the user may not have meant, and `onLongPress` stays
  the shortcut it always was. A row with no actions for a side is not
  draggable towards that side, a drag born on the leading edge never opens
  the leading actions (the platform back gesture keeps that strip), and a
  tile built without actions gets no gesture recognizer at all — its widget
  tree is the one it had before this existed.

- **A silenced room says until when.** `RoomTile` grows a third line and
  `ChatRoomAppBar` appends it to its subtitle, both from the new
  `ChatUiLocalizations.mutedUntilTemplate` (`'Muted until {date}'`, with
  `mutedUntil(date)` to fill it) and `DateFormatter.formatMuteUntil`, which
  converts the backend's UTC expiry to the device zone first — a mute that
  ends at 20:30 in Madrid must not advertise 18:30 — and prepends the day
  when the deadline is not today. A permanent mute carries no expiry and
  keeps the bell icon alone, and an expiry already elapsed (a stale cache)
  is ignored. Translated in all twelve locales.

- **`canStartRecording` / `onRecordingRejected`, on `ChatViewCallbacks` and
  on `MessageInput` alike** — a host that builds the composer itself takes
  the same two optional parameters, and `ChatView` simply forwards the
  callbacks it was given. They are asked the instant a finger lands on the
  mic button — before the recorder is
  armed and therefore before the platform asks for the microphone
  permission. Return `false` for a room that cannot take a voice message (a
  contact gate, a membership that ended) and nothing is armed; the host
  explains it through `onRecordingRejected`, or the composer floats the new
  `ChatUiLocalizations.recordingNotAllowed` over the button. Synchronous by
  design: an `await` there would sit between the finger landing and the
  recorder coming up on *every* legitimate recording. Left null, every touch
  goes through as before.

- **`ChatViewBehaviors.sustainedConnectionErrorDelay`**, and
  `ConnectionBanner.sustainedErrorDelay` /
  `ConnectionBanner.defaultSustainedErrorDelay` (8s) underneath it — see the
  banner's new behaviour under *Changed*.

- `MessageListState` is now public, with `rectForMessage(messageId)`:
  where a row sits on screen *right now*, or `null` when it is not laid
  out. A host anchoring an overlay to a row after an `await` should ask
  again through a `GlobalKey<MessageListState>` rather than reuse the rect
  a long press carried, which is a frame old by then.

- `MessageBubble.displayNameResolver`, wired by `MessageList` from the
  resolver the host already supplies, so a membership banner composed while
  the user cache was still cold gets a second chance at a real name when it
  repaints.

- **`resolveDisplayName` on `localizedSystemMessageText` and
  `localizedSystemMessageTextFromMetadata`**, both exported. Named and
  optional, so every existing call compiles and reads exactly as before.
  Hand one over and a membership label that is still the raw id it was
  meant to name — a banner composed while the user cache was cold — is
  looked up again on this paint; a label that already is a name stays
  frozen, the way the text of any other sent message does.

- **`ChatNoticeAnchor`**, a mixin for a `State` that raises SDK notices, plus
  `chatNoticeL10n(context, theme)` and the new `messenger:` / `presenter:`
  arguments on `showChatNotice`. It resolves the presenter, the
  `ScaffoldMessenger` and the localizations in `didChangeDependencies` — the
  last moment those lookups are guaranteed to answer — and hands them over
  as fallbacks later. See *Fixed*.

- `ChatController.confirmSent(..., pinnedAsSent: true)`, which freezes a row
  at `ReceiptStatus.sent` for the rest of the session — and, in practice,
  past it: the set of pinned ids lives only as long as the controller, but a
  row that reached the cache carrying `silentlyDropped` is re-derived as
  pinned on the next start, which is the freeze *Changed* describes.

- `MockMessagesApi.failNextSendWith`, a one-shot failure injector for tests
  that need to drive a send path's rejection branch.

### Changed

- **Breaking — `onSendMessageRequest` and `onEditMessage` return
  `FutureOr<bool>`** (on `ChatViewCallbacks` and on `MessageInput` alike),
  and `ThreadView.onSendReply` becomes `FutureOr<bool> Function(String)`.
  The verdict is *was this taken?*, not *did it arrive*:

  - `true` — something now owns the text (an optimistic bubble, a queue) and
    the composer clears, exactly as it always did. A send that reached the
    wire and failed there is `true`: its bubble is on screen with its own
    retry, and returning `false` would put the same words in two places.
  - `false` — the request was refused outright and the wording exists
    nowhere else (a closed contact gate, a read-only room, a moderation
    veto). The composer hands it back: the text where the user left it, the
    reply it was under, edit mode reopened on the message being edited.

  Migration is mechanical — a host that dispatches and does not care ends
  its callback with `return true`. The hand-back aborts on its own if the
  user started typing, replying or editing in the gap, so a refusal that
  resolves a second later never overwrites fresher input.

- **Breaking — `RoomListItem` and `UnreadRoom` carry
  `lastMessageIsSystem`**, defaulting to `false`. Only `UnreadRoom` is
  written to disk; `RoomListItem` never is, and takes the flag back from
  the stored `UnreadRoom` when the list is rehydrated — so a row keeps
  knowing across restarts that its last line was a system notice rather
  than something a person wrote. Breaking twice over, both
  times only where a signature is spelled out by hand or read positionally.
  Anyone implementing `ChatRoomsApi` themselves has to declare the matching
  `bool? lastMessageIsSystem` parameter `updateCachedRoomPreview` gains.
  And because the field sits in the middle of both models rather than at
  their end, the positional callbacks Freezed generates from them —
  `when`, `maybeWhen`, `whenOrNull` — take one more argument in that
  position, so every one already written against `RoomListItem` or
  `UnreadRoom` has to be updated. The constructors and `copyWith` are
  named throughout and compile untouched.

- **The composer clears the stored draft when it sends.** `MessageInput`
  emptied its own field but left `ChatController.draft` holding the wording
  that had just gone out, so anything that reads the draft back saw a
  message which no longer existed anywhere else: the composer reseeds
  itself from it on any rebuild that finds the field empty, and a host
  persisting drafts per room was keeping text the user had already sent. A
  send now ends with `setDraft(null, notify: false)` — silently, so nothing
  rebuilds on account of it. An edit leaves the draft untouched: it never
  held the edited message's text to begin with.

- **Breaking (behaviour) — `ChatViewBehaviors.withRoomState` stops
  overwriting the host's `readOnly` and `readOnlyLabel`.** They are now
  combined: the composer stays closed when *either* the room state or the
  host says so, and the room's own `readOnlyLabel` wins only when the room
  itself is read-only. An app that closes the composer for a reason only it
  knows — a contact gate, a per-app permission — was being silently
  re-opened by any room the SDK considered writable.

- **`ChatMessage.silentlyDropped` must not be rendered as its own state.**
  The old documentation invited a distinct treatment (a single grey check
  that never progresses); that is precisely the tell a block is meant not to
  give. The row renders as an ordinary "sent" and is now *frozen* there —
  no delivered cursor, fan-out or per-user ack may advance it, in the
  session or after a cold start. The flag is local bookkeeping.

- **`restoreComposerOnEditFailure` covers every refusal, not just the
  expired window.** `ForbiddenFailure`, `ContentFilterFailure` and
  `ValidationFailure` now reopen the composer on the edited message with the
  typed text, alongside `EditWindowExpiredFailure`. A refused edit has no
  failed bubble to fall back on — the adapter rolls the row back to the
  original wording — so this was the only thing standing between the user
  and losing what they had just written. The line is drawn at a refusal
  from the server, not at a failed trip to it: a request that never brought
  a verdict back (network, timeout) and a 5xx that says nothing about the
  wording still leave the composer shut. A host passing its own
  `onEditMessage` gets the same effect by returning `false`.

- **The chat-list row stops prefixing a sender onto text it did not write.**
  A system notice (`lastMessageIsSystem`) renders bare, the way deletions
  and reactions already did — "You: the plan starts in 24 hours" read as if
  the user had written it.

- **Breaking (behaviour) — `RoomTile.lastMessagePreviewBuilder` no longer
  gets a sender prefix in front of it.** A non-null builder is now taken as
  a self-contained sentence: **no sender prefix is prepended** to it any
  more (the receipt icon still is), because a host that already names the
  actor was getting it twice, as in "Alice: Alice joined the plan". The
  signature does not move, so nothing warns: a host that was relying on the
  SDK to put the name in front of its own preview has to write it itself.

- **The connection banner keeps red for a link that is really down.**
  A transport reports `error` the instant a socket drops and only moves to
  `connecting` once its backoff timer fires, so the raw state said "broken"
  during retries the user never needed to know about.
  `ChatConnectionState.error` now wears the discreet `reconnecting`
  presentation until the link has been down for
  `sustainedConnectionErrorDelay` (8s by default), and only then escalates
  to the red band with its icon. The label follows the presentation rather
  than the raw state — it is read out of `labels[reconnecting]` for as long
  as the demotion lasts — so a host that mapped its own wording onto
  `ChatConnectionState.error` sees the `reconnecting` entry instead during
  those first seconds. The countdown restarts only on `connected`, so a loop
  that keeps failing still escalates; `Duration.zero` restores the immediate
  red. `ConnectionBanner` is a `StatefulWidget` as a result, and
  its constructor grows the optional `sustainedErrorDelay` — still `const`,
  so every call site written against the old one compiles untouched. It
  does not behave as it did: the parameter defaults to the same 8s, so a
  screen that used to show the red band the instant its socket dropped now
  shows the discreet `reconnecting` presentation for those first eight
  seconds and escalates only if the link is still down. Pass
  `sustainedErrorDelay: Duration.zero` to get the old timing back.

- **The composer's attach button announces "Attach", not "Gallery".** It was
  reusing the label of one of the options behind it, so a screen reader named
  a single destination for a button that opens four. The new
  `ChatUiLocalizations.attach` string carries it, the attachment sheet is
  titled with the same words (`AttachmentPickerSheet.title`, suppressed by
  passing `''`), and hosts addressing the button by its semantics label in an
  integration test will need to follow. That title is a semantics header
  carrying the identifier `chat_attachment_sheet_title`, so a driver can
  wait on the sheet's heading by name instead of on the words in it —
  which change with the locale, and are gone entirely when the title is
  suppressed. The localization is done by `AttachmentPickerSheet.show`,
  which is where a `BuildContext` exists to do it: a host constructing the
  sheet widget directly and leaving `title` alone gets the English literal
  `'Attach'` in every locale, and has to pass the string itself.

- **A document bubble shows a readable size.** The raw `fileSize` a message
  carries is normally a byte count (`'387'`) and was printed verbatim; it is
  now scaled to B / KB / MB / GB / TB with one decimal from KB up — under
  1000 bytes it stays the whole count (`'387 B'`) — 1000-based like the
  platform pickers, with the decimal separator of the active locale. A host
  that already hands over formatted text (`'2.4 MB'`) keeps it: anything that
  does not parse as a non-negative integer is passed through untouched.

- **The delivery-status legend stops naming colours.** In English and in
  every locale that translates it, the group note now speaks of the
  *delivered* and *read* states rather than of grey and blue checks, so it
  still reads correctly under a custom `statusIconBuilder` or a palette that
  never had those colours.

### Fixed

- **Sending to someone who blocked you is finally invisible everywhere.**
  Two problems compounded. The block check only recognized
  `403 {"detail":"blocked"}`, but creating the 1:1 room answers with prose
  in `detail` and the token in `error` — so every guard on the
  room-creation path was dead code and a first message to a blocker came
  back as a failed bubble. It is token-first now (`error == "blocked"`, the
  `detail` match kept as a legacy fallback). And the swallow itself only
  existed for plain text: attachments, voice clips and forwards each raised
  a red row instead. All three now land the same way as text — the row stays
  at "sent", no `OperationError` is emitted, and the send reports success —
  across all four ways a DM room gets materialized (draft, attachment, voice
  and forward target), and on a manual retry.

  Every one of those rows is stamped `ChatMessage.silentlyDropped` as it is
  swallowed. The flag used to be set only where the backend answers the
  `sendDirectMessage` call with an empty `204`; a send refused with
  `403 blocked` now carries it too, which is what pins the row at "sent"
  for good and what survives to the cache.

  The swallowed row is written to the message cache as well, not just to the
  chat-list preview. The server has no record of it, so nothing would ever
  bring it back: without that, the sender reopened the room and found the
  message missing from the thread while the list still previewed it.

- **A refused edit is no longer indistinguishable from an applied one.**
  The 403 fallback compared the backend's `detail` verbatim against
  `edit_window_expired`, but the backend writes `edit window expired`,
  spaces and all — so the fallback never matched on exactly the servers it
  exists for. `detail` is now lower-cased and its whitespace collapsed
  before the comparison, and `EditWindowExpiredFailure` reaches the notice
  and the composer restore. The same normalization runs before the delete
  token, so a `delete window expired` written the same way now lands on
  `DeleteWindowExpiredFailure` instead of a bare `ForbiddenFailure`.

- **Notices raised while their screen is coming down are no longer lost.**
  An operation that fails as its route pops resumes on a context whose
  element is deactivated: `mounted` is still `true`, but every ancestor
  lookup answers with *Looking up a deactivated widget's ancestor is unsafe*
  rather than with `null`, which threw away the message *and* took the
  caller's remaining work with it. Every lookup in `showChatNotice` is now
  guarded, a presenter or a `snackBarBuilder` that throws degrades to the
  plain bar instead of losing the notice, and the SDK's own pages resolve
  their messenger, presenter and strings ahead of time through
  `ChatNoticeAnchor`.

- **The room header stops counting yesterday's members.** Reads whose whole
  contract is to re-read the server — the room detail fetched when a room is
  opened, on `RoomUpdatedEvent` and `UserRoleChangedEvent`, and by
  `GroupInfoPage` — now ask for `CachePolicy.networkFirst` instead of
  inheriting the host's `cacheFirst` default, and so does the detail read
  that materializes a room the list has never seen before, which was
  seeding a brand-new row from whatever the cache happened to hold. On top
  of that, a
  reconnect/resume resync re-reads the detail of the room currently open: it
  reloaded the list and the messages but not that detail, so a join missed
  while the socket was down printed its system banner in the transcript next
  to a header still counting the members the room had on the way in — and
  stayed that way for as long as the room stayed open.

- **The connection banner is no longer driven by unrelated errors.** A
  transport-level `ErrorEvent` reaching the event router used to set the
  connection state directly; the transport is now the only thing that
  governs the banner.

- **The reaction picker lands on the message it was opened from.** It was
  positioned with the rect measured at long-press time, by then a frame old
  and possibly from a recycled bubble, since the context menu had opened and
  closed in between; the row is re-measured just before the picker opens.
  The row also stays tinted while the picker is up, the picker is clamped
  inside the safe area and the keyboard inset, and a row that cannot be
  measured at all rests it over the composer instead of pinning it to the
  top edge.

- **A membership banner says a name, not a user id.** When the user cache
  had not yet heard of the person who joined or left, the banner was composed
  with the raw id and kept it forever. Composition now waits for the lookup
  within a 3-second budget (and keeps watching the cache when another path
  already had that id in flight, which the de-duplication answered with
  `null`), and past the budget the bubble still repairs the label on paint —
  including the metadata a host's own `systemMessageBuilder` or
  `systemMessageTextResolver` composes from, not just the SDK's sentence.

  The wait is paid where the banner is composed, and the router dispatches
  that composition without awaiting it. A banner whose names need the full
  three seconds can therefore land after events that arrived behind it —
  the transcript is right about what happened, not always about the order
  in which it did.

## 0.27.0 - 2026-08-21

Minor bump: no API is removed or narrowed, but several defaults now behave
differently — the unread divider anchors somewhere else, a group's grey ✓✓
stops waiting on members who never showed up, an empty room draws a card,
and the row whose context menu is open is tinted. Every one of them is
opt-out. A host that upgrades and rebuilds compiles untouched.

### Added

- **A room with no messages is a starting card, not a dead end.**
  `ChatViewBuilders.emptyRoomBuilder` builds what an empty room shows,
  receiving an `EmptyRoomInfo` — `roomId` (`null` while a DM is still a
  local draft), `isGroup`, `currentUser`, `otherUsers` / `otherUser`, and
  `onSendFirstMessage`, which sends text exactly as the composer would.
  `onSendFirstMessage` is `null` in a room that cannot be written to
  (read-only, blocked, or no send callback wired), so a card knows when to
  hide its offer. Return `null` from the builder for a room you have
  nothing to say about and the SDK's own card is drawn instead, so a host
  can decorate the rooms it recognizes and leave the rest alone.

  `EmptyRoomState` is the layout itself, exported so a host can keep the
  SDK's spacing and theming while supplying `header` (its own card above
  the explanation) and `actions` (the buttons under it).
  `DefaultEmptyRoomState` is the fallback: the SDK explanation plus, in a
  1:1 that can be written to, a one-tap 👋 as the first message. The
  suggestion is an emoji and not a phrase because the SDK cannot translate
  a greeting into a locale it does not ship.
  `ChatViewBehaviors.emptyTitle` / `emptySubtitle` / `emptyIcon` still
  replace the labels without replacing the card. **Diverges from
  WhatsApp**, which leaves an empty room bare except for its encryption
  notice.

- `MessageList.activeRowMessageId`, `activeRowColor` and
  `activeRowDecorationBuilder` — the row whose context menu is open, and
  how it is painted while it is.

- `ChatController(groupReceiptPolicy:)` with `GroupReceiptPolicy`, for
  hosts that want the old strict divisor back (`allMembers`).

- `MessageSearchView.currentUserId`, `emptyPromptText`,
  `resultCountLabelBuilder`, `showResultNavigation` and `autofocus`.

- `resolveUnreadBoundary`, the pure function that decides where the
  "N new messages" line lands, exported so a host can reason about (or
  test) the same decision the room makes.

- **A legend for the ticks, and times that do not lie.**
  `DeliveryStatusLegendSheet` is a sheet a host can open from its own room
  menu: the five delivery states, each drawn with the glyph the bubbles
  actually use (so a custom `bubble.statusIconBuilder` is honoured) and
  described with the same words the screen reader already speaks, plus a
  note about the group rule. Configurable through `theme`, `isGroup`,
  `states`, `entryBuilder` and `title`.

  `MessageInfoSheet` now says *when* only when it knows: the server keeps a
  read cursor per participant, not a timestamp per message, so an exact
  time exists only for the message that cursor points at. Every other
  message gets "no exact time" rather than a plausible-looking wrong one.
  `showApproximateReceiptTimes: true` opts into the honest upper bound
  ("by 10:42 at the latest") instead. Overridable through
  `receiptTimeFormatter` and `receiptSubtitleBuilder`; the per-row data is
  exposed as `MessageReceiptDetail`.

- Twelve strings moved into `ChatUiLocalizations` that used to be hardcoded
  in the search view and the sheets above, so a host can translate them:
  `searchPromptEmpty`, the singular/plural pair behind
  `searchResultCount(count)` (which goes through CLDR plural rules rather
  than `count == 1`), and the legend's own labels.

### Changed

- **The "N new messages" divider anchors on the reader's own read
  cursor**, not on a count taken from the end of whatever page happens to
  be loaded. Counting back N places put the line above the date separator
  and above the reader's own messages. The line now sits on the first
  message after the cursor, never on one of the reader's own, and is not
  drawn at all until the first page of history has settled. With no cursor
  available it degrades to the old count-back, restricted to incoming
  messages.

- **A group's grey ✓✓ no longer waits on members who never acknowledged
  anything.** A roster entry that has never produced a single receipt
  cannot be told apart from an invitee who never showed up, and holding
  every other member's delivery state on them left the sender with a
  bubble that never moved. The divisor is now the members who have ever
  confirmed something in the room, falling back to the whole roster while
  nobody has. Blue stays strict: it still means every member read the
  message. Revert with
  `ChatController(groupReceiptPolicy: GroupReceiptPolicy.allMembers)`.

- **Sender grouping breaks on a system message**, the way it already broke
  on a date separator: the first bubble after one shows its name and
  avatar again instead of reading as a continuation of a run interrupted
  minutes ago.

- **The row whose context menu is open is tinted** for as long as the menu
  stays up — the WhatsApp treatment for a message being acted on. Opt out
  with `MessageList.highlightRowWhileContextMenuOpen: false`, or take the
  decision over by driving `activeRowMessageId` yourself.

- **In-room search opens focused**, says what it searches before anything
  is typed, labels the user's own hits, and heads the list with a result
  count plus previous/next arrows.

### Fixed

- **A failed attachment no longer blanks the chat list row.** The revert
  read the previous message out of the room's own message controller
  alone, which is empty for a room the user never opened, so the row went
  blank instead of falling back to the preview it had been showing all
  along. `RoomListMutator` now remembers the confirmed preview each row
  carried before the optimistic one and restores it when the send fails.

- **`NomaChatView` stopped dropping two host builders.** It rebuilds
  `ChatViewBuilders` to layer the adapter's defaults underneath, and
  `blockedMessageBuilder` and `batchUserFetcher` were never copied across
  — a host that wired either through `NomaChatView` saw it silently
  ignored (wiring them on `ChatView` directly always worked).

### Known limitations

- `MessageSearchView`'s opening prompt and result count still ship as
  `en`/`es` literals inside `message_search_delegate.dart` rather than as
  `ChatUiLocalizations` keys; both are overridable per call site. See
  `CONVENTIONS.md` §4.

- The empty-room card's built-in first-message suggestion is a single
  emoji. Word suggestions are the host's to supply, through
  `EmptyRoomState.suggestions` from an `emptyRoomBuilder`, until the
  strings live in the localization bundle.

## 0.26.0 - 2026-08-20

Minor bump carrying two **breaking** additions and three changed defaults.
A host that upgrades and rebuilds compiles untouched unless it switches
exhaustively over `MessageAction` or implements `ChatClient` itself; the
behaviour changes are all opt-out. See `MIGRATING.md` for the upgrade path.

### Fixed

- **A failed attachment is no longer a dead end.** A photo whose
  `POST /attachments` never landed left a bubble that could not be sent,
  could not be removed, and that the chat list went on advertising as sent
  — the user walked away believing they had sent a picture nobody
  received. Three things changed:

  The bytes now survive the failure. `ChatUiAdapter.failedUploads` (a
  `FailedUploadRegistry`) holds them, so `messages.retrySend` on that
  bubble re-uploads the same file instead of refusing with
  `attachment_never_uploaded`. Only the two failures that prove the bytes
  never left were ever recoverable before, through the offline queue;
  every other upload failure — a 5xx, a gateway timing the request out, a
  rejected content type — had nothing to retry with. Retention is
  memory-only, ends with the session, and is bounded by two tunable caps
  (`maxEntries`, default 8; `maxBytesPerEntry`, default 12 MB); past them
  the retry refuses exactly as it did before.

  `ChatUiAdapter.messages.discardFailed(roomId, messageId)` is the way out
  for a user who gives up: the bubble, its cached pending copy and its
  retained bytes go, and nothing is sent. It is surfaced as
  `MessageAction.discardFailed` on failed outgoing rows, in place of
  "Delete" — which would promise a deletion for everyone that has nobody
  to reach, and which the delete window hid outright once the row aged,
  leaving the bubble unremovable.

  The chat list stops lying. A media send that fails now takes its
  optimistic preview back off the row, falling back to the room's newest
  real message or clearing it when the failed send was the only one. Text
  sends are unchanged.

  Both routes also empty the offline queue of that row. A send that failed
  on connectivity leaves a copy of itself in the queue, and the queue
  drains on every reconnect: without this, discarding sent the photo the
  user had just taken back, and retrying sent it twice — under two
  idempotency keys the server has no way to relate. Neither can be undone
  once it lands in a room somebody else is reading. `discardFailed` and
  `retrySend` now drop the queued copy through the new
  `ChatClient.cancelOfflineSend`.

  A retried voice note keeps its recording. The retry re-read the clip's
  length off the failed row but not its waveform, so a seven-second note
  went back out drawn as a flat bar.

- **A refused edit says so, and gives back what was typed.** An edit
  confirmed after the server-side window closed came back 403
  `edit_window_expired`, and the SDK swallowed it whole: the composer shut,
  the bubble rolled back to the original wording, and nothing appeared on
  screen — so the user believed they had corrected what they wrote. The
  refusal now surfaces through the operation-error stream as a localized
  snackbar (`ChatUiLocalizations.editWindowExpired`), and the composer
  re-opens in editing mode carrying the attempt rather than the wording the
  server still holds. Only that refusal reopens it: the expired window is
  the one failure the user is told about, so it is the one where the
  composer coming back reads as an explanation instead of an unexplained
  jump back into editing — a network hiccup leaves the composer shut, as
  before. Opt out with
  `ChatViewBehaviors(restoreComposerOnEditFailure: false)`; the mechanism
  underneath is `ChatController.setEditingMessage(message, draftText:)` and
  `ChatController.editingDraftText`.

- **A notice raised while a route is coming down is no longer lost.** Every
  short message the SDK shows on its own — an unblock that failed, a group
  that could not be created, a role change the server refused, the ten or
  so of them — went straight to
  `ScaffoldMessenger.of(context).showSnackBar`. That call walks *every*
  `Scaffold` registered with the messenger, and a `Scaffold` unregisters in
  `dispose`, never in `deactivate`: between the frame that removes a route
  and the end of that same frame, one dying `Scaffold` anywhere under the
  messenger threw the call of whoever was publishing, taking the notice and
  the rest of that callback's work with it. They now all go through
  `showChatNotice`, which publishes after the frame when the tree is still
  settling and swallows nothing.

- **A host that kept its own `enabledActions` is not stranded on a failed
  row.** The menu swaps `delete` for `discardFailed` on a send that failed,
  so an action set written before this release — one that has `delete` and
  no `discardFailed` — came back with no destructive action at all, leaving
  a red bubble with no way out. Such a set now keeps its own `delete` on
  those rows, ungated by the delete window, which has nothing to say about
  a message the server never saw. `NomaChatView`'s built-in delete callback
  discards a failed row instead of deleting it, without a dialog: asking
  the server to delete a message it never received fails, and leaves the
  bubble exactly where it was.

- **A room header's participant count follows joins and leaves.**
  `RoomListItem.memberCount` only ever came from a room-detail fetch, and a
  `user_joined` frame refreshed the roster without going back for it. The
  count therefore kept whatever number the room was opened with —
  contradicting the "… joined" system card printed right underneath it —
  and survived a leave-and-reopen, because the cached detail was stale as
  well. Both `user_joined` and `user_left` now invalidate the cached detail
  and re-read it, the way `user_role_changed` already did — the eviction
  completing *before* the read starts, so a slow store can no longer wipe
  the fresh detail it was meant to replace.

  Opening a room re-reads its detail too. A refresh driven only by frames
  is only as good as the socket: one `user_joined` lost to a reconnect and
  the count stayed wrong for as long as the row lived, which is precisely
  what "it was still wrong after leaving and coming back" meant. Entry is
  the cheap, self-healing moment to ask again, and it also picks up a
  renamed room, a new avatar and a read-only flag set while the app was
  away. Reads are single-flighted per room and a burst of roster frames
  collapses into one detail read plus one trailing re-read, so a plan
  filling up does not turn into one `GET /rooms/{id}` per frame.

- **Non-text bubbles reach a screen reader with a body.** A photo, a video,
  a shared location, a document and a failed upload all announced
  themselves as "You: , Sent" — sender, empty text, status. They now read
  "You: Photo, Sent", "You: Location, Sent", "You: contract.pdf, Sent",
  reusing the descriptions the chat list had been able to produce all
  along (emoji-free: a screen reader reads "📷" out loud). A failed send
  announces `Failed`, where it used to announce nothing at all.

  A caption no longer swallows what it captions: a photo sent with a line
  of text read as that line alone, leaving no clue there was an image
  above it, and now reads "You: Photo, en la playa, Sent". A forward is
  announced as one — the "Forwarded" marker the bubble draws was never
  spoken, and a forward carrying no text of its own was the last row still
  reaching a screen reader as "You: , Sent".

### Changed

- **Breaking** — **`MessageAction` gained `discardFailed`.** Only an
  exhaustive `switch` over `MessageAction` with no default arm needs a
  change; same shape as a new `MessageType` or `ChatFailure` variant. It is
  in the default action set of both `MessageContextMenu` and
  `NomaChatView`, and `ChatView` routes it to
  `ChatViewCallbacks.onDiscardFailedMessage`.

- **Breaking** — **`ChatClient` gained `cancelOfflineSend(String tempId)`.**
  It drops whatever the offline queue holds for an optimistic row and
  returns how many operations went. Only a host implementing `ChatClient`
  itself needs a change; `0` is the right answer for a client with no
  offline queue, which is what `MockChatClient` returns.

- **Deleting a message now asks first.** `MessageAction.delete` deletes for
  everyone and cannot be undone, and the gesture that starts it is a long
  press on a whole row — while blocking a contact and clearing a chat, both
  recoverable, each already confirmed. `NomaChatView`'s built-in delete
  callback now shows a confirmation dialog
  (`deleteMessageConfirmTitle` / `deleteMessageConfirmBody`).
  `MessageAction.deleteForMe` and `MessageAction.discardFailed` are not
  gated: neither leaves the device. Opt out with
  `ChatViewBehaviors(confirmDeleteForEveryone: false)`. A host that supplies
  its own `onDeleteMessage`, or replaces the long-press menu through
  `onMessageLongPress`, owns the confirmation itself.

- **Blocking someone now prunes their content in group rooms.** A block
  used to be cosmetic there: the name and avatar came off the bubble while
  the text, the shared location and the photo stayed exactly where they
  were, and nothing said a blocked person was in the room. Their rows are
  now replaced by a one-line placeholder — the new
  `BlockedContentPolicy.placeholder` default, which prunes the content
  while keeping the room honest about who is in it.
  `ChatViewBehaviors.blockedContentPolicy` also takes `hide` (drop the rows
  outright) and `show` (the previous behaviour, for a host whose backend
  already filters server-side). System rows are never pruned — they are the
  room narrating itself, not the blocked person speaking. 1:1 chats are
  untouched: they already collapse into the blocked-contact banner over an
  intact history, and pruning one would be the room saying the same thing
  twice and losing the conversation to say it.

  The prune reaches every surface that carried the content past the bubble:
  the **quoted strip** a reply paints of a blocked message, the
  **reactions** a blocked user left on anyone's message (subtracted from
  the counts; anonymous counts, with no reactor ids on the message, are
  left alone rather than guessed at), and the **room list preview** of a
  group whose last message is theirs (`RoomTile.blockedSenderIds` /
  `.blockedContentPolicy`, wired for free by `RoomListView` from the
  `adapter` it is already given). A group that is pruning also carries a
  one-line notice (`blockedInRoomNotice`) so a reader can tell why a
  stretch of the conversation went quiet — the ficha's "some indicator in
  the room". The notice appears only while the blocked person actually has
  content in the room.

  `blockedSenderIds` are **chat** user ids — the same space as
  `ChatMessage.from`, `RoomListItem.otherUserId` and
  `ChatUiAdapter.contacts.block`. A host whose own user ids differ has to
  map them first: an id that matches nobody prunes nothing, exactly like an
  empty set.

### Added

- **`ChatUiAdapter.failedUploads`** — the `FailedUploadRegistry` described
  above, exported so its two caps can be tuned.
- **`ChatUiAdapter.messages.discardFailed(roomId, messageId)`** — drops a
  failed outgoing row for good. Returns a `NotFoundFailure` for anything
  that is not a failed row of that room.
- **`ChatViewBehaviors.confirmDeleteForEveryone`**,
  **`.restoreComposerOnEditFailure`**, **`.blockedContentPolicy`**,
  **`.blockedSenderIds`** — all four default to the behaviour described
  above and all four are opt-out.
- **`ChatViewBuilders.blockedMessageBuilder`** — replaces the built-in
  blocked-sender placeholder.
- **`ChatViewCallbacks.onDiscardFailedMessage`** — wired by `NomaChatView`
  to `messages.discardFailed`.
- **`MessageList.blockedSenderIds` / `.blockedContentPolicy` /
  `.blockedMessageBuilder`**, **`RoomTile.blockedSenderIds` /
  `.blockedContentPolicy`**, **`RoomListView.blockedSenderIds` /
  `.blockedContentPolicy`** and **`MessageContextMenu.isFailed`** — the
  same knobs for a host driving those widgets directly. `MessageList`
  prunes in groups only, resolved from its own `isGroup`.
- **`ChatController.setEditingMessage(message, {draftText})`** and
  **`ChatController.editingDraftText`**.
- **`showChatNotice(context, message, {snackBarBuilder})`** and
  **`ChatNoticeScope`** — the single door every SDK notice goes through,
  and the host's override for it. Nothing has to be mounted for the
  notices to work; mount a `ChatNoticeScope` above your `MaterialApp` (so
  the routes the SDK pushes inherit it) to present them your own way, and
  return `false` from the presenter for the ones you would rather leave to
  the SDK.
- Six localized strings in all twelve bundled locales:
  `editWindowExpired`, `deleteMessageConfirmTitle`,
  `deleteMessageConfirmBody`, `blockedMessageHidden`,
  `blockedInRoomNotice`, `discardMessage`. They are confirmations and
  action labels, which the Nordic + Eastern-EU tier (`sv`, `no`, `da`,
  `pl`, `cs`) covers by policy rather than leaving to the English
  fallback — a dialog asking to delete a message for everyone is the last
  place to answer in a language the reader did not pick.

## 0.25.0 - 2026-08-19

Minor bump: a new opt-in analytics channel, additive across the board — no
existing signature changed, no type removed. A host that upgrades and
rebuilds compiles untouched and, wiring nothing new, emits exactly as
before.

### Added

- **`ChatAnalyticsSink` / `ChatAnalyticsEvent`** — a product-analytics
  channel, deliberately separate from `metricCallback`/`MetricCallback`
  (see `TELEMETRY.md`): this one is where room and message identifiers are
  allowed to travel, because a product funnel is meaningless without them.
  Four events: `roomOpened`, `messageReceived`, `voicePlayed`,
  `sendOutcome`. `ChatAnalyticsEvent` is a `freezed` sealed union —
  consumer `switch` statements need a wildcard case to stay forward
  compatible with a future variant, same as `MessageType` or `ChatFailure`.
  See `ANALYTICS.md` for the full contract, emission sites, and a wiring
  example.

  Settable on `ChatConfig.analyticsSink` (for `NomaChat.create` /
  `fromConfig`) **and** directly on `ChatUiAdapter`'s constructor — the
  latter matters for a host that builds `ChatUiAdapter` by hand instead of
  going through `NomaChat.create`, since a callback that only lived on
  `ChatConfig` would never reach it. `null` by default: wiring this is
  entirely opt-in, and a throwing sink is caught and dropped exactly like
  every other user-supplied callback in this SDK — analytics can never
  break the chat.

  Identifiers travel unhashed and the SDK does not sample, batch, or drop
  events — see `ANALYTICS.md` for why (a consumer that needs hashed ids,
  like `WB`, applies its own sanitizer unconditionally on the way out; a
  second transformation point inside the SDK would just be a second place
  for that mapping to drift).

  `ChatViewCallbacks.onVoicePlayed` is new too — `NomaChatView` always
  wires its own default there (publishing the analytics event) and
  additionally calls whatever the host sets, so a host callback never
  silently disables the SDK's own emission.

  Each event documents what it does and does not count — which send paths
  emit `sendOutcome`, why an unmaterialized DM draft emits no `roomOpened`,
  what `voicePlayed.firstListen` really means — in `ANALYTICS.md` under
  "Known limits of the four events". Read that section before building a
  funnel on top of these.

- **`ChatUiAdapter.dm.isDraftRoutingKey(key)`** — tells a synthetic
  `draft:<otherUserId>` routing key apart from a server-side room id,
  which callers previously had to do by re-encoding the prefix themselves.

Older releases: doc/CHANGELOG_ARCHIVE.md
