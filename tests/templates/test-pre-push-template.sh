#!/usr/bin/env bash
# tests/templates/test-pre-push-template.sh
# templates/pre-push must run correctly under POSIX sh: Husky 9 runs hooks with `sh`,
# and under dash `cmd &>/dev/null` backgrounds the command, so every `command -v X`
# check would look successful (PR #82 review).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0
DONE=0
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

for f in templates/pre-push skills/setup/templates/pre-push; do
  echo "$f"
  if grep -n -e '&>' "$REPO_ROOT/$f" >/dev/null; then
    fail "$f has no bash-only '&>' redirection ($(grep -n -e '&>' "$REPO_ROOT/$f" | cut -d: -f1 | tr '\n' ' '))"
  else
    pass "$f has no bash-only '&>' redirection"
  fi
  if command -v dash >/dev/null 2>&1; then
    dash -n "$REPO_ROOT/$f" && pass "$f parses under dash" || fail "$f parses under dash"
  else
    echo "  SKIP: dash not installed"
  fi
done

# Behaviour under POSIX sh with no jq/pnpm on PATH: the coverage step must use the
# node fallback and run enforcement.command, not fail on a missing jq.
if command -v dash >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  P="$TMP/proj"; mkdir -p "$P" "$TMP/bin"
  printf '{"name":"x","version":"1.0.0","scripts":{"lint":"true","typecheck":"true"}}\n' > "$P/package.json"
  printf '{"enforcement":{"command":"echo COVERAGE_RAN"}}\n' > "$P/.coverage-thresholds.json"
  for t in node npm sh env dirname cat grep sed head tr true printf; do
    src="$(command -v "$t" || true)"; [ -n "$src" ] && ln -sf "$src" "$TMP/bin/$t"
  done
  DASH="$(command -v dash)"
  rc=0; out="$(cd "$P" && PATH="$TMP/bin" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && grep -qF -e 'COVERAGE_RAN' <<<"$out"; then
    pass "under dash without jq/pnpm, the hook runs enforcement.command via the node fallback"
  else
    fail "under dash without jq/pnpm, the hook runs enforcement.command (rc=$rc): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  fi
else
  echo "  SKIP: dash or node not installed (behaviour not exercised)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
