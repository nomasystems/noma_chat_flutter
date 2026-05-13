# Releasing `noma_chat`

This document is for **maintainers** of the package. It explains how a new
version reaches pub.dev. End-user consumers do not need to read this file
(it is excluded from the tarball uploaded to pub.dev via `.pubignore`).

## Branching model

The repository uses **trunk-based development**:

- `main` is the only long-lived branch.
- All work lands on `main` through pull requests.
- Tags `vX.Y.Z` (and pre-release `vX.Y.Z-N`) on `main` are what get
  published to pub.dev.

If at some point we need a stabilisation branch (for example to maintain
a `0.x` line in parallel with a `1.x` branch), we will branch off `main`
with a name like `release/0.x` and document it here.

## Versioning

The package follows [Semantic Versioning](https://semver.org). Until `1.0.0`
**breaking changes are allowed in any minor release**; bumping the minor is
the signal. After `1.0.0`, breaking changes will require a major bump.

| Change type                    | Bump  |
| ------------------------------ | ----- |
| New backwards-compatible API   | minor |
| Bug fix without API change     | patch |
| Removing or renaming an API    | minor (pre-1.0) / major (post-1.0) |
| Pre-release for risky changes  | `X.Y.Z-rc.1`, `-beta.2`, … |

## Release procedure (manual)

The very first publication (currently `0.2.0`) is **manual** because
pub.dev needs to claim the package name for the uploader account. The same
manual flow is also the fallback if automated publishing is unavailable.

1. Make sure `main` is green:

    ```bash
    flutter pub get
    flutter analyze --fatal-infos --fatal-warnings
    flutter test
    dart doc --dry-run
    ```

2. Bump the version in `pubspec.yaml` (single source of truth).

3. Update `CHANGELOG.md` with a new top entry for the version, dated today.
   Group changes in `Added` / `Changed` / `Fixed` / `Removed` /
   `Known limitations` as in previous entries.

4. Commit everything as `release: vX.Y.Z` and push to `main`.

5. From the package root, dry-run:

    ```bash
    flutter pub publish --dry-run
    ```

    Should report `Package has 0 warnings.` (or only warnings you have
    already accepted as known). Fix anything that blocks publishing.

6. Publish for real:

    ```bash
    flutter pub publish
    ```

    The first time, this prompts a Google login in your browser. Subsequent
    invocations reuse the cached credentials. Confirm with `y`.

7. Tag the release and push the tag — this is what the automated workflow
   (see below) will key off of in the future:

    ```bash
    git tag vX.Y.Z
    git push origin vX.Y.Z
    ```

8. Open the [GitHub Releases page][releases] and create a release for the
   new tag, copy-pasting the matching section from `CHANGELOG.md`.

9. Within a couple of minutes the package and the rendered dartdoc should
   appear on:

   - <https://pub.dev/packages/noma_chat>
   - <https://pub.dev/documentation/noma_chat/latest/>

[releases]: https://github.com/nomasystems/noma_chat_flutter/releases

## Release procedure (automated, recommended once enabled)

After `0.2.0` is on pub.dev:

1. Go to the package admin page on pub.dev:
   <https://pub.dev/packages/noma_chat/admin> → **Automated publishing** →
   **Publishing from GitHub Actions**.
2. Authorise the repository `nomasystems/noma_chat_flutter` and set the
   tag pattern to `v{{version}}` (or the regex
   `^v[0-9]+\.[0-9]+\.[0-9]+(-.*)?$`).
3. From then on, the workflow at `.github/workflows/publish.yml` takes
   over. To release:

    ```bash
    # bump version in pubspec.yaml + CHANGELOG.md, commit, push
    git tag vX.Y.Z
    git push origin vX.Y.Z
    ```

    The workflow runs analyse + tests + dartdoc dry-run; on green it
    mints an OIDC token, hands it to pub.dev, and `dart pub publish
    --force` uploads the tarball. **No secrets are stored in the repo.**

4. If the workflow fails on the verification step ("Tag does not match
   pubspec.yaml version") the tag is left in place but pub.dev is not
   touched — fix the version mismatch with a follow-up commit + new tag.

## CI

`.github/workflows/ci.yml` runs on every pull request and push to `main`:

- `dart format` (must be clean)
- `flutter analyze --fatal-infos --fatal-warnings`
- `flutter test`
- `dart doc --dry-run`
- `pana` (informational, never blocks)

A pull request that does not turn this green should not be merged.

## Local sanity script

A reasonable pre-release local check, mirroring what CI does:

```bash
dart format --output=none --set-exit-if-changed . \
  && flutter analyze --fatal-infos --fatal-warnings \
  && flutter test \
  && dart doc --dry-run \
  && flutter pub publish --dry-run
```

If all five steps are green, the release is safe to cut.
