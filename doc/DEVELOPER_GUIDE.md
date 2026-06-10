# noma_chat — Developer Guide

Complete technical reference for integrating and customizing `noma_chat`.

**Contents**

1. [Architecture](#architecture)
2. [Setup & configuration](#setup--configuration)
3. [NomaChat facade](#nomachat-facade)
4. [SDK — sub-APIs](#sdk--sub-apis)
5. [Real-time modes](#real-time-modes)
6. [Events](#events)
7. [Cache](#cache)
8. [UI components — controllers](#ui-components--controllers)
9. [UI components — widgets](#ui-components--widgets)
10. [Customization hooks](#customization-hooks)
11. [Theming](#theming)
12. [Localization](#localization)
13. [Testing](#testing)
14. [Troubleshooting](#troubleshooting)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Your Flutter app                  │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│                  NomaChat (facade)                  │
│  ┌───────────────┐  ┌──────────────────────────┐   │
│  │  ChatClient   │  │     HiveChatDatasource    │   │
│  │  (8 sub-APIs) │  │  (persistent Hive cache)  │   │
│  └───────┬───────┘  └──────────────────────────┘   │
│          │  ┌──────────────────────────────────┐    │
│          └──│       ChatUiAdapter              │    │
│             │  (bridges SDK → UI controllers)  │    │
│             └──────────────┬─────────────────--┘    │
└────────────────────────────┼────────────────────────┘
                             │
             ┌───────────────┴──────────────┐
             │                              │
   ┌─────────▼──────────┐       ┌──────────▼──────────┐
   │   ChatController   │       │ RoomListController  │
   │  (single room UI)  │       │  (room list UI)     │
   └────────────────────┘       └─────────────────────┘
```

**Three layers:**

- **ChatClient** — pure SDK, no Flutter dependency. Handles transport, auth, retry, circuit breaker. Pluggable: bring your own implementation via `NomaChat.fromClient()`.
- **HiveChatDatasource** — local persistence. Caches messages, rooms, receipts. Transparent to consumers; the facade wires it automatically when `cache:` is provided.
- **ChatUiAdapter** — stateful bridge. Subscribes to `ChatClient.events`, maintains a DM contact-to-room index, drives `ChatController` and `RoomListController` with live updates.

---

## Setup & configuration

### Minimal

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
);
await chat.connect();
```

### With persistent cache

```dart
final chat = await NomaChat.create(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),
  cache: await HiveChatDatasource.open(),
);
```

### Full ChatConfig reference

```dart
final chat = await NomaChat.create(
  // Required
  baseUrl: 'https://chat.myapp.com/v1',   // REST base URL
  realtimeUrl: 'https://chat.myapp.com',  // WebSocket / SSE base URL
  tokenProvider: () => authService.getToken(),
  currentUser: ChatUser(id: userId, displayName: name),

  // Optional
  cache: await HiveChatDatasource.open(), // persistent cache; omit for in-memory
  config: ChatConfig(
    realtimeMode: RealtimeMode.auto,       // see Real-time modes
    logger: ChatConfig.debugOnlyLogger,    // prints to console in debug builds
    enableHttpLog: false,                  // log full HTTP request bodies
    hiveInitialized: false,                // set true if you call Hive.initFlutter() yourself
  ),
  isDmRoom: (detail) =>                    // see Customization hooks
      detail.type == RoomType.oneToOne &&
      detail.custom?['type'] == 'dm',
);
```

### Teardown

```dart
await chat.disconnect();
chat.dispose();
```

Call `dispose()` to release controllers and close Hive boxes. Typically in your top-level widget's `dispose()`.

---

## NomaChat facade

| Member | Description |
|---|---|
| `chat.client` | Raw `ChatClient` — 8 sub-APIs |
| `chat.adapter` | `ChatUiAdapter` — drives UI controllers |
| `chat.connect()` | Opens real-time connection |
| `chat.disconnect()` | Closes transport gracefully |
| `chat.dispose()` | Frees all resources |
| `chat.currentUser` | The `ChatUser` passed at creation |

### Pre-configured client

Use `NomaChat.fromClient()` when you need to inject a custom or pre-wired `ChatClient` (e.g. from a DI container):

```dart
final chat = NomaChat.fromClient(
  client: myCustomClient,
  currentUser: ChatUser(id: userId, displayName: name),
  isDmRoom: (detail) => ...,
);
```

---

## SDK — sub-APIs

Access all sub-APIs through `chat.client`:

```dart
chat.client.rooms
chat.client.messages
chat.client.members
chat.client.users
chat.client.contacts
chat.client.presence
chat.client.attachments
chat.client.auth
```

### Rooms

```dart
// List joined rooms
final rooms = await chat.client.rooms.list();

// Get a specific room
final detail = await chat.client.rooms.get(roomId);

// Create a room
await chat.client.rooms.create(
  name: 'Team Alpha',
  audience: RoomAudience.private,
);

// Update room config
await chat.client.rooms.updateConfig(roomId, name: 'New name');

// Mute / pin / hide
await chat.client.rooms.mute(roomId);
await chat.client.rooms.pin(roomId);
await chat.client.rooms.hide(roomId);

// Discover public rooms
final results = await chat.client.rooms.discover(query: 'flutter');

// Delete (owner only)
await chat.client.rooms.delete(roomId);
```

### Messages

```dart
// Send
await chat.client.messages.send(
  roomId,
  SendMessageRequest(
    text: 'Hello!',
    replyTo: parentMessageId,   // optional thread reply
    metadata: {'custom': true}, // optional custom payload
  ),
);

// Send via WebSocket (transport-agnostic; falls back to REST)
await chat.client.messages.sendViaWs(roomId, request);

// Fetch paginated
final page = await chat.client.messages.getAll(roomId, limit: 30);

// Search
final hits = await chat.client.messages.search(roomId, query: 'flutter');

// Edit / delete
await chat.client.messages.update(roomId, messageId, text: 'Edited');
await chat.client.messages.delete(roomId, messageId);

// Mark as read
await chat.client.messages.markAsRead(roomId, messageId);
await chat.client.messages.batchMarkAsRead([roomId1, roomId2]);

// Confirm delivery (double gray tick) — cursor semantics: one call per
// conversation covers every message at-or-before the given one, for any
// author. Idempotent (the server max-merges; older cursors are no-ops).
// With `ChatUiAdapter.autoConfirmDelivery` (default true) the adapter
// fires this automatically on live messages, chat load and the
// post-login room sync; call it manually only when that flag is off.
await chat.client.messages.markRoomAsDelivered(
  roomId,
  lastDeliveredMessageId: newestMessageId,
);

// Unread counts
final counts = await chat.client.messages.batchGetUnread([roomId1, roomId2]);

// Pins
await chat.client.messages.pin(roomId, messageId);
await chat.client.messages.unpin(roomId, messageId);

// Scheduled messages
await chat.client.messages.schedule(roomId, request, sendAt: futureDate);

// Clear room history (own messages only by default)
await chat.client.messages.clearChat(roomId);
```

### Members

```dart
await chat.client.members.add(roomId, userId: targetUserId);
await chat.client.members.remove(roomId, userId: targetUserId);
await chat.client.members.leave(roomId);
await chat.client.members.updateRole(roomId, userId: targetUserId, role: MemberRole.admin);
```

### Contacts & DMs

```dart
// Add / remove contacts
await chat.client.contacts.add(userId);
await chat.client.contacts.remove(userId);
final contacts = await chat.client.contacts.list();

// Get DM conversation messages
final messages = await chat.client.contacts.getConversationMessages(userId);

// Block / unblock
await chat.client.contacts.block(userId);
await chat.client.contacts.unblock(userId);
final blocked = await chat.client.contacts.listBlocked();
```

### Presence

```dart
final status = await chat.client.presence.get(userId);
final statuses = await chat.client.presence.getAll([userId1, userId2]);
await chat.client.presence.update(PresenceStatus.online);
await chat.client.presence.update(PresenceStatus.dnd);
```

### Attachments

```dart
// Upload a file and send in one step (UI components helper)
await chat.client.attachments.sendAttachment(
  roomId,
  filePath: '/path/to/image.jpg',
  mimeType: 'image/jpeg',
);

// Low-level upload / download
final url = await chat.client.attachments.upload(roomId, filePath);
await chat.client.attachments.download(url, saveTo: localPath);

// List and clean up
final files = await chat.client.attachments.listInRoom(roomId);
await chat.client.attachments.deleteInRoom(roomId, attachmentId);
```

---

## Real-time modes

Set via `ChatConfig.realtimeMode`:

| Mode | Behaviour |
|---|---|
| `RealtimeMode.auto` *(default)* | WebSocket first; falls back to SSE, then polling if WS fails or is unavailable. Reconnects automatically. |
| `RealtimeMode.webSocketOnly` | WS only. Throws if connection fails. |
| `RealtimeMode.serverSentEventsOnly` | SSE only. Good for environments where WS is blocked. |
| `RealtimeMode.polling` | HTTP long-poll. Higher latency, no server push. |
| `RealtimeMode.manual` | No automatic transport. Call `chat.client.refresh()` or `chat.client.refreshRoom(roomId)` to pull updates. |

### Manual refresh

```dart
// Refresh all rooms and messages
await chat.client.refresh();

// Refresh a specific room only
await chat.client.refreshRoom(roomId);
```

---

## Events

Subscribe to the raw event stream from `ChatClient`:

```dart
chat.client.events.listen((event) {
  switch (event) {
    case NewMessageEvent(:final message):
      print('New message: ${message.text}');
    case MessageUpdatedEvent(:final message):
      // ...
    case PresenceChangedEvent(:final userId, :final status):
      // ...
    // ...
  }
});
```

### Full event catalogue

| Event | Payload |
|---|---|
| `NewMessageEvent` | `message: ChatMessage` |
| `MessageUpdatedEvent` | `message: ChatMessage` |
| `MessageDeletedEvent` | `messageId`, `roomId` |
| `RoomCreatedEvent` | `room: RoomDetail` |
| `RoomUpdatedEvent` | `room: RoomDetail` |
| `RoomDeletedEvent` | `roomId` |
| `UserJoinedEvent` | `userId`, `roomId` |
| `UserLeftEvent` | `userId`, `roomId` |
| `UserRoleChangedEvent` | `userId`, `roomId`, `role: MemberRole` |
| `ReceiptUpdatedEvent` | `roomId`, `receipts: List<ChatReceipt>` |
| `MessageAckedEvent` | `roomId?`/`toUserId?` (room vs DM form), `messageId`, `seq: int`, `metadata?` — the server durably persisted an own message (single gray tick). Correlate WS sends by echoing a client id in the message `metadata`. |
| `MessageDeliveredEvent` | `roomId?` (absent in the DM form), `userId` (the confirmer), `messageId`, `seq: int` — the confirmer's delivered cursor advanced: every message at-or-before `messageId` is delivered to them. |
| `UserActivityEvent` | `userId`, `roomId`, `activity: UserActivity` |
| `DmActivityEvent` | `userId`, `activity: UserActivity` |
| `PresenceChangedEvent` | `userId`, `status: PresenceStatus` |
| `ReactionAddedEvent` | `messageId`, `reaction: ChatReaction` |
| `ReactionDeletedEvent` | `messageId`, `reactionId` |
| `BroadcastEvent` | `payload: Map<String, dynamic>` |
| `UnreadUpdatedEvent` | `roomId`, `count: int` |

---

## Cache

`HiveChatDatasource` wraps Hive CE. Pass it to `NomaChat.create()` to enable persistence:

```dart
cache: await HiveChatDatasource.open()
```

Without it, the SDK uses a no-op in-memory store that discards data on restart.

### Advanced cache options

```dart
cache: await HiveChatDatasource.open(
  encryptionKey: myEncryptionKey,   // AES-256 at-rest encryption
  messageTtl: Duration(days: 30),   // auto-evict old messages
  evictionPolicy: EvictionPolicy.lru,
)
```

### Backup and restore

```dart
final backup = await cache.export();
await cache.import(backup);
```

---

## UI components — controllers

### ChatController

Manages state for a single chat room. Feed it to `ChatView`:

```dart
final controller = ChatController(chat: chat, roomId: roomId);

// In widget
ChatView(controller: controller)

// Active room tracking (auto-marks as read)
controller.setActive(true);

// Manual send (when not using ChatView's built-in input)
await controller.send(SendMessageRequest(text: 'Hello'));

// React
await controller.addReaction(messageId, emoji: '👍');
await controller.removeReaction(messageId, reactionId: id);

// Forward
await controller.forwardMessage(messageId, toRooms: [roomId1, roomId2]);

// Dispose when done
controller.dispose();
```

### RoomListController

Manages the full room list:

```dart
final controller = RoomListController(chat: chat);

RoomListView(controller: controller)

// Handle invitations
controller.onInvitationAccepted = (roomId) { /* navigate */ };
controller.onInvitationRejected = (roomId) { /* show snackbar */ };

controller.dispose();
```

---

## UI components — widgets

### Core screens

| Widget | Purpose |
|---|---|
| `ChatView` | Full chat screen with input, bubble list, app bar |
| `RoomListView` | Paginated room list with unread badges, mute/pin/hide options |
| `GroupSetupPage` | Multi-step group creation flow |
| `GroupInfoPage` | Edit group name, avatar, add/remove/promote members |
| `ProfileSettingsPage` | User profile with avatar picker + crop |
| `MediaGalleryPage` | Scrollable gallery of all room attachments |
| `MessageSearchView` | Full-text message search with result highlighting |

### Bubble types

`MessageBubble` dispatches to the appropriate sub-widget based on `ChatMessage.type`:

| Type | Widget |
|---|---|
| Text | `TextBubble` |
| Image | `ImageBubble` |
| Audio | `AudioBubble` |
| Video | `VideoBubble` |
| File | `FileBubble` |
| Link | `LinkPreviewBubble` |
| Location | `LocationBubble` (opens Google Maps by default) |

### Input area

`ChatView` renders a `MessageInput` that includes:
- Text field with @mention autocomplete
- Send button
- Attachment picker sheet (photos, videos, files, location, custom slots)
- Voice recorder with lock-to-record gesture and waveform preview

### Auxiliary widgets

| Widget | Purpose |
|---|---|
| `ChatRoomAppBar` | WhatsApp-style app bar with room title, subtitle, avatar and action menu |
| `QuickRepliesBar` | Horizontally scrollable chips for quick reply suggestions |
| `TypingIndicator` | Animated three-dot bubble |
| `PinnedMessagesBanner` | Tappable banner showing the latest pinned message |
| `ReactionBar` | Per-message emoji summary strip |
| `ReactionPicker` | Full emoji picker sheet |
| `SwipeToReply` | Swipe gesture that sets reply context on the input |
| `ThreadView` | Inline thread reply list |
| `DateSeparator` | Sticky date labels between message groups |
| `MessageStatusIcon` | Sent / delivered / read ticks |
| `UserAvatar` | Network image with fallback initials |

---

## Customization hooks

### isDmRoom

Controls which `oneToOne` rooms are treated as DMs (affects contact-to-room routing, typing indicators, and the lazy DM creation flow):

```dart
isDmRoom: (RoomDetail detail) =>
    detail.type == RoomType.oneToOne &&
    detail.custom?['type'] == 'dm',
```

Omit to use the default: any `RoomType.oneToOne` room is a DM.

### RoomTitleResolver

Controls what title is displayed in `RoomTile` and `ChatRoomAppBar`:

```dart
roomTitleResolver: RoomTitleResolver(
  resolveTitle: (RoomDetail detail, String currentUserId) {
    if (detail.type == RoomType.oneToOne) {
      return detail.members
          .firstWhere((m) => m.userId != currentUserId)
          .displayName;
    }
    return detail.name ?? 'Unnamed';
  },
),
```

### RoomTile builders

`RoomListView` accepts per-slot builder overrides:

```dart
RoomListView(
  controller: controller,
  leadingBuilder: (context, room) => MyCustomAvatar(room),
  trailingBuilder: (context, room) => MyBadge(room.unreadCount),
  subtitleBuilder: (context, room) => MyPresenceRow(room),
  lastMessagePreviewBuilder: (context, message) => MyPreview(message),
  typingUserNameResolver: (userId) => contactBook.getName(userId),
)
```

### AttachmentPickerSheet — extra slots

Add custom options to the attachment picker:

```dart
ChatView(
  controller: controller,
  attachmentPickerExtraOptions: [
    AttachmentPickerOption(
      icon: Icons.location_on,
      label: 'Location',
      onTap: () => myLocationPicker(),
    ),
  ],
  onShareLocation: (context) => myLocationPicker(),
)
```

### ChatRoomOption factories

Build action menus from predefined factories or custom entries:

```dart
ChatView(
  controller: controller,
  roomOptions: [
    ChatRoomOption.muteRoom(controller),
    ChatRoomOption.pinRoom(controller),
    ChatRoomOption.searchMessages(controller),
    ChatRoomOption.mediaGallery(controller),
    ChatRoomOption.reportUser(controller, onReport: (userId) { ... }),
    ChatRoomOption.custom(
      label: 'Export chat',
      icon: Icons.download,
      onTap: () => exportChat(),
    ),
  ],
)
```

### Location bubble

By default `LocationBubble` opens Google Maps when tapped. Override:

```dart
ChatView(
  controller: controller,
  onLocationTap: (lat, lng) => myMapSheet(lat, lng),
)
```

### AvatarStorage

Plug in your own storage backend for uploaded avatars:

```dart
NomaChat.create(
  ...
  avatarStorage: MyS3AvatarStorage(),
)
```

Implement `AvatarStorage` with `upload(Uint8List bytes) → Future<String>` (returns the public URL).

---

## Theming

Pass a `ChatTheme` to `ChatView` and `RoomListView`, or set it globally via your `MaterialApp`:

```dart
ChatView(
  controller: controller,
  theme: ChatTheme.branded(
    accent: Color(0xFF4F46E5),
    contrastingOnAccent: Colors.white,
  ),
)
```

### Factories

| Factory | Description |
|---|---|
| `ChatTheme.lightPreset()` | Full light theme with sensible defaults for every surface |
| `ChatTheme.darkPreset()` | Full dark theme |
| `ChatTheme.resolved(context)` | Picks light or dark based on `MediaQuery.platformBrightnessOf` |
| `ChatTheme.branded(accent:, contrastingOnAccent:)` | Derives ~12 accent slots (bubble, send button, badge, reply bar, audio cue…) from one colour |
| `ChatTheme.highContrast()` | WCAG-AAA preset — white-on-black with 7:1 minimum contrast |

### Sub-theme structure

```dart
ChatTheme(
  // Sub-themes
  bubble: ChatBubbleTheme(...),      // incoming/outgoing colors, radius, padding, text style
  input: ChatInputTheme(...),        // background, hint, send button, attachment icon
  roomList: ChatRoomListTheme(...),  // tile, unread badge, separator
  markdown: ChatMarkdownTheme(...),  // bold, italic, code, link styles

  // Cross-cutting flat slots
  backgroundColor: Color(...),
  primaryColor: Color(...),
  onPrimaryColor: Color(...),
  borderRadius: 12.0,
  // ... 140+ more fields
)
```

See the `ChatTheme` class documentation for the complete field reference.

---

## Localization

Seven locales ship out of the box:

```dart
MaterialApp(
  localizationsDelegates: const [
    ChatUiLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: [
    ...ChatUiLocalizations.supportedLocales,
    // your app locales
  ],
)
```

Supported: `en`, `es`, `fr`, `de`, `it`, `pt`, `ca`.

The SDK falls back to English when no delegate is registered. Widgets access strings through `ChatUiLocalizations.of(context)`.

### Custom strings

Register `ChatUiLocalizations.override(...)` in place of `delegate` to
customise individual strings while keeping the seven bundled locales. The
overrides layer on top of whichever locale is active:

```dart
localizationsDelegates: [
  ChatUiLocalizations.override(
    send: 'Submit',
    writeMessage: 'Write a message…',
  ),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
],
supportedLocales: ChatUiLocalizations.supportedLocales,
```

To scope overrides to a single language, pass `locale:` and chain the
default `delegate` so the other locales keep their bundled copy:

```dart
localizationsDelegates: [
  ChatUiLocalizations.override(locale: const Locale('en'), send: 'Submit'),
  ChatUiLocalizations.delegate, // es/fr/de/it/pt/ca use bundled copy
],
```

Any of the 225 string fields can be overridden; unspecified ones keep the
bundled translation. `copyWith` is also available if you build a
`ChatUiLocalizations` instance directly.

---

## Testing

Import the testing barrel in your test files:

```dart
import 'package:noma_chat/noma_chat_testing.dart';
```

### MockChatClient

`MockChatClient` is a pre-built mock (Mocktail-based) that stubs all sub-API calls:

```dart
final mockClient = MockChatClient();
final chat = NomaChat.fromClient(
  client: mockClient,
  currentUser: testUser,
);

// Stub a call
when(() => mockClient.rooms.list()).thenAnswer((_) async => [testRoom]);

// Inject fake events
mockClient.injectEvent(NewMessageEvent(message: testMessage));
```

To simulate delivery ticks, emit the cursor events the backend would send —
a single `messageDelivered` flips every own message at-or-before the cursor:

```dart
// Single gray tick: the server acked the send (carries the seq).
mockClient.emitEvent(
  const ChatEvent.messageAcked(roomId: 'r1', messageId: 'm2', seq: 2),
);

// Double gray tick: bob's delivered cursor reached m2 (covers m1 too).
mockClient.emitEvent(
  const ChatEvent.messageDelivered(
    roomId: 'r1',
    userId: 'bob',
    messageId: 'm2',
    seq: 2,
  ),
);

// Outbound confirmations are recorded for assertions:
expect(mockClient.messages.markRoomAsDeliveredCalls, isNotEmpty);
```

### Fake adapter

For widget tests that don't need the full facade:

```dart
final adapter = FakeChatUiAdapter(currentUser: testUser);
adapter.injectRoom(testRoom);
adapter.injectMessage(testMessage);

testWidgets('shows message bubble', (tester) async {
  final controller = ChatController.fromAdapter(adapter, roomId: testRoom.id);
  await tester.pumpWidget(ChatView(controller: controller));
  expect(find.text(testMessage.text!), findsOneWidget);
});
```

### Integration tests with real backend

For integration tests against a real CHT instance, wire a real `NomaChat` with a test-environment URL and a fixture JWT. See [TESTING.md](../TESTING.md) for the full setup.

---

## Troubleshooting

### `MissingPluginException` on startup

`NomaChat.create()` calls `Hive.initFlutter()` automatically. If you initialise Hive yourself before calling `NomaChat.create()`, pass `hiveInitialized: true` in `ChatConfig` to skip the double-init.

### WebSocket connects but events never arrive

CHT requires a JWT in the first `auth` frame. Verify `tokenProvider` returns a non-expired token. Enable logging to see the auth frame:

```dart
config: ChatConfig(logger: ChatConfig.debugOnlyLogger)
```

### `ChatAuthException` on every API call

Ensure `tokenProvider` **throws** when the token cannot be refreshed. If it returns a stale token instead, the SDK retries indefinitely without surfacing an error.

### Messages not persisting after a cold restart

Confirm `cache: await HiveChatDatasource.open()` is passed to `NomaChat.create()`. Without it the SDK uses an in-memory no-op store.

### `Invalid argument(s): path must not be null` on web

Call `await Hive.initFlutter()` (or let `NomaChat.create()` do it) before any Hive access. Ensure `hive_ce_flutter` is in your `pubspec.yaml` dependencies.

### Voice recording returns `permissionDenied` on Web

Voice recording is not supported on Web in this release (the recorder stages audio on the local file system). Use `kIsWeb` to hide the record button, or open a feature request.

### `ChatResult` / `ChatSuccess` types not found

You are on `noma_chat` pre-1.0. These types were renamed in the 1.0 release cycle. See [MIGRATING.md](../MIGRATING.md).

### `MockChatClient` not found after upgrading

Mock classes moved to a dedicated barrel. Import `package:noma_chat/noma_chat_testing.dart` in test files.

### Room list shows duplicate DMs after reconnect

The adapter deduplicates `oneToOne` rooms on reconnect using its contact-to-room index. If you see duplicates, verify that `isDmRoom` is consistent (same predicate on every `NomaChat.create()` call in the same session) and that your backend returns the same `roomId` for the same DM pair.
