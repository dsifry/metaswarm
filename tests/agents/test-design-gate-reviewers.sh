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
assert_not_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" x; shift 2
  for x in "$@"; do
    if grep -qF -e "$x" <<<"$text"; then fail "$label: contains '$x'"; return; fi
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
assert_in "Purpose lists the UX Reviewer Agent as item 5, before CTO" "$T" \
  '5. **UX Reviewer Agent** - ' '6. **CTO Agent** - ' 'All six must approve'
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
  'describes the integration wiring' 'checked at plan review' 'UI-FLOWS'
assert_in "UX prompt approves backend-only designs only when the task needs no UI" "$UXP" \
  'no user-facing UI' 'return APPROVED with no findings' 'If the task requires UI but the design omits it'
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
echo "(c) both design-reviewer twins name UX and map it to the UX persona"
# ---------------------------------------------------------------------------
for f in agents/design-reviewer.md skills/start/agents/design-reviewer.md; do
  D="$(cat "$REPO_ROOT/$f")"
  assert_in "$f names UX in description and body" "$D" \
    'The role (PM, Architect, Designer, Security, UX or CTO) is passed in the prompt' \
    'passes the **role** in the prompt: PM, Architect, Designer, Security, UX or CTO'
  if grep -q -E -e '^\| UX \| `(\./)?agents/ux-reviewer-agent\.md` \|$' <<<"$D"; then
    pass "$f maps UX to agents/ux-reviewer-agent.md"
  else
    fail "$f maps UX to agents/ux-reviewer-agent.md"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "(e) the UX Reviewer persona twins"
# ---------------------------------------------------------------------------
fm() { awk 'NR==1 { if ($0 != "---") exit; next } /^---[[:space:]]*$/ { exit } { print }' "$1"; }
fmv() { fm "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
for f in agents/ux-reviewer-agent.md skills/start/agents/ux-reviewer-agent.md; do
  if [ ! -f "$REPO_ROOT/$f" ]; then fail "$f exists"; continue; fi
  pass "$f exists"
  if [ "$(fmv "$REPO_ROOT/$f" name)" = "ux-reviewer-agent" ] && [ "$(fmv "$REPO_ROOT/$f" model)" = "inherit" ] \
     && fmv "$REPO_ROOT/$f" description | grep -q -F -e 'Use as the UX role in the design review gate.'; then
    pass "$f frontmatter: name ux-reviewer-agent, model inherit, UX-role description"
  else
    fail "$f frontmatter: name ux-reviewer-agent, model inherit, UX-role description"
  fi
  assert_in "$f has the persona header, UI-FLOWS pointer and rubric reference" "$(cat "$REPO_ROOT/$f")" \
    '**Type**: `ux-reviewer-agent`' '**Spawned By**: Design Review Gate' \
    'templates/UI-FLOWS.md' 'rubrics/ux-review-rubric.md' 'describes the integration wiring' 'no user-facing UI' \
    'If the task requires UI but the design omits it'
done
if [ -f "$REPO_ROOT/agents/ux-reviewer-agent.md" ] && [ -f "$REPO_ROOT/skills/start/agents/ux-reviewer-agent.md" ]; then
  nd="$(diff <(sed 's#\./##g;s#\.claude/##g' "$REPO_ROOT/agents/ux-reviewer-agent.md") \
             <(sed 's#\./##g;s#\.claude/##g' "$REPO_ROOT/skills/start/agents/ux-reviewer-agent.md") || true)"
  [ -z "$nd" ] && pass "ux-reviewer-agent twins differ only in path prefixes" \
    || fail "ux-reviewer-agent twins differ beyond path prefixes: $nd"
fi

# ---------------------------------------------------------------------------
echo ""
echo "(g) the UX review rubric"
# ---------------------------------------------------------------------------
RUB="$REPO_ROOT/rubrics/ux-review-rubric.md"
RUBRIC_GUIDE_REF='`guides/delivery-scope.md` (plugin root; `../guides/delivery-scope.md` from a skill'"'"'s `rubrics/` dir)'
if [ -f "$RUB" ]; then pass "rubrics/ux-review-rubric.md exists"; R="$(cat "$RUB")"; else fail "rubrics/ux-review-rubric.md exists"; R=""; fi
assert_in "UX rubric uses the finding contract" "$R" \
  '**Used By**: UX Reviewer Agent' "$RUBRIC_GUIDE_REF" \
  'protects: <credible user scenario | explicit requirement | DoD item>' \
  'blocker: yes | no' '"BLOCKING if …" checks produce critical or major findings. They block only with `protects`.'
assert_in "UX rubric covers the issue #12 criteria" "$R" \
  'trigger' 'visible outcome' 'component hierarchy' 'text wireframe' \
  'Empty state' 'Loading state' 'Error state' 'integration work unit' 'app shell' 'UI-FLOWS' 'Accessibility'
assert_in "UX rubric approves designs with no user-facing UI only when the task needs none" "$R" \
  'no user-facing UI' 'APPROVED with no findings' 'If the task requires UI but the design omits it' \
  'describes the integration wiring' 'checked at plan review'
assert_not_in "UX rubric does not require work units before decomposition" "$R" \
  'An explicit integration work unit exists'
PRA="$(cat "$REPO_ROOT/rubrics/plan-review-rubric-adversarial.md")"
assert_in "plan-review Completeness requires the UI integration work unit" "$PRA" \
  '| UI integration work unit | BLOCKING if missing |'
for m in skills/design-review-gate/rubrics/ux-review-rubric.md skills/start/rubrics/ux-review-rubric.md; do
  if [ -f "$RUB" ] && [ -f "$REPO_ROOT/$m" ] && cmp -s "$RUB" "$REPO_ROOT/$m"; then
    pass "$m mirrors the rubric"
  else
    fail "$m mirrors the rubric"
  fi
done
grep -q -F -e "'rubrics/ux-review-rubric.md'" "$REPO_ROOT/lib/sync-resources.js" \
  && pass "RUBRIC_SYNC lists the UX rubric" || fail "RUBRIC_SYNC lists the UX rubric"

# ---------------------------------------------------------------------------
echo ""
echo "(h) the gate's UX prompt follows the rubric"
# ---------------------------------------------------------------------------
assert_in "UX prompt reads ./rubrics/ux-review-rubric.md and the persona" "$UXP" \
  './rubrics/ux-review-rubric.md' 'ux-reviewer-agent.md'

# ---------------------------------------------------------------------------
echo ""
echo "(i) stated agent and rubric counts match the files"
# ---------------------------------------------------------------------------
AGENTS_N="$(ls "$REPO_ROOT"/agents/*.md | wc -l | tr -d ' ')"
RUBRICS_N="$(ls "$REPO_ROOT"/rubrics/*.md | wc -l | tr -d ' ')"
for f in .claude-plugin/plugin.json .codex-plugin/plugin.json gemini-extension.json README.md; do
  grep -q -F -e "$AGENTS_N agents" "$REPO_ROOT/$f" && pass "$f states $AGENTS_N agents" || fail "$f states $AGENTS_N agents"
done
grep -q -F -e "$RUBRICS_N quality review rubrics" "$REPO_ROOT/README.md" \
  && pass "README.md states $RUBRICS_N quality review rubrics" || fail "README.md states $RUBRICS_N quality review rubrics"
IDX="$REPO_ROOT/docs/index.html"
assert_in "docs/index.html headings state the counts" "$(cat "$IDX")" \
  "<h4>$AGENTS_N Agents</h4>" "<h4>$RUBRICS_N Quality Rubrics</h4>"
n="$(awk '/<!-- AGENTS -->/,/<\/table>/' "$IDX" | grep -c -F -e '<tr><td>' || true)"
[ "$n" -eq "$AGENTS_N" ] && pass "docs/index.html agent roster has $AGENTS_N rows" \
  || fail "docs/index.html agent roster has $AGENTS_N rows (found $n)"
# USAGE agent tables: one row per agents/*.md, each pointing at a real file
U="$REPO_ROOT/USAGE.md"
ua="$(grep -o -E '^\| \*\*[^|]+\*\* \| `agents/[a-z0-9-]+\.md`' "$U" | sed -E 's/.*`(agents\/[a-z0-9-]+\.md)`/\1/' | sort -u)"
fa="$(cd "$REPO_ROOT" && ls agents/*.md | sort)"
[ "$ua" = "$fa" ] && pass "USAGE.md agent tables list exactly agents/*.md ($AGENTS_N)" \
  || fail "USAGE.md agent tables differ from agents/*.md: $(diff <(echo "$fa") <(echo "$ua") | grep '^[<>]' | tr '\n' ' ')"
ur="$(awk '/^## Rubrics/,/^## Scripts/' "$U" | grep -o -E '^\| `[a-z0-9-]+\.md`' | sed -E 's/^\| `(.*)`/rubrics\/\1/' | sort -u)"
fr="$(cd "$REPO_ROOT" && ls rubrics/*.md | sort)"
[ "$ur" = "$fr" ] && pass "USAGE.md rubric table lists exactly rubrics/*.md ($RUBRICS_N)" \
  || fail "USAGE.md rubric table differs from rubrics/*.md: $(diff <(echo "$fr") <(echo "$ur") | grep '^[<>]' | tr '\n' ' ')"
# Drift guard: every two-digit agent count and every rubric count stated anywhere equals the files.
CNT_EXCLUDES=(':!CHANGELOG.md' ':!docs/plans/' ':!docs/handoffs/' ':!.beads/' ':!tests/')
bad=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  num="$(sed -E 's/^[^:]*:[0-9]+:[^0-9]*([0-9]+).*/\1/' <<<"$hit")"
  [ "$num" = "$AGENTS_N" ] || bad="$bad $(cut -d: -f1,2 <<<"$hit")($num agents)"
done < <(git -C "$REPO_ROOT" grep -n -o -i -E -e '(^|[^0-9.])[1-9][0-9]\+? ((ai|specialist|specialized|specialist ai|specialized ai) )?agent(s|[[:space:]]+personas|[[:space:]]+definitions)' -- . "${CNT_EXCLUDES[@]}" || true)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  num="$(sed -E 's/^[^:]*:[0-9]+:[^0-9]*([0-9]+).*/\1/' <<<"$hit")"
  [ "$num" = "$RUBRICS_N" ] || bad="$bad $(cut -d: -f1,2 <<<"$hit")($num rubrics)"
done < <(git -C "$REPO_ROOT" grep -n -o -i -E -e '(^|[^0-9.])[0-9]+ (quality |review |quality review )?rubrics' -- . "${CNT_EXCLUDES[@]}" || true)
[ -z "$bad" ] && pass "every stated agent/rubric count equals the files ($AGENTS_N agents, $RUBRICS_N rubrics)" \
  || fail "stale agent/rubric counts:$bad"

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
  'product manager, architect, designer, security( design)?,? (and |or )?cto'
  '(^|[^[:alnum:]_])5 (specialist|parallel|design) (reviewers|agents)'
  'five (review|parallel|design) agents'
  'spawn (5|five) parallel'
  '`pm`, `architect`, `designer`, `security`, `cto`'
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
  'feedback from Product Manager, Architect, Designer, Security Design, and CTO agents'
  'Trigger the gate with 5 specialist reviewers'
  'Then five review agents run'
  'Spawn 5 parallel Task() subagents'
  'teammates (`pm`, `architect`, `designer`, `security`, `cto`)'
)
NEG_ALLOWED=(
  'role in prompt: PM, Architect, Designer, Security, UX Reviewer, CTO'
  'The role (PM, Architect, Designer, Security, UX or CTO) is passed'
  'All six must approve; 6 reviewers (6 agents) in a 6-agent review'
  'ran 15 agents and 25 reviewers'
  'teammates (`pm`, `architect`, `designer`, `security`, `ux`, `cto`)'
  'feedback from Product Manager, Architect, Designer, Security Design, UX Reviewer and CTO agents'
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
