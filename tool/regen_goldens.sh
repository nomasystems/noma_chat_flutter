#!/usr/bin/env bash
#
# Regenerate golden baselines on CI (Linux) and pull them into the repo.
#
# Golden tests render widgets pixel-for-pixel. macOS and the CI runner (Linux)
# rasterise text and anti-aliasing slightly differently, so a baseline made on a
# Mac fails on CI and vice-versa. The committed baselines are therefore the
# CI-Linux ones, produced by the `regen-goldens` workflow. Run this when a golden
# test changes (a new golden, or a restyled widget) and you need fresh Linux
# baselines without owning a Linux machine.
#
# Requires: gh (authenticated). Run on the branch whose baselines you want.
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
branch="$(git rev-parse --abbrev-ref HEAD)"

echo "▶ Dispatching regen-goldens on '$branch'…"
gh workflow run regen-goldens.yml --ref "$branch"

echo "▶ Waiting for the run to register…"
run_id=""
for _ in $(seq 1 20); do
  sleep 3
  run_id="$(gh run list --workflow=regen-goldens.yml --branch "$branch" \
    --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$run_id" ] && break
done
[ -n "$run_id" ] || { echo "✗ Could not find the workflow run." >&2; exit 1; }

echo "▶ Watching run $run_id (regenerating on Linux)…"
gh run watch "$run_id" --exit-status

echo "▶ Downloading regenerated baselines…"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" -n goldens -D "$tmp"
cp -R "$tmp"/. test/golden/goldens/

changed="$(git status --porcelain test/golden/goldens/ | wc -l | tr -d ' ')"
echo
if [ "$changed" -eq 0 ]; then
  echo "✓ Baselines already up to date — nothing changed."
else
  echo "✓ $changed baseline(s) updated. Review and commit:"
  git status --short test/golden/goldens/
  echo
  echo "    git add test/golden/goldens && git commit -m 'chore: regenerate golden baselines'"
fi
