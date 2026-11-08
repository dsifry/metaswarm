#!/usr/bin/env bash
# tests/commands/test-command-sources.sh
# Content checks for command sources (#64): legacy redirect shims and /external-tools-health.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap '[ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
has() { grep -qF -e "$2" "$REPO_ROOT/$1"; }

# Legacy commands are short redirect shims (items 2-5 of #64 lived in their old bodies).
SHIM_MAX_LINES=30
check_shim() { # <file> <target command>
  local f="$1" target="$2" n
  echo "Legacy shim: $f -> $target"
  n=$(wc -l <"$REPO_ROOT/$f" | tr -d ' ')
  [ "$n" -le "$SHIM_MAX_LINES" ] && pass "$f is a short shim ($n lines)" || fail "$f is a short shim ($n lines > $SHIM_MAX_LINES)"
  has "$f" "deprecated" && pass "$f says it is deprecated" || fail "$f says it is deprecated"
  has "$f" "$target" && pass "$f redirects to $target" || fail "$f redirects to $target"
  if grep -qE -e 'npx metaswarm(@latest)? (install|changelog)' "$REPO_ROOT/$f"; then
    fail "$f has no nonexistent CLI commands"
  else
    pass "$f has no nonexistent CLI commands"
  fi
}
check_shim commands/metaswarm-setup.md /setup
check_shim commands/metaswarm-update-version.md /update

# /external-tools-health runs each adapter's health command and reports its fields (item 6).
F=commands/external-tools-health.md
echo "External tools health: $F"
for adapter in codex gemini; do
  has "$F" "$adapter.sh\" health" && pass "$F runs $adapter.sh health" || fail "$F runs $adapter.sh health"
done
for field in '"status"' '"auth_valid"' '"version"' '"model"'; do
  has "$F" "$field" && pass "$F reports $field" || fail "$F reports $field"
done
if has "$F" "bash bin/external-tools-verify.sh"; then
  fail "$F does not run the repo self-test as a health check"
else
  pass "$F does not run the repo self-test as a health check"
fi

# Go coverage gate (#64 item 5): the command setup writes must fail below the threshold.
SETUP=skills/setup/SKILL.md
echo "Go coverage gate: $SETUP"
GO_CMD=$(sed -n 's/^  - go → `"\(.*\)"`$/\1/p' "$REPO_ROOT/$SETUP")
GO_ROW=$(grep -E '^\| go test \|' "$REPO_ROOT/$SETUP" | awk -F'`' '{print $4}')
[ -n "$GO_CMD" ] && pass "$SETUP has a go enforcement command" || fail "$SETUP has a go enforcement command"
[ "$GO_ROW" = "$(printf '%s' "$GO_CMD" | sed 's/<threshold>/{threshold}/g')" ] && pass "$SETUP go table row matches the command" || fail "$SETUP go table row matches the command ('$GO_ROW' vs '$GO_CMD')"
case "$GO_CMD" in *'<threshold>'*) pass "go command uses the threshold" ;; *) fail "go command uses the threshold" ;; esac
if command -v go >/dev/null 2>&1 && [ -n "$GO_CMD" ]; then
  GOMOD="$(mktemp -d)"
  printf 'module example.com/cov\n\ngo 1.20\n' > "$GOMOD/go.mod"
  printf 'package cov\n\nfunc Covered() int { return 1 }\n\nfunc Uncovered() int { return 2 }\n' > "$GOMOD/cov.go"
  printf 'package cov\n\nimport "testing"\n\nfunc TestCovered(t *testing.T) { if Covered() != 1 { t.Fatal() } }\n' > "$GOMOD/cov_test.go"
  run_go() { (cd "$GOMOD" && GOFLAGS=-mod=mod bash -c "${GO_CMD//<threshold>/$1}" >/dev/null 2>&1) && echo 0 || echo 1; }
  [ "$(run_go 100)" = 1 ] && pass "go gate fails below the threshold (50% < 100%)" || fail "go gate fails below the threshold (50% < 100%)"
  [ "$(run_go 40)" = 0 ] && pass "go gate passes at or above the threshold (50% >= 40%)" || fail "go gate passes at or above the threshold (50% >= 40%)"
  rm -rf "${GOMOD:?}"
else
  echo "  SKIP: go not installed (gate not executed)"
fi
grep -E '^\| Go \|' "$REPO_ROOT/docs/coverage-enforcement.md" | grep -qF -e 'go tool cover' \
  && pass "docs/coverage-enforcement.md Go example enforces the threshold" \
  || fail "docs/coverage-enforcement.md Go example enforces the threshold"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
