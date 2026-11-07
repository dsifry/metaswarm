#!/usr/bin/env bash
# tests/lib/test-sync-resources.sh
# Tests for sync-resources.js build script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
  fi
}

echo "Testing sync-resources.js..."

# Test 0: .claude/commands/ mirrors every commands/*.md (issue #61).
# In this repo, project commands are the only copies Claude Code loads, so drift
# silently serves stale workflow rules. Runs before --sync so drift is caught.
echo "Test 0: .claude/commands mirrors commands/*.md"
for src in "$REPO_ROOT"/commands/*.md; do
  name="$(basename "$src")"
  if cmp -s "$src" "$REPO_ROOT/.claude/commands/$name"; then
    result="SAME"
  else
    result="DIFF"
  fi
  assert_eq ".claude/commands/$name matches commands/$name" "SAME" "$result"
done

# Test 0b: --check detects drift in a mirrored command
echo "Test 0b: --check fails when a mirrored command drifts"
probe="$REPO_ROOT/.claude/commands/prime.md"
backup="$(mktemp)"
cp "$probe" "$backup"
trap 'cp "$backup" "$probe"; rm -f "$backup"' EXIT
printf '\ndrift\n' >> "$probe"
if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  result="PASS"
else
  result="FAIL"
fi
cp "$backup" "$probe"
assert_eq "Check fails on drifted .claude/commands copy" "FAIL" "$result"

# Test 1: Check mode should pass when files are in sync
echo "Test 1: Check mode passes when synced"
if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  result="PASS"
else
  result="FAIL"
fi
assert_eq "Check mode passes" "PASS" "$result"

# Test 2: Sync mode runs without error
echo "Test 2: Sync mode runs without error"
if (cd "$REPO_ROOT" && node lib/sync-resources.js --sync >/dev/null 2>&1); then
  result="PASS"
else
  result="FAIL"
fi
assert_eq "Sync mode succeeds" "PASS" "$result"

# Test 3: After syncing, check mode should still pass
echo "Test 3: Check after sync still passes"
if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  result="PASS"
else
  result="FAIL"
fi
assert_eq "Check after sync passes" "PASS" "$result"

# Test 4: No arguments prints usage and exits non-zero
echo "Test 4: No arguments prints usage"
result=$(cd "$REPO_ROOT" && node lib/sync-resources.js 2>&1 || true)
TOTAL=$((TOTAL + 1))
if echo "$result" | grep -q "Usage"; then
  PASS=$((PASS + 1))
  echo "  PASS: Prints usage without arguments"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected usage message, got: $result"
fi

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
