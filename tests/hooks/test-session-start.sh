#!/usr/bin/env bash
# tests/hooks/test-session-start.sh
# Unit tests for session-start.sh hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../hooks/session-start.sh"
PASS=0
FAIL=0
TOTAL=0

assert_json_valid() {
  local desc="$1"
  local output="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{JSON.parse(d);process.exit(0)})" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — output was not valid JSON"
    echo "  Output: $output"
  fi
}

assert_contains() {
  local desc="$1"
  local output="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected to contain: $expected"
  fi
}

assert_not_contains() {
  local desc="$1"
  local output="$2"
  local unexpected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — should NOT contain: $unexpected"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

# --- Test setup ---
TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

echo "Running session-start.sh tests..."
echo ""

# --- Test 1: New project (no .metaswarm/project-profile.json) ---
echo "Test 1: New project detection"
TEST_CWD="$TMPDIR_BASE/test1"
mkdir -p "$TEST_CWD"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains setup nudge" "$output" "metaswarm:setup"

# --- Test 2: Configured project (has .metaswarm/project-profile.json) ---
echo "Test 2: Configured project"
TEST_CWD="$TMPDIR_BASE/test2"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_not_contains "No setup nudge" "$output" "metaswarm:setup"

# --- Test 3: Legacy install detection ---
echo "Test 3: Legacy install detection"
TEST_CWD="$TMPDIR_BASE/test3"
mkdir -p "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin"
echo '{"name":"metaswarm","version":"0.8.0"}' > "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin/plugin.json"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"npm"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains migrate message" "$output" "metaswarm:migrate"

# --- Test 4: BEADS dedup detection ---
echo "Test 4: BEADS dedup detection"
TEST_CWD="$TMPDIR_BASE/test4"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Simulate a BEADS plugin in the cache
MOCK_CACHE="$TMPDIR_BASE/.claude/plugins/cache/beads-marketplace/beads/1.0.0/.claude-plugin"
mkdir -p "$MOCK_CACHE"
echo '{"name":"beads","version":"1.0.0"}' > "$MOCK_CACHE/plugin.json"
output=$(cd "$TEST_CWD" && HOME="$TMPDIR_BASE" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"

# --- Test 5: Multi-line bd prime output produces valid JSON ---
echo "Test 5: Multi-line content produces valid JSON"
TEST_CWD="$TMPDIR_BASE/test5"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Create a mock bd that outputs multi-line content
MOCK_BIN="$TMPDIR_BASE/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/bd" << 'MOCKBD'
#!/bin/bash
echo "Line 1 with \"quotes\""
echo "Line 2 with backslash \\"
echo "Line 3 with tabs	here"
MOCKBD
chmod +x "$MOCK_BIN/bd"
output=$(cd "$TEST_CWD" && PATH="$MOCK_BIN:$PATH" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Multi-line output produces valid JSON" "$output"

# --- Test 6: Idempotency (run twice, same output) ---
echo "Test 6: Idempotency"
TEST_CWD="$TMPDIR_BASE/test6"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output1=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
output2=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
TOTAL=$((TOTAL + 1))
if [ "$output1" = "$output2" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: Same output on repeated runs"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Output differs between runs"
fi

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
