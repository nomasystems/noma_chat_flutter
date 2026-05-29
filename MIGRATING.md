# Migration guide

## 0.5.x → 0.6.x

### Breaking: type renames

Several types were prefixed with `Chat` to avoid collisions with types from
other packages (`result_dart`, `dartz`, pagination helpers, etc.).

| Before (0.5.x)              | After (0.6.x)                 |
| --------------------------- | ----------------------------- |
| `Result<T>`                 | `ChatResult<T>`               |
| `Success<T>`                | `ChatSuccess<T>`              |
| `Failure`                   | `ChatFailureResult`           |
| `PaginationParams`          | `ChatPaginationParams`        |
| `CursorPaginationParams`    | `ChatCursorPaginationParams`  |
| `PaginatedResponse<T>`      | `ChatPaginatedResponse<T>`    |
| `SortOrder`                 | `ChatSortOrder`               |

`ChatFailure` (the sealed base class for all domain-specific failures) keeps
its name — only the `Failure` result-wrapper type that was distinct from it
was renamed to `ChatFailureResult`.

**Before:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final Result<PaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: PaginationParams(limit: 20, sortOrder: SortOrder.desc),
  );

  switch (result) {
    case Success(:final value):
      // use value.items
    case Failure(:final failure):
      // handle failure
  }
}
```

**After:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final ChatResult<ChatPaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: ChatPaginationParams(limit: 20, sortOrder: ChatSortOrder.desc),
  );

  switch (result) {
    case ChatSuccess(:final value):
      // use value.items
    case ChatFailureResult(:final failure):
      // handle failure
  }
}
```

**Cursor pagination:**

```dart
// Before
final params = CursorPaginationParams(cursor: lastCursor, limit: 50);
// After
final params = ChatCursorPaginationParams(cursor: lastCursor, limit: 50);
```

### Breaking: mock classes moved to a testing barrel

`MockChatClient` and its eight `Mock*Api` siblings were removed from the
primary `package:noma_chat/noma_chat.dart` barrel. Import the dedicated
testing barrel in test files:

```dart
// Before
import 'package:noma_chat/noma_chat.dart'; // exposed MockChatClient

// After
import 'package:noma_chat/noma_chat_testing.dart'; // all Mock*Api siblings
```

The primary barrel is unchanged for production imports.

### Behaviour change: RetryInterceptor

Non-idempotent verbs (POST, PATCH, DELETE) are no longer retried on transient
connection errors by default. If you have a POST endpoint that is safe to
replay (e.g. because it is idempotent on your backend), opt in per request:

```dart
await chat.client.messages.sendCustom(
  roomId: roomId,
  payload: myPayload,
  extra: {'idempotent': true}, // opt-in replay for this call
);
```

### New: `ChatConfig.developerLogger` / `debugOnlyLogger`

Two ready-made logger callbacks are now available as static helpers on
`ChatConfig` — no need to wire `dart:developer` manually:

```dart
// Before
import 'dart:developer' as dev;
final chat = await NomaChat.create(
  // …
  logger: (level, msg) => dev.log(msg, name: 'noma_chat'),
);

// After
final chat = await NomaChat.create(
  // …
  logger: ChatConfig.debugOnlyLogger, // silent in release, developer.log in debug
);
```

### New: `MetricCallback` (observability)

Wire a metric sink to capture SDK-emitted telemetry events:

```dart
final chat = await NomaChat.create(
  // …
  metricCallback: (name, data) => myAnalytics.record(name, data),
);
```

See [TELEMETRY.md](./TELEMETRY.md) for the full event catalog.
