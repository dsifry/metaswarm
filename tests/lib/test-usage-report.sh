#!/usr/bin/env bash
# tests/lib/test-usage-report.sh
# End-to-end tests for bin/metaswarm-usage against synthetic fixture transcripts

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bin/metaswarm-usage"
FX="$ROOT/tests/lib/fixtures/usage"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "metaswarm-usage Tests"
echo "====================="
echo ""

# 1. Executable, shebang, no dependencies
if [ -x "$BIN" ]; then pass "bin/metaswarm-usage is executable"; else fail "bin/metaswarm-usage missing or not executable"; fi
if head -1 "$BIN" 2>/dev/null | grep -q '^#!/usr/bin/env node$'; then pass "has node shebang"; else fail "missing node shebang"; fi
if grep -Eo "require\\(['\"][^'\"]*['\"]\\)" "$BIN" | grep -Evq "require\\(['\"](fs|os|path)['\"]\\)" 2>/dev/null; then fail "requires a third-party package"; else pass "no third-party requires"; fi
if [ -f "$ROOT/skills/setup/bin/metaswarm-usage" ] && cmp -s "$BIN" "$ROOT/skills/setup/bin/metaswarm-usage"; then pass "synced copy in skills/setup/bin"; else fail "skills/setup/bin copy missing or differs"; fi

# 2. Text report: exact rows
OUT="$("$BIN" --root "$FX" 2>&1)" || true
check_row() {
  if echo "$OUT" | grep -Eq "$2"; then pass "$1"; else fail "$1 (pattern: $2)"; fi
}
check_row "type row general-purpose" '^general-purpose +8 +16 +97 +907 +52$'
check_row "type row unknown" '^unknown +2 +6 +51 +501 +26$'
check_row "model row opus" '^claude-opus-5-5 +12 +56 +498 +4909 +255$'
check_row "model row sonnet" '^claude-sonnet-5-5 +12 +20 +119 +1109 +64$'
check_row "phase row plan-review" '^plan-review +5 +34 +305 +3006 +157$'
check_row "phase row implement" '^implement +4 +7 +61 +601 +31$'
check_row "phase row unclassified" '^unclassified +4 +8 +53 +503 +28$'
check_row "malformed line count reported" 'Skipped 1 malformed line'

# 3. Duplicate message id counted once (a2: 20/200/2000/100, not doubled)
check_row "dedup: plan-reviewer type" '^plan-reviewer +2 +21 +201 +2001 +101$'

# 4. Empty root
EMPTY="$(mktemp -d)"
set +e
EOUT="$("$BIN" --root "$EMPTY" 2>&1)"; ECODE=$?
set -e
rmdir "$EMPTY"
if [ "$ECODE" -eq 0 ] && echo "$EOUT" | grep -qi 'no transcripts'; then pass "empty root: 'no transcripts', exit 0"; else fail "empty root behaviour (code $ECODE)"; fi

# 5. --project glob
POUT="$("$BIN" --root "$FX" --project '*beta*' 2>&1)" || true
if echo "$POUT" | grep -Eq '^plan-review +2 +'; then pass "--project glob filters"; else fail "--project glob did not filter"; fi

# 6. --json parses
if "$BIN" --root "$FX" --json | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(j.agents===25?0:1)'; then pass "--json parses with 25 agents"; else fail "--json invalid"; fi

# 7. --gates
GOUT="$("$BIN" --root "$FX" --gates 2>&1)" || true
if echo "$GOUT" | grep -Eq '^plan-review +2 +1 +1 +0 +1\.50'; then pass "--gates: plan-review 2 occurrences, avg 1.50 rounds"; else fail "--gates plan-review row"; fi

# 8. --pricing
PF="$(mktemp)"
cat > "$PF" <<'JSON'
{"claude-opus-5-5":{"input":15,"cacheWrite":18.75,"cacheRead":1.5,"output":75},
 "claude-sonnet-5-5":{"input":3,"cacheWrite":3.75,"cacheRead":0.3,"output":15}}
JSON
COUT="$("$BIN" --root "$FX" --pricing "$PF" 2>&1)" || true
rm -f "$PF"
if echo "$COUT" | grep -q 'Cost (USD)'; then pass "--pricing adds cost column"; else fail "--pricing cost column missing"; fi
if echo "$COUT" | grep -Eq '^claude-opus-5-5 .* 0\.0367$'; then pass "opus cost 0.0367"; else fail "opus cost row"; fi

# Coverage gate enforces the 100% thresholds for bin/metaswarm-usage (not just reports them)
for f in "$ROOT/.coverage-thresholds.json" "$ROOT/.github/workflows/ci.yml"; do
  if grep -q -- '--test-coverage-lines=100' "$f" && grep -q -- '--test-coverage-branches=100' "$f" && grep -q -- '--test-coverage-functions=100' "$f"; then
    pass "$(basename "$f") enforces 100% node coverage thresholds"
  else
    fail "$(basename "$f") does not enforce node coverage thresholds"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
