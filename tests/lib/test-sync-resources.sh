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
