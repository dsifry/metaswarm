#!/usr/bin/env bash
# tests/agents/test-workflow-enforcement.sh
# Issue #67: reconcile metaswarm workflow enforcement with superpowers >= 6.4.1.
# Each section is owned by one work unit; later work units append sections.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUIDE="$REPO_ROOT/guides/workflow-enforcement.md"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if ! grep -qF -e "$s" <<<"$text"; then fail "$label: missing '$s'"; return; fi
  done
  pass "$label"
}

# Canonical strings (reused by later work units)
T_TRIGGER='Run the Design Review Gate only for project-sized work: brainstorming wrote and committed a design doc file (superpowers 6.4.x Architectural path; 7.x project size). Designs given only in chat (quick tasks, small or bounded changes) skip the gate.'
T_LOCATIONS='`docs/plans/*-design.md` and `docs/superpowers/specs/*-design.md`'
T_INTERCEPT='Run the Plan Review Gate after the plan is written and before writing-plans presents the plan: do not link the plan, ask the user to review it, or offer an execution choice until all 3 reviewers PASS.'
T_NATIVE='**Native inline execution** (`superpowers:executing-plans`) — I implement every task myself in this session, then one fresh reviewer checks the whole branch. Cheapest and fastest; no independent review until the end.'

# ---------------------------------------------------------------------------
echo "WU1: canonical guide"
# ---------------------------------------------------------------------------

if [ -f "$GUIDE" ]; then pass "guides/workflow-enforcement.md exists"; G="$(cat "$GUIDE")"; else fail "guides/workflow-enforcement.md exists"; G=""; fi

assert_in "guide has T-TRIGGER" "$G" "$T_TRIGGER"
assert_in "guide has T-LOCATIONS" "$G" "$T_LOCATIONS"
assert_in "guide has T-INTERCEPT" "$G" "$T_INTERCEPT"
assert_in "guide has T-NATIVE" "$G" "$T_NATIVE"
assert_in "guide names tiers and versions" "$G" "Bounded" "Architectural" "6.4.1" "7.0.2"

for d in brainstorming-extension design-review-gate plan-review-gate start orchestrated-execution; do
  m="$REPO_ROOT/skills/$d/guides/workflow-enforcement.md"
  if [ -f "$GUIDE" ] && [ -f "$m" ] && cmp -s "$GUIDE" "$m"; then
    pass "skills/$d mirror is byte-identical"
  else
    fail "skills/$d mirror is byte-identical"
  fi
done

if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  pass "sync-resources --check exits 0"
else
  fail "sync-resources --check exits 0"
fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
