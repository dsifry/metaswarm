#!/usr/bin/env bash
# tests/agents/test-requirement-choice.sh
# "Ask as soon as a blocker rests on a requirement choice": one definition in the guide,
# every needs_user copy points at it, the orchestrator classifies before the helper runs,
# the Clarification report asks with options, pros/cons, a recommendation and a rationale, and the
# planner and coders STOP and ask instead of choosing silently.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
GUIDE="guides/delivery-scope.md"
PASS=0
FAIL=0
DONE=0
trap '[ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
has() { grep -qF -- "$2" "$1" && pass "$1 has '$2'" || fail "$1 missing '$2'"; }

section() {
  awk -v re="$2" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$1"
}

echo "Test 1: one definition in the guide"
n="$(grep -c '^- \*\*Requirement choice\.\*\*' "$GUIDE" || true)"
[ "$n" = 1 ] && pass "guide defines Requirement choice exactly once" || fail "guide defines Requirement choice $n times"
SF="$(section "$GUIDE" '^### Signal fields')"
for s in 'Requirement choice' 'two or more acceptable' 'how strong a proof' 'is not a requirement choice' \
  'needs_user: yes' 'origin: requirement' 'classifiedBy' 'pros and cons' 'recommended option'; do
  grep -qF -- "$s" <<<"$SF" && pass "Signal fields has '$s'" || fail "Signal fields missing '$s'"
done
for f in skills/*/guides/delivery-scope.md; do
  cmp -s "$GUIDE" "$f" && pass "$f in sync" || fail "$f differs from $GUIDE"
done

echo "Test 2: every needs_user definition copy references the guide"
COPIES=0
while IFS= read -r line; do
  f="${line%%:*}"; COPIES=$((COPIES + 1))
  case "$line" in
    *"or the fix is a requirement choice (see the guide)"*) pass "$f needs_user copy references the requirement choice" ;;
    *) fail "$f needs_user copy lacks the requirement-choice clause: $line" ;;
  esac
done < <(grep -rnE 'needs_user: yes \| no +(#|\().*blockers only: yes only if' agents rubrics skills --include='*.md' --include='*.sh' | grep -v '^skills/.*/guides/')
[ "$COPIES" -ge 18 ] && pass "found $COPIES needs_user copies" || fail "only $COPIES needs_user copies found"

echo "Test 3: orchestrator classifies before the helper"
for s in skills/orchestrated-execution/SKILL.md skills/plan-review-gate/SKILL.md skills/design-review-gate/SKILL.md; do
  step="$(grep -F -- '**After each round, before the rule.**' "$s" || true)"
  for t in 'requirement choice' 'classifiedBy: orchestrator' 'needs_user: yes' 'origin: requirement' 'even when the reviewer said no'; do
    grep -qF -- "$t" <<<"$step" && pass "$s classify step has '$t'" || fail "$s classify step missing '$t'"
  done
done
DUTY="$(section "$GUIDE" '^### Clarify signals')"
for t in 'orchestrator classifies' 'classifiedBy: orchestrator' 'C1 fires that same round' 'recommended default'; do
  grep -qF -- "$t" <<<"$DUTY" && pass "Clarify signals has '$t'" || fail "Clarify signals missing '$t'"
done
grep -qF 'questions never block' <<<"$DUTY" && pass "duty keeps the non-blocking-questions rule" || fail "duty missing non-blocking rule"

echo "Test 4: Clarification report asks with options, pros/cons, a recommendation and a rationale"
REPORT="$(section "$GUIDE" '^### Clarification report')"
n="$(grep -c '^### Clarification report' "$GUIDE" || true)"
[ "$n" = 1 ] && pass "exactly one Clarification report template" || fail "$n Clarification report templates"
for t in 'Pros:' 'Cons:' 'Recommended:' 'Rationale:'; do
  grep -qF -- "$t" <<<"$REPORT" && pass "report template has '$t'" || fail "report template missing '$t'"
done

echo "Test 5: planner and coders STOP on an unsettled requirement choice"
for f in agents/planner.md agents/coder.md agents/supercoder.md skills/start/agents/planner.md skills/start/agents/coder.md skills/start/agents/supercoder.md; do
  has "$f" 'requirement choice'
  has "$f" 'options with pros/cons and a recommendation'
done
has skills/orchestrated-execution/SKILL.md 'a requirement choice the brief does not settle'

echo "Test 6: plugin copies are in sync"
node lib/sync-resources.js --check >/dev/null && pass "sync-resources --check" || fail "sync-resources --check"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" = 0 ]
