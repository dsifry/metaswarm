#!/usr/bin/env bash
# tests/agents/test-decision-requests.sh
# One "decision request" format for every ask to the user: the questions are numbered 1, 2, 3,
# the options in each are lettered A, B, C (the user replies "1 A 2 C"), one block per option, each
# with Pros and Cons, and "Why recommended" on the recommended option only; a "Reply with" line
# and an "If there's no answer" default. Defined once
# in guides/delivery-scope.md; every decision-ask site references it; the Clarification,
# escalation and execution-method templates use the option-block shape; lettered option
# templates and a Recommended option without Why recommended fail.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
GUIDE="guides/delivery-scope.md"
PASS=0
FAIL=0
DONE=0
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

section() {
  awk -v re="$2" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$1"
}

# Option-block shape. Counts only template lines (not prose), so a prose mention of the
# format in a section does not count as a template field.
OPT_HEAD='^[> ]*\*\*Option [A-Z]:'
cnt() { grep -cE -- "$1" <<<"$2" || true; }
# template_ok <text>: per-option blocks with Pros and Cons each, Why recommended on the
# recommended option only, lettered options, a reply instruction and a no-answer default.
template_ok() {
  local t="$1" heads pros cons why tag
  heads="$(cnt "$OPT_HEAD" "$t")"
  pros="$(cnt '^[> ]*- Pros:' "$t")"
  cons="$(cnt '^[> ]*- Cons:' "$t")"
  why="$(cnt '^[> ]*- Why recommended:' "$t")"
  tag="$(cnt "${OPT_HEAD} .*\(Recommended\)" "$t")"
  [ "$heads" -ge 2 ] || return 1
  [ "$pros" = "$heads" ] && [ "$cons" = "$heads" ] || return 1
  [ "$tag" -ge 1 ] && [ "$why" = "$tag" ] || return 1
  grep -qE '^[> ]*\*\*Option A:' <<<"$t" || return 1
  grep -qE '^[> ]*\*\*Option [0-9]+|^[> ]*\*\*Option [A-Z][a-z]|^[> ]*\*\*Option [a-z]\b' <<<"$t" && return 1
  grep -qE '^[> ]*Reply with .*letter' <<<"$t" || return 1
  grep -qF "If there's no answer:" <<<"$t" || return 1
  return 0
}
check_template() { # <name> <text>
  if template_ok "$2"; then pass "$1 has lettered option blocks (Pros/Cons each, Why recommended on the recommended one, reply and default lines)"
  else fail "$1 does not match the option-block shape"; fi
}

echo "Test 1: the definition exists once, with the option-block shape"
n="$(grep -c '^## Decision requests' "$GUIDE" || true)"
[ "$n" = 1 ] && pass "guide has exactly one '## Decision requests'" || fail "guide has $n '## Decision requests'"
DEF="$(section "$GUIDE" '^## Decision requests')"
for s in 'Decision 1' 'Option A' 'Pros' 'Cons' '(Recommended)' 'Why recommended' 'goals or constraints' \
  'Numbering rule' '1 A 2 C' 'Never numbers for options' 'relayed from a reviewer or a coder' 'Reply with' "If there's no answer" \
  'Exempt' 'fact' 'uestions never block'; do
  grep -qF -- "$s" <<<"$DEF" && pass "definition has '$s'" || fail "definition missing '$s'"
done
check_template "definition template" "$DEF"
n="$( (git grep -l '^## Decision requests' -- '*.md' ':!skills/*/guides/*' ':!docs' || true) | wc -l | tr -d ' ')"
[ "$n" = 1 ] && pass "defined in exactly one source file" || fail "defined in $n source files"
for f in skills/*/guides/delivery-scope.md; do
  cmp -s "$GUIDE" "$f" && pass "$f in sync" || fail "$f differs from $GUIDE"
done

echo "Test 2: templates use the lettered option-block shape"
check_template "Clarification report" "$(section "$GUIDE" '^### Clarification report')"
check_template "escalation template (guide)" "$(section "$GUIDE" '^## Escalation template')"
check_template "execution method menu (workflow-enforcement)" "$(section guides/workflow-enforcement.md '^## Execution method menu')"
for f in CLAUDE.md templates/CLAUDE.md skills/setup/templates/CLAUDE.md; do
  check_template "$f Execution Method Choice" "$(section "$f" '^### Execution Method Choice')"
done
check_template "plan-review-gate escalation" "$(section skills/plan-review-gate/SKILL.md '^### Phase 4: Escalation')"
check_template "design-review-gate escalation" "$(section skills/design-review-gate/SKILL.md '^### Escalation')"
check_template "orchestrated-execution VALIDATE escalation" "$(section skills/orchestrated-execution/SKILL.md '^### Step 4: ESCALATE')"

echo "Test 3: negative checks"
good='**Option A: A** (Recommended)\none\n- Pros: x\n- Cons: y\n- Why recommended: z\n\n**Option B: B**\ntwo\n- Pros: x\n- Cons: y\n\nReply with a letter. If there'"'"'s no answer: wait.\n'
printf "$good" > "$FIX/good.md"
if template_ok "$(cat "$FIX/good.md")"; then pass "a well-formed block passes"; else fail "a well-formed block failed"; fi
neg() { # <name> <awk program applied to the good block>
  awk "$2" "$FIX/good.md" > "$FIX/neg.md"
  if template_ok "$(cat "$FIX/neg.md")"; then fail "$1 passed"; else pass "$1 fails"; fi
}
neg "Recommended without Why recommended" '!/Why recommended/'
neg "an option without Cons" '!/- Cons: y/ || seen++'
neg "an option without Pros" '!/- Pros: x/ || seen++'
neg "numbered options" '{ sub(/Option A:/, "Option 1:"); sub(/Option B:/, "Option 2:"); print }'
neg "no reply-with-a-letter line" '!/Reply with a letter/'
neg "no no-answer default" '{ sub(/ If there.s no answer: wait\./, ""); print }'
neg "Why recommended on a non-recommended option" '{ print } /^- Cons: y$/ && ++n == 2 { print "- Why recommended: q" }'
neg "old Choices/Recommended/Rationale layout" '/^\*\*Option A:/ { print "**Choices:**"; print "1. A"; next } /^\*\*Option B:/ { print "2. B"; next } !/^- (Pros|Cons|Why)/'

echo "Test 3b: no numbered option templates; finding-contract options field is lettered"
bad="$( (git grep -nE '^[> -]*(\*\*)?Option [0-9]+\b' -- '*.md' ':!CHANGELOG.md' ':!docs' ':!knowledge' ':!tests' ':!skills/*/guides/*' || true) )"
[ -z "$bad" ] && pass "no numbered 'Option 1' templates in user-facing text" || fail "numbered option templates: $bad"
bad="$( (git grep -nE '\*\*(Choices|Recommended|Rationale):\*\*' -- '*.md' ':!CHANGELOG.md' ':!docs' ':!knowledge' ':!tests' ':!skills/*/guides/*' || true) )"
[ -z "$bad" ] && pass "no old Choices/Recommended/Rationale field labels" || fail "old labels remain: $bad"
grep -E '^- options:' "$GUIDE" | grep -qF 'lettered A, B, C (never numbers)' && pass "finding contract options field is lettered" || fail "finding contract options field is not lettered"

echo "Test 4: every decision-ask site references the one definition"
SITES=(
  guides/workflow-enforcement.md
  CLAUDE.md AGENTS.md GEMINI.md
  templates/CLAUDE.md templates/CLAUDE-append.md templates/AGENTS.md templates/AGENTS-append.md templates/GEMINI.md templates/GEMINI-append.md
  skills/setup/templates/CLAUDE.md skills/setup/templates/CLAUDE-append.md skills/setup/templates/AGENTS.md
  skills/setup/templates/AGENTS-append.md skills/setup/templates/GEMINI.md skills/setup/templates/GEMINI-append.md
  agents/issue-orchestrator.md agents/cto-agent.md agents/release-engineer-agent.md agents/security-auditor-agent.md agents/sre-agent.md
  skills/start/agents/issue-orchestrator.md skills/start/agents/cto-agent.md skills/start/agents/release-engineer-agent.md
  skills/start/agents/security-auditor-agent.md skills/start/agents/sre-agent.md
  commands/start-task.md .claude/commands/start-task.md commands/pr-shepherd.md .claude/commands/pr-shepherd.md
  commands/review-design.md .claude/commands/review-design.md
  skills/brainstorming-extension/SKILL.md skills/create-issue/SKILL.md skills/design-review-gate/SKILL.md
  skills/handling-pr-comments/SKILL.md skills/migrate/SKILL.md skills/orchestrated-execution/SKILL.md
  skills/plan-review-gate/SKILL.md skills/pr-shepherd/SKILL.md skills/setup/SKILL.md skills/start/SKILL.md
)
for f in "${SITES[@]}"; do
  if [ -f "$f" ] && grep -qF 'Decision requests' "$f" && grep -qF 'delivery-scope.md' "$f"; then pass "$f references Decision requests"
  else fail "$f does not reference Decision requests in delivery-scope.md"; fi
done
# No copy of the format text: the definition's own sentence appears only in the guide copies.
n="$( (git grep -lF 'Every time the orchestrator, an agent or a gate asks the user to decide' -- '*.md' ':!skills/*/guides/*' ':!CHANGELOG.md' || true) | wc -l | tr -d ' ')"
[ "$n" = 1 ] && pass "the definition text is not copied" || fail "the definition text appears in $n source files"

echo "Test 5: every file that asks the user to decide is a site or a listed exemption"
# Fact-only or descriptive mentions; the reason is the part after the colon.
EXEMPT=(
  "README.md: describes the gates; asks nothing"
  "USAGE.md: describes the gates; asks nothing"
  "GETTING_STARTED.md: describes the gates; asks nothing"
  "guides/agent-coordination.md: a table row naming the retry limit; the orchestrator owns the ask"
  "commands/metaswarm-update-version.md: tells the user to run /update; no choice offered"
  "skills/external-tools/SKILL.md: auth errors tell the user to fix credentials; no choice offered"
  "templates/todo-management.md: a note format for BEADS, not an ask"
  "skills/setup/templates/todo-management.md: copy of templates/todo-management.md"
)
exempt_has() { local e; for e in "${EXEMPT[@]}"; do [ "${e%%:*}" = "$1" ] && return 0; done; return 1; }
site_has() { local s; for s in "${SITES[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
while IFS= read -r f; do
  if site_has "$f" || exempt_has "$f" || [ "$f" = "$GUIDE" ]; then pass "$f is a site or exempt"
  else fail "$f asks the user to decide but is neither a site nor exempt"; fi
done < <(git grep -lEi 'AskUserQuestion|ask the user|escalate (to )?(the )?(human|user)|escalate to COO|ASK_USER|WAITING_FOR_USER|present options|Human Escalation|ask the human|wait for (the )?user|user decision' \
  -- '*.md' ':!CHANGELOG.md' ':!docs' ':!tests' ':!knowledge' ':!skills/*/guides/*' ':!skills/setup/knowledge' ':!evals')

echo "Test 6: plugin copies are in sync"
node lib/sync-resources.js --check >/dev/null && pass "sync-resources --check" || fail "sync-resources --check"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" = 0 ]
