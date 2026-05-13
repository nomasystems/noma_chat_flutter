# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/) from `0.2.0`
onwards. Until `1.0.0`, **breaking changes may land in any minor release**.

## [0.2.0] - 2026-05-13

First public release. The SDK has been used internally for several months and
the API surface, UI Kit, persistent cache and adapter are considered stable
enough for external evaluation; the pre-1.0 versioning keeps room for breaking
changes informed by real-world feedback before committing to a 1.0 contract.

### Added

- **Message search** end-to-end: `MessageSearchController`,
  `MessageSearchView` with case-insensitive query highlighting, and
  `ChatView.initialMessageId` to scroll-and-highlight a target message after
  navigating back from results.
- **Read receipts**: blue double-check in `MessageStatusIcon` (default
  `messageStatusReadColor` shipped in `ChatTheme.defaults`) and automatic
  `ReadReceiptAvatars` row in group rooms when receipts are available.
  Public helper `readersFor(ChatMessage, List<ReadReceipt>)` for custom
  derivations.
- **Optimistic UI** across the adapter: every mutating operation
  (`sendMessage`, `editMessage`, `deleteMessage`, `sendReaction`,
  `deleteReaction`, `muteRoom`/`unmuteRoom`, `pinRoom`/`unpinRoom`,
  `pinMessage`/`unpinMessage`, `hideRoom`, …) updates local state first and
  rolls back on failure.
- **Operation errors stream**: `ChatUiAdapter.operationErrors` — a broadcast
  `Stream<OperationError>` carrying `OperationKind`, the original
  `ChatFailure` and `roomId`/`messageId`/`userId` context for every adapter
  failure. Designed for global snackbars and telemetry without wrapping each
  call site.
- **Pinned messages** state in `ChatController`
  (`pinnedMessages` + `addPin`/`removePin`/`setPins`/`clearPins`/`isPinned`).
  `adapter.loadPins(roomId)` now seeds it too.
- **Dark theme** shipped as `ChatTheme.dark` and `ChatTheme.highContrast`.
- **Example app** with four pages (home, chat room, message search, pinned
  messages) and a `GlobalErrorBanner` that subscribes to `operationErrors`.
- Comprehensive dartdoc across all public APIs (entry points, sub-APIs,
  models, controllers, theme, l10n, every widget and bubble).

### Tests

- 1156 tests passing + 4 skipped in the full suite.
- Golden tests for the seven non-network bubbles in light and dark themes
  plus the five outgoing message status icons (19 baselines).
- Integration tests exercising the full adapter flow against
  `MockChatClient`.
- Performance regression guard for `HiveChatDatasource` on 10k messages.
- Accessibility audit using `meetsGuideline` (Android/iOS tap target,
  labeled tap target, text contrast).
- System-message l10n parity across the seven shipped locales
  (`en`, `es`, `fr`, `de`, `it`, `pt`, `ca`).

### Known limitations

- Golden tests for `ImageBubble` and `LinkPreviewBubble` are skipped:
  `CachedNetworkImage` pulls in `flutter_cache_manager` →
  `sqflite` + `path_provider`, which is impractical to mock in plain widget
  tests without an extra dependency such as `sqflite_common_ffi`.
- Push notifications integration is not part of this release.
- `ChatEvent` does not yet emit `MessagePinnedEvent` / `MessageUnpinnedEvent`,
  so cross-client pin synchronisation requires a manual `loadPins` refresh.

## [0.1.0] - Unreleased

Initial development version. Used internally during the SDK's design and
test phase; never published to pub.dev. Replaced by `0.2.0`.
