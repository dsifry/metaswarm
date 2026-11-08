#!/usr/bin/env bash
# tests/agents/test-design-gate-reviewers.sh
# The Design Review Gate runs 6 reviewers (PM, Architect, Designer, Security,
# UX Reviewer, CTO; issue #12), and every description of the gate agrees.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRG="$REPO_ROOT/skills/design-review-gate/SKILL.md"
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
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap '${NEG:+rm -rf "$NEG"}; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

# section <file> <ERE for the heading line>: prints the heading and its body up to the
# next ## or ### heading outside a code fence (headings inside fenced prompts don't end it)
section() {
  awk -v re="$2" '
    {
      isfence = 0
      if (substr($0, 1, 3) == "```") { run = $0; sub(/[^`].*$/, "", run); isfence = 1 }
    }
    on && fence == "" && !isfence && /^###? / { exit }
    !on && $0 ~ re { on = 1 }
    on { print }
    isfence { if (fence == "") fence = run; else if ($0 == fence) fence = "" }
  ' "$1"
}

echo ""
echo "Design Review Gate: 6 reviewers"
echo "==============================="
echo ""

T="$(cat "$DRG")"

# ---------------------------------------------------------------------------
echo "(a) the gate spawns 6 design-reviewer Task calls, one of them UX review"
# ---------------------------------------------------------------------------
PH1="$(section "$DRG" '^### Phase 1: Spawn Review Agents')"
n="$(grep -cF -e 'subagent_type: roleType("design-reviewer")' <<<"$PH1" || true)"
[ "$n" -eq 6 ] && pass "Phase 1 spawns 6 roleType(\"design-reviewer\") Task calls" \
  || fail "Phase 1 spawns 6 roleType(\"design-reviewer\") Task calls (found $n)"
n="$(grep -cF -e 'Task({' <<<"$PH1" || true)"
[ "$n" -eq 6 ] && pass "Phase 1 has 6 Task({ blocks" || fail "Phase 1 has 6 Task({ blocks (found $n)"
assert_in "Phase 1 has the UX review Task" "$PH1" \
  'description: "UX review"' 'prompt: uxReviewPrompt(designDocPath)' 'uxResult'
assert_in "Purpose lists the UX Reviewer Agent as item 6" "$T" \
  '6. **UX Reviewer Agent** - ' 'All six must approve'
assert_in "ReviewResult agent union has ux-reviewer" "$T" '| "ux-reviewer" |'
assert_in "Team Mode names the ux teammate" "$T" \
  'spawn 6 reviewers as named teammates (`pm`, `architect`, `designer`, `security`, `ux`, `cto`)'
assert_in "Task Mode spawns 6" "$T" '**Task Mode** (default): Spawn 6 parallel `Task()` subagents'
assert_in "FRESH review re-runs all six" "$T" '"FRESH review" means re-running all six reviewers'
assert_in "PASS rule names all six" "$T" '**PASS, advance**: all six agents are APPROVED'
APPR="$(section "$DRG" '^### Approved Design')"
assert_in "Approved table has a UX Reviewer row" "$APPR" '| UX Reviewer     | APPROVED |'

# ---------------------------------------------------------------------------
echo ""
echo "(b) the UX Reviewer Agent Prompt"
# ---------------------------------------------------------------------------
UXP="$(section "$DRG" '^### UX Reviewer Agent Prompt')"
if [ -n "$UXP" ]; then pass "UX Reviewer Agent Prompt section exists"; else fail "UX Reviewer Agent Prompt section exists"; fi
assert_in "UX prompt has the persona structure" "$UXP" \
  '## Your Task' '## Design Document' '## Review Criteria' '${sharedFindingRules}' '## Output Format' \
  '"agent": "ux-reviewer"' '"findings": ['
assert_in "UX prompt checklist covers issue #12" "$UXP" \
  'trigger' 'visible outcome' 'component hierarchy' \
  'Empty, loading and error states are defined for each view' \
  'explicit integration work unit that wires the components into the app shell' 'UI-FLOWS'
assert_in "UX prompt approves backend-only designs" "$UXP" \
  'no user-facing UI' 'return APPROVED with no findings'
ln_sec="$(grep -n -E '^### Security Design Agent Prompt' "$DRG" | cut -d: -f1 || true)"
ln_ux="$(grep -n -E '^### UX Reviewer Agent Prompt' "$DRG" | cut -d: -f1 || true)"
ln_cto="$(grep -n -E '^### CTO Agent Prompt' "$DRG" | cut -d: -f1 || true)"
if [ -n "$ln_sec" ] && [ -n "$ln_ux" ] && [ -n "$ln_cto" ] && [ "$ln_sec" -lt "$ln_ux" ] && [ "$ln_ux" -lt "$ln_cto" ]; then
  pass "UX prompt sits between the Security Design and CTO prompts"
else
  fail "UX prompt sits between the Security Design and CTO prompts (sec=$ln_sec ux=$ln_ux cto=$ln_cto)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "(c) both design-reviewer twins name UX"
# ---------------------------------------------------------------------------
for f in agents/design-reviewer.md skills/start/agents/design-reviewer.md; do
  D="$(cat "$REPO_ROOT/$f")"
  assert_in "$f names UX in description, body and role table" "$D" \
    'The role (PM, Architect, Designer, Security, UX or CTO) is passed in the prompt' \
    'passes the **role** in the prompt: PM, Architect, Designer, Security, UX or CTO' \
    "| UX | none: the checklist is in the gate's UX Reviewer prompt |"
done
n="$(ls "$REPO_ROOT"/agents/*.md | wc -l | tr -d ' ')"
[ "$n" -eq 22 ] && pass "agents/ still has 22 agents (no new UX agent file)" \
  || fail "agents/ still has 22 agents (no new UX agent file; found $n)"

# ---------------------------------------------------------------------------
echo ""
echo "(d) no stale 5-reviewer phrasing for the gate"
# ---------------------------------------------------------------------------
# All patterns are case-insensitive EREs matched per line. The bare "5 agents"
# pattern excludes a leading "(" so "(5 agents)" has its own pattern.
STALE_RE=(
  'five specialist'
  'all five'
  '(^|[^[:alnum:]_(])5 agents'
  '(^|[^[:alnum:]_])5-agent'
  '(^|[^[:alnum:]_])5 reviewers'
  '(^|[^[:alnum:]_])5-reviewer'
  '\(5 agents\)'
  '(^|[^[:alnum:]_])5 review agents'
  'pm, architect, designer, security,? (and |or )?cto'
)
STALE_EXCLUDES=(
  ':!CHANGELOG.md'
  ':!docs/plans/'
  ':!docs/handoffs/'
  ':!.beads/'
  ':!tests/'
)

# stale_hits <git-repo> <pathspec>...  sets SH_OUT to offending "file:line:text" lines
# and SH_RC (0 ok, 2 if git grep itself errored; never swallowed).
SH_OUT=""; SH_RC=0
stale_hits() {
  local repo="$1" pat out rc; shift
  SH_RC=0; SH_OUT=""
  for pat in ${STALE_RE[@]+"${STALE_RE[@]}"}; do
    rc=0; out=$(git -C "$repo" grep -n -i -E -e "$pat" -- "$@") || rc=$?
    if [ "$rc" -ge 2 ]; then SH_RC=2; SH_OUT="$SH_OUT"$'\n'"git grep error rc=$rc for '$pat'"
    elif [ "$rc" -eq 0 ]; then SH_OUT="$SH_OUT"$'\n'"$out"; fi
  done
  SH_OUT="$(printf '%s\n' "$SH_OUT" | sed '/^$/d' | sort -u)"
}

stale_hits "$REPO_ROOT" . "${STALE_EXCLUDES[@]}"
if [ "$SH_RC" -ne 0 ]; then
  fail "stale reviewer-count guard: git grep failed: $SH_OUT"
elif [ -z "$SH_OUT" ]; then
  pass "no stale 5-reviewer Design Review Gate wording"
else
  fail "stale 5-reviewer wording ($(printf '%s\n' "$SH_OUT" | wc -l | tr -d ' ') lines): $(printf '%s\n' "$SH_OUT" | cut -d: -f1,2 | tr '\n' ' ')"
fi

# Negative self-test in a scratch git repo. Each BAD line must be flagged by
# exactly one pattern (so deleting any pattern fails), every pattern must flag at
# least one BAD line (so a new pattern without a fixture fails), and no ALLOWED
# line may be flagged.
NEG_BAD=(
  'spawns five specialist agents'
  'All five must approve'
  'Wait for 5 agents to approve'
  'Parallel 5-agent review'
  'Trigger design review gate (5 reviewers)'
  'Run 5-reviewer design review'
  'MUST run Design Review Gate (5 agents) first'
  'Wait for all 5 review agents to approve'
  'role in prompt: PM, Architect, Designer, Security, CTO'
  'The role (PM, Architect, Designer, Security or CTO) is passed'
  'spawns PM, Architect, Designer, Security, and CTO agents'
)
NEG_ALLOWED=(
  'role in prompt: PM, Architect, Designer, Security, UX Reviewer, CTO'
  'The role (PM, Architect, Designer, Security, UX or CTO) is passed'
  'All six must approve; 6 reviewers (6 agents) in a 6-agent review'
  'ran 15 agents and 25 reviewers'
)
NEG="$(mktemp -d)"
git -C "$NEG" init -q
printf '%s\n' "${NEG_BAD[@]}" "${NEG_ALLOWED[@]}" >"$NEG/bad.md"
git -C "$NEG" add bad.md
neg_ok=1; neg_msg=""
stale_hits "$NEG" .; neg="$SH_OUT"
[ "$SH_RC" -eq 0 ] || { neg_ok=0; neg_msg="$neg_msg rc=$SH_RC"; }
i=0
while [ "$i" -lt "${#NEG_BAD[@]}" ]; do
  n=$((i + 1))
  grep -qF "bad.md:$n:" <<<"$neg" || { neg_ok=0; neg_msg="$neg_msg unflagged:$n"; }
  i=$((i + 1))
done
j=0
while [ "$j" -lt "${#NEG_ALLOWED[@]}" ]; do
  n=$((${#NEG_BAD[@]} + j + 1))
  ! grep -qF "bad.md:$n:" <<<"$neg" || { neg_ok=0; neg_msg="$neg_msg allowed-flagged:$n"; }
  j=$((j + 1))
done
NEG_COUNTS=""
neg_one() { # <pattern>: prints the flagged line numbers for that pattern alone
  (
    STALE_RE=("$1")
    stale_hits "$NEG" .
    printf '%s\n' "$SH_OUT" | sed -n 's/^bad\.md:\([0-9]*\):.*/\1/p'
  )
}
for pat in ${STALE_RE[@]+"${STALE_RE[@]}"}; do
  hits="$(neg_one "$pat")"
  [ -n "$hits" ] || { neg_ok=0; neg_msg="$neg_msg no-fixture:'$pat'"; }
  NEG_COUNTS="$NEG_COUNTS"$'\n'"$hits"
done
i=0
while [ "$i" -lt "${#NEG_BAD[@]}" ]; do
  n=$((i + 1))
  c=$(printf '%s\n' "$NEG_COUNTS" | grep -cx -e "$n" || true)
  [ "$c" -eq 1 ] || { neg_ok=0; neg_msg="$neg_msg line$n-matched-by-$c"; }
  i=$((i + 1))
done
if [ "$neg_ok" -eq 1 ]; then
  pass "stale reviewer-count guard self-test: each pattern has its own fixture, 6-reviewer lines allowed"
else
  fail "stale reviewer-count guard self-test:$neg_msg"
fi
rm -rf "${NEG:?}"; NEG=""

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
