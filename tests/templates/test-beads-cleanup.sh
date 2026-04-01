#!/usr/bin/env bash
# tests/templates/test-beads-cleanup.sh
# Verifies that redundant beads files have been removed and
# remaining references are updated for standalone beads plugin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
TOTAL=0

assert_file_missing() {
  local desc="$1"
  local filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$REPO_ROOT/$filepath" ]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — file still exists: $filepath"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

assert_file_exists() {
  local desc="$1"
  local filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$REPO_ROOT/$filepath" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — file missing: $filepath"
  fi
}

assert_file_contains() {
  local desc="$1"
  local filepath="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$expected" "$REPO_ROOT/$filepath" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — '$filepath' does not contain: $expected"
  fi
}

assert_file_not_contains() {
  local desc="$1"
  local filepath="$2"
  local unexpected="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$unexpected" "$REPO_ROOT/$filepath" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — '$filepath' still contains: $unexpected"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

echo "Running beads cleanup verification tests..."
echo ""

# --- Test 1: Redundant files removed ---
echo "Test 1: Redundant files removed"
assert_file_missing "beads-self-reflect.ts removed from scripts/" "scripts/beads-self-reflect.ts"
assert_file_missing "beads-self-reflect.ts removed from setup scripts/" "skills/setup/scripts/beads-self-reflect.ts"
assert_file_missing "beads-config.yaml removed from templates/" "templates/beads-config.yaml"
assert_file_missing "beads-config.yaml removed from setup templates/" "skills/setup/templates/beads-config.yaml"

# --- Test 2: Kept files still present ---
echo "Test 2: Kept files still present"
assert_file_exists "beads-fetch-pr-comments.ts kept" "scripts/beads-fetch-pr-comments.ts"
assert_file_exists "beads-fetch-conversation-history.ts kept" "scripts/beads-fetch-conversation-history.ts"
assert_file_exists "Setup copy of beads-fetch-pr-comments.ts kept" "skills/setup/scripts/beads-fetch-pr-comments.ts"
assert_file_exists "Setup copy of beads-fetch-conversation-history.ts kept" "skills/setup/scripts/beads-fetch-conversation-history.ts"

# --- Test 3: CLAUDE.md templates updated ---
echo "Test 3: CLAUDE.md templates reference standalone beads plugin"
assert_file_contains "Root CLAUDE.md mentions automatic bd prime" "CLAUDE.md" "standalone beads plugin"
assert_file_contains "Template CLAUDE.md mentions automatic bd prime" "templates/CLAUDE.md" "standalone beads plugin"
assert_file_contains "Setup template CLAUDE.md mentions automatic bd prime" "skills/setup/templates/CLAUDE.md" "standalone beads plugin"
assert_file_contains "Root CLAUDE.md mentions bd decision" "CLAUDE.md" "bd decision"
assert_file_contains "Template CLAUDE.md mentions bd decision" "templates/CLAUDE.md" "bd decision"

# --- Test 4: Developer setup references standalone plugin ---
echo "Test 4: Developer setup references standalone plugin installation"
assert_file_contains "templates/beads-developer-setup.md references plugin install" "templates/beads-developer-setup.md" "/plugin install beads"
assert_file_contains "setup template references plugin install" "skills/setup/templates/beads-developer-setup.md" "/plugin install beads"
assert_file_not_contains "templates/beads-developer-setup.md no longer references beads-self-reflect.ts" "templates/beads-developer-setup.md" "beads-self-reflect.ts"
assert_file_not_contains "setup template no longer references beads-self-reflect.ts" "skills/setup/templates/beads-developer-setup.md" "beads-self-reflect.ts"

# --- Test 5: README references standalone plugin ---
echo "Test 5: README templates reference standalone plugin"
assert_file_contains "templates/beads-readme.md references plugin install" "templates/beads-readme.md" "/plugin install beads"
assert_file_contains "setup template readme references plugin install" "skills/setup/templates/beads-readme.md" "/plugin install beads"

# --- Test 6: Setup SKILL.md no longer lists beads-self-reflect.ts ---
echo "Test 6: Setup SKILL.md updated"
assert_file_not_contains "Setup SKILL.md no longer lists beads-self-reflect.ts in scripts to copy" "skills/setup/SKILL.md" "- \`beads-self-reflect.ts\`"
assert_file_contains "Setup SKILL.md still lists beads-fetch-pr-comments.ts" "skills/setup/SKILL.md" "beads-fetch-pr-comments.ts"
assert_file_contains "Setup SKILL.md still lists beads-fetch-conversation-history.ts" "skills/setup/SKILL.md" "beads-fetch-conversation-history.ts"

# --- Test 7: USAGE.md updated ---
echo "Test 7: USAGE.md updated"
assert_file_not_contains "USAGE.md no longer lists beads-self-reflect.ts" "USAGE.md" "beads-self-reflect.ts"
assert_file_contains "USAGE.md lists beads-fetch-conversation-history.ts" "USAGE.md" "beads-fetch-conversation-history.ts"

# --- Test 8: self-reflect command references bd compact ---
echo "Test 8: self-reflect command references bd compact"
assert_file_contains "self-reflect references bd compact" "commands/self-reflect.md" "bd compact"

# --- Test 9: No hook conflicts ---
echo "Test 9: Session hook avoids conflict with beads plugin"
assert_file_contains "Hook checks for standalone beads" "hooks/session-start.sh" "beads_standalone"
assert_file_contains "Hook skips priming when beads standalone detected" "hooks/session-start.sh" "beads_standalone\" = false"

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
