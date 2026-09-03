# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/). From `1.0.0`
onwards, breaking changes require a **major version bump**.

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

## 0.24.0 - 2026-08-18

Minor bump: three behaviour fixes in the chat surface, no API added, none
removed, no signature changed. A host that upgrades and rebuilds compiles
untouched. Two things change on screen and one of them can break a **test** —
the message context menu now opens from anywhere on the row, not only from the
bubble.

### Changed

- **The long-press that selects a message spans the whole row.** WhatsApp
  behaviour: the avatar, the empty half of the line beside the bubble, the
  reaction bar and the thread link all open the message menu, where before the
  gesture was clipped to the bubble's own box — at most 75 % of the width, and
  frequently much less for a short message. `onMessageLongPress` and every
  callback above it keep their signature; what changed is the area that fires
  them.

  The recognizer **moved**, it was not duplicated: there is one
  `LongPressGestureRecognizer` per row, now at row level with
  `HitTestBehavior.opaque` so the empty side of the line is live. Whatever the
  message *text* did on long-press it still does, unchanged by this release:
  selectable text wins that arena on its own, but it is only selectable when
  the host leaves `onSwipeToReply` unwired — `MessageBubble` sets
  `enableSelection: onSwipeToReply == null`, and `NomaChatView` always wires
  swipe-to-reply, so under the default surface the text long-press opened the
  menu before this release and still does.

  **Nothing changes for a screen reader.** The row detector is built with
  `excludeFromSemantics: true`, so it publishes no node: a `GestureDetector`
  otherwise contributes a node carrying a `longPress` action, and on iOS an
  action alone is enough to make a node focusable — VoiceOver would have gained
  a second, label-less, full-width stop stacked on the bubble's own. The
  long-press action stays declared exactly once, on the bubble's `Semantics`,
  which is the node that carries the label. `test/ui/widgets/message_bubble_row_long_press_test.dart`
  fails if that flag is ever dropped.

  Risk for a host's tests: an existing test that long-presses at coordinates
  inside the bubble still passes — the area only grew. A test that asserted a
  long-press *outside* the bubble does nothing will now see the menu open.

### Fixed

- **Delivery ticks are right on the first frame after opening a room.** A room
  whose own sent messages had already been delivered painted a single ✓ and
  swapped to ✓✓ a moment later. The state was never wrong, only late: the
  cached message rows carry the receipt they held when they were written, and a
  ✓✓ that arrived as a realtime event while the room was closed never reached
  them, so recovering it waited on two network round trips (the message page,
  then the receipt cursors).

  Two halves, both on the local side, neither of them a new stored field —
  the per-message `receipt` and the per-room cursor box were both already on
  disk:

  - Opening a room now reads the stored receipt cursors and applies them in the
    same synchronous turn as the cached rows, before the first frame is
    scheduled. `getRoomReceipts` stays pinned to `networkFirst`, and the
    network pass still runs and still wins — a receipt is applied monotonically,
    so a stale local cursor can only mark fewer rows, never walk a tick
    backwards.
  - A receipt frame that arrives for a room nobody has open now writes the
    cursor to the receipt box. With no controller there was nothing to advance
    and nothing to drain, so that ✓✓ used to exist only as the in-memory
    room-list tick while the cached rows kept saying ✓. A `sent` frame and the
    user's own read receipts are ignored, as before.

  An adapter built without a `cache:` is unaffected in either direction.

- **The chat list shows a preview line for a location, a forward and a deleted
  message.** A map arrived as an untyped row with an empty body and the row's
  subtitle came out blank; the same for a forward with no text of its own, and
  a deleted message still showed its old text. Two things fixed it:

  - The room-listing mapper now honours `messageType` for `location`,
    `forward`, `reply` and `audio`, and `isDeleted`, on the `lastUnreadMessage`
    projection — the backend emits them from the same vocabulary the package
    already uses to type a message. Where the field is absent, a location is
    still recognised from numeric `lat`/`lng` in the metadata, the way the
    full-message mapper already did.
  - A document or a named audio file keeps its name in the preview
    (`📄 contrato.pdf` instead of `📄 File`). The name travels in the message
    metadata and the listing mapper was only reading a top-level field that the
    projection does not send.

  A reaction *on* the last message is deliberately not read as "this row is a
  reaction": the `reaction` field of a listing row lists the reactions the
  message received, and treating it as the row's own type would replace a
  perfectly good text preview with a reaction sentence. Reaction previews keep
  coming from the realtime path, as before.

- **The chat-list preview strings are translated in all 12 shipped languages.**
  `previewLocation`, `previewPhoto`, `previewVideo`, `previewVoiceTemplate`,
  `previewDocumentTemplate`, `attachmentPreview`, `audioPreview`,
  `previewSticker`, the deleted-message pair and the three reaction-preview
  templates existed only in `en, es, fr, de, it, pt, ca` and fell back to
  English in `sv, no, da, pl, cs`. They are now set in all of them. No key was
  added or renamed. The rest of the documented English-fallback gap in those
  five locales is unchanged.

## 0.23.0 - 2026-08-18

Minor bump: the automation vocabulary of `0.22.0` gains one attribute and one
name. Nothing is removed, no signature changes, no rendering moves and no
screen-reader announcement changes, so a host that upgrades and rebuilds
compiles untouched. The one thing that can break is a **test** that hardcoded
the old message-bubble name — see *Changed*.

### Added

- **A message bubble says who wrote it, as an attribute of its name.** The
  bubble now answers to `chat_message_<messageId>_outgoing` when the current
  user sent it and to `chat_message_<messageId>_incoming` otherwise, on both
  halves — the row's `ValueKey` and the bubble's `Semantics(identifier:)`. Until
  now the only thing that told the two apart on screen was the bubble colour and
  which side of the room it sat on, neither of which a driver can read, and the
  screen-reader label that does say it is localised. `messageBubbleSemanticsId`
  is exported so a test asks the SDK for the name instead of re-deriving it.
- **The delivery tick of a message row carries its own name.**
  `chat_message_<messageId>_status`, published on both halves of
  `MessageStatusIcon`, so a driver points at the tick of one specific message
  instead of at "some check somewhere". `messageStatusSemanticsId` is exported.

  **Read the reach before you build a harness on it.** A bubble consolidates
  the announcements of everything it contains into a single screen-reader
  label and excludes its own subtree, so inside a bubble the two halves land on
  two nodes: the `ValueKey` on the tick, and the identifier on a bare sibling
  node — name only, no label, value, hint or action — stacked over the bubble's
  corner. That keeps the message reading as one unit with its delivery state
  announced once. What it costs is iOS: `SemanticsObject.isAccessibilityElement`
  is decided by `isFocusable`, which asks for a label, a value, a hint or a
  non-scrolling action and **does not look at the identifier**, so a node
  carrying only a name is not published as a `UIAccessibilityElement` and an
  XCUITest or `idb` dump will not list it. Inside a bubble, therefore:
  `ValueKey` (widget tests, `integration_test`, the VM Service) everywhere,
  `resource-id` on Android, and **nothing on iOS**. On iOS assert delivery from
  the bubble's own node, whose label ends in the localised delivery state. A
  `MessageStatusIcon` given a `messageId` and rendered outside a bubble is the
  simple case: both halves sit on the icon itself and it is published normally,
  because its own label makes it focusable.
- `MessageStatusIcon.messageId` — optional, `null` by default. Names the tick;
  `null` in the room-list preview, where the icon summarises the last message of
  a room rather than a row of a timeline and has no single id to answer to. A
  `statusIconBuilder` override replaces the SDK's icon and, with it, the name.

### Changed

- **The message bubble name gains the authorship suffix.**
  `chat_message_<messageId>` becomes `chat_message_<messageId>_outgoing` or
  `chat_message_<messageId>_incoming`. The suffix wraps the identity the name
  already carried, never replaces it with a positional one, and the list's
  `findChildIndexCallback` — which parses the key back to reconcile rows — moves
  in the same change, so scroll-position stability is unaffected. A test or
  driver that hardcoded the old string updates it, or better, calls
  `messageBubbleSemanticsId(messageId, isOutgoing: …)`.

## 0.22.0 - 2026-08-16

Minor bump, not a patch on `0.21.0`: the release adds public API (one
constructor field and seven exported helpers). Nothing is removed and no
signature changes, so a host that upgrades and rebuilds compiles untouched.

### Added

- **Stable automation names on the chat room and its eleven internal surfaces.**
  49 names (39 fixed, 10 templated on a row's own id) now travel with the widgets
  the SDK paints: the composer field, the send and attach buttons, every message
  bubble, reaction pills and the reaction picker, the media / documents / links
  gallery and its tabs, the full-screen image viewer, starred messages, in-room
  search, the attachment sheet and the camera's viewfinder, shutter and review
  step — including their loading, empty and error states. Every name is published
  **twice with the same literal**: as the widget's `ValueKey`, which is what
  `find.byKey` and an `integration_test` see from inside the app, and as
  `Semantics(identifier:)`, which surfaces outside it as `resource-id` on Android
  and `accessibilityIdentifier` on iOS, so the same string drives a widget test, a
  UiAutomator dump and an XCUITest run. Names read `<area>_<element>_<kind>` in
  lower snake case under a `chat_` prefix (`chat_send_button`,
  `chat_gallery_media_tab`, `chat_camera_review_send`); collection rows carry
  their own id (`chat_message_<messageId>`, `chat_starred_item_<messageId>`).
  Accessibility is untouched: where a `Semantics` node already existed only
  `identifier:` was added, so every label, `button`/`enabled` flag and custom
  action reads exactly as before, and no `Semantics` was nested inside another.
- `AttachmentSheetOption.identifier` — optional, `null` by default. Names a row of
  `AttachmentPickerSheet` for automation: the string becomes both the row's
  `ValueKey` and its `Semantics.identifier`, so a driver points at an option
  regardless of the locale its `label` renders in. The four built-in rows carry
  `chat_attachment_option_camera` / `_gallery` / `_file` / `_location`; a host row
  in `extraOptions` that passes nothing falls back to
  `chat_attachment_option_extra_<position>`, stable only while the list keeps its
  order — pass a name of your own when it does not.
- Seven exported helpers that build the templated names, so a test asks the SDK
  for a row's name instead of re-deriving the format: `attachmentSemanticsId`,
  `mediaCellSemanticsId`, `docRowSemanticsId` (`media_gallery_view.dart`,
  `docs_list_view.dart`), `linkRowSemanticsId`, `searchResultSemanticsId`,
  `starredRowSemanticsId` and `starredUnstarSemanticsId`. `attachmentSemanticsId`
  is the shared suffix — the backend's `attachmentId` when it sent one, otherwise
  the url + sender + timestamp triple — so the same attachment answers to the same
  name on the Media grid and on the Docs list.

### Changed

- **Widget keys renamed to the new naming.** The five bare keys on the camera
  screen (`preview`, `close`, `flip`, `recordingPill`, `controls`) are now
  `chat_camera_preview`, `chat_camera_close`, `chat_camera_flip`,
  `chat_camera_recording_pill` and `chat_camera_controls`. Three list
  reconciliation keys gain the matching prefix while keeping the identity they
  already carried: a message row goes from `ValueKey(message.id)` to
  `chat_message_<messageId>`, a documents row from
  `<url>-<senderId>-<timestamp>` to `chat_gallery_doc_<attachmentId>` (falling
  back to that same triple when the backend sent no attachment id), and a links
  row from `<url>-<timestamp>` to `chat_gallery_link_<url>-<timestamp>`. Gallery
  grid cells, which reconciled by position, gain a key of their own —
  `chat_gallery_media_<attachmentId>`, with the same fallback as the documents
  row. None of these keys is part of the exported
  API and none was ever documented as one, so nothing to compile breaks; a host
  that hardcoded one of the old strings in its **own** widget tests updates the
  string.
- The `MediaGalleryPage` tabs are built with `Tab(child: Text(...))` instead of
  `Tab(text: ...)` so the name rides the label. The `Text` is a verbatim copy of
  what `Tab` builds internally for `text:` (`softWrap: false`,
  `overflow: TextOverflow.fade`), and the widgets stay `Tab`s, so the tab bar
  measures and renders identically.

### Known limitations

- The package publishes the names and nothing else: turning the semantics tree on
  is the host's call (`WidgetsBinding.instance.ensureSemantics()` under a test
  flavour, or the platform's own accessibility service). Without it the
  `Semantics` half is invisible to a native driver, while the `ValueKey` half
  works regardless.
- Surfaces the host owns are still the host's to name — the `AppBar` around
  `MessageSearchView` and `StarredMessagesView`, and any attachment sheet injected
  in place of the SDK's own.

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
