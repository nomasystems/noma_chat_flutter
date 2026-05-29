# noma_chat example

A small Flutter app that exercises the main pieces of `noma_chat`. It runs in
two modes selected at compile time via `--dart-define=MODE=...`:

- **mock** (default) — wires `MockChatClient` with seeded demo data. Useful
  for trying the UI Kit and SDK shape without any backend running.
- **cht** — connects to a real `apps/user_client` instance over HTTP Basic
  auth. Shows the onboarding flow you would build into your own app
  (register/login → persist → reconnect on reopen → logout).

## Quick start (mock mode)

```sh
cd example
flutter pub get
flutter run
```

You will see three demo rooms (DM, group, announcement) and can play with
messages, reactions, pins, search, etc.

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

## Pages

| Page                  | Feature                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| `home_page`           | Room list (DM, group, announcement) via `RoomListView` + AppBar with Logout in cht mode            |
| `chat_room_page`      | `ChatView` with send/edit/delete/react/reply/pin actions                                           |
| `message_search_page` | `MessageSearchView` + `MessageSearchController`, scroll-to-message via `ChatView.initialMessageId` |
| `pinned_messages_page`| Lists `ChatController.pinnedMessages`, demonstrates optimistic pin/unpin                           |
| `global_error_banner` | Subscribes to `adapter.operationErrors` and shows SnackBars on failure                             |
| `onboarding_page`     | Name picker for cht mode (auto-confirms when `AUTOLOGIN_AS` is set)                                |

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
- `mock_data.dart` — seeds the mock client with three rooms and a handful
  of messages of different `MessageType`s.
