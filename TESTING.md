# Testing

`noma_chat` ships with **908+ tests** across SDK, cache, UI Kit, and facade.

## Status

| Suite | Approx. test count |
|---|---|
| SDK (`test/sdk/`) | ~278 |
| Cache (`test/cache/`) | ~137 |
| UI Kit (`test/ui/`) | ~488 |
| Facade (`test/facade/`) | ~5 |
| **Total** | **~908+** |

A small number of preexisting tests fail in `thread_view_test.dart` and some semantic tests (UI dependencies that drifted). They do not block development.

## Running tests

```bash
# Full suite
flutter test

# By area
flutter test test/sdk/
flutter test test/cache/
flutter test test/ui/

# Single suite
flutter test test/sdk/transport/ws_transport_test.dart

# Coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

For iterative work, use targeted suites. Running the full set takes minutes and surfaces a lot of output you don't need.

## Conventions

### What to test

Tests cover **business logic, not pure presentation** (rule inherited from WB monorepo). Specifically:

- Sub-API repositories (`MessagesApi`, `RoomsApi`, etc.)
- Controllers (`ChatController`, `RoomListController`) — state transitions and event handling
- Transport layer (`WsTransport`, `SseTransport`, `TransportManager`)
- `EventParser` and all mappers
- `HiveChatDatasource` — serialization, eviction, TTL, migrations, corrupt data resilience
- `OfflineQueue` — enqueue, dedup, restore, retry strategy
- DI wiring (facade) — ensure objects are created and connected
- `ChatUiAdapter` — event-to-controller sync, optimistic actions
- Utilities (`last_message_preview`, `date_formatter`, `url_detector`)

**Do not write tests for**: widgets that only render UI from props with no logic. Visual correctness is verified manually and through QA.

### Mocking

Mocks use `mocktail` (not `mockito`). Pattern:

```dart
class _MockDio extends Mock implements Dio {}
class _FakeRequestOptions extends Fake implements RequestOptions {}

setUpAll(() {
  registerFallbackValue(_FakeRequestOptions());
});

when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async => Response(...));
verify(() => dio.fetch<dynamic>(any())).called(1);
```

### MockChatClient

`src/mock/mock_chat_client.dart` is a complete in-memory implementation of `ChatClient` (~30 methods, simulated events, configurable latency). Used for:

- UI integration tests
- The example app
- Consumer apps during development before backend is reachable

### Test data helpers

Build models with sensible defaults using helper constructors in test files:

```dart
ChatMessage testMessage({String? text, MessageType? type, ...}) =>
  ChatMessage(id: 'm1', roomId: 'r1', text: text ?? 'hi', timestamp: DateTime.now(), ...);
```

### Hive in tests

`HiveChatDatasource` tests use `Hive.init(temp_dir)`. Each test is isolated with `tearDown` cleanup.

## CI

Tests run as part of the WB mobile CI pipeline (GitHub Actions). See `WB/.github/workflows/` for details. The package is exercised both standalone and as a dependency of `WB/mobile/`.

## When you add or change features

Update the relevant suite(s):

- New sub-API method → tests in `test/sdk/api/`
- New event type → `test/sdk/transport/event_parser_test.dart` + `ChatUiAdapter` handler test
- New cache field → roundtrip test in `test/cache/`
- New UI widget with logic → `test/ui/widgets/` (logic only, not presentation)
- New model with Freezed → `test/sdk/models/` roundtrip

When you touch the public API, also update the example app in `example/` to demonstrate the new feature.

## Known limitations

- Some preexisting tests in `thread_view_test.dart` and a few semantic tests fail due to UI dependency drift. Tracked but not blocking.
- `chat_ui_adapter` bootstrap tests for presence are pending (require extending `_DmRoomsApi` / `_FailableMembersApi` wrappers with `presence.getAll()` stubs).
- Coverage isn't enforced numerically in pre-release. Aim for high coverage on business logic.
