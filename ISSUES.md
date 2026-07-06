# Known issues & technical debt

Bugs, gaps and deferred cleanups that are known and intentionally not fixed
yet, plus pointers for when someone picks them up. See `AUDIT_2026-07-06.md`
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

## API surface

### Global message search: spec/dartdoc mismatch, no room correlation

`ChatMessagesApi.search(query)` (no `roomId`) is documented (client-side
dartdoc) as searching globally across every room the caller belongs to, but
`doc/chat-api-openapi.yml`'s `/messages/search` operation marks `roomId` as a
**required** query parameter — this looks like spec drift rather than a
confirmed backend capability and needs verifying against the real backend
before a host app builds a global-search screen on it. Separately,
`ChatMessage` has no `roomId`/`conversationId` field, so even a genuinely
global search response gives the UI no built-in way to group hits by
conversation. See `doc/DEVELOPER_GUIDE.md`, "Message search — room-scoped vs
global" for the caveat as currently documented.

### Scheduled messages have no cancellation UI in the example app

`messages.schedule` / `listScheduled` / `cancelScheduled` exist and are
documented (`doc/DEVELOPER_GUIDE.md`, "Scheduled messages"), but the example
app does not demonstrate them. Low priority — the sub-API is fully covered by
SDK tests; this is example-app coverage debt only.

### `noma_chat_otel` span naming/shape is not customizable

`packages/noma_chat_otel`'s `OtelSpanBuilder` is a `static`-only,
non-instantiable (`abstract final`) class: `spanNames` cannot be overridden
at runtime and the class cannot be subclassed, despite its README describing
"Override the default mapping via `OtelSpanBuilder.spanNames`" as if it were
a supported customization point. A consumer that needs different span names
or richer span shape (durations instead of instantaneous spans, custom
attribute mapping) has to fork `nomaChatOtelCallback` today. Tracked here
rather than fixed because `packages/noma_chat_otel/lib/**` is outside this
pass's file ownership (docs + `test/golden/` only).
