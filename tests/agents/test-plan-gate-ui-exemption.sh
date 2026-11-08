#!/usr/bin/env bash
# tests/agents/test-plan-gate-ui-exemption.sh
# #83 item 4: the plan-review gate skips small plans (under 2 work units and
# 3 files), which let a one-work-unit UI plan skip the Completeness check for a
# UI integration work unit. A plan that builds user-facing UI always gets the
# gate, whatever its size.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/plan-review-gate/SKILL.md"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Plan-review gate: UI plans are exempt from the size threshold"
threshold="$(grep -n 'Do NOT use for' "$SKILL" || true)"
[ -n "$threshold" ] && pass "found the size threshold" || fail "no 'Do NOT use for' line in $SKILL"
if printf '%s\n' "$threshold" | grep -qi 'user-facing UI' && printf '%s\n' "$threshold" | grep -qi 'whatever its size\|regardless of size'; then
  pass "the threshold says a plan that builds user-facing UI always gets the gate"
else
  fail "the threshold doesn't exempt UI plans: $threshold"
fi
if printf '%s\n' "$threshold" | grep -qi 'UI integration work unit'; then
  pass "it names the check the exemption protects (UI integration work unit)"
else
  fail "the exemption doesn't say why (UI integration work unit check)"
fi
anti="$(grep -n 'Skipping the gate for "simple" plans' "$SKILL" || true)"
if printf '%s\n' "$anti" | grep -qi 'user-facing UI'; then
  pass "anti-pattern 4 also covers UI plans"
else
  fail "anti-pattern 4 still gives only the size rule: $anti"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
