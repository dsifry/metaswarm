#!/usr/bin/env bash
# tests/agent-selection/test-agent-scorer.sh
# Validate agent scoring with weighted decay

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Agent Scorer Tests"
echo "=================="
echo ""

# --- Test: agent-scorer.js exists ---
if [ -f "$ROOT/lib/agent-scorer.js" ]; then
  pass "agent-scorer.js exists"
else
  fail "agent-scorer.js not found"
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test: no history returns static priority ---
cat > "$TMPDIR/stats.jsonl" << 'JSONL'
JSONL

set +e
RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "no history: scorer exited non-zero"
else
  FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")
  if [ "$FIRST" = "gemini" ]; then
    pass "no history: returns static priority (gemini first)"
  else
    fail "no history: expected gemini first, got $FIRST"
  fi
fi

# --- Test: tool with high recent success rate ranks higher ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)

cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
JSONL

set +e
RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "scoring: scorer exited non-zero"
else
  FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")
  if [ "$FIRST" = "codex" ]; then
    pass "scoring: codex (100% success) ranks above gemini (0% success)"
  else
    fail "scoring: expected codex first, got $FIRST"
  fi
fi

# --- Test: decay weights recent results more ---
OLD_DATE="2026-02-01T00:00:00Z"

cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
JSONL

set +e
RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex" \
  --static-priority "gemini,codex" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "decay: scorer exited non-zero"
else
  FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")
  if [ "$FIRST" = "codex" ]; then
    pass "decay: recent codex successes outweigh old gemini successes"
  else
    fail "decay: expected codex first, got $FIRST"
  fi
fi

# --- Test: failure pattern penalty ---
cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
JSONL

set +e
RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "codex,gemini" \
  --static-priority "codex,gemini" \
  --min-samples 3 \
  --decay-rate 0.1 \
  --task-tags "database,async" 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ]; then
  fail "failure penalty: scorer exited non-zero"
else
  FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")
  if [ "$FIRST" = "gemini" ]; then
    pass "failure penalty: gemini wins for database tasks despite codex having higher base rate"
  else
    fail "failure penalty: expected gemini first for database tasks, got $FIRST"
  fi
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
