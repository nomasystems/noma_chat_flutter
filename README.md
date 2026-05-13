# noma_chat

Plug & play Flutter chat package. One dependency, five lines of setup.

## Quick start

```yaml
dependencies:
  noma_chat: ^0.2.0
```

```dart
import 'package:noma_chat/noma_chat.dart';

final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
);
await chat.connect();
```

## What's included

- **SDK** — REST client, WebSocket & SSE real-time transport, auth, retry, circuit breaker, offline queue
- **Cache** — Persistent local storage with Hive CE (opt-in, enabled by default)
- **UI Kit** — Chat view, room list, message bubbles, reactions, typing indicators, voice messages, image viewer, theme, l10n (7 languages)

## Architecture

```
NomaChat (facade)
├── ChatClient          — 8 sub-APIs (messages, rooms, users, contacts, presence, search, threads, pins)
├── HiveChatDatasource  — persistent cache (transparent to the consumer)
└── ChatUiAdapter       — bridges SDK events to UI controllers
```

## Advanced usage

For pre-configured components or custom clients:

```dart
final chat = NomaChat.fromClient(
  client: myCustomClient,
  currentUser: ChatUser(id: userId, displayName: name),
);
```

Access the SDK directly for advanced operations:

```dart
final rooms = await chat.client.rooms.list();
await chat.client.rooms.create(name: 'Team', audience: RoomAudience.public);
```

### Distinguishing DMs from other one-to-one rooms

By default the adapter treats any room with `RoomType.oneToOne` as a DM and
indexes it in its contact-to-room cache (used to route typing indicators and
to look up "the existing DM with this user" from the UI). If your backend
returns `oneToOne` for rooms that are conceptually **not** DMs (for example,
a 1-to-1 group chat tied to a calendar event, or a support channel between an
agent and a user), provide an `isDmRoom` predicate so the adapter only caches
real DMs:

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
  isDmRoom: (detail) =>
      detail.type == RoomType.oneToOne &&
      detail.custom?['type'] == 'dm',
);
```

The predicate receives the full `RoomDetail` (including `type` and `custom`)
and must return `true` only for rooms you want treated as DMs. When the
parameter is omitted, the legacy behaviour is preserved
(`detail.type == RoomType.oneToOne` is enough). The predicate is also
accepted by `NomaChat.fromClient` and by `ChatUiAdapter` directly.

## Example

See the [example app](example/) for a working demo with `MockChatClient`.

## More documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — internal layers, transports, cache, UI adapter
- [INTEGRATION.md](./INTEGRATION.md) — contract with the Noma chat backend (endpoints, auth, real-time, WS close codes, S2S)
- [TESTING.md](./TESTING.md) — conventions, running tests, mocking patterns
- [CHANGELOG.md](./CHANGELOG.md) — version history

## Links

- Source: [github.com/nomasystems/noma_chat_flutter](https://github.com/nomasystems/noma_chat_flutter)
- Issues: [github.com/nomasystems/noma_chat_flutter/issues](https://github.com/nomasystems/noma_chat_flutter/issues)
- License: [Apache-2.0](./LICENSE)
