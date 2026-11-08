#!/usr/bin/env bash
# Every test suite with an EXIT trap must fail when it aborts before its summary.
#
# bash 3.2 (macOS) exits with the EXIT trap's status, usually 0, when `set -u`
# aborts a script, so a suite that crashes halfway looks like a pass. The guard
# is a DONE flag set after the summary and a trap that exits 1 unless DONE=1
# (knowledge: gotcha-ms-bash32-trap-masks-set-u).
#
# For each suite, this test writes a copy next to the original with a forced
# unbound-variable abort right after the trap line, runs it, and requires a
# non-zero exit plus the guard's "ABORTED before summary" message. The message
# check makes the test meaningful on bash >= 4 too, where the abort is already
# non-zero.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
PASS=0
FAIL=0
COPY=""
DONE=0
trap '${COPY:+rm -f "$COPY"}; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== EXIT-trap abort guard ==="
CHECKED=0
for suite in "$ROOT"/tests/*/test-*.sh; do
  [ "$suite" = "$SELF" ] && continue
  rel="${suite#"$ROOT"/}"
  line="$(grep -n "trap .* EXIT" "$suite" | head -1 | cut -d: -f1)"
  [ -n "$line" ] || continue
  CHECKED=$((CHECKED + 1))
  # The copy sits beside the original so its own ROOT/dirname logic still works;
  # the leading dot keeps it out of the tests/*/test-*.sh glob.
  COPY="$(dirname "$suite")/.forced-abort-$(basename "$suite")"
  awk -v n="$line" '{ print } NR == n { print "set -u; : \"$__FORCED_ABORT_UNBOUND\"" }' "$suite" > "$COPY"
  out="$(cd "$ROOT" && bash "$COPY" 2>&1)"
  rc=$?
  rm -f "$COPY"
  COPY=""
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ABORTED before summary"; then
    pass "$rel fails when it aborts before its summary"
  else
    fail "$rel: forced abort gave exit $rc without the DONE guard message"
  fi
done

# Guards the loop itself: a broken glob or grep must not pass vacuously.
[ "$CHECKED" -ge 9 ] && pass "checked $CHECKED suites with EXIT traps" || fail "only $CHECKED suites with EXIT traps found (expected >= 9)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
