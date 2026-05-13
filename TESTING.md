# Testing

`noma_chat` ships with **1474+ passing tests** (+ 4 skipped) across the SDK,
cache, UI Kit, integration, accessibility and golden suites. Line coverage
is enforced at **≥80%** in CI.

## What's covered

| Area | What's tested |
| --- | --- |
| `test/sdk/` | Sub-API repositories, transports (WS / SSE / manager), interceptors (auth, retry, circuit breaker), mappers, models, offline queue. |
| `test/cache/` | `HiveChatDatasource` (serialization, eviction, TTL, migrations, corrupt data, 10k-message performance regression guard). |
| `test/ui/` | `ChatController`, `RoomListController`, `MessageSearchController`, `ChatUiAdapter` (events + optimistic ops + operation errors), localizations, theme, utilities, widgets with logic. |
| `test/facade/` | `NomaChat.create` / `fromClient` wiring. |
| `test/integration/` | End-to-end flow against `MockChatClient` (load → open → send → edit → delete → pin → mute). |
| `test/a11y/` | `meetsGuideline` audits for tap-target sizes, labels and contrast on the main widgets. |
| `test/golden/` | 19 golden baselines for bubbles (7 widgets × 2 themes) and outgoing message status icons. |

4 golden tests are intentionally skipped (`ImageBubble` and
`LinkPreviewBubble`, both themes) because `CachedNetworkImage` pulls in
`flutter_cache_manager` → `sqflite` + `path_provider`, which isn't worth
mocking for a widget test in this codebase.

## Running tests

```bash
# Full suite
flutter test

# By area
flutter test test/sdk/
flutter test test/cache/
flutter test test/ui/
flutter test test/integration/
flutter test test/golden/

# Single file
flutter test test/sdk/transport/ws_transport_test.dart

# Coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

For iterative work, use targeted suites. The full set takes a few minutes
and is normally only run before releasing.

### Golden tests

```bash
# Verify (default)
flutter test test/golden/

# Regenerate baselines after an intentional visual change
flutter test --update-goldens test/golden/
```

Always review the new `.png` diffs visually before committing — the whole
point of goldens is catching unintended changes.

## Conventions

### What to test

Tests cover **business logic, not pure presentation**:

- Sub-API repositories (`MessagesApi`, `RoomsApi`, …).
- Controllers — state transitions and event handling.
- Transport layer (`WsTransport`, `SseTransport`, `TransportManager`).
- `EventParser` and all mappers.
- `HiveChatDatasource` — serialization, eviction, TTL, migrations,
  corrupt data resilience.
- `OfflineQueue` — enqueue, dedup, restore, retry strategy.
- Facade wiring — that the right objects are created and connected.
- `ChatUiAdapter` — event-to-controller sync, optimistic actions,
  `operationErrors` stream.
- Utilities (`last_message_preview`, `date_formatter`, `url_detector`,
  `read_receipts_helper`, `markdown_parser`).

Widgets with no behaviour (pure renderers from props) are covered by
golden tests rather than by widget tests. Visual correctness for the rest
relies on the example app and manual QA.

### Mocking

The package uses `mocktail`. Typical pattern:

```dart
class _MockDio extends Mock implements Dio {}
class _FakeRequestOptions extends Fake implements RequestOptions {}

setUpAll(() {
  registerFallbackValue(_FakeRequestOptions());
});

when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async => Response(...));
verify(() => dio.fetch<dynamic>(any())).called(1);
```

### `MockChatClient`

`src/mock/mock_chat_client.dart` is a complete in-memory implementation of
`ChatClient` (sub-APIs, simulated events, configurable latency). It is
re-exported as part of the public API and is used by:

- UI and integration tests.
- The example app (`example/`).
- Consumer apps during development before the real backend is reachable.

### Hive in tests

`HiveChatDatasource` tests use `Hive.init(<temp dir>)` and clean up in
`tearDown`. Each test is isolated.

## CI

The repository's CI workflow is at `.github/workflows/ci.yml`. It runs
on every pull request and push to `main`:

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze --fatal-infos --fatal-warnings`
- `flutter test`
- `dart doc --dry-run`
- `pana` (informational, never blocks).

A red CI is a blocker for merge.

## When you add or change features

Update the relevant suite(s):

- New sub-API method → tests in `test/sdk/api/`.
- New event type → `test/sdk/transport/event_parser_test.dart` +
  `ChatUiAdapter` handler test.
- New cache field → roundtrip test in `test/cache/`.
- New UI widget with logic → `test/ui/widgets/` (logic only).
- New visual bubble or status → golden test in `test/golden/`.
- New model with Freezed → `test/sdk/models/` roundtrip.

When you touch the public API, also update the example app in `example/`
to exercise the new behaviour.

## Known limitations

- The 4 skipped golden tests listed above. Mocking the
  `flutter_cache_manager` chain (with e.g. `sqflite_common_ffi`) would
  unblock them; not done yet because the cost isn't worth the coverage.
- Numeric coverage isn't enforced. Aim for high coverage on business logic
  and keep `flutter test` green.
