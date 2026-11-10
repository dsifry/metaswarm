#!/usr/bin/env bash
# tests/agents/test-reviewer-criteria.sh
# #105: reviewer agent definitions carry their role criteria, so a fresh
# subagent gets them whatever the orchestrator's prompt says. The embedded
# copies must not drift from their sources:
#   design-reviewer "## Role criteria"  <- each role's "## Review Criteria" in
#                                           skills/design-review-gate/SKILL.md
#   plan-reviewer   "## Role criteria"  <- "## Review Categories" in
#                                           rubrics/plan-review-rubric-adversarial.md
# Comparison strips leading '#' and whitespace and drops blank lines, so the
# demoted heading levels inside the embed don't count as drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRG="$REPO_ROOT/skills/design-review-gate/SKILL.md"
RUBRIC="$REPO_ROOT/rubrics/plan-review-rubric-adversarial.md"
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

NEG=""
DONE=0
trap '${NEG:+rm -rf "$NEG"}; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

norm() { sed -E 's/^#+//; s/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' || true; }

# src_role <skill file> <prompt heading>: the role's checklist, from the line after
# "## Review Criteria" to the first stop marker.
src_role() {
  awk -v h="### $2" '
    $0 == h { inblk = 1; next }
    inblk && /^### .* Agent Prompt$/ { exit }
    inblk && $0 == "## Review Criteria" { on = 1; next }
    on && (index($0, "${sharedFindingRules}") || /^## Required Context/ || /^## Output Format/) { exit }
    on { print }
  ' "$1"
}
# emb_role <agent file> <role>: the "### <role>" subsection of "## Role criteria".
emb_role() {
  awk -v h="### $2" '
    $0 == "## Role criteria" { sec = 1; next }
    sec && /^## / { exit }
    sec && $0 == h { on = 1; next }
    on && /^### / { exit }
    on { print }
  ' "$1"
}
src_plan() { awk '$0 == "## Review Categories" { on = 1; next } on && $0 == "---" { exit } on { print }' "$1"; }
# emb_plan <agent file>: "## Role criteria" from its first ### heading to the section end.
emb_plan() { awk '$0 == "## Role criteria" { sec = 1; next } sec && /^## / { exit } sec && /^### / { on = 1 } on { print }' "$1"; }

# same <label> <source text> <embedded text>
same() {
  local a b
  a="$(norm <<<"$2")"; b="$(norm <<<"$3")"
  if [ -z "$a" ]; then fail "$1: source block is empty"; return; fi
  if [ "$a" = "$b" ]; then pass "$1"; else
    fail "$1: embedded criteria drifted from the source"
    { diff <(echo "$a") <(echo "$b") || true; } | head -6 | sed "s/^/      /"
  fi
}

ROLES=("PM|Product Manager Agent Prompt" "Architect|Architect Agent Prompt" "Designer|Designer Agent Prompt"
  "Security|Security Design Agent Prompt" "UX|UX Reviewer Agent Prompt" "CTO|CTO Agent Prompt")

check_design() { # <label prefix> <skill file> <agent file>
  local r role head
  for r in "${ROLES[@]}"; do
    role="${r%%|*}"; head="${r#*|}"
    same "$1 design-reviewer $role criteria match the gate prompt" "$(src_role "$2" "$head")" "$(emb_role "$3" "$role")"
  done
}

echo "Embedded criteria match their sources"
for d in agents skills/start/agents; do
  check_design "$d:" "$DRG" "$REPO_ROOT/$d/design-reviewer.md"
  same "$d: plan-reviewer criteria match the rubric's Review Categories" "$(src_plan "$RUBRIC")" "$(emb_plan "$REPO_ROOT/$d/plan-reviewer.md")"
done

echo "Criteria apply whatever the task prompt focuses on"
for d in agents skills/start/agents; do
  for a in design-reviewer plan-reviewer; do
    RC="$(awk '$0 == "## Role criteria" { on = 1 } on && /^## / && $0 != "## Role criteria" { exit } on { print }' "$REPO_ROOT/$d/$a.md")"
    assert_in "$d/$a: Role criteria apply whatever the task prompt focuses on" "$RC" \
      'whatever the task prompt focuses on' 'never replaces these criteria'
  done
  CC="$(awk '$0 == "## Criteria check" { on = 1; next } on && /^## / { exit } on { print }' "$REPO_ROOT/$d/design-reviewer.md")"
  assert_in "$d/design-reviewer: requires a Criteria check table" "$CC" \
    '### Criteria check' 'one row per checklist item' 'PASS / FAIL / N/A' 'one line of evidence'
done

echo "Criteria receipt (fix 3)"
sect() { awk -v h="$1" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$2"; }
for d in agents skills/start/agents; do
  for a in design-reviewer plan-reviewer adversarial-reviewer; do
    RS="$(sect "## Criteria receipt" "$REPO_ROOT/$d/$a.md")"
    assert_in "$d/$a: requires the Criteria applied receipt after the verdict heading" "$RS" \
      '`Criteria applied: ' 'directly after the verdict heading' 'first line of the body' \
      'read it first' 'the rubric you actually applied' 're-requested'
  done
  RS="$(sect "## Criteria receipt" "$REPO_ROOT/$d/adversarial-reviewer.md")"
  assert_in "$d/adversarial-reviewer: receipt names the rubric per mode" "$RS" \
    'Collaborative mode' 'code-review-rubric' 'Adversarial mode' 'adversarial-review-rubric' 'names a different rubric'
  assert_in "$d/design-reviewer: Criteria check table comes right after the receipt" \
    "$(sect "## Criteria check" "$REPO_ROOT/$d/design-reviewer.md")" 'right after the `Criteria applied:` line'
done
GUIDE_RULE="$(grep -F 'Missing criteria receipt' "$REPO_ROOT/guides/delivery-scope.md" || true)"
assert_in "guide: missing receipt is re-requested once, then accepted as a follow-up" "$GUIDE_RULE" \
  '`Criteria applied:`' 'any verdict' 're-requested once' 'accepted' 'follow-up' 'never blocks' \
  'Codex' 'Gemini' 'in-session'
for g in skills/plan-review-gate/SKILL.md skills/design-review-gate/SKILL.md skills/orchestrated-execution/SKILL.md; do
  assert_in "$g: malformed-output rule covers a missing receipt" "$(grep -F 'is re-requested once in the contract format' "$REPO_ROOT/$g")" \
    'without a `Criteria applied:` line' 're-requested once' 'never blocks'
done

echo "Self-test: drift is detected"
NEG="$(mktemp -d)"
cp "$REPO_ROOT/agents/design-reviewer.md" "$NEG/d.md"
sed -i.bak 's/Follows existing codebase patterns/Follows some codebase patterns/' "$NEG/d.md"
neg="$(check_design "neg" "$DRG" "$NEG/d.md" 2>&1 || true)"
if grep -q "FAIL: neg design-reviewer Architect criteria match the gate prompt: embedded criteria drifted" <<<"$neg"; then
  pass "self-test: a changed Architect checklist line is reported as drift"
else
  fail "self-test: a changed Architect checklist line was not detected"
fi
neg="$(same "neg-empty" "" "")"
if grep -q "FAIL: neg-empty: source block is empty" <<<"$neg"; then pass "self-test: an empty source is never a match"; else fail "self-test: an empty source matched"; fi
rm -rf "${NEG:?}"; NEG=""

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
