#!/usr/bin/env bash
#
# Pre-commit hook for noma_chat.
#
# Install once with:
#   ln -s ../../tool/pre-commit.sh .git/hooks/pre-commit
#
# Runs `dart format --set-exit-if-changed` and `flutter analyze
# --fatal-infos --fatal-warnings` on the package and the example. Fails
# the commit if either reports issues, mirroring the CI gates so local
# breakage is caught before push.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "[pre-commit] dart format check ..."
if ! dart format --output=none --set-exit-if-changed .; then
  echo
  echo "FAIL: code is not formatted. Run 'dart format .' and re-stage."
  exit 1
fi

echo "[pre-commit] flutter analyze ..."
if ! flutter analyze --fatal-infos --fatal-warnings; then
  echo
  echo "FAIL: analyzer reported issues."
  exit 1
fi

if [[ -d example ]]; then
  echo "[pre-commit] flutter analyze (example) ..."
  pushd example >/dev/null
  if ! flutter analyze --fatal-infos --fatal-warnings; then
    echo
    echo "FAIL: example analyzer reported issues."
    popd >/dev/null
    exit 1
  fi
  popd >/dev/null
fi

echo "[pre-commit] OK"
