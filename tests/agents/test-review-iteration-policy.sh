#!/usr/bin/env bash
# tests/agents/test-review-iteration-policy.sh
# Issue #54: severity-gated review iteration + Delivery Scope & Overengineering policy.
# Each cycle section is owned by one work unit; later work units append sections.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUIDE="$REPO_ROOT/guides/delivery-scope.md"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# section <file> <heading-regex>: prints from the matching heading to the next heading of the same or higher level
section() {
  [ -f "$1" ] || return 0
  awk -v re="$2" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$1"
}

assert_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$text"; then fail "$label: missing '$s'"; return; fi
  done
  pass "$label"
}

assert_not_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if grep -qF -- "$s" <<<"$text"; then fail "$label: contains '$s'"; return; fi
  done
  pass "$label"
}

FORBIDDEN=('general-purpose' 'roleType(' 'Task({')

# ---------------------------------------------------------------------------
echo "Cycle 1: the policy exists once and is synced (WU1)"
# ---------------------------------------------------------------------------

if [ -f "$GUIDE" ]; then pass "guides/delivery-scope.md exists"; G="$(cat "$GUIDE")"; else fail "guides/delivery-scope.md exists"; G=""; fi

# DoD 1.1: required clauses
assert_in "guide: block-only-for list" "$G" \
  'Block delivery only for' \
  'a credible normal-usage failure' \
  'a missing or contradictory requirement' \
  'a broken key happy path' \
  'an important error or recovery-path failure'
assert_in "guide: do-not-expand list" "$G" \
  'Do not expand the current work unit for' \
  'theoretical states' \
  'exhaustive race or corruption permutations' \
  'speculative abstractions or security hardening' \
  'polish that is not required for safe normal use' \
  'Record worthwhile hardening as follow-up work instead'
assert_in "guide: all 5 overengineering signals" "$G" \
  'repeated review/fix cycles without a new user-visible risk' \
  'tests for states the real storage or API cannot produce' \
  'abstractions added only to satisfy synthetic tests' \
  'validation growing faster than the feature' \
  'delaying integrated user testing for low-likelihood edge cases'
assert_in "guide: when-a-signal-appears steps" "$G" \
  'When a signal appears' \
  "restate the work unit's Definition of Done" \
  'Classify each open concern as blocker or follow-up' \
  'smallest change in an existing owner' \
  'Advance once the blocker criteria'
assert_in "guide: finding contract fields" "$G" \
  'severity: critical | major | minor | nit' \
  'protects: <credible user scenario | explicit requirement | DoD item>' \
  'evidence: <file:line or expected-vs-found>' \
  'blocker: yes | no' \
  'yes only if severity ∈ {critical, major} AND protects is non-empty'
assert_in "guide: verdict is FAIL only on blocker: yes" "$G" \
  'FAIL only if there is at least one `blocker: yes`'
assert_in "guide: mapping from existing check tables" "$G" \
  '"BLOCKING if …" checks produce critical or major findings' \
  'They block only with `protects`' \
  '"WARNING" checks produce minor findings'
assert_in "guide: findings without protects are advisory" "$G" \
  'Findings without `protects` are advisory' \
  'advisory, not a blocker'
assert_in "guide: malformed/legacy output rule" "$G" \
  'Malformed or legacy output' \
  're-requests the review once' \
  'escalates with the raw output' \
  'never treats such a FAIL as PASS'
assert_in "guide: ordered iteration rule" "$G" \
  'SAFETY_CAP = 10' \
  'file every minor/nit finding as a follow-up' \
  '1. no blocker: yes findings            → PASS, advance' \
  '2. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal' \
  '3. the same critical/major finding recurs after a fix attempt for it,' \
  'or two reviewers rate the same finding blocker vs. non-blocker   → escalate' \
  '4. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers' \
  '5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;' \
  'any still names a credible scenario → escalate with a recommendation;' \
  'otherwise downgrade them to follow-ups and advance' \
  '6. otherwise                           → fix blockers, re-validate, FRESH review' \
  '10 rounds'
assert_in "guide: single-reviewer note (per work unit)" "$G" \
  'Single-reviewer gates' \
  'is simply false' \
  'per work unit'
assert_in "guide: 'this round fixed', round counting, re-validate notes" "$G" \
  '"This round fixed"' \
  'The first round has none' \
  'What counts as a round' \
  'Task Mode' \
  'Team Mode' \
  '"Re-validate"' \
  'running VALIDATE again'
assert_in "guide: follow-up rule" "$G" \
  'bd create --type task' \
  '### Follow-ups' \
  '`bd create` fails' \
  'more than a day'
assert_in "guide: escalation template" "$G" \
  'Critical' 'Major' 'Minor' 'Nit' \
  'Round history' \
  '**Recommendation**: <commit|another pass|human decision> — <reason'

# DoD 1.2: mirrors exist and sync check passes
MIRRORS=(
  skills/orchestrated-execution/guides/delivery-scope.md
  skills/plan-review-gate/guides/delivery-scope.md
  skills/design-review-gate/guides/delivery-scope.md
  skills/start/guides/delivery-scope.md
  skills/external-tools/guides/delivery-scope.md
)
for m in "${MIRRORS[@]}"; do
  [ -f "$REPO_ROOT/$m" ] && pass "mirror exists: $m" || fail "mirror exists: $m"
done
if grep -qF "'guides/delivery-scope.md'" "$REPO_ROOT/lib/sync-resources.js"; then
  pass "sync-resources.js has a GUIDE_SYNC entry for guides/delivery-scope.md"
else
  fail "sync-resources.js has a GUIDE_SYNC entry for guides/delivery-scope.md"
fi
if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  pass "node lib/sync-resources.js --check"
else
  fail "node lib/sync-resources.js --check"
fi

# DoD 1.3: 9 instruction files carry the section
INSTRUCTION_FILES=(
  CLAUDE.md AGENTS.md GEMINI.md
  templates/CLAUDE.md templates/CLAUDE-append.md
  templates/AGENTS.md templates/AGENTS-append.md
  templates/GEMINI.md templates/GEMINI-append.md
)
SECTIONS=""
for f in "${INSTRUCTION_FILES[@]}"; do
  S="$(section "$REPO_ROOT/$f" '^#+ Delivery Scope & Review Iteration$')"
  [ -n "$S" ] && pass "$f: has 'Delivery Scope & Review Iteration' heading" \
              || fail "$f: has 'Delivery Scope & Review Iteration' heading"
  assert_in "$f: section states the rule inline and references the guide" "$S" \
    'guides/delivery-scope.md' '10 rounds' 'advisory' 'iterate' 'advance' 'escalate' 'protects'
  case "$f" in
    templates/*) assert_in "$f: says the guide lives in the metaswarm plugin" "$S" 'metaswarm plugin' ;;
  esac
  # The inline bullets are read in order, so they must follow the guide's rule order:
  # PASS (1), escalate (2-3), iterate (4), stop and advance (5).
  order="$(grep -nE '^- \*\*(No `blocker: yes` findings|Escalate to the human|Iterate|Stop and advance)\*\*' <<<"$S" | sed -E 's/^[0-9]+:- \*\*([A-Za-z]+).*/\1/' | tr '\n' ' ')"
  [ "$order" = "No Escalate Iterate Stop " ] && pass "$f: inline bullets follow the guide's rule order" \
    || fail "$f: inline bullets follow the guide's rule order (got: $order)"
  SECTIONS+="$S"$'\n'
done

# DoD 1.4: no spawn-site syntax in the guide, mirrors or new sections
assert_not_in "guide: no general-purpose / roleType( / Task({" "$G" "${FORBIDDEN[@]}"
for m in "${MIRRORS[@]}"; do
  M=""; [ -f "$REPO_ROOT/$m" ] && M="$(cat "$REPO_ROOT/$m")"
  assert_not_in "$m: no general-purpose / roleType( / Task({" "$M" "${FORBIDDEN[@]}"
done
assert_not_in "instruction-file sections: no general-purpose / roleType( / Task({" "$SECTIONS" "${FORBIDDEN[@]}"

# ---------------------------------------------------------------------------
echo ""
echo "Cycle 2: reviewer contract in rubrics, adapters and reviewer agents (WU2)"
# ---------------------------------------------------------------------------

readf() { [ -f "$REPO_ROOT/$1" ] && cat "$REPO_ROOT/$1" || true; }

CONTRACT=(
  'severity: critical | major | minor | nit'
  'protects: <credible user scenario | explicit requirement | DoD item>'
  'evidence: <file:line or expected-vs-found>'
  'blocker: yes | no'
)
RUBRIC_GUIDE_REF='`guides/delivery-scope.md` (plugin root; `../guides/delivery-scope.md` from a skill'"'"'s `rubrics/` dir)'

# DoD 2.1: the 3 adversarial/external rubrics carry the contract, mapping, advisory clause and guide ref
CONTRACT_RUBRICS=(
  rubrics/adversarial-review-rubric.md
  rubrics/plan-review-rubric-adversarial.md
  rubrics/external-tool-review-rubric.md
)
for r in "${CONTRACT_RUBRICS[@]}"; do
  R="$(readf "$r")"
  assert_in "$r: 4-level severity scale and contract fields" "$R" "${CONTRACT[@]}"
  assert_in "$r: protects required for critical/major" "$R" \
    '`protects:` is required for critical and major findings'
  assert_in "$r: blocker definition" "$R" \
    'yes only if severity ∈ {critical, major} AND protects is non-empty'
  assert_in "$r: mapping from check tables" "$R" \
    '"BLOCKING if …" checks produce critical or major findings' \
    'They block only with `protects`' \
    '"WARNING" checks produce minor findings'
  assert_in "$r: unjustified findings are advisory" "$R" 'advisory'
  assert_in "$r: references the guide (plugin root and skill-relative path)" "$R" "$RUBRIC_GUIDE_REF"
  V="$(section "$REPO_ROOT/$r" '^## Verdict')"
  assert_in "$r: Verdict section is FAIL iff at least one blocker: yes" "$V" 'at least one `blocker: yes`'
  O="$(section "$REPO_ROOT/$r" '^## Output Format')"
  assert_in "$r: Output Format template shows the 4 fields" "$O" \
    'severity:' 'protects:' 'evidence:' 'blocker:' 'blocker: yes'
done

# DoD 2.1a: adapter footers ask for the 4 fields and FAIL only on blocker: yes
for a in skills/external-tools/adapters/codex.sh skills/external-tools/adapters/gemini.sh; do
  A="$(readf "$a")"
  assert_in "$a: footer asks for severity/protects/evidence/blocker" "$A" \
    'severity: critical | major | minor | nit' 'protects:' 'evidence:' 'blocker: yes | no'
  assert_in "$a: FAIL only on blocker: yes" "$A" 'FAIL only if at least one finding has blocker: yes'
  assert_not_in "$a: no legacy BLOCKING verdict / classification" "$A" \
    'FAIL if any BLOCKING' '"classification": "BLOCKING|WARNING"' 'Classification: BLOCKING or WARNING'
done
assert_in "gemini.sh: JSON schema carries the 4 fields" "$(readf skills/external-tools/adapters/gemini.sh)" \
  '"severity": "critical|major|minor|nit"' '"protects":' '"evidence":' '"blocker": "yes|no"'

# DoD 2.2: the "err on FAIL" bias is gone from both adversarial rubrics and their mirrors
for r in rubrics/adversarial-review-rubric.md \
         skills/orchestrated-execution/rubrics/adversarial-review-rubric.md \
         skills/start/rubrics/adversarial-review-rubric.md \
         rubrics/plan-review-rubric-adversarial.md \
         skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md \
         skills/start/rubrics/plan-review-rubric-adversarial.md; do
  [ -f "$REPO_ROOT/$r" ] && pass "$r exists" || fail "$r exists"
  assert_not_in "$r: no 'when in doubt' FAIL bias" "$(readf "$r")" \
    "When in doubt, it's BLOCKING" 'Err on the side of FAIL'
done
if grep -qF "'skills/start/rubrics/plan-review-rubric-adversarial.md'" "$REPO_ROOT/lib/sync-resources.js"; then
  pass "sync-resources.js syncs plan-review-rubric-adversarial.md into skills/start/rubrics/"
else
  fail "sync-resources.js syncs plan-review-rubric-adversarial.md into skills/start/rubrics/"
fi

# DoD 2.3: the collaborative code-review rubric defers to the severity rule
CR="$(readf rubrics/code-review-rubric.md)"
assert_not_in "code-review-rubric.md: no fixed 3-round cap" "$CR" 'Maximum Iterations: 3' 'After 3 rounds'
assert_in "code-review-rubric.md: references the severity rule" "$CR" 'severity rule' 'delivery-scope.md'

# DoD 2.4: reviewer agents carry the contract in both copies (clauses checked, not byte-compared)
for dir in agents skills/start/agents; do
  if [ "$dir" = agents ]; then P=''; else P='./'; fi
  for ag in adversarial-reviewer plan-reviewer design-reviewer; do
    f="$dir/$ag.md"; T="$(readf "$f")"
    assert_in "$f: states the finding contract" "$T" "${CONTRACT[@]}" \
      'yes only if severity ∈ {critical, major} AND protects is non-empty'
    assert_in "$f: references the guide (${P:-plugin-root} path)" "$T" "\`${P}guides/delivery-scope.md\`"
  done
  T="$(readf "$dir/adversarial-reviewer.md")"
  assert_in "$dir/adversarial-reviewer.md: FAIL only on blocker: yes" "$T" 'at least one `blocker: yes`'
  assert_in "$dir/adversarial-reviewer.md: iteration defers to the orchestrator's severity rule" "$T" \
    "orchestrator's severity rule" '10-round cap'
  assert_not_in "$dir/adversarial-reviewer.md: no fixed 3-iteration cap" "$T" \
    'Maximum Iterations: 3' 'max 3 iterations' 'persist after 3 iterations'
  T="$(readf "$dir/plan-reviewer.md")"
  assert_in "$dir/plan-reviewer.md: points at the adversarial plan rubric" "$T" \
    "\`${P}rubrics/plan-review-rubric-adversarial.md\`"
  assert_not_in "$dir/plan-reviewer.md: no longer points at the collaborative plan rubric" "$T" 'plan-review-rubric.md`'
  assert_in "$dir/plan-reviewer.md: FAIL only on blocker: yes" "$T" 'at least one `blocker: yes`'
  T="$(readf "$dir/design-reviewer.md")"
  assert_in "$dir/design-reviewer.md: NEEDS_REVISION requires a blocker" "$T" \
    'NEEDS_REVISION requires at least one `blocker: yes` finding'
  assert_in "$dir/design-reviewer.md: contract overrides persona output format" "$T" \
    "Use the persona file for its checklist and criteria only; the finding contract and blocker-based verdict REPLACE the persona file's output format and NEEDS_REVISION criteria."
  assert_not_in "$dir/design-reviewer.md: no longer follows the persona output format" "$T" \
    'criteria and output format'
  T="$(readf "$dir/cto-agent.md")"
  assert_not_in "$dir/cto-agent.md: no fixed 3-iteration cap" "$T" \
    'Maximum Iterations: 3' "doesn't pass after 3 iterations"
  assert_in "$dir/cto-agent.md: iteration defers to the severity rule" "$T" \
    "orchestrator's severity rule" '10-round cap'
done

# DoD 2.5: no old-shape template or classification statement survives in WU2's files
OLD_SHAPE=('### BLOCKING Issues' '### WARNINGS' 'FAIL (BLOCKING)' 'BLOCKING or WARNING' 'BLOCKING / WARNING' 'classified as BLOCKING')
WU2_FILES=(
  "${CONTRACT_RUBRICS[@]}"
  skills/orchestrated-execution/rubrics/adversarial-review-rubric.md
  skills/start/rubrics/adversarial-review-rubric.md
  skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md
  skills/start/rubrics/plan-review-rubric-adversarial.md
  skills/external-tools/rubrics/external-tool-review-rubric.md
  skills/external-tools/adapters/codex.sh
  skills/external-tools/adapters/gemini.sh
)
for dir in agents skills/start/agents; do
  for ag in adversarial-reviewer plan-reviewer design-reviewer cto-agent; do WU2_FILES+=("$dir/$ag.md"); done
done
for f in "${WU2_FILES[@]}"; do
  assert_not_in "$f: no old-shape BLOCKING/WARNING template or statement" "$(readf "$f")" "${OLD_SHAPE[@]}"
  case "$f" in
    *agents/*) assert_not_in "$f: no 'Maximum Iterations: 3'" "$(readf "$f")" 'Maximum Iterations: 3' ;;
  esac
done

# ---------------------------------------------------------------------------
echo ""
echo "Cycle 3: gate skills run the severity rule (WU3)"
# ---------------------------------------------------------------------------

OE=skills/orchestrated-execution/SKILL.md
PRG=skills/plan-review-gate/SKILL.md
DRG=skills/design-review-gate/SKILL.md
GATES=("$OE" "$PRG" "$DRG")

# between <file> <start-fixed-string> <end-fixed-string>: lines from the first start match up to (not including) the next end match
between() {
  [ -f "$REPO_ROOT/$1" ] || return 0
  awk -v s="$2" -v e="$3" 'on && index($0, e) { exit } index($0, s) { on = 1 } on' "$REPO_ROOT/$1"
}

RULE_LINES=(
  'file every minor/nit finding as a follow-up'
  '1. no blocker: yes findings            → PASS, advance'
  '2. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal'
  '3. the same critical/major finding recurs after a fix attempt for it,'
  'or two reviewers rate the same finding blocker vs. non-blocker   → escalate'
  '4. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers'
  '5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;'
  'any still names a credible scenario → escalate with a recommendation;'
  'otherwise downgrade them to follow-ups and advance'
  '6. otherwise                           → fix blockers, re-validate, FRESH review'
)
RECOMMENDATION='**Recommendation**: <commit|another pass|human decision> — <reason from the rule>'

for g in "${GATES[@]}"; do
  T="$(readf "$g")"
  # DoD 3.1: the ordered rule, the cap, the overengineering check, the guide reference
  assert_in "$g: repeats the ordered decision lines 1-6" "$T" "${RULE_LINES[@]}"
  order_ok=1; prev=0
  for n in '1. no blocker: yes' '2. round >= 10' '3. the same critical/major' '4. this round fixed' '5. an overengineering signal' '6. otherwise'; do
    ln="$(grep -nF -- "$n" "$REPO_ROOT/$g" | head -1 | cut -d: -f1 || true)"
    if [ -z "$ln" ] || [ "$ln" -le "$prev" ]; then order_ok=0; break; fi
    prev="$ln"
  done
  [ "$order_ok" -eq 1 ] && pass "$g: decision lines appear in order 1-6" || fail "$g: decision lines appear in order 1-6"
  assert_in "$g: 10-round cap, overengineering check, guide reference" "$T" \
    'SAFETY_CAP' '10 rounds' 'overengineering signal' 'restate the DoD' '`./guides/delivery-scope.md`'
  # DoD 3.3: escalation template grouped by severity with round history and recommendation
  assert_in "$g: escalation template groups by severity, has round history and recommendation" "$T" \
    '**Critical**' '**Major**' '**Minor**' '**Nit**' 'Round history' "$RECOMMENDATION"
  # DoD 3.4: minor/nit become follow-ups (BEADS, else a ### Follow-ups section)
  assert_in "$g: minor/nit findings become follow-ups" "$T" \
    'minor/nit' 'follow-up' 'bd create --type task' '### Follow-ups'
  # DoD 3.6: no "any single BLOCKING issue" verdict line in any gate
  assert_not_in "$g: no 'Any single BLOCKING issue' verdict line" "$T" 'Any single BLOCKING issue'
done

# DoD 3.5: no fixed review-iteration count in files that drive behaviour.
# WU4 added agents/issue-orchestrator.md and its mirror to this list.
FIXED_COUNT_PHRASES=(
  'max 3 iterations' 'Max 3 iterations' 'max 3x' 'max 3 →' '(max 3)' 'max 3 retries' 'Max 3 retry cycles'
  'of 3)' 'of 3.' 'N of 3' '1 of 3' 'Re-review attempt 1/3' '3/3 iterations'
  'After 3 iterations' 'after 3 iterations' 'After 3 rounds' 'after 3 rounds' 'After 3 review cycles'
  'After 3 failed iterations' 'Rounds 2-3' 'Round 4: Escalation'
  'Maximum Iterations: 3' 'Max retries (3) exceeded' 'Gate completed within 3 iterations' 'After 3 FAILs'
  '3 attempts per gate'
)
PHRASE_FILES=("${GATES[@]}")
for f in "$REPO_ROOT"/rubrics/*.md "$REPO_ROOT"/skills/*/rubrics/*.md; do PHRASE_FILES+=("${f#"$REPO_ROOT"/}"); done
for dir in agents skills/start/agents; do
  for ag in adversarial-reviewer plan-reviewer design-reviewer cto-agent issue-orchestrator; do PHRASE_FILES+=("$dir/$ag.md"); done
done
for f in "${PHRASE_FILES[@]}"; do
  [ -f "$REPO_ROOT/$f" ] || { fail "$f exists"; continue; }
  assert_not_in "$f: no fixed review-iteration count" "$(readf "$f")" "${FIXED_COUNT_PHRASES[@]}"
done

# --- orchestrated-execution ---
T="$(readf "$OE")"
# DoD 3.2: Phase 3 reviewer spawn prompt carries the blocker criteria and the contract
RS="$(between "$OE" '**Reviewer spawn template**' '**Phase 3 outcomes:**')"
assert_in "$OE: reviewer spawn prompt carries the contract and blocker criteria" "$RS" \
  "${CONTRACT[@]}" 'yes only if severity ∈ {critical, major} AND protects is non-empty' \
  'Any `blocker: yes` finding means overall FAIL' \
  'Report every finding with the 4 fields; minor/nit findings are recorded as follow-ups, not suggestions' \
  '`./guides/delivery-scope.md`'
assert_not_in "$OE: reviewer spawn prompt drops the old rules" "$RS" \
  'Do NOT suggest improvements' 'Any single BLOCKING issue'
# DoD 3.1: overview box and state machine move to the severity rule
assert_in "$OE: overview box points at the severity rule" "$T" 'FRESH review → severity rule (cap 10)'
assert_in "$OE: state machine: VALIDATE branch names VALIDATE, REVIEW branch the severity rule" "$T" \
  '(max 3 VALIDATE)' 'FAIL: severity rule (cap 10):'
# DoD 3.6: contradicting text rewritten
assert_not_in "$OE: contradicting text removed" "$T" \
  "found issues but they're minor, committing anyway" \
  'treating FAIL as a suggestion rather than a blocking transition' \
  'zero BLOCKING issues' 'any BLOCKING issue'
assert_in "$OE: contradicting text replaced" "$T" \
  'committing with an unresolved `blocker: yes` finding' \
  'treating a `blocker: yes` FAIL as advisory'
# DoD 3.7: On FAIL protocol moves to the severity rule; step 6 stays verbatim
ONFAIL="$(section "$REPO_ROOT/$OE" '^### On FAIL: Mandatory Re-Review Protocol')"
[ -n "$ONFAIL" ] && pass "$OE: On FAIL heading kept" || fail "$OE: On FAIL heading kept"
assert_in "$OE: On FAIL protocol runs the severity rule and tracks rounds" "$ONFAIL" \
  "${RULE_LINES[@]}" 'Review round 1/10'
assert_in "$OE: On FAIL step 6 (coder model escalation) is verbatim" "$ONFAIL" \
  '6. **Coder model escalation**: after `escalation.coder.after_failures` failed VALIDATE attempts (default 2, read from `.metaswarm/models.yaml`), re-spawn the coder with `roleType("coder")` plus a per-call `model` set to `escalation.coder.claude` (default `opus`). The per-call `model` overrides the agent-file default (the `coder` role'"'"'s `sonnet`).'
TR="$(section "$REPO_ROOT/$OE" '^### Transition Rules')"
assert_in "$OE: transition rule scopes the 3-attempt cap to VALIDATE" "$TR" \
  'VALIDATE gets 3 attempts' 'REVIEW follows the severity rule'
# DoD 3.7: Recovery Protocol scoped to VALIDATE
RECOVERY="$(section "$REPO_ROOT/$OE" '^## 9\. Recovery Protocol')"
STEP1="$(printf '%s\n' "$RECOVERY" | awk '/^### Step 1/{on=1} /^### Step 2/{on=0} on')"
STEP3="$(printf '%s\n' "$RECOVERY" | awk '/^### Step 3/{on=1} /^### Step 4/{on=0} on')"
STEP4="$(printf '%s\n' "$RECOVERY" | awk '/^### Step 4/{on=1} on')"
[ -n "$STEP3" ] && pass "$OE: Recovery Protocol '### Step 3' heading kept" || fail "$OE: Recovery Protocol '### Step 3' heading kept"
assert_in "$OE: Recovery Protocol says it covers VALIDATE, REVIEW goes to the severity rule" "$RECOVERY" \
  'VALIDATE failures' 'REVIEW failures' 'severity rule'
assert_in "$OE: Recovery Step 1 sends REVIEW failures to the severity rule" "$STEP1" 'REVIEW' 'severity rule'
assert_in "$OE: Recovery Step 3 names VALIDATE as the scope of the 3-attempt cap" "$STEP3" 'VALIDATE'
assert_in "$OE: Recovery Step 4 template names VALIDATE" "$STEP4" 'Failed VALIDATE After 3 Attempts'
assert_not_in "$OE: Recovery Step 4 history has no REVIEW rows" "$STEP4" '| REVIEW |'
# DoD 3.9: PR body carries the follow-ups list
PREPR="$(section "$REPO_ROOT/$OE" '^## 8\.5\. Pre-PR Knowledge Capture')"
assert_in "$OE: pre-PR guidance puts ### Follow-ups in the PR body" "$PREPR" 'PR body' '### Follow-ups'

# --- plan-review-gate ---
T="$(readf "$PRG")"
for p in 'Feasibility Reviewer Prompt' 'Completeness Reviewer Prompt' 'Scope & Alignment Reviewer Prompt'; do
  P="$(section "$REPO_ROOT/$PRG" "^### $p")"
  [ -n "$P" ] || { fail "$PRG: found $p"; continue; }
  # DoD 3.2
  assert_in "$PRG $p: carries the contract and blocker criteria" "$P" \
    "${CONTRACT[@]}" 'yes only if severity ∈ {critical, major} AND protects is non-empty' \
    'Any `blocker: yes` finding means overall FAIL' '= blocker (major; protects:'
  assert_not_in "$PRG $p: no old BLOCKING FAIL criteria" "$P" \
    'BLOCKING FAIL' 'Any single BLOCKING issue' 'Do NOT suggest improvements'
done
# DoD 3.6
assert_not_in "$PRG: contradicting text removed" "$T" 'the issues are minor' 'Unlimited iterations'
assert_in "$PRG: contradicting text replaced" "$T" \
  'downgrading a justified blocker without the rule' 'Severity-gated iteration, cap 10'

# --- design-review-gate ---
T="$(readf "$DRG")"
# DoD 3.2: every persona prompt inserts the shared finding rules
SFR="$(section "$REPO_ROOT/$DRG" '^### Shared Finding Rules')"
assert_in "$DRG: shared finding rules carry the contract and blocker criteria" "$SFR" \
  "${CONTRACT[@]}" 'yes only if severity ∈ {critical, major} AND protects is non-empty' \
  'NEEDS_REVISION only if at least one finding has `blocker: yes`'
for p in 'Product Manager Agent Prompt' 'Architect Agent Prompt' 'Designer Agent Prompt' 'Security Design Agent Prompt' 'CTO Agent Prompt'; do
  P="$(section "$REPO_ROOT/$DRG" "^### $p")"
  [ -n "$P" ] || { fail "$DRG: found $p"; continue; }
  assert_in "$DRG $p: inserts the shared finding rules" "$P" '${sharedFindingRules}'
done
# DoD 3.6
assert_not_in "$DRG: contradicting text removed" "$T" 'If any NEEDS_REVISION' 'One or more reviewers found blocking issues'
assert_in "$DRG: NEEDS_REVISION is blocker-based" "$T" 'any `blocker: yes` finding'

# ---------------------------------------------------------------------------
echo ""
echo "Cycle 4: gate output formats use the contract; no old-shape template anywhere (WU3)"
# ---------------------------------------------------------------------------

# DoD 3.10: design-review-gate
T="$(readf "$DRG")"
assert_in "$DRG: ReviewResult carries findings: Finding[]" "$T" \
  'findings: Finding[]' 'interface Finding' \
  'severity: "critical" | "major" | "minor" | "nit"' 'protects: string' 'evidence: string' 'blocker: "yes" | "no"' \
  'suggestions: string[]' 'questions: string[]'
n="$(grep -cF '"findings": [' "$REPO_ROOT/$DRG" || true)"
[ "$n" -eq 5 ] && pass "$DRG: 5 persona JSON schemas have a findings array" || fail "$DRG: 5 persona JSON schemas have a findings array (found $n)"
n="$(grep -cF '"severity": "critical|major|minor|nit", "protects": "<' "$REPO_ROOT/$DRG" || true)"
[ "$n" -eq 5 ] && pass "$DRG: 5 persona findings use the 4 fields" || fail "$DRG: 5 persona findings use the 4 fields (found $n)"
NR="$(section "$REPO_ROOT/$DRG" '^### Needs Revision')"
assert_in "$DRG: Needs Revision template groups by severity, tags each agent, shows the 4 fields" "$NR" \
  '#### Critical' '#### Major' '[Security Design]' '[Designer]' 'protects:' 'evidence:' 'Rule decision'
ESC="$(section "$REPO_ROOT/$DRG" '^### Escalation')"
assert_in "$DRG: Escalation template groups by severity and tags each agent" "$ESC" \
  '**Critical**' '**Major**' '[CTO]' 'Round history' "$RECOMMENDATION"

# DoD 3.10: plan-review-gate
PRO="$(section "$REPO_ROOT/$PRG" '^### Per-Reviewer Output')"
assert_in "$PRG: per-reviewer output lists findings with the 4 fields" "$PRO" \
  'severity:' 'protects:' 'evidence:' 'blocker:' 'at least one `blocker: yes`'
CF="$(section "$REPO_ROOT/$PRG" '^### Consolidated Gate Output .Any FAIL.')"
assert_in "$PRG: consolidated FAIL groups by severity, tags reviewers, shows rule decision" "$CF" \
  '#### Critical' '#### Major' '[Completeness]' '[Scope & Alignment]' 'Rule decision'
map_ln="$(grep -nF '"BLOCKING if …" checks produce critical or major findings' "$REPO_ROOT/$PRG" | head -1 | cut -d: -f1 || true)"
tbl_ln="$(grep -nF '| Check | Classification | Criteria |' "$REPO_ROOT/$PRG" | head -1 | cut -d: -f1 || true)"
if [ -n "$map_ln" ] && [ -n "$tbl_ln" ] && [ "$map_ln" -lt "$tbl_ln" ]; then
  pass "$PRG: mapping note sits above the check tables"
else
  fail "$PRG: mapping note sits above the check tables"
fi
n="$(grep -cF '"BLOCKING if …" checks produce critical or major findings' "$REPO_ROOT/$PRG" || true)"
[ "$n" -eq 1 ] && pass "$PRG: mapping note appears once" || fail "$PRG: mapping note appears once (found $n)"

# DoD 3.10: orchestrated-execution Phase 3 outcomes
P3="$(between "$OE" '**Phase 3 outcomes:**' '**Fresh reviewer rule:**')"
assert_in "$OE: Phase 3 outcomes are blocker-based" "$P3" \
  'no `blocker: yes` finding' 'at least one `blocker: yes` finding' 'severity rule'

# DoD 3.11: no old-shape reviewer output in any file that drives behaviour.
# Design-persona briefs are excluded by name; design-reviewer.md overrides their output format.
OLD_SHAPE_ALL=('### BLOCKING Issues' 'FAIL (BLOCKING)' 'BLOCKING or WARNING' 'BLOCKING / WARNING'
               'blockers: string[]' 'classified as BLOCKING' '"classification": "BLOCKING' '"blockers": [')
shopt -s nullglob
for f in "$REPO_ROOT"/agents/*.md "$REPO_ROOT"/rubrics/*.md "$REPO_ROOT"/skills/*/SKILL.md \
         "$REPO_ROOT"/skills/*/rubrics/*.md "$REPO_ROOT"/skills/start/agents/*.md \
         "$REPO_ROOT"/skills/external-tools/adapters/*.sh; do
  case "$(basename "$f")" in
    product-manager-agent.md|designer-agent.md|security-design-agent.md|architect-agent.md|cto-agent.md) continue ;;
  esac
  assert_not_in "${f#"$REPO_ROOT"/}: no old-shape reviewer output" "$(cat "$f")" "${OLD_SHAPE_ALL[@]}"
done
shopt -u nullglob

# ---------------------------------------------------------------------------
echo ""
echo "Cycle 5: issue-orchestrator runs the severity rule (WU4)"
# ---------------------------------------------------------------------------

for f in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  [ -f "$REPO_ROOT/$f" ] || { fail "$f exists"; continue; }
  T="$(readf "$f")"
  assert_in "$f: references the severity rule and blocker: yes" "$T" \
    'severity-gated iteration' 'cap 10' 'delivery-scope.md' 'Any `blocker: yes` finding means overall FAIL' \
    "${CONTRACT[@]}"
  assert_not_in "$f: no old fixed-count / BLOCKING rules" "$T" 'Any single BLOCKING issue' 'After 3 FAILs'
done

# ---------------------------------------------------------------------------
echo "PR #57 review fixes"

# Rule line 3 needs finding history across compaction: execution state keeps open
# findings and fix attempts for the orchestrator only.
OE="$REPO_ROOT/skills/orchestrated-execution/SKILL.md"
STATE="$(awk '/cat > .beads\/context\/execution-state.md/{on=1} on{print} on&&/^STATE_EOF$/{exit}' "$OE")"
assert_in "orchestrated-execution: execution state records open findings and fix attempts" "$STATE" \
  '## Open Findings' 'Severity' 'Protects' 'Fix attempts' 'never passed to reviewers'
RECOVERY="$(section "$OE" '^### Context Recovery Protocol')"
assert_in "orchestrated-execution: recovery reloads open findings for the orchestrator only" "$RECOVERY" \
  'Open Findings' 'rule line 3' 'never pass them to a fresh reviewer'

# Collaborative CRITICAL/HIGH/MEDIUM/LOW findings map onto the contract.
for r in rubrics/code-review-rubric.md skills/start/rubrics/code-review-rubric.md; do
  assert_in "$r: maps collaborative severities onto the contract" "$(cat "$REPO_ROOT/$r")" \
    'CRITICAL → critical' 'HIGH → major' 'MEDIUM → minor' 'LOW → nit'
done
for a in agents/adversarial-reviewer.md skills/start/agents/adversarial-reviewer.md; do
  assert_in "$a: collaborative severities point to the mapping" "$(cat "$REPO_ROOT/$a")" \
    'code-review-rubric.md' 'When to Stop Iterating'
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
