# noma_chat example

A small Flutter app that exercises the main pieces of `noma_chat`. It runs in
two modes selected at compile time via `--dart-define=MODE=...`:

- **mock** (default) — wires `MockChatClient` with seeded demo data. Useful
  for trying the UI components and SDK shape without any backend running.
- **cht** — connects to a real `apps/user_client` instance over HTTP Basic
  auth. Shows the onboarding flow you would build into your own app
  (register/login → persist → reconnect on reopen → logout).

## Quick start (mock mode)

```sh
cd example
flutter pub get
flutter run
```

You will see six demo rooms (three DMs, two groups, one announcement
channel) and can play with messages, reactions, pins, search, etc.

## Connecting to a real CHT backend

Compile the example with `MODE=cht` and point it at your backend:

```sh
flutter run \
  --dart-define=MODE=cht \
  --dart-define=BASE_URL=http://localhost:8077/v1 \
  --dart-define=REALTIME_URL=http://localhost:8077
```

On first launch you get an **onboarding screen** asking for a name. The
example posts `POST /v1/users` with HTTP Basic auth (`<name>:`), updates the
display name, and connects. The username is persisted in
`SharedPreferences` so subsequent launches skip onboarding. There is a
**Logout** action in the AppBar overflow menu that clears the persisted
name and returns to onboarding.

### Auto-login for automated runs

Pass `AUTOLOGIN_AS=<username>` to pre-fill the onboarding field and submit
on first frame, skipping any manual interaction:

```sh
flutter run \
  --dart-define=MODE=cht \
  --dart-define=BASE_URL=http://localhost:8077/v1 \
  --dart-define=REALTIME_URL=http://localhost:8077 \
  --dart-define=AUTOLOGIN_AS=alice
```

A subsequent **Logout** within the same session suppresses the auto-login
so the user can enter a different name (otherwise it would relog-loop).

## 0.34.0 feature tour

Beyond the pieces already listed below, this app exercises the SDK
surface added between 0.29.0 and 0.34.0:

| Feature                          | Where                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------- |
| `RoomListView.swipeActionsBuilder` | `home_page.dart` — swipe a row for Pin/Archive shortcuts                               |
| `RoomTile.subtitleHeaderBuilder`   | `catalog_page.dart` — "RoomTile" section, an extra line above the preview              |
| `CameraCapturePage.show` + captions | `chat_room_page.dart` — camera row in the attachment sheet, caption travels to `sendAttachment` |
| `ChatViewBuilders.readOnlyNoticeBuilder` | `chat_room_page.dart` — wired on every room; the notice itself only renders against a backend that reports a read-only room (announcement channel where you are not the owner, `writePolicy: ownerOnly`, or muted), so it stays hidden in mock mode, where `MockChatClient` always reports `RoomRole.owner` |
| `UserDirectoryResolver`           | `chat_session.dart` (`demoUserDirectoryResolver`) — resolves "Dana", a group member the mock chat client never seeded as a user |
| `NomaChat.create`/`fromClient(bootstrapCurrentUser:)` | `chat_session.dart` — mock-mode login                                  |
| `RoomListController.participantNameResolver` | wired automatically by the adapter — search the room list by member name (open a group first so its roster is known) |

## Pages

| Page                  | Feature                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| `home_page`           | Room list (DM, group, announcement) via `RoomListView` + AppBar with Logout in cht mode            |
| `chat_room_page`      | `ChatView` with send/edit/delete/react/reply/pin actions                                           |
| `message_search_page` | `MessageSearchView` + `MessageSearchController`, scroll-to-message via `ChatView.initialMessageId` |
| `pinned_messages_page`| Lists `ChatController.pinnedMessages`, demonstrates optimistic pin/unpin                           |
| `global_error_banner` | Subscribes to `adapter.operationErrors` and shows SnackBars on failure                             |
| `onboarding_page`     | Name picker for cht mode (auto-confirms when `AUTOLOGIN_AS` is set)                                |
| `catalog_page`        | Storybook-style visual catalog of UI components (status icons, avatars, bubbles, `RoomTile`)       |

## Files

- `main.dart` — entry point. Calls `Hive.initFlutter()` (required by
  `NomaChat.create` for the persistent cache) and runs `NomaChatExampleApp`.
- `app.dart` — root widget. Branches on `MODE`: mock mode wires
  `MockChatClient` directly; cht mode reads `SharedPreferences` to restore
  the last username and either skips straight to chat or shows the
  onboarding screen.
- `chat_session.dart` — `openChatSession(mode, username)` factory. In cht
  mode builds `ChatConfig.withAuthInterceptor(BasicAuthInterceptor(...))`,
  registers the user idempotently (`users.create()` ignoring
  `ConflictFailure`), updates display name, and connects.
- `onboarding_page.dart` — text field + "Enter chat" button. Pre-fills and
  auto-confirms when `AUTOLOGIN_AS` is non-empty.
- `chat_provider.dart` — `InheritedWidget` exposing the `NomaChat` instance.
- `mock_data.dart` — seeds the mock client with six rooms and a handful
  of messages of different `MessageType`s. One member of the engineering
  group ("Dana") is never registered as a chat user on purpose — see
  `demoUserDirectoryResolver` in `chat_session.dart`.
