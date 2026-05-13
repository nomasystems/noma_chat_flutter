# Changelog

All notable changes to `noma_chat` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [Semantic Versioning](https://semver.org/) from `0.2.0`
onwards. Until `1.0.0`, **breaking changes may land in any minor release**.

## [0.3.0] - 2026-05-13

Quality + architecture release. No public API breaking changes; the audio
backend migration is transparent to consumers.

### Changed

- **Audio backend**: migrated from `just_audio` to `audioplayers ^6.1.0`.
  Same feature surface (play / pause / seek / playback rate / state stream)
  but `audioplayers` ships implementations for all six Flutter targets,
  unblocking Linux and Windows. `pubspec.yaml` `platforms:` now lists
  android / ios / macos / linux / windows / web; see README "Platform
  support" for the production / best effort breakdown.
- **`ChatClient` interface**: `set onOfflineMessageSent` is now part of the
  abstract contract (was concrete-only on `NomaChatClient`). The UI adapter
  no longer needs an `as NomaChatClient` cast. `MockChatClient` and any
  custom `ChatClient` impl in tests implement the setter (no-op is fine).
- **`ChatUiAdapter` internal SRP refactor** (no API change): the 2272-line
  monolith was split into four `part of` collaborators —
  `_PresenceManager`, `_ChatEventRouter`, `_RoomEnricher`,
  `_OptimisticHandler`. The facade is now ~1500 lines and the
  responsibilities are obvious from the file layout.
- **`MockChatClient.rooms`** now emits `RoomUpdatedEvent` after each
  successful `mute` / `unmute` / `pin` / `unpin` / `hide` / `unhide` to
  match the real client's event semantics. Tests that count events should
  expect one per mutation.
- **Models**: every public value-object class in `lib/src/models/` and
  `lib/src/ui/models/` is now annotated `@immutable`. No runtime
  difference; the analyzer now flags accidental subclassed mutability.

### Fixed

- `loadRooms()` and `_enrichAndSetRooms` guard `_disposed` after every
  long await so they cannot write to a disposed `ValueNotifier` or
  `RoomListController`.
- `rejectInvitation` now restores the room on network failure (previously
  it dropped the invitation permanently if the request errored out).
- `sendThreadReply` no longer double-emits to `operationErrors`: both
  `OperationKind.sendMessage` and `OperationKind.sendThreadReply` used to
  fire for a single failure. `sendMessage` accepts an optional
  `operationKind` override and the thread-reply path uses it to emit a
  single, more specific kind.
- `loadMoreMessages` wraps its body in `try/finally` so
  `controller.setLoadingMore(false)` runs even if the SDK call leaks an
  exception past the `Result` wrapper.
- `VoiceRecordingController.startRecording()` early-returns with
  `StartRecordingResult.permissionDenied` on Web (it was crashing on
  `dart:io` / `path_provider`). A MediaRecorder-backed Web flow is on
  the roadmap.
- `LinkPreviewFetcher` retries cached failures after a configurable TTL
  (default 5 min) instead of caching `null` forever. Transient network
  glitches no longer poison the per-session preview cache.
- Hardcoded English Semantics labels in `ImageBubble`, `VideoBubble` and
  `ScrollToBottomButton` are now routed through `theme.l10n`. A new
  `scrollToBottom` localisation key was added across all seven shipped
  locales (en / es / fr / de / it / pt / ca).
- Dark + high-contrast themes now ship explicit `markdownCodeStyle` and
  `markdownLinkStyle` overrides; the previous defaults bled light-mode
  values into the dark UI and failed WCAG AA contrast for inline links.
- A handful of dark-theme accent colours (`reactionBackgroundColor`,
  `audioPlayButtonColor`, `audioListenedIconColor`,
  `audioUnlistenedIconColor`, `linkPreviewBackgroundColor`) are now
  overridden in `ChatTheme.dark` instead of inheriting light defaults.
- Voice upload progress `ValueNotifier`s detached after a completed
  upload are now tracked and disposed during `adapter.dispose()` (they
  used to outlive the adapter when the optimistic bubble held a
  reference).
- `_resolveDmContact` rewritten from a `Future.sync().then().catchError()`
  chain to `async`/`await` + `try`/`catch` with an explicit `unawaited()`
  so the fire-and-forget intent is visible at the call site.

### Documentation

- README `Platform support` table rewritten to reflect the audioplayers
  migration (six platforms supported via the new backend; voice
  recording on Web is documented as "Limited" with the reason).
- `RELEASING.md` updated for the now-live automated publishing flow,
  including the three pub.dev configuration toggles and the four
  failure modes a maintainer might hit.
- `TESTING.md` test counts refreshed to reflect the current suite size
  (1474+) and the 80% coverage gate enforced in CI.
- `markdown_parser.dart` dartdoc now lists the supported inline syntax
  and the deliberate non-support (`[label](url)`, block markdown).

### Tests

- 1485 tests passing on Linux (CI), + 4 skipped. On macOS the 19 golden
  bubble diffs fail by ~1% pixel-diff because the baselines are
  generated on Linux for CI; regenerate locally with
  `flutter test --update-goldens` if needed.
- Coverage 80.55% (8248/10239), enforced ≥80% in CI.

## [0.2.1] - 2026-05-13

Post-publish polish driven by the pub.dev scoring report. No behavioural
changes; consumers on `^0.2.0` pick this up automatically.

### Fixed

- **Static analysis**: 17 stale `*.freezed.dart` files were left behind from
  an earlier migration of plain models off Freezed. `dart analyze` ignored
  them locally (excluded via `analysis_options.yaml`) but pana ran a
  separate analysis that surfaced 1 176 errors against them. The files are
  now deleted; the remaining `admin_models.freezed.dart` is genuinely
  generated and stays.
- **`hive_ce` lower bound**: bumped from `^2.7.0` to `^2.19.0`. Older
  versions did not yet expose `package:hive_ce/hive_ce.dart`, so a
  consumer with `dart pub downgrade` would fail to compile.
- **`just_audio` constraint**: bumped from `^0.9.42` to `^0.10.0` so the
  package tracks the current stable line.

### Changed

- `pubspec.yaml` now declares `platforms:` explicitly. Supported targets
  are **android, ios, macos, web**. Windows and Linux are excluded because
  `just_audio` (transitive, used for voice playback) does not support them.
- README has a new **Platform support** section documenting which
  platforms are production-tested vs best-effort vs unsupported, with the
  exact transitive-dep blocker for Windows/Linux.

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
