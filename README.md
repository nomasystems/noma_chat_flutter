# noma_chat

[![pub package](https://img.shields.io/pub/v/noma_chat.svg)](https://pub.dev/packages/noma_chat)
[![ci](https://github.com/nomasystems/noma_chat_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/nomasystems/noma_chat_flutter/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/nomasystems/noma_chat_flutter/branch/main/graph/badge.svg)](https://codecov.io/gh/nomasystems/noma_chat_flutter)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](./LICENSE)

Full-featured Flutter chat in one dependency. Drop it in, wire five lines, ship.

<p align="center">
  <img src="screenshots/realtime_demo.gif" width="420" alt="Two users chatting in real time with reactions"/>
</p>

---

## What you get

| Layer | What's included |
|---|---|
| **SDK** | REST client · WebSocket / SSE / polling with auto-failover · auth · retry · circuit breaker · offline queue |
| **Cache** | Persistent Hive CE storage — messages, rooms and receipts survive cold restarts |
| **UI components** | 30+ production-ready widgets: bubbles, voice messages, reactions, mentions, threads, group flows, search |

---

## Quick start

```yaml
# pubspec.yaml
dependencies:
  noma_chat: ^0.10.0
  # The default persistent cache is Hive-backed; you initialise it (see below).
  hive_ce_flutter: ^2.3.4
```

```dart
import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noma_chat/noma_chat.dart';

Future<void> main() async {
  // Required before NomaChat.create: the SDK's default Hive cache opens its
  // boxes immediately, so Hive must be initialised first. Skip this only if
  // you disable the cache (`enableCache: false`) or supply your own
  // `localDatasource`.
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final chat = await NomaChat.create(
    baseUrl: 'https://chat.myapp.com/v1',
    realtimeUrl: 'https://chat.myapp.com',
    tokenProvider: () => authService.getToken(),
    currentUser: ChatUser(id: userId, displayName: name),
  );
  await chat.connect();

  runApp(MyApp(chat: chat));
}
```

> Cache disabled? If you pass `enableCache: false` (or your own
> `localDatasource`), you don't need `hive_ce_flutter` or `Hive.initFlutter()`.

Drop the UI into your widget tree:

```dart
// Full chat-room screen — app bar + message list + every room behavior
// (history & pin load, unread divider, group member hydration, blocked /
// room-removed reactions, role-aware context menu, report dialog) auto-wired.
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  onRoomLeft: () => Navigator.of(context).maybePop(),
)

// Room list — the SDK owns the controller; pass currentUserId so the
// own-message ticks and the "You:" group prefix render correctly.
RoomListView(
  controller: chat.roomListController,
  currentUserId: userId,
)
```

`NomaChatView` is the recommended way to render a room. For a fully custom
screen, compose `ChatView` (with your own `ChatController`, app bar and
callbacks) by hand instead — see the [Developer Guide](./doc/DEVELOPER_GUIDE.md#nomachatview).

---

## Screenshots

<p align="center">
  <img src="screenshots/room_list.png" width="200" alt="Room list with unread badges"/>
  &nbsp;&nbsp;
  <img src="screenshots/chat_view.png" width="200" alt="Chat with reactions and mentions"/>
  &nbsp;&nbsp;
  <img src="screenshots/voice_recorder.png" width="200" alt="Voice recorder with lock gesture"/>
  &nbsp;&nbsp;
  <img src="screenshots/group_info.png" width="200" alt="Group info and member management"/>
</p>

---

## Features at a glance

**SDK**
- Real-time: WebSocket → SSE → polling, automatic failover between transports
- Circuit breaker + exponential backoff + offline message queue
- Token rotation without reconnecting
- 8 sub-APIs: auth, users, rooms, members, messages, contacts, presence, attachments
- Global or per-room message search — `messages.search(query)` spans every room the user belongs to; `messages.search(query, roomId:)` stays scoped
- Bidirectional opaque-cursor pagination — page back through history and catch up on newer messages
- Stable, localizable error tokens — branch and translate on `ChatFailure.errorToken` (a snake_case code such as `room_not_found` or `rate_limited`), never on an English string
- GDPR self-service deletion — `users.deleteCurrentUser()` erases the authenticated account, token-scoped so it can't target the wrong user

**Security & observability**
- Standard TLS transport — the SDK relies on the operating system's CA trust store to validate server certificates; it does **not** pin certificates
- Optional at-rest cache encryption — hand `NomaChat.create` a Hive AES cipher and the offline message / room store is encrypted on device
- Structured `logger` + `metricCallback` hooks; an official OpenTelemetry adapter, `noma_chat_otel`, turns every WebSocket / HTTP / cache event into a span with zero boilerplate

**UI components — messages**
- Text, image, audio, video, file and link-preview bubbles
- Voice recording with lock-to-record gesture
- Emoji reactions + reaction picker
- @mentions with autocomplete overlay
- Threaded replies
- WhatsApp-style delivery ticks (sending → sent → delivered → read → failed),
  cursor-based and confirmed automatically
- Per-user read receipts (DM any-read → blue; group all-read → blue)
- Typing indicators
- Forward to multiple rooms
- Pinned messages banner
- Message search

**UI components — rooms & people**
- Room list with unread badges, mute, pin and hide
- WhatsApp-style DM flow (lazy room creation before first message)
- Block / unblock (blocker syncs list; blocked user is never notified)
- Group creation, name + avatar edit, member add / remove / promote
- Profile and avatar management with built-in crop flow
- Media gallery page
- Quick replies bar
- Invitation accept / reject callbacks

**Theme & l10n**
- `ChatTheme` with 155+ fields
- `ChatTheme.branded(accent:)` — derives ~12 accent slots from one colour
- Light / dark presets, high-contrast WCAG-AAA mode
- 7 locales out of the box: `en`, `es`, `fr`, `de`, `it`, `pt`, `ca`

---

## Theming

One line to match your brand:

```dart
theme: ChatTheme.branded(
  accent: Colors.indigo,
  contrastingOnAccent: Colors.white,
)
```

Or full control:

```dart
theme: ChatTheme(
  bubble: ChatBubbleTheme(outgoingColor: Color(0xFF4F46E5)),
  input: ChatInputTheme(backgroundColor: Colors.white),
  roomList: ChatRoomListTheme(unreadBadgeColor: Color(0xFF4F46E5)),
)
```

Even the delivery ticks are replaceable — per state, with SDK fallback:

```dart
bubble: ChatBubbleTheme(
  statusIconBuilder: (context, data) =>
      data.state == MessageDeliveryState.read
      ? Icon(Icons.done_all, size: data.size, color: Colors.teal)
      : null, // SDK default for the other states
)
```

See [Developer Guide — Theming](./doc/DEVELOPER_GUIDE.md#theming) for all 155+ fields.

---

## Platform support

| Platform | Status | Notes |
|---|---|---|
| Android | **Production** | Primary target. Chat, attachments, voice, presence, offline cache exercised end-to-end. |
| iOS | **Production** | Primary target. Same as Android. |
| macOS / Linux / Windows | Best effort | SDK and UI components work; voice uses platform audio backends. Not exercised in production. |
| Web | Limited | SDK, cache (IndexedDB) and audio playback work. Voice **recording** is disabled (filesystem staging). |

---

## Backend

`noma_chat` is built to talk to a **Nomasystems chat backend**. That backend exposes a REST + WebSocket/SSE API described by a public **OpenAPI 3.0 contract** — [browse the rendered API reference](https://redocly.github.io/redoc/?url=https://raw.githubusercontent.com/nomasystems/noma_chat_flutter/main/doc/chat-api-openapi.yml) or read the [source spec](https://github.com/nomasystems/noma_chat_flutter/blob/main/doc/chat-api-openapi.yml). The SDK speaks exactly that contract, so it runs against **any** backend that implements the spec — not only ours.

The Nomasystems chat backend is **planned to be open-sourced, but is not public yet**. To use it as part of a commercial product, get in touch: **[info@nomasystems.com](mailto:info@nomasystems.com)**.

- Integration guide (endpoints, auth, WS frames): [INTEGRATION.md](./INTEGRATION.md)
- Nomasystems: [www.nomasystems.com](https://www.nomasystems.com/)

---

## Documentation

| Document | Contents |
|---|---|
| [Developer Guide](./doc/DEVELOPER_GUIDE.md) | Architecture · all APIs · configuration · theming · customization · events · testing |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Internal layers and data-flow diagrams |
| [INTEGRATION.md](./INTEGRATION.md) | Backend contract (endpoints, auth, WS frames, S2S) |
| [Backend API reference](https://redocly.github.io/redoc/?url=https://raw.githubusercontent.com/nomasystems/noma_chat_flutter/main/doc/chat-api-openapi.yml) | Rendered OpenAPI 3.0.1 (Redoc) · [source spec](https://github.com/nomasystems/noma_chat_flutter/blob/main/doc/chat-api-openapi.yml) |
| [SECURITY.md](./SECURITY.md) | Threat model · what the SDK does and does not guarantee · consumer hardening checklist |
| [MIGRATING.md](./MIGRATING.md) | Step-by-step upgrade guide for every breaking release |
| [CHANGELOG.md](./CHANGELOG.md) | Version history |

---

## When NOT to use

- **Custom backend with incompatible wire protocol** — the SDK speaks the [Nomasystems chat API contract](https://github.com/nomasystems/noma_chat_flutter/blob/main/doc/chat-api-openapi.yml) (REST + WS/SSE, JWT, specific error codes). Any backend that implements that OpenAPI spec works out of the box; for anything else you can plug a custom `ChatClient` via `NomaChat.fromClient()`, but adapting the full contract is non-trivial. Consider whether it fits before adopting.
- **End-to-end encryption** — TLS in transit, with optional at-rest encryption of the on-device cache, but messages are **not** end-to-end encrypted. If E2EE is a hard requirement, use a different SDK.
- **Hard latency SLO under ~100 ms** — the SDK is push-based but does not advertise a real-time SLO. For voice / video signalling, use a dedicated SDK.

---

## Troubleshooting

Common issues and fixes are documented in the [Developer Guide — Troubleshooting](./doc/DEVELOPER_GUIDE.md#troubleshooting) section.

## Development

- Tests: `flutter test -x golden`. Golden (snapshot) tests run on CI/Linux as the
  source of truth — see [`test/golden/README.md`](test/golden/README.md).
- Regenerate golden baselines after a UI change, without a Linux machine:
  `tool/regen_goldens.sh` (drives the `regen-goldens` workflow and pulls the PNGs).

---

## Links

- Nomasystems: [www.nomasystems.com](https://www.nomasystems.com/)
- Source: [github.com/nomasystems/noma_chat_flutter](https://github.com/nomasystems/noma_chat_flutter)
- Issues: [github.com/nomasystems/noma_chat_flutter/issues](https://github.com/nomasystems/noma_chat_flutter/issues)
- License: [Apache-2.0](./LICENSE)
