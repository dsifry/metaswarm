#!/bin/bash
# test-opencode-adapter.sh — Structural tests for the OpenCode external-tools adapter.
#
# These tests do NOT invoke real models (no network, no cost). They verify the
# adapter's contract: it exists, dispatches commands correctly, validates
# arguments, and produces well-formed health output.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ADAPTER="${REPO_ROOT}/skills/external-tools/adapters/opencode.sh"
COMMON="${REPO_ROOT}/skills/external-tools/adapters/_common.sh"

PASS=0
FAIL=0

pass() {
  printf '  PASS: %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf '  FAIL: %s\n' "$1"
  FAIL=$((FAIL + 1))
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label exists"
  else
    fail "$label MISSING: $path"
  fi
}

assert_file_executable() {
  local path="$1"
  local label="$2"
  if [[ -x "$path" ]]; then
    pass "$label is executable"
  else
    fail "$label is NOT executable: $path"
  fi
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if grep -qE -- "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' not found in $file)"
  fi
}

assert_grep_i() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if grep -qiE -- "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' not found in $file)"
  fi
}

# ---------------------------------------------------------------------------
# 1. Adapter file exists and is executable
# ---------------------------------------------------------------------------
assert_file_exists "$ADAPTER" "OpenCode adapter"
assert_file_executable "$ADAPTER" "OpenCode adapter"

# ---------------------------------------------------------------------------
# 2. Adapter exposes the three required commands
# ---------------------------------------------------------------------------
assert_grep 'cmd_health()' "$ADAPTER" "Adapter defines cmd_health"
assert_grep 'cmd_implement()' "$ADAPTER" "Adapter defines cmd_implement"
assert_grep 'cmd_review()' "$ADAPTER" "Adapter defines cmd_review"

# ---------------------------------------------------------------------------
# 3. Adapter sources the shared common helpers
# ---------------------------------------------------------------------------
assert_grep '_common.sh' "$ADAPTER" "Adapter sources _common.sh"

# ---------------------------------------------------------------------------
# 4. Adapter uses minimal env (env -i) for invocation, like codex.sh
# ---------------------------------------------------------------------------
assert_grep 'env -i' "$ADAPTER" "Adapter uses 'env -i' for minimal environment"

# ---------------------------------------------------------------------------
# 5. Adapter invokes `opencode run --format json` (headless)
# ---------------------------------------------------------------------------
assert_grep 'run --pure --format json' "$ADAPTER" "Adapter uses 'opencode run --pure --format json'"

# ---------------------------------------------------------------------------
# 6. Adapter passes --dir <worktree> for workspace isolation
# ---------------------------------------------------------------------------
assert_grep 'XT_WORKTREE' "$ADAPTER" "Adapter references XT_WORKTREE"
assert_grep '\-\-dir "\$XT_WORKTREE"' "$ADAPTER" "Adapter passes --dir for worktree isolation"

# ---------------------------------------------------------------------------
# 7. Adapter supports --model override (since OpenCode is multi-provider)
# ---------------------------------------------------------------------------
assert_grep 'XT_MODEL' "$ADAPTER" "Adapter references XT_MODEL"
assert_grep 'METASWARM_OPENCODE_MODEL' "$ADAPTER" "Adapter honors METASWARM_OPENCODE_MODEL env override"

# ---------------------------------------------------------------------------
# 8. Adapter dispatch handles unknown commands with a usage message
# ---------------------------------------------------------------------------
unknown_output="$("$ADAPTER" __nope__ 2>&1 || true)"
if printf '%s' "$unknown_output" | grep -q 'Usage:'; then
  pass "Unknown command prints usage"
else
  fail "Unknown command did not print usage"
fi

# ---------------------------------------------------------------------------
# 9. health subcommand emits a well-formed JSON envelope
#    (works whether opencode is installed or not)
# ---------------------------------------------------------------------------
health_output="$("$ADAPTER" health 2>/dev/null)"
# Normalize whitespace for substring checks (jq pretty-prints across lines)
health_norm="$(printf '%s' "$health_output" | tr -d '\n' | tr -s ' ')"

if printf '%s' "$health_norm" | grep -qE '"tool":[[:space:]]*"opencode"'; then
  pass "health JSON contains tool=opencode"
else
  fail "health JSON missing tool=opencode (got: $health_output)"
fi

if printf '%s' "$health_norm" | grep -qE '"status":[[:space:]]*"(ready|degraded|unavailable)"'; then
  pass "health JSON contains a valid status"
else
  fail "health JSON missing valid status (got: $health_output)"
fi

if printf '%s' "$health_norm" | grep -qE '"auth_valid":'; then
  pass "health JSON contains auth_valid"
else
  fail "health JSON missing auth_valid (got: $health_output)"
fi

if printf '%s' "$health_norm" | grep -qE '"model":[[:space:]]*"'; then
  pass "health JSON contains model"
else
  fail "health JSON missing model (got: $health_output)"
fi

# Validate JSON parses cleanly when jq is available
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$health_output" | jq . >/dev/null 2>&1; then
    pass "health JSON parses with jq"
  else
    fail "health JSON does not parse with jq (got: $health_output)"
  fi
fi

# ---------------------------------------------------------------------------
# 10. _common.sh exposes extract_cost_opencode
# ---------------------------------------------------------------------------
assert_grep 'extract_cost_opencode()' "$COMMON" "_common.sh defines extract_cost_opencode"

# ---------------------------------------------------------------------------
# 11. _common.sh parse_args supports --model
# ---------------------------------------------------------------------------
assert_grep '\-\-model' "$COMMON" "_common.sh parse_args handles --model"
assert_grep 'XT_MODEL=""' "$COMMON" "_common.sh initializes XT_MODEL"

# ---------------------------------------------------------------------------
# 12. implement/review fail fast on missing arguments
# ---------------------------------------------------------------------------
implement_err="$("$ADAPTER" implement 2>&1 || true)"
if printf '%s' "$implement_err" | grep -q '\-\-worktree is required'; then
  pass "implement requires --worktree"
else
  fail "implement did not error on missing --worktree (got: $implement_err)"
fi

review_err="$("$ADAPTER" review 2>&1 || true)"
if printf '%s' "$review_err" | grep -q '\-\-worktree is required'; then
  pass "review requires --worktree"
else
  fail "review did not error on missing --worktree (got: $review_err)"
fi

# ---------------------------------------------------------------------------
# 13. SKILL.md and external-tools.yaml mention opencode
# ---------------------------------------------------------------------------
assert_grep_i 'opencode' "$REPO_ROOT/skills/external-tools/SKILL.md" "SKILL.md mentions opencode"
assert_grep_i 'opencode:' "$REPO_ROOT/templates/external-tools.yaml" "external-tools.yaml has opencode adapter block"

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
