# `noma_chat` — API & code conventions

This document codifies the patterns the SDK follows so any new widget,
adapter method, or extension point lands consistently. It is binding
for SDK code (everything under `lib/src/`); the `example/` app and
external consumers SHOULD follow it but are not gated.

## 1. Callback naming

| Suffix      | Sync? | Returns        | Purpose                                                                   |
|-------------|-------|----------------|---------------------------------------------------------------------------|
| `*Resolver` | sync  | `T?` / `T`     | Local resolution (id → name/avatar) from caches the host already holds.   |
| `*Fetcher`  | async | `Future<T>`    | Network/IO load (Cognito profile, remote avatar metadata, …).             |
| `*Builder`  | sync  | `Widget`       | Flutter convention. Receives `(BuildContext, ...)`.                       |
| `*Formatter`| sync  | `String`       | Locale-aware or domain-specific formatting (e.g. date, currency).         |
| `on*`       | sync  | `void`         | User event callback (`onTap`, `onSelected`). Errors propagated elsewhere. |

Examples (canonical):

```dart
typedef DisplayNameResolver = String? Function(String userId);
typedef UserFetcher = Future<ChatUser> Function(String userId);
typedef AvatarBuilder = Widget Function(BuildContext context, String userId);
typedef DateFormatter = String Function(DateTime when);
```

When a slot is inline on a widget (no public typedef), match the suffix:

```dart
final String? Function(String userId)? displayNameResolver;  // ✅
final String? Function(String userId)? userDisplayName;      // ❌ rename
final Future<X> Function(...)?         someResolver;         // ❌ rename → *Fetcher
```

## 2. Return type policy

| Layer                     | Returns                          | Why                                       |
|---------------------------|----------------------------------|-------------------------------------------|
| `client.X.foo(...)`       | `Future<Result<T>>`              | All API calls expose typed failures.      |
| `adapter.foo(...)`        | `Future<Result<T>>`              | Wraps API + emits to `operationErrors`.   |
| Controller mutations      | `void` (notifies listeners)      | Reactive surface.                         |
| Widget `show()` (no data) | `Future<void>`                   | Side-effect only sheets/pages.            |
| Widget `show()` (has data)| `Future<X?>` (null = cancelled)  | Picker/edit flows that produce a value.   |

The SDK never throws across public API boundaries. Internal errors are
caught and turned into `Result.Failure(ChatFailure)` of the appropriate
subtype (`AuthFailure`, `NetworkFailure`, `StorageFailure`, …).

## 3. Theme & default values

* Every widget accepts `theme: ChatTheme = ChatTheme.defaults` and reads
  every visual property through it. Hardcoded `Color`/`TextStyle` are
  forbidden in widget bodies — always `theme.X ?? DefaultPalette.Y`.
* `DefaultPalette` (`lib/src/ui/theme/default_palette.dart`) holds the
  fallback colors used by the SDK out of the box. Add new fallbacks
  there before sprinkling new `Color(0xFFXXXXXX)` literals.
* Numeric defaults (durations, lengths, sizes) live in `RoomDefaults`
  (`lib/src/ui/room_defaults.dart`). Examples:
  `RoomDefaults.searchDebounce`, `RoomDefaults.minGroupNameLength`,
  `RoomDefaults.avatarUploadMaxBytes`. Add new ones there.

## 4. L10n keys

* Every user-facing string sits in `ChatUiLocalizations`. No hardcoded
  English in widget code (`Text('Loading…')` is forbidden).
* Widgets read strings through `theme.l10nOf(context)`, never through
  `theme.l10n` directly — `Text(theme.l10nOf(context).loading)`. The
  `l10nOf` extension (`ChatThemeL10n`, in `chat_theme.dart`, so it comes
  with the import every widget already has) returns the instance the host
  put on `ChatTheme.l10n`, or the one published by the `Localizations`
  ancestor when the theme carries the default. Reading `theme.l10n`
  directly makes the widget deaf to `ChatUiLocalizations.delegate` and to
  runtime locale changes.
* A method that needs a string but has no `BuildContext` takes one
  (`String _label(BuildContext context)`) and the caller in `build` passes
  it along. Only helpers that already receive a resolved
  `ChatUiLocalizations` are exempt — the adapter layer
  (`lib/src/ui/adapter/`) is one of them: it has no context and keeps its
  own injected `l10n`.
* **Never persist a string the adapter composed.** It would be frozen in the
  language of the session that wrote it, which is not the one the reader
  will necessarily have on screen, and it would sit in the same field as
  text a person typed — where telling the two apart afterwards is guesswork.
  Persist the ingredients instead — a type, an emoji, ids, display names, a
  "who is the local user" flag — and rebuild the sentence at paint time from
  a pure function that takes `ChatUiLocalizations`:
  `buildLastMessagePreview` for room-list rows,
  `localizedSystemMessageText` for membership banners. A stored string is
  the fallback for rows written before the ingredients existed, never the
  primary source.
* What is left over — a string the SDK genuinely cannot rebuild from a row,
  today only the self-chat title — follows `ChatUiAdapter.l10n`: every
  handler reads it on each use, so the swap is in place and cannot fail, and
  the setter re-stamps the rows that carry it. `NomaChatView` and
  `RoomListView` push the ambient bundle in on `didChangeDependencies`
  (`adoptAmbientL10n`), so registering the delegate is enough and a host
  that assigns `l10n` itself is never overridden.
* **Closed:** `MessageSearchView`'s opening prompt and its result count were
  `en`/`es` literals inside `message_search_delegate.dart`; they are now the
  bundle keys `searchPromptEmpty` and the `searchResultCountSingularTemplate`
  / `searchResultCountPluralTemplate` pair, read through
  `l10n.searchResultCount(count)` so the plural form follows the locale's
  CLDR category instead of `count == 1`. The two per-call overrides
  (`emptyPromptText`, `resultCountLabelBuilder`) still win over the bundle.
  The singular/plural pair is why the key is not the single
  `searchResultCountTemplate` this bullet used to propose.
* Templates use `{n}`, `{user}`, `{count}` placeholders consumed via
  `String.replaceAll`. Helpers in `chat_ui_localizations.dart` wrap the
  most common cases (`feedbackForwarded(count)`, etc.).
* New keys must land with translations in `en` (canonical) and `es`
  (first-class). Other locales (fr/de/it/pt/ca) accept best-effort
  translations on the same PR; locales without an override fall back to
  `en` automatically.
* The Nordic + Eastern-EU tier (sv/no/da/pl/cs) carries a documented core
  set instead of the whole file, and the English fallback covers the rest.
  A new key that belongs to that set — the composer, the chat list, the
  connection banner, **message actions and their confirmations**, group
  management, settings, presence — is translated there in the same change
  as everywhere else. Leaving a destructive-action dialog to the fallback
  is not "an explicit gap", it is a confirmation the reader cannot read.
  The 2026-08 batch (`searchPromptEmpty`, the `searchResultCount*` pair,
  `receiptNoExactTime`, `receiptAtLatestTemplate`, the
  `deliveryStatusLegend*` keys and the `status*Description` sentences) sits
  outside that set — a search screen and two explanatory surfaces, none of
  them a decision the reader has to make — so it ships in en/es/fr/de/it/pt/ca
  and rides the English fallback in that tier.

## 5. Models — `==` and `copyWith`

* Identity-bearing models (anything with a stable server id —
  `ChatMessage`, `ChatRoom`, `ChatUser`, `ChatRoomDetail`) use
  **id-only equality** (`other.id == id`). Mutations through the adapter
  re-emit the same record; identity stays under the id.
* Value-like denormalisations used by list-view rebuild paths
  (`UnreadRoom`, `RoomListItem`) use **full-field equality** so a
  `ListenableBuilder` notices when only the badge / preview changes.
* All immutable models expose `copyWith`. New fields must extend it.

## 6. Adapter — internal state

The adapter holds N independent state clusters (controllers, DM
mapping, typing throttle, voice upload progress, attachment-upload
cancel tokens, user cache, blocked users, …). Today they live as
separate fields on the class with section comments grouping them. A
future milestone (1.0) will wrap each cluster in a private struct
(`_TypingState`, `_VoiceState`, `_UserCacheState`, …) so
`disconnect()` / `signOut()` iterate one container instead of
remembering to clear N maps. Until then:

* Every new state field MUST be cleared in **both** `disconnect()` and
  `signOut()`. Forgetting one is the bug class the struct refactor
  prevents at the type level.
* Async methods that mutate state after `await` MUST check `_disposed`
  before applying the result. `_ensureUserCached` / `loadMessages` are
  the canonical examples.

## 7. SDK vs example responsibility

* The example app under `example/lib/` is **wiring only** — it composes
  SDK widgets, holds dart-define configuration, and decorates its own
  AppBars. Anything else (data fetching, user lookup, suggestion
  discovery, group creation flow, profile editing, …) lives in the
  SDK and the example consumes it.
* If a helper would be useful to any consumer (WB/mobile, others),
  promote it to `lib/src/utils/` or surface it through the adapter.
  Examples in this release: `StableUserId.forDisplayName(...)`,
  `SuggestionBarController`, `initialsOf(name)`, `DefaultPalette`.

## 8. Breaking changes & deprecation

* Pre-1.0 the SDK does NOT keep deprecated APIs around. Renames /
  removals land as hard breaks in the same change, documented in
  `CHANGELOG.md` under `[Unreleased]/Changed` or `Removed`.
* The consumer is expected to migrate via a `search-and-replace`
  snippet documented in the same CHANGELOG entry.
* After 1.0 this flips: deprecated APIs survive at least one minor
  before removal, with `@Deprecated('Use X instead. Removed in 2.0.')`
  annotations.

## 9. Deferred refactors (milestone 1.0)

These improvements are tracked but explicitly deferred because the
cost (refactor + risk + test surface) outweighs the current pain:

* **Full Freezed migration** of all 19 models. Today the broken
  equality on `UnreadRoom` is fixed manually; the rest of the models
  follow the id-equality / `copyWith` policy above without Freezed.
* **`ChatTheme` sub-configs** (`BubbleThemeConfig`, `InputThemeConfig`,
  …). The current flat 460+ field class is monolithic but stable;
  splitting would touch every widget that reads `theme.X` (~100 sites)
  for marginal benefit before 1.0.
* **User cache unification** — `_userCache` (memory) and
  `ChatLocalDatasource` (disk) are independent today. Merging would let
  cold-starts surface user details fetched in a previous session, but
  requires extending the datasource API and migrating call sites.

When you land work on any of these, update this section so the next
person knows it's done.

## 10. Emerging patterns

Patterns that solidified during the Phases 1–7 audit cycle. Apply them
to any new or refactored code in `lib/src/`.

### 10.1 Sealed result type — `ChatResult<T>`

Public SDK methods return `Future<ChatResult<T>>`. The two concrete
subtypes are `ChatSuccess<T>` (success branch, carries `.data`) and
`ChatFailureResult<T>` (failure branch, carries `.failure`). The
sealed class makes `switch` exhaustive, which is the preferred
consumption pattern:

```dart
final result = await client.rooms.createRoom(...);
switch (result) {
  case ChatSuccess(:final data):
    // use data
  case ChatFailureResult(:final failure):
    // handle failure
}
```

Convenience helpers (`fold`, `getOrElse`, `map`, `flatMap`,
`castFailure`, `mapFailure`) cover the common idioms; use them instead
of repeated `switch` blocks. The old informal `Result<T>` name still
appears in some doc comments — always use `ChatResult<T>` in new code.
See `lib/src/core/result.dart`.

### 10.2 `_asString` guard for JSON string fields

Any JSON field that might arrive from the backend as a non-string type
(number, list, null) must be extracted with an `is String` guard, never
with a bare `as String?` cast. The canonical form is a private static
helper that mirrors the one in `EventParser`:

```dart
static String? _asString(Object? value) => value is String ? value : null;
```

Add this helper at the top of the parser or mapper class and call it
for every string field extracted from a raw `Map<String, dynamic>`.
The inline one-liner (`value is String ? value as String : null`) is
acceptable when the helper would only be called once. Never write
`json['field'] as String?` — a `TypeError` will be thrown at runtime if
the backend sends `42` or `[]` where a string is expected, and this
class of bug is invisible in tests that use well-typed fixtures. See the
`EventParser` and `RoomMapper` implementations for reference.

### 10.3 Metric emission for observable SDK events

Any code path that a consumer might want to observe (reconnect,
disconnect, error, cache miss, token refresh, …) must emit a metric via
the `MetricCallback` wired through `ChatConfig`:

```dart
_metricCallback?.call('event_name', {'key': value, ...});
```

The callback type is `void Function(String metric, Map<String, dynamic> data)`
(see `lib/src/_internal/cache/cache_manager.dart`). Metric names use
`snake_case`. When you add a new observable event, add a row to
`TELEMETRY.md` with the metric name, the fields emitted, and when it
fires — the callback is the machine-readable contract, `TELEMETRY.md`
is the human-readable one. Do not emit metrics that include PII (user
ids, message bodies, room names).

### 10.4 `@experimental` on in-flux APIs

Any method, class, or typedef that may be renamed, restructured, or
removed before 1.0.0 must carry the `@experimental` annotation from
`package:flutter/foundation.dart`:

```dart
import 'package:flutter/foundation.dart' show experimental;

@experimental
class MyInFluxFeature { ... }
```

This is a compile-time signal to consumers (IDEs surface a warning)
rather than runtime behaviour. Remove the annotation when the API
stabilises. Do not add `@experimental` retroactively to APIs that
consumers are already relying on unless they will actually change.

### 10.5 Per-room write lock for cache mutations

Any method that mutates the per-room message index (save, delete, patch,
clear) must run inside the room lock:

```dart
return _withRoomLock(roomId, () async {
  // all reads + writes to this room's box happen here
});
```

The lock is a promise-chain per room key (`_roomLocks` map):
same-room operations serialise; different-room operations still run in
parallel. Without the lock, two concurrent `saveMessages` calls can
interleave their `await` points and corrupt the id-to-position index,
producing duplicate or missing messages on the next load. Methods that
are called from inside an already-held lock must be suffixed `Unlocked`
(e.g. `_clearMessagesUnlocked`) and must never call `_withRoomLock`
themselves — doing so would deadlock. See
`lib/src/cache/hive_chat_datasource.dart` for the canonical
implementation.

### 10.6 `computeBackoffMs` for all backoff

All exponential-backoff logic must use the shared helper:

```dart
import 'package:noma_chat/src/_internal/util/backoff.dart';

final delay = computeBackoffMs(
  attempt: attempt,         // 0-based
  baseMs: 1000,
  maxMs: 60000,
  jitterMs: 1000,
);
```

Never inline `baseMs * pow(2, attempt)` or a custom jitter formula.
The helper caps the attempt counter, applies jitter before the cap so
the result is never above `maxMs`, and accepts an optional `Random` for
deterministic tests. Using it everywhere means retry behaviour is
uniform across WebSocket reconnects, HTTP retries, and queue flush
attempts. See `lib/src/_internal/util/backoff.dart`.

### 10.7 `RequestOptions.extra` contract

Dio interceptors communicate via `options.extra`. The SDK reserves the
following keys — do not reuse them for other purposes:

| Key | Set by | Read by | Meaning |
|---|---|---|---|
| `'idempotent'` | call sites | `RetryInterceptor` | `true` opts the request into automatic retry on network errors, even for non-GET verbs. Only set this when the operation is genuinely safe to repeat. |
| `'requestId'` | `RestClient` (auto-generated UUID) | `HttpDebugLogger`, `_ObservabilityInterceptor` | Correlates request/response/error log lines. Present in metric payloads as `requestId`. |
| `'_authRetried'` | `BearerAuthInterceptor` | same | Guards against infinite token-refresh loops. Internal; do not read or write from outside the interceptor. |
| `'_retryAttempt'` | `RetryInterceptor` | same | Current retry count. Internal; do not read or write from outside the interceptor. |

To opt a new endpoint into retry:

```dart
await _dio.post(
  '/v1/rooms/$roomId/receipts',
  data: body,
  options: Options(extra: {'idempotent': true}),
);
```

### 10.8 Injection seam + working built-in default

Anything the SDK can do *for* the consumer, it does — and still lets the
consumer replace it. The shape is always the same three pieces:

1. An **abstract class** naming the role (`AvatarStorage`,
   `AttachmentMediaLoader`, `VideoThumbnailer`). Never a bare typedef when
   the collaborator holds state or has more than one method.
2. A **working default implementation** in the same file
   (`DefaultAvatarStorage`, `AuthenticatedAttachmentLoader`,
   `NativeVideoThumbnailer`), wired by the constructor / `NomaChatView` with
   `?? const TheDefault()`.
3. **Zero `required` parameters** on the widget or facade that consumes it.

The test for whether a seam is done right: a host that passes nothing gets
the full behaviour, and a host that passes something never has to reproduce
plumbing the SDK already owns. If turning the feature *off* is a legitimate
choice, ship the no-op implementation too (`NoVideoThumbnailer`) rather than
making the field nullable — `null` reads as "unset", not as "disabled".

Third-party plugins live **behind** the seam, never in the calling code, so
swapping one is a single-file change. Anything the plugin needs that the
caller does not have (a file path where the caller holds bytes) is bridged
inside the default implementation, not threaded through the interface.

Platform coverage is decided by a getter in `PlatformSupport`, not by
`dart:io` checks at the call site, and `pubspec.yaml`'s `platforms:` block
stays at all six regardless — a plugin without an implementation for a
target does not strip this package's platform tags.

### 10.9 Message fields lifted out of `metadata`

The backend round-trips arbitrary message metadata, which is how media
details reach the receiver. A key that the SDK reads on **every** message of
a kind (`mimeType`, `fileName`, `fileSize`, `thumbnailUrl`,
`thumbnailAttachmentId`, `attachmentId`) is lifted to a first-class
`ChatMessage` field. Doing so means touching four places, and missing any
one of them is a silent data-loss bug:

1. `lib/src/models/message.dart` — the field (+ `build_runner`).
2. `MessageMapper._internalMetadataKeys` — so it is stripped from the public
   `metadata` map instead of appearing twice.
3. `MessageMapper.fromDto` — read it back out of `meta` onto the field.
4. `lib/src/cache/serialization.dart` — **both** `messageToMap` and
   `messageFromMap`, or the field silently vanishes on the next cold start.

Keys read by exactly one bubble type and by nothing else (`waveform`,
`duration`, `lat`, `lng`, `linkTitle`) stay in the public `metadata` map and
are read from there. When in doubt, prefer leaving it in `metadata`: lifting
is a breaking change to the model, un-lifting is not.

### 10.10 Fuzz-first testing for parsers

Any new parser (JSON deserializer, event mapper, DTO factory) must have
a fuzz test in `test/sdk/fuzz/`. The test must cover:

1. A fixed corpus of known adversarial inputs (null fields, wrong types,
   empty strings, oversized payloads, Unicode overrides).
2. A property-based loop with `Random(seed)` for reproducibility — use
   a constant seed so CI is deterministic and a failing seed can be
   committed as a regression.

```dart
final random = Random(1337);  // fixed seed — change only when adding new generators

test('100 random inputs do not throw', () {
  for (var i = 0; i < 100; i++) {
    final input = buildRandomInput(random);
    expect(() => MyParser.parse(input), returnsNormally,
        reason: 'iter $i: $input');
  }
});
```

The test must never `expect(result, isNotNull)` on individual random
inputs — only `returnsNormally`. Parsers return `null` for unrecognised
payloads by design. See `test/sdk/fuzz/event_parser_fuzz_test.dart` for
a complete reference.

### 10.11 Test identifiers — one name, published twice

Anything a test or an automation driver has to point at (a button, a field,
a row, a loading/empty/error state) carries a name, and that **same literal**
is published in two places:

```dart
Semantics(
  identifier: 'chat_send_button',
  child: IconButton(key: const ValueKey('chat_send_button'), …),
)
```

Both halves are required because they are read from opposite sides. The
`ValueKey` is what works **inside** the app — `find.byKey` in a widget test,
an `integration_test`, the VM Service. The `Semantics(identifier:)` is what
works **outside** it — Flutter maps it to `resource-id` in an Android
UiAutomator dump and to `accessibilityIdentifier` for XCUITest / idb. Ship
one half and the element is unreachable from the other side; ship two
different strings and every harness needs a translation table.

Naming: `<area>_<element>_<kind>`, lower snake case, English, under the
`chat_` scope prefix — `chat_message_input`, `chat_gallery_media_tab`,
`chat_camera_review_send`. Elements of a collection interpolate their own
id rather than an index (`chat_message_${messageId}_outgoing`,
`chat_starred_item_$messageId`, `chat_gallery_doc_$attachmentId`), and when
the two halves are built in different files the name comes from one shared
helper (`docRowSemanticsId`, `searchResultSemanticsId`) so a mismatch is not
expressible.

A property a harness would otherwise read off a pixel — who wrote a message,
which of two bubbles is mine — is published as a suffix of the name
(`_outgoing` / `_incoming`), never left to the colour, the alignment or a
localised label. The suffix wraps the identity the name already carried, so
the element is still addressed by id and never by position.

Accessibility outranks instrumentation, always:

* Never nest a `Semantics` inside another. If the widget already has one,
  add the `identifier:` parameter to the existing node.
* Never degrade what is already there — a `label`, `hint`, `button`,
  `enabled`, `excludeSemantics` or a custom action stays exactly as it was.
  The identifier is a name, not a description: it is never a substitute for
  a screen-reader label.
* A node added purely to carry a name is bare — `identifier:` only, no
  `container: true`, no `label`, no flags — so it merges into the node the
  widget already publishes instead of creating a sibling that steals focus.

Renaming a key that a list uses for reconciliation is allowed, but the new
name must **wrap the identity the old one carried** (id, or the same tuple
as before), never replace it with a positional one, and any code that parses
the key back (`findChildIndexCallback`) is updated in the same change.

A control that only exists inside a `MessageBubble` (the audio play/speed
controls, the upload cancel/retry targets) still carries both halves, but the
`identifier` half is inert there: the bubble merges its subtree into one
announcement with `excludeSemantics: true`, so no descendant reaches the
semantics tree at all. Name it anyway — the `ValueKey` half works, and the
widget rendered standalone publishes both — and interpolate the message id so
two rows of the same list never answer to the same name.

Uniqueness is a property of a **settled** frame, not of every frame. A
cross-fade or a tab slide keeps the outgoing subtree mounted next to the
incoming one, so a name both of them carry is published twice for the length
of the animation. Do not scope the name to the transition — that hands the
harness two names for one visible control. Document the window in the README
(`Names during a transition`) and settle the frame before addressing it.

A name is proven by a test that asserts on the **semantics tree**, not just
the widget tree: `find.bySemanticsIdentifier(name)` (or
`tester.getSemantics(...)` with `isSemantics(identifier: …, label: …)`) plus
`find.byKey(ValueKey(name))`, under a `tester.ensureSemantics()` handle that
`tearDown` disposes. Turning the semantics tree on in production is the
host's decision — `ensureSemantics` never appears under `lib/`.

Those per-name tests are a registry: they prove the names we know about are
reachable, and they cannot see a control that shipped without one.
`test/a11y/semantics_identifier_sweep_test.dart` closes that gap by reading
`lib/` instead of the tree — any `Semantics` declaring `button`, `link`,
`textField`, `slider`, `onTap`, `onLongPress` or `customSemanticsActions`
without an `identifier:` fails it, and its failure message says what to add.
A control that genuinely has no identity to publish — no id reaches it, so
every instance would answer to one name — is exempted by adding its path and
the reason to the `_unnamedByDesign` map at the top of that file. That map is
for controls that cannot be named, never for controls not yet named.

A `Semantics` node is not always involved, so the same file carries a second
sweep over the Material widgets whose whole purpose is to be tapped —
`IconButton`, `InkWell`, `TextButton`, `ElevatedButton`, `FilledButton` and
their siblings. One of those taking a non-null `onPressed` / `onTap` /
`onLongPress` / `onChanged` / `onSelected`, and not nested inside a
`Semantics` that already publishes an identifier, fails it: an `IconButton`
with a tooltip reads fine to a screen reader and still lands in a native dump
without an `AXUniqueId`. Files whose buttons are known to be unnamed are
listed in `_materialControlsNotYetNamed`, keyed by path and carrying both the
surface they belong to and **how many** unnamed buttons that file holds today.
The count is exact in both directions: adding one more to a listed file fails
the sweep just as a fresh file would, and naming one fails it until the number
comes down. Unlike `_unnamedByDesign` that list is a deferral, not a blessing.

### 10.12 Notices go through `showChatNotice`

No widget under `lib/` calls `ScaffoldMessenger` itself. Every short
message the SDK raises on its own — an unblock that failed, a group that
could not be created, a permission denied — goes through
`showChatNotice(context, message)` (`lib/src/ui/utils/chat_notice.dart`).

`ScaffoldMessengerState.showSnackBar` walks every `Scaffold` registered
with the messenger, and a `Scaffold` unregisters in `dispose`, never in
`deactivate`: publishing from inside the frame that tears a route down
throws, and the notice dies with the caller's remaining work.
`showChatNotice` publishes after the frame when the tree is still
settling, and gives the host one override point — `ChatNoticeScope` — for
presenting notices its own way.

Pass `snackBarBuilder` when the bar needs a shape of its own (margins, an
action, a longer duration); do not rebuild the publication path around it.

### 10.13 Host content in an SDK slot — `XxxBuilder` returning `null`

Where the SDK owns *where* something appears and the host owns *what* it
says, the seam is a nullable `XxxBuilder` field on `ChatViewBuilders` whose
return type is nullable too (`emptyRoomBuilder`, `blockedMessageBuilder`,
`systemMessageBuilder`, `headerBuilder`).

Nullable in both positions on purpose. The field being `null` means the
host wired nothing at all; the *return* being `null` means the host was
asked about this particular item and had nothing to add. A host that only
decorates the rooms it recognizes must be able to say so per call, without
reimplementing the SDK's fallback for the rest.

Three obligations come with a slot like this:

1. The fallback is a **public widget**, not a private helper
   (`DefaultEmptyRoomState`), so a host can wrap or reuse it, and a test can
   assert on it by type.
2. The composable layout is **exported separately** from the fallback
   (`EmptyRoomState` vs `DefaultEmptyRoomState`), so a host can keep the
   SDK's spacing and theming while replacing the content.
3. Whatever the host needs to act arrives in **one immutable argument
   object** (`EmptyRoomInfo`), never as a growing parameter list. Callbacks
   inside it are `null` when the action is unavailable — an empty room that
   cannot be written to hands over `onSendFirstMessage: null` rather than a
   callback that silently does nothing.

`NomaChatView` layers adapter defaults under the host's builders by
rebuilding `ChatViewBuilders` field by field. Every new field must be
copied there too; a slot missing from `_resolveBuilders` is silently
dropped for every host that goes through `NomaChatView`, which is all of
them.

### 10.14 What counts as a link — `UrlDetector`

`UrlDetector` (`lib/src/ui/utils/url_detector.dart`) is the single
definition of "this piece of text is a link" for the whole SDK: the
bubble's markdown parser, the link preview card, the composer preview and
the room's *Links* tab all go through `extractUrls` or `matchAt`. Never add
a second regular expression somewhere else — the two entry points share the
same gates precisely so a string is a link in the bubble exactly when it is
one in the Links list.

A match with an explicit scheme (`https://…`) is always a link. A **bare**
match has to earn it, or every dotted word in prose — `informe.pdf`,
`notas.txt`, a full stop typed without the space after it — turns blue and
sends the reader to a browser error page:

* it starts with `www.`, or
* it carries a path, query or fragment, or
* its last label is a known top-level domain.

The recognised suffixes are a short built-in list: the common generic ones
plus the country codes of the locales the SDK ships. A host whose users
routinely write bare domains under a suffix that list misses adds them once
at start-up:

```dart
UrlDetector.extraTlds.add('barcelona');
```

This is deliberately *not* a `ChatTheme` field: it is not a visual decision,
and a set that every consumer shares does not belong in a sealed per-view
model. Entries are matched case-insensitively, so `'Barcelona'` and
`'barcelona'` are the same suffix.
