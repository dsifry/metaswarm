#!/bin/bash
# external-tools-verify.sh — End-to-end verification for the external-tools skill
#
# Tests adapter scripts, shared helpers, config templates, and documentation.
# Prints PASS/FAIL per check with a final summary and exit code.
#
# Usage: bin/external-tools-verify.sh

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve paths relative to the repo root
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ADAPTERS_DIR="${REPO_ROOT}/skills/external-tools/adapters"
COMMON_SH="${ADAPTERS_DIR}/_common.sh"
CODEX_SH="${ADAPTERS_DIR}/codex.sh"
GEMINI_SH="${ADAPTERS_DIR}/gemini.sh"

PASS_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() {
  printf 'PASS: %s\n' "$1"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail() {
  printf 'FAIL: %s\n' "$1"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

# ---------------------------------------------------------------------------
# 1. _common.sh tests
# ---------------------------------------------------------------------------
printf '\n=== _common.sh ===\n'

# Syntax check
check "_common.sh syntax" bash -n "$COMMON_SH"

# create_secure_tmp: directory exists and has mode 700
TMP_DIR="$(bash -c "source '$COMMON_SH' && create_secure_tmp")"
if [[ -d "$TMP_DIR" ]]; then
  PERMS="$(stat -f '%Lp' "$TMP_DIR" 2>/dev/null || stat -c '%a' "$TMP_DIR" 2>/dev/null || printf '')"
  if [[ "$PERMS" == "700" ]]; then
    pass "create_secure_tmp permissions (700)"
  else
    fail "create_secure_tmp permissions (got $PERMS, expected 700)"
  fi
  rm -rf "$TMP_DIR"
else
  fail "create_secure_tmp did not create a directory"
fi

# classify_error: timeout (exit 124) -> "timeout"
RESULT="$(bash -c "source '$COMMON_SH' && classify_error 124 ''")"
if [[ "$RESULT" == "timeout" ]]; then
  pass "classify_error 124 -> timeout"
else
  fail "classify_error 124 -> expected 'timeout', got '$RESULT'"
fi

# classify_error: command not found (exit 127) -> "tool_not_installed"
RESULT="$(bash -c "source '$COMMON_SH' && classify_error 127 ''")"
if [[ "$RESULT" == "tool_not_installed" ]]; then
  pass "classify_error 127 -> tool_not_installed"
else
  fail "classify_error 127 -> expected 'tool_not_installed', got '$RESULT'"
fi

# classify_error: generic error -> "tool_crash"
RESULT="$(bash -c "source '$COMMON_SH' && classify_error 1 ''")"
if [[ "$RESULT" == "tool_crash" ]]; then
  pass "classify_error 1 -> tool_crash"
else
  fail "classify_error 1 -> expected 'tool_crash', got '$RESULT'"
fi

# emit_error: produces valid JSON
ERROR_JSON="$(bash -c "source '$COMMON_SH' && emit_error codex implement gpt-5.3-codex 1 1 '' 0 ''")"
if printf '%s' "$ERROR_JSON" | jq . >/dev/null 2>&1; then
  pass "emit_error produces valid JSON"
else
  fail "emit_error does not produce valid JSON"
fi

# ---------------------------------------------------------------------------
# 2. codex.sh tests
# ---------------------------------------------------------------------------
printf '\n=== codex.sh ===\n'

# Syntax check
check "codex.sh syntax" bash -n "$CODEX_SH"

# Health produces valid JSON
HEALTH_JSON="$(bash "$CODEX_SH" health 2>/dev/null || true)"
if printf '%s' "$HEALTH_JSON" | jq . >/dev/null 2>&1; then
  pass "codex.sh health produces valid JSON"
else
  fail "codex.sh health does not produce valid JSON"
fi

# Health JSON contains required keys
if printf '%s' "$HEALTH_JSON" | jq -e '.tool and .status and .model' >/dev/null 2>&1; then
  pass "codex.sh health JSON has required keys (tool, status, model)"
else
  fail "codex.sh health JSON missing required keys"
fi

# ---------------------------------------------------------------------------
# 3. gemini.sh tests
# ---------------------------------------------------------------------------
printf '\n=== gemini.sh ===\n'

# Syntax check
check "gemini.sh syntax" bash -n "$GEMINI_SH"

# Health produces valid JSON
HEALTH_JSON="$(bash "$GEMINI_SH" health 2>/dev/null || true)"
if printf '%s' "$HEALTH_JSON" | jq . >/dev/null 2>&1; then
  pass "gemini.sh health produces valid JSON"
else
  fail "gemini.sh health does not produce valid JSON"
fi

# Health JSON contains required keys
if printf '%s' "$HEALTH_JSON" | jq -e '.tool and .status and .model' >/dev/null 2>&1; then
  pass "gemini.sh health JSON has required keys (tool, status, model)"
else
  fail "gemini.sh health JSON missing required keys"
fi

# ---------------------------------------------------------------------------
# 4. File existence checks
# ---------------------------------------------------------------------------
printf '\n=== File existence ===\n'

check "templates/external-tools.yaml exists" test -f "${REPO_ROOT}/templates/external-tools.yaml"
check "skills/external-tools/SKILL.md exists" test -f "${REPO_ROOT}/skills/external-tools/SKILL.md"
check "rubrics/external-tool-review-rubric.md exists" test -f "${REPO_ROOT}/rubrics/external-tool-review-rubric.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
printf '\n=== Summary ===\n'
printf '%d/%d passed, %d failed\n' "$PASS_COUNT" "$TOTAL" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
