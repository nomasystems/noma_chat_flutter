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

## Release procedure (automated, **recommended**)

Automated publishing is **live** as of `0.2.1`. The pub.dev side is
configured at <https://pub.dev/packages/noma_chat/admin> →
**Publishing from GitHub Actions**:

- Repository: `nomasystems/noma_chat_flutter`
- Tag pattern: `v{{version}}`
- "Enable publishing from `push` events": **on**
- `workflow_dispatch`: off (the workflow does not declare a `workflow_dispatch:` trigger)
- "Require GitHub Actions environment": off (single maintainer)

The end-to-end flow:

```bash
# 1. bump version in pubspec.yaml + CHANGELOG.md, commit, push
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: release vX.Y.Z"
git push

# 2. tag and push the tag — this is what triggers publishing
git tag vX.Y.Z
git push origin vX.Y.Z
```

The workflow at `.github/workflows/publish.yml`:

1. Verifies the git tag matches the `version:` in `pubspec.yaml`.
   On mismatch it fails fast and pub.dev is not touched — fix with a
   follow-up commit + new tag.
2. Runs `flutter analyze --fatal-infos --fatal-warnings` and
   `flutter test` on a fresh `ubuntu-latest` runner.
3. Runs `dart doc --dry-run`.
4. Delegates to `dart-lang/setup-dart/.github/workflows/publish.yml@v1`,
   which mints a short-lived OIDC token, sends it to pub.dev, and
   `dart pub publish --force` uploads the tarball.

**No secrets are stored anywhere.** Authentication is bound to the
repository + tag-pattern configured on pub.dev; GitHub signs a JWT with
the workflow context (repo, ref, run id, actor) and pub.dev verifies it
against GitHub's public keys.

### Why a publish run might fail

- **OIDC trust** is set up wrong on pub.dev (last step "Authentication
  failed!" with exit 65). Re-check the repo and tag pattern on the
  admin page and rerun: `gh run rerun <run-id>`.
- **Tag does not match pubspec version** — fix the version mismatch.
- **`flutter analyze` finds issues** — the run reflects what was on the
  tag's commit, even if `main` is green. Cut a new patch with the fix
  and tag it.

## CI

`.github/workflows/ci.yml` runs on every pull request and push to `main`:

- `dart format` (must be clean)
- `flutter analyze --fatal-infos --fatal-warnings`
- `flutter test --coverage`
- Coverage gate — fails if line coverage drops below **80%**
- `dart doc --dry-run`
- `pana` (informational, never blocks)

A pull request that does not turn this green should not be merged.

## Local sanity script

A reasonable pre-release local check, mirroring what CI does:

```bash
dart format --output=none --set-exit-if-changed . \
  && flutter analyze --fatal-infos --fatal-warnings \
  && flutter test --coverage \
  && awk 'BEGIN{lh=0;lf=0} /^LF:/{sub("LF:","");lf+=$1} /^LH:/{sub("LH:","");lh+=$1} END{p=(lh/lf)*100; printf "Coverage: %.2f%%\n", p; exit (p<80)}' coverage/lcov.info \
  && dart doc --dry-run \
  && flutter pub publish --dry-run
```

If all six steps are green, the release is safe to cut.
