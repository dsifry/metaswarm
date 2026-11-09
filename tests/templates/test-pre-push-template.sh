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
  if [ "$rc" -eq 0 ] && grep -qxF -e 'COVERAGE_RAN' <<<"$out"; then   # exact line: not the "Running: ..." log
    pass "under dash without jq/pnpm, the hook runs enforcement.command via the node fallback"
  else
    fail "under dash without jq/pnpm, the hook runs enforcement.command (rc=$rc): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  fi
  # #83: lint and typecheck run only when package.json defines them, and a
  # failing script fails the hook (typecheck failures used to be ignored).
  run_hook() { # <package.json scripts JSON> -> sets HOOK_RC, HOOK_OUT
    printf '{"name":"x","version":"1.0.0","scripts":%s}\n' "$1" > "$P/package.json"
    HOOK_RC=0; HOOK_OUT="$(cd "$P" && PATH="$TMP/bin" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || HOOK_RC=$?
  }
  run_hook '{}'
  if [ "$HOOK_RC" -eq 0 ] && grep -qxF -e 'COVERAGE_RAN' <<<"$HOOK_OUT"; then
    pass "with no lint or typecheck script, the hook skips them and still runs coverage"
  else
    fail "missing lint/typecheck scripts broke the hook (rc=$HOOK_RC): $(printf '%s' "$HOOK_OUT" | tail -3 | tr '\n' ' ')"
  fi
  run_hook '{"lint":"exit 3","typecheck":"true"}'
  [ "$HOOK_RC" -ne 0 ] && grep -qF '✓ lint' <<<"$HOOK_OUT" && ! grep -qxF 'COVERAGE_RAN' <<<"$HOOK_OUT" \
    && pass "a failing lint script fails the hook at the lint step" || fail "a failing lint script passed the hook (rc=$HOOK_RC): $(printf '%s' "$HOOK_OUT" | tail -3 | tr '\n' ' ')"
  run_hook '{"lint":"true","typecheck":"exit 3"}'
  [ "$HOOK_RC" -ne 0 ] && grep -qF '✓ typecheck' <<<"$HOOK_OUT" && ! grep -qxF 'COVERAGE_RAN' <<<"$HOOK_OUT" \
    && pass "a failing typecheck script fails the hook at the typecheck step" || fail "a failing typecheck script passed the hook (rc=$HOOK_RC): $(printf '%s' "$HOOK_OUT" | tail -3 | tr '\n' ' ')"
  # #97: a Node project with no node on PATH must not silently skip lint.
  NB="$TMP/bin-nonode"; mkdir -p "$NB"
  for t in npm sh env dirname cat grep sed head tr true printf; do
    src="$(command -v "$t" || true)"; [ -n "$src" ] && ln -sf "$src" "$NB/$t"
  done
  printf '{"name":"x","version":"1.0.0","scripts":{"lint":"true"}}\n' > "$P/package.json"
  rc=0; out="$(cd "$P" && PATH="$NB" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && grep -qi 'node' <<<"$out" && ! grep -q 'skipping' <<<"$out"; then
    pass "package.json without node on PATH fails the hook instead of skipping lint"
  else
    fail "missing node was skipped (rc=$rc): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  fi
  # #97: the format step uses pnpm only when the project does (pnpm-lock.yaml),
  # like lint and typecheck.
  PB="$TMP/bin-pnpm"; mkdir -p "$PB"; cp -P "$TMP/bin/"* "$PB/"
  printf '#!/bin/sh\necho "pnpm $*" >> "%s"\n' "$TMP/pnpm.log" > "$PB/pnpm"; chmod +x "$PB/pnpm"
  : > "$TMP/pnpm.log"
  printf '{"name":"x","version":"1.0.0","scripts":{"lint":"true","typecheck":"true"}}\n' > "$P/package.json"
  rm -f "$P/pnpm-lock.yaml"
  rc=0; out="$(cd "$P" && PATH="$PB" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ ! -s "$TMP/pnpm.log" ] && pass "with pnpm installed but no pnpm-lock.yaml, nothing runs through pnpm" \
    || fail "pnpm ran in an npm project (rc=$rc): $(tr '\n' ' ' < "$TMP/pnpm.log")"
  : > "$P/pnpm-lock.yaml"
  rc=0; out="$(cd "$P" && PATH="$PB" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || rc=$?
  grep -q 'format' "$TMP/pnpm.log" && pass "with pnpm-lock.yaml, the format check runs through pnpm" \
    || fail "format check skipped pnpm in a pnpm project: $(tr '\n' ' ' < "$TMP/pnpm.log")"
  rm -f "$P/pnpm-lock.yaml"
  # A UTF-8 byte-order mark (some Windows editors add one) is still a valid package.json.
  printf '\357\273\277{"name":"x","version":"1.0.0","scripts":{"lint":"exit 3"}}\n' > "$P/package.json"
  HOOK_RC=0; HOOK_OUT="$(cd "$P" && PATH="$TMP/bin" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || HOOK_RC=$?
  [ "$HOOK_RC" -ne 0 ] && grep -qF '✓ lint' <<<"$HOOK_OUT" \
    && pass "a package.json with a BOM is read (its lint script runs)" || fail "a BOM package.json was rejected (rc=$HOOK_RC): $(printf '%s' "$HOOK_OUT" | tail -3 | tr '\n' ' ')"
  # A package.json node can't parse must not read as "no script".
  printf '{"name": "x", "scripts": {\n' > "$P/package.json"
  HOOK_RC=0; HOOK_OUT="$(cd "$P" && PATH="$TMP/bin" "$DASH" "$REPO_ROOT/templates/pre-push" 2>&1)" || HOOK_RC=$?
  [ "$HOOK_RC" -ne 0 ] && grep -qi 'package.json' <<<"$HOOK_OUT" && ! grep -q 'skipping' <<<"$HOOK_OUT" \
    && pass "a malformed package.json fails the hook instead of skipping lint" || fail "a malformed package.json was skipped (rc=$HOOK_RC): $(printf '%s' "$HOOK_OUT" | tail -3 | tr '\n' ' ')"
else
  echo "  SKIP: dash or node not installed (behaviour not exercised)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
