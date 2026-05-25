#!/usr/bin/env bash
#
# Runs the full test suite with coverage and prints a per-file report ordered
# from worst to best. Mirrors the CI gate (≥85%) and fails with the same
# threshold so local + CI agree.
#
# Usage:
#   tool/coverage.sh             # default ≥85% gate
#   tool/coverage.sh 80          # override gate
#   tool/coverage.sh --no-gate   # just print the report

set -euo pipefail

cd "$(dirname "$0")/.."

GATE="${1:-85}"
SKIP_GATE=0
if [[ "${GATE}" == "--no-gate" ]]; then
  SKIP_GATE=1
  GATE=0
fi

echo "Running flutter test --coverage ..."
flutter test --coverage

echo
echo "Per-file coverage (worst → best):"
echo

awk '
  /^SF:/ { f=$0; sub("SF:","",f); next }
  /^LF:/ { sub("LF:",""); lf=$0; next }
  /^LH:/ { sub("LH:",""); lh=$0; next }
  /^end_of_record/ {
    if (lf > 0) {
      pct=(lh/lf)*100
      printf "%6.2f%%  %5d/%-5d  %s\n", pct, lh, lf, f
    }
    f=""; lf=0; lh=0
  }
' coverage/lcov.info | sort -n | head -40

echo
echo "Total coverage:"
awk '
  BEGIN{lh=0; lf=0}
  /^LF:/{sub("LF:",""); lf+=$1}
  /^LH:/{sub("LH:",""); lh+=$1}
  END{
    pct=(lh/lf)*100
    printf "  %d/%d = %.2f%%\n", lh, lf, pct
    if ('"$SKIP_GATE"'==0 && pct < '"$GATE"'.0) {
      print "FAIL: coverage below '"$GATE"'% gate"
      exit 1
    }
  }
' coverage/lcov.info
