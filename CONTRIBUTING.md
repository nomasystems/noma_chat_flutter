# Contributing to `noma_chat`

Thanks for taking the time to contribute! This document covers the basics
of how to get a change merged into the package. For release management see
[RELEASING.md](./RELEASING.md).

## Code of conduct

By participating you agree to behave respectfully towards other
contributors. We follow a "be kind, assume good faith" baseline; harassment
of any kind will get you removed from the project.

## Quick start

```bash
git clone git@github.com:nomasystems/noma_chat_flutter.git
cd noma_chat_flutter
flutter pub get
flutter test
```

To run the example app against a `MockChatClient`:

```bash
cd example
flutter pub get
flutter run
```

## Reporting bugs

Open an issue at
<https://github.com/nomasystems/noma_chat_flutter/issues> and include:

- **What you tried** — minimal code snippet or steps to reproduce.
- **What you expected** vs **what happened**.
- Versions: `flutter --version`, `noma_chat` version from `pubspec.lock`,
  target platform (iOS/Android/web/desktop).
- Logs / stack traces if available. Redact tokens and PII.

## Proposing changes

For anything non-trivial (new feature, public API change, refactor that
touches multiple layers), please **open an issue first** to align on the
approach before writing code. Small bug fixes and documentation
improvements can go straight to a PR.

## Pull request checklist

Before opening a PR, please make sure:

- [ ] `dart format .` is clean.
- [ ] `flutter analyze --fatal-infos --fatal-warnings` reports no issues.
- [ ] `flutter test` is green.
- [ ] `dart doc --dry-run` reports `Found 0 warnings and 0 errors.`.
- [ ] New public API has a `///` dartdoc explaining what it does and (when
      non-obvious) why.
- [ ] If you changed user-facing behaviour, a test covers it.
- [ ] If the change is observable by consumers, you added a bullet to
      `CHANGELOG.md` under an `## Unreleased` section (we move it to the
      version entry at release time).

CI runs all of the above on every PR. A red CI is a blocker.

## Style notes

The codebase has a few non-default conventions worth mentioning:

- **Internal symbols** live under `lib/src/_internal/` and are not
  re-exported from `lib/noma_chat.dart`. Don't promote anything from
  there without discussion.
- **Public API** lives in `lib/src/` and is re-exported from
  `lib/noma_chat.dart`. Anything exported is part of the package's
  semver contract.
- **Sealed `Result<T>` over throws** for SDK calls. The adapter layer
  surfaces failures via `OperationError` events; don't add `throw`s
  across that boundary unless documented.
- **No `print`** in production code. Use the `logger` parameter that
  flows through `ChatConfig`.
- **Dartdoc on every public class, enum, top-level function and
  exported widget.** First sentence is the summary; further paragraphs
  add details. See existing widgets for the style.
- **Tests live in `test/`** mirroring the `lib/src/` structure. Goldens
  live in `test/golden/goldens/`.

## Tests, goldens, and CI

- Run a focused test: `flutter test test/path/to/file_test.dart`.
- Update goldens (only when the change is visually intentional):
  `flutter test --update-goldens test/golden/`. Commit the resulting
  `.png` files alongside the code change.
- The Pana score (pub.dev points proxy) is computed in CI and shown for
  reference only — it does not block.

## Where to look

- [ARCHITECTURE.md](./ARCHITECTURE.md) — internal layers, transports,
  cache, UI adapter.
- [INTEGRATION.md](./INTEGRATION.md) — contract with the Noma chat
  backend.
- [TESTING.md](./TESTING.md) — testing conventions and mocking patterns.
- [RELEASING.md](./RELEASING.md) — how a version reaches pub.dev.

## Licence

By contributing you agree that your contributions will be licensed under
the [Apache License 2.0](./LICENSE).
