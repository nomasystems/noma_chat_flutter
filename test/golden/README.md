# Golden tests

Golden (snapshot) tests render a widget to a PNG and compare it pixel-for-pixel
against a committed baseline in [`goldens/`](goldens). They cover the message
bubbles (`bubbles_light_test.dart`, `bubbles_dark_test.dart`) and the
delivery-status icons (`message_status_test.dart`).

## Why baselines are generated on CI

Text rasterisation and anti-aliasing differ between macOS and the CI runner
(Linux), so a baseline generated on a Mac fails on CI and vice-versa. **The
committed baselines are the CI-Linux ones.** Locally we therefore *skip* golden
tests; CI runs them on Linux as the source of truth:

```bash
flutter test -x golden       # local: everything except goldens
```

`ci.yml` runs the full suite (goldens included) on Linux and excludes them on
macOS (`-x golden`).

## Regenerating baselines when a golden changes

If you add a golden test or restyle a widget a snapshot covers, the baseline
must be regenerated **on Linux**. You don't need a Linux machine — the
`regen-goldens` workflow does it. The helper script drives the whole round-trip:

```bash
tool/regen_goldens.sh
```

It dispatches [`.github/workflows/regen-goldens.yml`](../../.github/workflows/regen-goldens.yml)
(which runs `flutter test --update-goldens test/golden/` on Linux and uploads the
result as the `goldens` artifact), waits for it, downloads the regenerated PNGs
into `goldens/`, and reports what changed. Review the diff and commit.

> Pushing to a `release/**` branch also triggers `regen-goldens` automatically;
> the script is for any other branch (or an on-demand refresh).

### Manual fallback (no script)

```bash
gh workflow run regen-goldens.yml --ref "$(git branch --show-current)"
gh run watch <run-id> --exit-status          # run-id from `gh run list`
gh run download <run-id> -n goldens -D /tmp/g
cp -R /tmp/g/. test/golden/goldens/
```

When a golden test fails, the actual/diff PNGs are written to
[`failures/`](failures) (gitignored) so you can eyeball what moved.
