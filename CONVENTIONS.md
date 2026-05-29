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
  English in widget code (`Text('Loading…')` is forbidden — use
  `theme.l10n.loading`).
* Templates use `{n}`, `{user}`, `{count}` placeholders consumed via
  `String.replaceAll`. Helpers in `chat_ui_localizations.dart` wrap the
  most common cases (`feedbackForwarded(count)`, etc.).
* New keys must land with translations in `en` (canonical) and `es`
  (first-class). Other locales (fr/de/it/pt/ca) accept best-effort
  translations on the same PR; locales without an override fall back to
  `en` automatically.

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
mapping, typing throttle, voice upload progress, user cache, blocked
users, …). Today they live as separate fields on the class with
section comments grouping them. A future milestone (1.0) will wrap
each cluster in a private struct (`_TypingState`, `_VoiceState`,
`_UserCacheState`, …) so `disconnect()` / `signOut()` iterate one
container instead of remembering to clear N maps. Until then:

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

### 10.8 Fuzz-first testing for parsers

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
