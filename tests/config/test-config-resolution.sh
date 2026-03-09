#!/usr/bin/env bash
# tests/config/test-config-resolution.sh
# Validate tribunal.yaml deep-merge resolution logic

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Config Resolution Tests"
echo "======================="
echo ""

# --- Test: resolve-config.js exists ---
if [ -f "$ROOT/lib/resolve-config.js" ]; then
  pass "resolve-config.js exists"
else
  fail "resolve-config.js not found"
fi

# --- Test: common-only resolution (no tool override) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
  sandbox: docker
  coverage:
    lines: 100
    branches: 100
YAML

set +e
RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "common-only: resolver exited non-zero"
else
  TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")
  if [ "$TIMEOUT" = "300" ]; then
    pass "common-only: timeout_seconds = 300"
  else
    fail "common-only: expected 300, got $TIMEOUT"
  fi
fi

# --- Test: scalar override ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
  sandbox: docker
claude:
  timeout_seconds: 600
YAML

set +e
RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "scalar override: resolver exited non-zero"
else
  TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")
  if [ "$TIMEOUT" = "600" ]; then
    pass "scalar override: claude timeout_seconds = 600"
  else
    fail "scalar override: expected 600, got $TIMEOUT"
  fi
fi

# --- Test: nested object merge (not replace) ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  coverage:
    lines: 100
    branches: 100
    functions: 100
gemini:
  coverage:
    branches: 90
YAML

set +e
RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "gemini" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "nested merge: resolver exited non-zero"
else
  LINES=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.lines)")
  BRANCHES=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.branches)")
  FUNCTIONS=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.functions)")
  if [ "$LINES" = "100" ] && [ "$BRANCHES" = "90" ] && [ "$FUNCTIONS" = "100" ]; then
    pass "nested merge: gemini overrides branches only, lines+functions inherited"
  else
    fail "nested merge: expected 100/90/100, got $LINES/$BRANCHES/$FUNCTIONS"
  fi
fi

# --- Test: array replace (not merge) ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  debate:
    agents:
      - architect
      - security
      - cto
claude:
  debate:
    agents:
      - architect
      - security
      - cto
      - designer
YAML

set +e
RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "array replace: resolver exited non-zero"
else
  COUNT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.debate.agents.length)")
  if [ "$COUNT" = "4" ]; then
    pass "array replace: claude debate agents = 4 (replaced, not merged)"
  else
    fail "array replace: expected 4, got $COUNT"
  fi
fi

# --- Test: missing tool block uses common as-is ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
claude:
  timeout_seconds: 600
YAML

set +e
RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "codex" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "missing tool block: resolver exited non-zero"
else
  TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")
  if [ "$TIMEOUT" = "300" ]; then
    pass "missing tool block: codex falls back to common"
  else
    fail "missing tool block: expected 300, got $TIMEOUT"
  fi
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
