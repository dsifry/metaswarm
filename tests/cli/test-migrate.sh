#!/usr/bin/env bash
# tests/cli/test-migrate.sh
# Validate tribunal migrate command

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Migration Tests"
echo "==============="
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test: migrates .coverage-thresholds.json into tribunal.yaml ---
mkdir -p "$TMPDIR/.metaswarm"

cat > "$TMPDIR/.coverage-thresholds.json" << 'JSON'
{
  "thresholds": {
    "lines": 95,
    "branches": 90,
    "functions": 100,
    "statements": 95
  },
  "enforcement": {
    "command": "npm test -- --coverage",
    "blockPRCreation": true,
    "blockTaskCompletion": true
  }
}
JSON

cat > "$TMPDIR/.metaswarm/project-profile.json" << 'JSON'
{"stack": "node", "name": "test-project"}
JSON

node "$ROOT/lib/migrate-config.js" "$TMPDIR" 2>&1

if [ -f "$TMPDIR/tribunal.yaml" ]; then
  pass "tribunal.yaml created"
else
  fail "tribunal.yaml not created"
fi

if [ -d "$TMPDIR/.tribunal" ]; then
  pass ".metaswarm/ renamed to .tribunal/"
else
  fail ".tribunal/ directory not found"
fi

if [ ! -d "$TMPDIR/.metaswarm" ]; then
  pass ".metaswarm/ removed after migration"
else
  fail ".metaswarm/ still exists after migration"
fi

# Check coverage values were migrated
LINES=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1 | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.lines)")

if [ "$LINES" = "95" ]; then
  pass "coverage.lines migrated correctly (95)"
else
  fail "coverage.lines: expected 95, got $LINES"
fi

# --- Test: enforcement command migrated ---
CMD=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1 | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.enforcement.command)")

if [ "$CMD" = "npm test -- --coverage" ]; then
  pass "enforcement.command migrated correctly"
else
  fail "enforcement.command: expected 'npm test -- --coverage', got '$CMD'"
fi

# --- Test: does not overwrite existing tribunal.yaml ---
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2"' EXIT

echo "existing: true" > "$TMPDIR2/tribunal.yaml"
mkdir -p "$TMPDIR2/.metaswarm"
cat > "$TMPDIR2/.metaswarm/project-profile.json" << 'JSON'
{"stack": "node"}
JSON

RESULT=$(node "$ROOT/lib/migrate-config.js" "$TMPDIR2" 2>&1)
CONTENT=$(cat "$TMPDIR2/tribunal.yaml")

if [ "$CONTENT" = "existing: true" ]; then
  pass "existing tribunal.yaml not overwritten"
else
  fail "existing tribunal.yaml was overwritten"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
