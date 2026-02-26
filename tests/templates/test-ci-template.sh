#!/usr/bin/env bash
# tests/templates/test-ci-template.sh
# Validates CI template security properties

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_not_contains() {
  local desc="$1" file="$2" pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    grep -n "$pattern" "$file"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

assert_contains() {
  local desc="$1" file="$2" pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected pattern: $pattern"
  fi
}

CI_FILE="templates/ci.yml"

echo "Testing CI template security..."

assert_not_contains "No eval in CI template" "$CI_FILE" 'eval "\$'
assert_contains "Uses array-based execution" "$CI_FILE" 'CMD_ARRAY'
assert_contains "Has allowlist check" "$CI_FILE" 'npm\|pnpm\|yarn\|npx\|bun\|cargo\|pytest\|go\|make'
assert_contains "Has metacharacter rejection" "$CI_FILE" 'shell metacharacters'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
