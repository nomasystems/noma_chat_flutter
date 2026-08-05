# Known issues & technical debt

Bugs, gaps and deferred cleanups that are known and intentionally not fixed
for the full audit this file's entries are drawn from — this document only
tracks what's still open after that audit's remediation pass.

## Testing

### Golden tests for `ImageBubble` are skipped (sqflite dependency)

`ImageBubble` renders through `CachedNetworkImage`, which pulls in
`flutter_cache_manager` → `sqflite`. `sqflite_common` requires a
`databaseFactory` (normally wired via `sqflite_common_ffi` on desktop/test
hosts) to be registered before any DB operation; stubbing the platform
method channel is not enough because the package short-circuits inside
`databaseFactory` itself, before it would reach a channel call. Pulling in
`sqflite_common_ffi` as a dev dependency just to make two placeholder-image
goldens pass hasn't been judged worth the added test-only dependency.

**Current workaround**: `ImageBubble outgoing — {dark,light} (skipped)` in
`test/golden/bubbles_dark_test.dart` / `bubbles_light_test.dart` are marked
`skip: true`. Visual coverage for the shared image-loading chrome (rounded
corners, caption overlay, timestamp placement) is not lost — `VideoBubble`
exercises the same layout with a nullable thumbnail and is not skipped.
`LinkPreviewBubble` avoids the same trap differently: its golden passes
`imageUrl: null`, which skips the `CachedNetworkImage` branch entirely and
renders the text-only OG card — so it is **not** skipped, only tested without
its optional image path. (`TESTING.md`'s "4 skipped goldens" count predates
this: unskip that document's ImageBubble count to 2 the next time it's
touched — `LinkPreviewBubble` was never actually skipped in the checked-in
suite.)

**To unblock properly**: add `sqflite_common_ffi` as a dev dependency and
call `databaseFactory = databaseFactoryFfi` in the golden test `setUpAll`
before rendering `ImageBubble`. Estimated a small, self-contained change —
not done here to avoid adding a new dev dependency inside a docs/golden-only
pass.

### `golden_toolkit` → `alchemist` migration done

The suite migrated from `golden_toolkit` (discontinued on pub.dev) to
`alchemist: ^0.12.0`. `pubspec.yaml` no longer lists `golden_toolkit`.

What changed: `test/flutter_test_config.dart` (new) wraps the whole `test/`
run in `AlchemistConfig.runWithConfig`, disabling alchemist's CI variant
(obscured text, "Ahem" font — it would fail on every baseline since this
suite never generated one) and resolving baselines to the same flat
`test/golden/goldens/<name>.png` paths as before. `helpers/golden_helpers.dart`
now exposes `goldenBubbleTest(description, fileName, child, ...)`, a thin
wrapper around alchemist's `goldenTest` that keeps the existing `goldenHost`
wrapping and fixed per-bubble `Size`; the three test files call it instead of
`testGoldens` + `screenMatchesGolden`. Every baseline PNG was regenerated
with `--update-goldens` (alchemist's renderer/surface-sizing differs from
`golden_toolkit`'s, so the old PNGs were not reused) and the suite was run
clean twice to rule out renderer flakiness before dropping the old
dependency.

One behavioral difference to be aware of: alchemist's `goldenTest(skip:
true)` returns before registering the test at all, so the 2 skipped
`ImageBubble` cases no longer show up as an explicit `~2` skip count in
`flutter test` output — they simply don't appear. The suite's total (21
passing) and coverage are unchanged.

## Attachments

### A queued attachment re-uploads its bytes when only the send fails

`NomaChatClient._executeOfflineOp` replays a `PendingSendAttachment` as one
unit: upload, then send. When the upload succeeds and the send that follows
it fails, `OfflineQueue._drainWith` re-enqueues the whole operation, so the
next drain uploads the same bytes again — N drains leave N blobs on the
server, up to `offlineQueueMaxRetries`. The message itself is not
duplicated (`clientMessageId` covers that); the blob is. The upload inside
the drain also ignores the `kind.isPreResponse` predicate that
`enqueueOfflineAttachment` applies at the door, so a `receive`-phase
timeout there re-uploads too.

**To unblock properly**: split the operation in two phases — once the
upload resolves, re-enqueue a `PendingSendMessage` carrying the resolved
`attachmentUrl`/`attachmentId` instead of the byte-carrying
`PendingSendAttachment` (or store the resolved id on the op itself, via
`PendingSendAttachment.withRetry`, and skip the upload when it is already
there), and apply the same pre-response predicate to the in-drain upload
failure before re-enqueuing.

### Pending-row rehydration matches on text + timestamp, not the idempotency key

**Known limitation of 0.17.0, not inherited debt.** The heuristic below
predates this release, but the symptom it now produces does not: 0.17.0 is
what puts a `clientMessageId` on media rows, and that key is what turns a
harmless duplicate bubble into a delivered message repainted as failed.
Classify it as introduced here, not as pre-existing, and read the paragraph
below as a description of *this* version's behaviour.

`ChatUiAdapter._rehydratePendingMessages` decides a cached pending row has
been superseded by comparing `m.text == p.message.text` within a timestamp
window. Media rows are built without `text` while the send puts `''` on the
wire, so a backend echoing `''` makes `null != ''` and the row is not
recognised as superseded: the stale failed row is re-added and, because
media rows now carry a `clientMessageId`, it resolves onto the
authoritative message and repaints a delivered message as failed until the
next reload. In 0.16.0 the same cache state produced a second, duplicate
bubble instead — worse to look at, but it left the delivered message
alone.

**To unblock properly**: check `m.clientMessageId == p.message.clientMessageId
&& m.id != p.message.id` before the text/timestamp heuristic, drop the
pending row from the cache when it matches, and cover it with a
rehydration test (failed attachment row + authoritative message already in
the controller → one non-failed bubble carrying the real id).

## API surface

### Global message search: no room correlation on hits

The spec/dartdoc mismatch previously tracked here is resolved: the resynced
`doc/chat-api-openapi.yml` now marks `roomId` on `/messages/search` as
optional and documents that omitting it spans all of the caller's rooms,
matching the client-side dartdoc. What remains open: `ChatMessage` has no
`roomId`/`conversationId` field, so a global search response gives the UI no
built-in way to group hits by conversation. See `doc/DEVELOPER_GUIDE.md`,
"Message search — room-scoped vs global" for the caveat as currently
documented.

### Scheduled messages have no cancellation UI in the example app

`messages.schedule` / `listScheduled` / `cancelScheduled` exist and are
documented (`doc/DEVELOPER_GUIDE.md`, "Scheduled messages"), but the example
app does not demonstrate them. Low priority — the sub-API is fully covered by
SDK tests; this is example-app coverage debt only.

### `MessageAction.forward` needs host wiring to appear at all

`NomaChatView` leaves `forward` out of its default context menu (0.17.0)
because the package has no room picker it can open on the host's behalf, so
the tile would close the sheet and do nothing. Hosts that want it add it
back via `contextMenuActionsResolver` and answer it in
`onContextMenuAction`. Closing this properly means the SDK shipping an
opinionated target-room picker wired to `adapter.messages.forward` — a
product decision, not a bug fix.

### `onTapVideo` has no default, so unwired videos show no play overlay

The package bundles no video player, so `ChatViewCallbacks.onTapVideo` is
the one tap callback `NomaChatView` cannot fill in (unlike `onTapImage`,
which opens the bundled `ImageViewer`, and `onTapFile`). Since 0.17.0
`VideoBubble` paints its play overlay only when a handler is wired, so an
unwired host shows a thumbnail rather than a dead button. Closing this means
picking a playback dependency for the package.

### Links inside `ThreadView` replies are still inert

0.17.0 restored link taps in the message timeline by forwarding `onTapLink`
from `MessageBubble` to the `TextBubble` it builds. `ThreadView` builds its own
`MessageBubble` for every reply and passes no `onTapLink` — it has no such
parameter to pass — so a URL in a threaded reply is still painted blue and
underlined with no recognizer behind it. Closing this means giving `ThreadView`
the same callback surface the timeline has: the callback is the whole of the
missing wiring.

### `@mentions` look tappable but have no callback in the public API

`parseMarkdown` paints an `@mention` in the theme's mention colour at `w600`
and attaches a recognizer when handed an `onTapMention`. `TextBubble` accepts
one, but nothing upstream can supply it: `MessageBubble` does not declare the
field and `ChatViewCallbacks` has no `onTapMention` at all. Unlike the link
case this is not a lost wire — the wire was never drawn. Closing it means
adding the callback to `ChatViewCallbacks` and threading it down the same path
`onTapLink` takes, or documenting `ChatMarkdownTheme.mentionStyle` (reached as
`theme.markdown.mentionStyle`) as pure emphasis so nobody themes a mention to
look like a control.

### The room long-press menu needs host wiring to appear at all

Since 0.17.0 `RoomListView` claims the long press only when
`onContextMenuAction`, `onLongPressRoom` or `contextMenuBuilder` is supplied,
because it holds a `RoomListController` and no adapter and so cannot resolve a
single `RoomAction` itself. Closing this properly means either giving the view
an optional adapter, so mute / pin / mark-as-read gain real defaults, or
promoting an adapter-aware room list to the public API the way `NomaChatView`
wraps `ChatView`. Deleting a room would stay host-owned either way.

### An explicit English theme is indistinguishable from no theme at all

Widgets resolve strings through `ChatTheme.l10nOf(context)`, which prefers
the instance the host put on `ChatTheme.l10n` and otherwise reads the
`Localizations` ancestor. "The host put an instance there" is decided by an
`identical` check against the canonical `ChatUiLocalizations.en` constant,
because `ChatUiLocalizations` declares no `operator ==` and `ChatTheme.l10n`
is non-nullable with `en` as its default.

So a host that deliberately hands the chat `ChatUiLocalizations.en` — or
`forLanguageCode('en')`, `forLanguageCode(null)`, or any unsupported code,
all of which return that same instance — while its app locale is not English
gets the app locale instead of the English it asked for. The workaround is
documented on `ChatThemeL10n`: pass `ChatUiLocalizations.en.copyWith()`,
which is a distinct instance and wins. Anything built with `copyWith` (the
usual way to tweak strings) is unaffected.

`ChatUiAdapter` decides "the host took the language into its own hands" the
same way and inherits the same blind spot: a host that passes exactly
`ChatUiLocalizations.en` to the constructor (or to `NomaChat.create`) reads
as "unset", so `NomaChatView` / `RoomListView` push the ancestor bundle in
over it. Assigning `adapter.l10n` at any point pins it whatever the value,
and `ChatUiLocalizations.en.copyWith()` works at construction time.

**To close properly**: make `ChatTheme.l10n` nullable, so "unset" is `null`
and any instance the host passes is honoured verbatim, and give
`ChatUiAdapter` a nullable `l10n:` for the same reason. That is a breaking
change to a public field and to every `copyWith` call site that reads it, so
it belongs in a major release rather than alongside one.
