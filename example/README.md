# noma_chat example

A small Flutter app that exercises the main pieces of `noma_chat` against a
`MockChatClient`. Use it as a reference when wiring the package into your
own app, or as a sandbox to play with the UI Kit without a real backend.

## Run

```sh
cd example
flutter pub get
flutter run
```

## What is demonstrated

| Page                | Feature                                                    |
| ------------------- | ---------------------------------------------------------- |
| `home_page`         | Room list (DM, group, announcement) via `RoomListView`     |
| `chat_room_page`    | `ChatView` with send/edit/delete/react/reply/pin actions   |
| `message_search_page` | `MessageSearchView` + `MessageSearchController`, scroll-to-message via `ChatView.initialMessageId` |
| `pinned_messages_page` | Lists `ChatController.pinnedMessages`, demonstrates optimistic pin/unpin |
| `global_error_banner` | Subscribes to `adapter.operationErrors` and shows SnackBars on failure |

## Files

- `main.dart` — entry point, runs `NomaChatExampleApp`.
- `app.dart` — boots `MockChatClient`, seeds data, wires the global error
  banner via `MaterialApp.builder`.
- `chat_provider.dart` — `InheritedWidget` exposing the `NomaChat` instance.
- `mock_data.dart` — seeds the mock client with three rooms and a handful
  of messages of different `MessageType`s.

## Wiring against a real backend

Replace the `MockChatClient` creation in `app.dart` with `NomaChat.create`:

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
);
await chat.connect();
```

The rest of the example app keeps working unchanged.
