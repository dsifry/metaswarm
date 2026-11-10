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
TITLE_DESC=('title: <short label, ≤ ~80 chars>' 'description: <1-3 sentences: what is wrong and why it matters>')

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
  '2. a Clarify signal (C1–C4) fires' \
  '3. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal' \
  '4. the same critical/major finding recurs after a fix attempt for it,' \
  'or two reviewers rate the same finding blocker vs. non-blocker   → escalate' \
  '5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;' \
  'any still names a credible scenario → escalate with a recommendation;' \
  'otherwise downgrade them to follow-ups and advance' \
  '6. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers' \
  '7. otherwise                           → fix blockers, re-validate, FRESH review' \
  '10 rounds'
assert_in "guide: single-reviewer note (per work unit)" "$G" \
  'Single-reviewer gates' \
  "(orchestrated execution's Phase 3 adversarial review)" \
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
# Rule line 4 deliberately narrows issue #54's "reviewers disagree on severity" to
# disagreement that changes blocker; the guide must say why.
assert_in "guide: severity-disagreement note (only a blocker split escalates)" "$G" \
  '**Severity disagreement.**' \
  'Only disagreement that changes `blocker` escalates' \
  'critical-vs-major or minor-vs-nit split changes no outcome' \
  'only one names `protects`' \
  'only if their `blocker` fields differ'
assert_in "guide: follow-up rule" "$G" \
  'bd create --type task' \
  '### Follow-ups' \
  '`bd create` fails' \
  'more than a day'
assert_in "guide: escalation template" "$G" \
  'Critical' 'Major' 'Minor' 'Nit' \
  'Round history' \
  '**Recommendation**: <revise|clarify|narrow scope|defer|cancel> — <reason'

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
  # No blockers (1), Clarify (2), Escalate (3-4), Overengineering (5), Iterate (6-7).
  order="$(grep -nE '^- \*\*(No `blocker: yes` findings|Clarify|Escalate to the human|Iterate|Overengineering signal)\*\*' <<<"$S" | sed -E 's/^[0-9]+:- \*\*([A-Za-z]+).*/\1/' | tr '\n' ' ')"
  if [ "$order" = "No Clarify Escalate Overengineering Iterate " ]; then pass "$f: inline bullets follow the guide's rule order"
  else fail "$f: inline bullets follow the guide's rule order (got: $order)"; fi
  # The copied conditions match the guide: blocker-vs-non-blocker disagreement (line 4)
  # and line 5's escalate-or-downgrade outcome.
  assert_in "$f: inline escalate/overengineering conditions match the guide" "$S" \
    'rate the same finding blocker vs. non-blocker' 'escalate if any still names a credible scenario'
  assert_not_in "$f: no loose 'disagree on severity' condition" "$S" 'disagree on severity'

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
  "${TITLE_DESC[@]}"
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

# DoD 2.1a: adapter footers ask for the 6 fields and FAIL only on blocker: yes
for a in skills/external-tools/adapters/codex.sh skills/external-tools/adapters/gemini.sh; do
  A="$(readf "$a")"
  assert_in "$a: footer asks for severity/protects/evidence/blocker" "$A" \
    'severity: critical | major | minor | nit' 'protects:' 'evidence:' 'blocker: yes | no'
  assert_in "$a: FAIL only on blocker: yes" "$A" 'FAIL only if at least one finding has blocker: yes'
  assert_not_in "$a: no legacy BLOCKING verdict / classification" "$A" \
    'FAIL if any BLOCKING' '"classification": "BLOCKING|WARNING"' 'Classification: BLOCKING or WARNING'
done
assert_in "gemini.sh: JSON schema carries the 6 fields" "$(readf skills/external-tools/adapters/gemini.sh)" \
  '"title":' '"description":' '"severity": "critical|major|minor|nit"' '"protects":' '"evidence":' '"blocker": "yes|no"'

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
  '2. a Clarify signal (C1–C4) fires      → stop: misunderstanding analysis, Clarification report, wait for the user'
  '3. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal'
  '4. the same critical/major finding recurs after a fix attempt for it,'
  'or two reviewers rate the same finding blocker vs. non-blocker   → escalate'
  '5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;'
  'any still names a credible scenario → escalate with a recommendation;'
  'otherwise downgrade them to follow-ups and advance'
  '6. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers'
  '7. otherwise                           → fix blockers, re-validate, FRESH review'
)
RECOMMENDATION='**Recommendation**: <revise|clarify|narrow scope|defer|cancel> — <reason from the rule>'

for g in "${GATES[@]}"; do
  T="$(readf "$g")"
  # DoD 3.1: the ordered rule, the cap, the overengineering check, the guide reference
  assert_in "$g: repeats the ordered decision lines 1-7" "$T" "${RULE_LINES[@]}"
  order_ok=1; prev=0
  for n in '1. no blocker: yes' '2. a Clarify signal' '3. round >= 10' '4. the same critical/major' '5. an overengineering signal' '6. this round fixed' '7. otherwise'; do
    ln="$(grep -nF -- "$n" "$REPO_ROOT/$g" | head -1 | cut -d: -f1 || true)"
    if [ -z "$ln" ] || [ "$ln" -le "$prev" ]; then order_ok=0; break; fi
    prev="$ln"
  done
  [ "$order_ok" -eq 1 ] && pass "$g: decision lines appear in order 1-7" || fail "$g: decision lines appear in order 1-7"
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
  'Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions' \
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
[ "$n" -eq 6 ] && pass "$DRG: 6 persona JSON schemas have a findings array" || fail "$DRG: 6 persona JSON schemas have a findings array (found $n)"
n="$(grep -cF '"severity": "critical|major|minor|nit", "protects": "<' "$REPO_ROOT/$DRG" || true)"
[ "$n" -eq 6 ] && pass "$DRG: 6 persona findings use the 6 fields" || fail "$DRG: 6 persona findings use the 6 fields (found $n)"
NR="$(section "$REPO_ROOT/$DRG" '^### Needs Revision')"
assert_in "$DRG: Needs Revision template groups by severity, tags each agent, shows the 6 fields" "$NR" \
  '#### Critical' '#### Major' '[Security Design]' '[Designer]' 'protects:' 'evidence:' 'Rule decision'
ESC="$(section "$REPO_ROOT/$DRG" '^### Escalation')"
assert_in "$DRG: Escalation template groups by severity and tags each agent" "$ESC" \
  '**Critical**' '**Major**' '[CTO]' 'Round history' "$RECOMMENDATION"

# DoD 3.10: plan-review-gate
PRO="$(section "$REPO_ROOT/$PRG" '^### Per-Reviewer Output')"
assert_in "$PRG: per-reviewer output lists findings with the 6 fields" "$PRO" \
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

# Rule line 4 (recurring) needs finding history across compaction: execution state keeps open
# findings and fix attempts for the orchestrator only.
OE="$REPO_ROOT/skills/orchestrated-execution/SKILL.md"
STATE="$(awk '/cat > .beads\/context\/execution-state.md/{on=1} on{print} on&&/^STATE_EOF$/{exit}' "$OE")"
assert_in "orchestrated-execution: execution state records open findings and fix attempts" "$STATE" \
  '## Open Findings' 'Description' 'Evidence' 'Severity' 'Protects' 'Fix attempts' 'never passed to reviewers'
RECOVERY="$(section "$OE" '^### Context Recovery Protocol')"
assert_in "orchestrated-execution: recovery reloads open findings for the orchestrator only" "$RECOVERY" \
  'Open Findings' 'rule line 4' 'never pass them to a fresh reviewer' \
  'match each fresh finding by its title/description and protects' \
  'use evidence only as a secondary signal'
assert_not_in "orchestrated-execution: Open Findings example avoids line-number evidence" "$STATE" '<file:line evidence>'

# Collaborative CRITICAL/HIGH/MEDIUM/LOW findings map onto the contract.
for r in rubrics/code-review-rubric.md skills/start/rubrics/code-review-rubric.md; do
  assert_in "$r: maps collaborative severities onto the contract" "$(cat "$REPO_ROOT/$r")" \
    'CRITICAL → critical' 'HIGH → major' 'MEDIUM → minor' 'LOW → nit'
  # The collaborative verdict follows the blocker rule: an unprotected CRITICAL is advisory.
  CRITERIA="$(section "$REPO_ROOT/$r" '^## Approval Criteria')"
  assert_in "$r: collaborative verdict keys on blockers, not raw severity" "$CRITERIA" \
    'Any CRITICAL blocker' 'Any HIGH blocker' 'Zero HIGH blockers' \
    'name nothing they protect are advisory'
  # Approval never coexists with an open blocker: no "accepted with justification" escape.
  assert_not_in "$r: no justified-blocker approval exception" "$CRITERIA" 'with justification' 'without justification'
  assert_not_in "$r: no raw-severity CHANGES REQUIRED rule" "$CRITERIA" 'Any CRITICAL issues exist'
  # Output examples show the Protects line, so collaborative reviewers can produce blockers.
  assert_in "$r: collaborative output example carries Protects" "$(cat "$REPO_ROOT/$r")" \
    '**Protects**:'
done
for a in agents/adversarial-reviewer.md skills/start/agents/adversarial-reviewer.md; do
  STEP6="$(section "$REPO_ROOT/$a" '^### Step 6: Provide Feedback')"
  assert_in "$a: collaborative feedback example carries Protects" "$STEP6" '**Protects**:'
done
for a in agents/adversarial-reviewer.md skills/start/agents/adversarial-reviewer.md; do
  assert_in "$a: collaborative severities point to the mapping" "$(cat "$REPO_ROOT/$a")" \
    'code-review-rubric.md' 'When to Stop Iterating'
done

# ---------------------------------------------------------------------------
echo "Issue #59: VALIDATE attempts and review rounds are tracked separately"

# The Work Unit Status table splits the old ambiguous Retries column.
WU_TABLE="$(grep -F '| WU |' <<<"$STATE")"
assert_in "orchestrated-execution: Work Unit Status table splits VALIDATE attempts from review rounds" "$WU_TABLE" \
  '| VALIDATE attempts (0-3) |' '| Review rounds (0-10) |'
assert_not_in "orchestrated-execution: no ambiguous Retries column" "$STATE" '| Retries |'
assert_in "orchestrated-execution: Current Position names both counters" "$STATE" \
  '- VALIDATE attempts: <0-3>' '- Review round: <1-10>'
assert_not_in "orchestrated-execution: no ambiguous retry count in execution state" "$STATE" 'retry count'

# Recovery reads a pre-#59 state file: an old Retries value counts as VALIDATE attempts.
assert_in "orchestrated-execution: recovery maps a legacy Retries column" "$RECOVERY" \
  'legacy `Retries` column' 'VALIDATE attempts' 'Review round'

# Prose that describes execution state names both counters, not a single retry count.
for f in skills/orchestrated-execution/SKILL.md skills/handoff/SKILL.md commands/prime.md .claude/commands/prime.md; do
  assert_not_in "$f: no ambiguous 'retry count' for execution state" "$(cat "$REPO_ROOT/$f")" 'retry count'
done
for f in skills/orchestrated-execution/SKILL.md agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  T="$(cat "$REPO_ROOT/$f")"
  assert_in "$f: retry labels count VALIDATE attempts only" "$T" 'Track VALIDATE attempts with labels'
  assert_in "$f: retry labels reset on VALIDATE PASS" "$T" 'remove the `retry:N` label when VALIDATE passes'
  assert_not_in "$f: no ambiguous retry tracking heading" "$T" 'Track retries with labels' 'Track retry count:'
done

# The VALIDATE attempt counter is defined: consecutive failures, reset on PASS (PR #65 review).
# Review rounds are variable (severity rule, cap 10), so the VALIDATE limit must not accumulate across rounds.
COUNTER_DEF='VALIDATE attempts count consecutive failed VALIDATE runs for the work unit; a VALIDATE PASS resets the count to 0, so each review round'"'"'s re-validation starts fresh. The number of review rounds is governed separately by the severity rule and its 10-round cap'
assert_in "orchestrated-execution: Max retries rule defines the VALIDATE counter" \
  "$(grep -F '**Max retries**' "$OE")" "$COUNTER_DEF"
assert_in "orchestrated-execution: Step 3 RETRY defines the VALIDATE counter" \
  "$(section "$OE" '^### Step 3: RETRY')" "$COUNTER_DEF"
assert_in "orchestrated-execution: execution state annotates the VALIDATE counter" "$STATE" \
  '- VALIDATE attempts: <0-3> (consecutive failed VALIDATE runs; resets to 0 on PASS)'
for a in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  assert_in "$a: Recovery Protocol defines the VALIDATE counter" \
    "$(section "$REPO_ROOT/$a" '^### Recovery Protocol')" "$COUNTER_DEF"
done

for f in skills/orchestrated-execution/SKILL.md agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  assert_not_in "$f: VALIDATE counter does not accumulate across review rounds" "$(cat "$REPO_ROOT/$f")" 'never resets'
done

# Pin the VALIDATE 3-attempt limit and the separate review cap in the issue orchestrator (PR #57 follow-up).
for a in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  RP="$(section "$REPO_ROOT/$a" '^### Recovery Protocol')"
  assert_in "$a: VALIDATE gets 3 attempts; review follows the severity rule" "$RP" \
    'VALIDATE failures (tests, coverage, lint, typecheck) get up to 3 attempts per work unit' \
    'Review FAILs follow severity-gated iteration instead (cap 10 rounds' \
    'After 3 VALIDATE failures, or when the severity rule says escalate'
done

echo ""
echo "Issue #58 WU1: canonical contract has title and description"

for f in guides/delivery-scope.md \
  skills/orchestrated-execution/guides/delivery-scope.md \
  skills/plan-review-gate/guides/delivery-scope.md \
  skills/design-review-gate/guides/delivery-scope.md \
  skills/start/guides/delivery-scope.md \
  skills/external-tools/guides/delivery-scope.md; do
  T="$(readf "$f")"
  assert_in "$f: contract lists title and description" "$T" "${TITLE_DESC[@]}"
  assert_in "$f: missing title/description is malformed" "$T" 'missing `title` or `description`'
  assert_in "$f: escalation template uses <title>: <description>" "$T" '**Critical**: <title>: <description>'
  assert_in "$f: over-length title is advisory" "$T" 'over ~80 characters is advisory, not malformed'
  assert_not_in "$f: no four-field wording or <finding> placeholder" "$T" 'four fields' '4 fields' '<finding>'
done

echo ""
echo "Issue #58 WU2: rubrics carry title and description"

for f in rubrics/adversarial-review-rubric.md \
  skills/orchestrated-execution/rubrics/adversarial-review-rubric.md \
  skills/start/rubrics/adversarial-review-rubric.md \
  rubrics/plan-review-rubric-adversarial.md \
  skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md \
  skills/start/rubrics/plan-review-rubric-adversarial.md \
  rubrics/external-tool-review-rubric.md \
  skills/external-tools/rubrics/external-tool-review-rubric.md; do
  FC="$(section "$REPO_ROOT/$f" '^## Finding Contract')"
  assert_in "$f: Finding Contract lists title and description" "$FC" "${TITLE_DESC[@]}"
  assert_in "$f: Finding Contract says six fields" "$FC" 'Every finding carries six fields'
  assert_not_in "$f: no four-field wording" "$(readf "$f")" 'four fields' '4 fields' '4-field'
done

# Bare field-list FAIL examples carry title and description lines
for f in rubrics/adversarial-review-rubric.md \
  skills/orchestrated-execution/rubrics/adversarial-review-rubric.md \
  skills/start/rubrics/adversarial-review-rubric.md \
  rubrics/plan-review-rubric-adversarial.md \
  skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md \
  skills/start/rubrics/plan-review-rubric-adversarial.md; do
  EX="$(section "$REPO_ROOT/$f" '^### For FAIL')"
  assert_in "$f: FAIL example carries title and description" "$EX" '- title:' '- description:'
done

# External rubric's Evidence Requirements field list names title and description
for f in rubrics/external-tool-review-rubric.md skills/external-tools/rubrics/external-tool-review-rubric.md; do
  ER="$(section "$REPO_ROOT/$f" '^## Evidence Requirements')"
  assert_in "$f: Evidence Requirements lists title and description" "$ER" '**title**' '**description**' 'six contract fields'
done

for f in rubrics/code-review-rubric.md skills/start/rubrics/code-review-rubric.md; do
  assert_in "$f: collaborative mapping carries title and description" "$(readf "$f")" 'each with a title and description'
done

echo ""
echo "Issue #58 WU3: reviewer agents carry title and description"

for dir in agents skills/start/agents; do
  for ag in adversarial-reviewer plan-reviewer design-reviewer; do
    f="$dir/$ag.md"
    [ -f "$REPO_ROOT/$f" ] || { fail "$f exists"; continue; }
    FC="$(section "$REPO_ROOT/$f" '^#+ Finding Contract')"
    assert_in "$f: Finding Contract lists title and description" "$FC" "${TITLE_DESC[@]}"
    assert_in "$f: Finding Contract says six fields" "$FC" 'Every finding carries six fields'
    assert_not_in "$f: no four-field wording" "$(readf "$f")" 'four fields' '4 fields' '4-field'
  done
  f="$dir/issue-orchestrator.md"
  [ -f "$REPO_ROOT/$f" ] || { fail "$f exists"; continue; }
  FS="$(between "$f" '## Findings' '## Rules')"
  assert_in "$f: reviewer prompt Findings list carries title and description" "$FS" "${TITLE_DESC[@]}"
  assert_in "$f: reviewer prompt asks for 6 fields" "$(readf "$f")" \
    'Report every finding with the 6 fields defined in `' 'guides/delivery-scope.md`:' \
    'Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.'
  assert_not_in "$f: no four-field wording" "$(readf "$f")" 'four fields' '4 fields' '4-field'
done

# Twins differ from their agents/ source only in ./ and .claude/ path prefixes
for ag in adversarial-reviewer plan-reviewer design-reviewer issue-orchestrator cto-agent; do
  if diff -q <(sed 's#\./##g;s#\.claude/##g' "$REPO_ROOT/agents/$ag.md") \
    <(sed 's#\./##g;s#\.claude/##g' "$REPO_ROOT/skills/start/agents/$ag.md") >/dev/null 2>&1; then
    pass "$ag: twin differs only in path prefixes"
  else
    fail "$ag: twin differs only in path prefixes"
  fi
done

echo ""
echo "Issue #58 WU4: gate skills carry title and description"

OE_R=skills/orchestrated-execution/SKILL.md
PRG_R=skills/plan-review-gate/SKILL.md
DRG_R=skills/design-review-gate/SKILL.md

# title_first <label> <text>: every field-list `severity:` line is directly preceded by
# the canonical title and description lines (title, description come first).
title_first() {
  local label="$1" text="$2" bad
  bad="$(awk '
    index($0, "severity: critical | major | minor | nit") {
      n++
      if (index(p1, "description: <1-3 sentences: what is wrong and why it matters>") == 0 ||
          index(p2, "title: <short label, ≤ ~80 chars>") == 0) b++
    }
    { p2 = p1; p1 = $0 }
    END { if (n == 0) print "none"; else if (b > 0) print b }
  ' <<<"$text")"
  if [ -z "$bad" ]; then pass "$label"; else fail "$label (bad: $bad)"; fi
}

# DoD 4.1: every reviewer return-format template lists title and description first
RS="$(between "$OE_R" '**Reviewer spawn template**' '**Phase 3 outcomes:**')"
assert_in "$OE_R: reviewer spawn template carries title and description" "$RS" "${TITLE_DESC[@]}" \
  'Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:'
title_first "$OE_R: reviewer spawn template lists title and description first" "$RS"
for p in 'Feasibility Reviewer Prompt' 'Completeness Reviewer Prompt' 'Scope & Alignment Reviewer Prompt'; do
  P="$(section "$REPO_ROOT/$PRG_R" "^### $p")"
  assert_in "$PRG_R $p: carries title and description" "$P" "${TITLE_DESC[@]}" \
    'Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:' \
    'Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.'
  title_first "$PRG_R $p: lists title and description first" "$P"
done
PRO="$(section "$REPO_ROOT/$PRG_R" '^### Per-Reviewer Output')"
assert_in "$PRG_R: Per-Reviewer Output carries title and description" "$PRO" "${TITLE_DESC[@]}"
title_first "$PRG_R: Per-Reviewer Output lists title and description first" "$PRO"
assert_not_in "$PRG_R: Per-Reviewer Output drops the duplicate '1. <title>' heading" "$PRO" '1. <title>'
assert_in "$PRG_R: contract mention names all 6 fields" "$(readf "$PRG_R")" \
  '6-field contract (`title`, `description`, `severity`, `protects`, `evidence`, `blocker`)'
SFR="$(section "$REPO_ROOT/$DRG_R" '^### Shared Finding Rules')"
assert_in "$DRG_R: shared finding rules carry title and description" "$SFR" "${TITLE_DESC[@]}" \
  'Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:'
title_first "$DRG_R: shared finding rules list title and description first" "$SFR"
assert_in "$DRG_R: Phase 2 names the 6-field contract" "$(readf "$DRG_R")" 'Every finding uses the 6-field contract'

# DoD 4.2: interface Finding carries both fields, title first
IF="$(between "$DRG_R" 'interface Finding {' 'interface ReviewResult')"
assert_in "$DRG_R: interface Finding has title and description" "$IF" \
  'title: string; // short label, ≤ ~80 chars' \
  'description: string; // 1-3 sentences: what is wrong and why it matters'
first_field="$(sed -n 2p <<<"$IF")"
assert_in "$DRG_R: interface Finding lists title first" "$first_field" 'title: string;'

# DoD 4.1: the 6 persona JSON examples open with title and description
JSON_OPEN='{ "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit"'
n="$(grep -cF -- "$JSON_OPEN" "$REPO_ROOT/$DRG_R" || true)"
[ "$n" -eq 6 ] && pass "$DRG_R: 6 persona JSON findings open with title and description" \
  || fail "$DRG_R: 6 persona JSON findings open with title and description (found $n)"
n="$(grep -cF -- '{ "severity"' "$REPO_ROOT/$DRG_R" || true)"
[ "$n" -eq 0 ] && pass "$DRG_R: no persona JSON finding opens with severity" \
  || fail "$DRG_R: no persona JSON finding opens with severity (found $n)"

# DoD 4.3: Open Findings header
STATE58="$(awk '/cat > .beads\/context\/execution-state.md/{on=1} on{print} on&&/^STATE_EOF$/{exit}' "$REPO_ROOT/$OE_R")"
assert_in "$OE_R: Open Findings header has a Title column" "$STATE58" \
  '| Finding | Title | Description | Evidence | Severity | Protects | First round | Fix attempts | Status |' \
  '|---------|-------|-------------|----------|----------|----------|-------------|--------------|--------|'
OF_ROW="$(grep -F '| WU-002-F1 |' <<<"$STATE58" || true)"
cols="$(awk -F'|' '{ print NF - 2 }' <<<"$OF_ROW")"
[ "$cols" = 9 ] && pass "$OE_R: Open Findings example row has 9 cells" \
  || fail "$OE_R: Open Findings example row has 9 cells (got: $cols)"

# DoD 4.4: recovery step c matches on title/description and protects, with a legacy fallback
REC58="$(section "$REPO_ROOT/$OE_R" '^### Context Recovery Protocol')"
assert_in "$OE_R: recovery step c reloads and matches on title/description and protects" "$REC58" \
  '(title, description, evidence, severity, protects, fix attempts)' \
  'match each fresh finding by its title/description and protects' \
  'use evidence only as a secondary signal' \
  'A saved finding without a title (written before this change) falls back to description plus protects' \
  'rule line 4' 'never pass them to a fresh reviewer' 'legacy `Retries` column'

# DoD 4.5: render, escalation and follow-up lines use <title> (and <description> on critical/major)
assert_in "$OE_R: escalation lines use <title>/<description>" "$(readf "$OE_R")" \
  '- **Critical**: <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Major**: <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Minor**: <title> (follow-up filed)' '- **Nit**: <title> (follow-up filed)'
assert_in "$PRG_R: escalation and follow-up lines use <title>/<description>" "$(readf "$PRG_R")" \
  '- **Critical**: [Feasibility] <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Major**: [Completeness] <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Minor**: [Scope & Alignment] <title> (follow-up filed)' '- **Nit**: [Feasibility] <title> (follow-up filed)' \
  '- [Scope & Alignment] minor: <title> (bd-123)' '- [Feasibility] minor: <title> (bd-124)' \
  '- [Scope & Alignment] nit: <title> (bd-125)'
assert_in "$DRG_R: escalation and follow-up lines use <title>/<description>" "$(readf "$DRG_R")" \
  '- **Critical**: [Security Design] <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Major**: [Architect] <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Major**: [CTO] <title>: <description> — protects: <...> — evidence: <...>' \
  '- **Minor**: [Designer] <title> (follow-up filed)' '- **Nit**: [CTO] <title> (follow-up filed)' \
  '- [Architect] minor: <title> (bd-123)' '- [Security Design] minor: <title> (bd-124)' \
  '- [Architect] minor: <title> (bd-125)' '- [Designer] nit: <title> (bd-126)' \
  '- [Security Design] minor: <title> (bd-127)'

# DoD 4.6: malformed-output rules say 6 fields; no 4-field wording or <finding> anywhere
for g in "$OE_R" "$PRG_R" "$DRG_R"; do
  MR="$(grep -F 'is re-requested once in the contract format' "$REPO_ROOT/$g" || true)"
  assert_in "$g: malformed-output rule says 'lack the 6 fields'" "$MR" 'lack the 6 fields'
  assert_not_in "$g: no 4-field wording or <finding> placeholder" "$(readf "$g")" \
    '4 fields' 'four fields' '4-field' '<finding>'
done

# ---------------------------------------------------------------------------
echo ""
echo "Issue #58 WU5: adapters carry title and description; repo-wide guard"
# ---------------------------------------------------------------------------

CODEX_A="skills/external-tools/adapters/codex.sh"
GEMINI_A="skills/external-tools/adapters/gemini.sh"
CX="$(readf "$CODEX_A")"
GM="$(readf "$GEMINI_A")"

# DoD 5.1: codex footer asks for title/description, JSON keys include both, explanation gone
assert_in "$CODEX_A: footer asks for title and description" "$CX" "${TITLE_DESC[@]}"
assert_in "$CODEX_A: JSON keys list carries title and description first" "$CX" \
  '(array of objects with keys "title", "description", "severity", "protects", "evidence", "blocker", "theme", plus "needs_user", "origin" and "assumption" on blockers)'
assert_not_in "$CODEX_A: no explanation field" "$CX" '"explanation"' 'explanation:'
CX_FIELDS="$(grep -E '^   - (title|description|severity|protects|evidence|blocker):' <<<"$CX" | head -2 | sed -E 's/^   - //' || true)"
assert_in "$CODEX_A: title and description are the first two fields" "$CX_FIELDS" "${TITLE_DESC[@]}"

# DoD 5.2: gemini field list starts with the canonical lines; JSON example carries title/description
assert_in "$GEMINI_A: field list asks for title and description" "$GM" "${TITLE_DESC[@]}"
assert_not_in "$GEMINI_A: no bare 'Description of the issue' line" "$GM" \
  '- Description of the issue' '"description": "Description of the issue"'
GM_FIELDS="$(grep -E '^   - ' <<<"$GM" | head -2 | sed -E 's/^   - //' || true)"
assert_in "$GEMINI_A: title and description are the first two fields" "$GM_FIELDS" "${TITLE_DESC[@]}"
GM_JSON="$(sed -n '/^Respond in JSON format:/,/^PROMPT_EOF/p' "$REPO_ROOT/$GEMINI_A")"
assert_in "$GEMINI_A: example JSON carries title and description" "$GM_JSON" \
  '"title": "<short label, ≤ ~80 chars>"' '"description": "<1-3 sentences: what is wrong and why it matters>"'
DESC_N="$(grep -c '"description":' <<<"$GM_JSON" || true)"
if [ "$DESC_N" = "1" ]; then pass "$GEMINI_A: example JSON has exactly one description key"
else fail "$GEMINI_A: example JSON has exactly one description key (found $DESC_N)"; fi
key_line() { { grep -nF -- "$1" <<<"$GM_JSON" || true; } | head -1 | cut -d: -f1; }
T_L="$(key_line '"title":')"; D_L="$(key_line '"description":')"; S_L="$(key_line '"severity":')"
if [ -n "$T_L" ] && [ -n "$D_L" ] && [ -n "$S_L" ] && [ "$T_L" -lt "$D_L" ] && [ "$D_L" -lt "$S_L" ]; then
  pass "$GEMINI_A: example JSON orders title, description before severity"
else
  fail "$GEMINI_A: example JSON orders title, description before severity (title=$T_L description=$D_L severity=$S_L)"
fi

# DoD 5.5: no contract-bearing source carries 4-field wording or the <finding> placeholder
GUARD_FILES=()
shopt -s nullglob
for gf in "$REPO_ROOT"/guides/*.md "$REPO_ROOT"/rubrics/*.md "$REPO_ROOT"/agents/*.md \
          "$REPO_ROOT"/skills/*/SKILL.md "$REPO_ROOT"/skills/*/rubrics/*.md \
          "$REPO_ROOT"/skills/*/guides/*.md "$REPO_ROOT"/skills/start/agents/*.md \
          "$REPO_ROOT"/skills/external-tools/adapters/*.sh; do
  GUARD_FILES+=("${gf#"$REPO_ROOT"/}")
done
shopt -u nullglob
if [ "${#GUARD_FILES[@]}" -gt 0 ]; then pass "repo-wide guard: found ${#GUARD_FILES[@]} contract-bearing files"
else fail "repo-wide guard: found no contract-bearing files"; fi
for gf in "${GUARD_FILES[@]}"; do
  assert_not_in "$gf: no 4-field wording or <finding> placeholder" "$(readf "$gf")" \
    '4 fields' 'four fields' '4-field' '<finding>'
done

# ---------------------------------------------------------------------------
echo "Issue #58 PR #66 review: exact-format output templates use explicit title/description fields"
# Reviewers told to "use this exact format" must not copy a bold-heading title,
# or their findings lack the named title/description fields the malformed rule checks.
EXACT=(
  "agents/adversarial-reviewer.md|^### Step A5"
  "skills/start/agents/adversarial-reviewer.md|^### Step A5"
  "rubrics/adversarial-review-rubric.md|^## Output Format"
  "skills/orchestrated-execution/rubrics/adversarial-review-rubric.md|^## Output Format"
  "skills/start/rubrics/adversarial-review-rubric.md|^## Output Format"
  "rubrics/plan-review-rubric-adversarial.md|^## Output Format"
  "skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md|^## Output Format"
  "skills/start/rubrics/plan-review-rubric-adversarial.md|^## Output Format"
  "rubrics/external-tool-review-rubric.md|^## Output Format"
  "skills/external-tools/rubrics/external-tool-review-rubric.md|^## Output Format"
)
for entry in "${EXACT[@]}"; do
  f="${entry%%|*}"; re="${entry#*|}"
  X="$(section "$REPO_ROOT/$f" "$re")"
  assert_in "$f: exact-format findings carry explicit title and description fields" "$X" \
    '1. - title:' '   - description:'
  if grep -qE '^[0-9]+\. \*\*' <<<"$X"; then
    fail "$f: exact-format findings still use a bold-heading title"
  else
    pass "$f: exact-format findings use no bold-heading title"
  fi
done

# ---------------------------------------------------------------------------
echo "Issue #68: escalation never approves; no Override with open blockers"
# A gate is approved only when a review round has no `blocker: yes` finding (or via rule line 5).
# Escalating to the human never approves: there is no option that advances with open blockers.
ESC_OPTIONS=('**Revise**' '**Narrow scope**' '**Defer**' '**Cancel**')
# The canonical guide's template also offers the fifth option and its recommendation enum (issue #103).
GUIDE_ESC_OPTIONS=("${ESC_OPTIONS[@]}" '**Clarify the requirement / re-brainstorm**' '<revise|clarify|narrow scope|defer|cancel>')
for f in guides/delivery-scope.md skills/orchestrated-execution/guides/delivery-scope.md \
         skills/plan-review-gate/guides/delivery-scope.md skills/design-review-gate/guides/delivery-scope.md \
         skills/start/guides/delivery-scope.md skills/external-tools/guides/delivery-scope.md; do
  T="$(cat "$REPO_ROOT/$f")"
  assert_in "$f: states escalation never approves" "$T" \
    '**Escalation never approves.**' 'fresh review round' 'no option that advances with open blockers'
  assert_in "$f: escalation template lists the standard options" "$(section "$REPO_ROOT/$f" '^## Escalation template')" \
    "${GUIDE_ESC_OPTIONS[@]}"
done
for f in skills/plan-review-gate/SKILL.md skills/design-review-gate/SKILL.md skills/orchestrated-execution/SKILL.md; do
  assert_in "$f: escalation Options are the standard five" "$(section "$REPO_ROOT/$f" '^### Options')" "${ESC_OPTIONS[@]}" '**Clarify the requirement / re-brainstorm**'
done
for f in skills/plan-review-gate/SKILL.md skills/design-review-gate/SKILL.md commands/review-design.md \
         .claude/commands/review-design.md skills/brainstorming-extension/SKILL.md skills/start/SKILL.md \
         guides/delivery-scope.md; do
  T="$(cat "$REPO_ROOT/$f")"
  if grep -qiE '(^|[^a-z])override([^a-z]|$)' <<<"$T"; then
    fail "$f: offers an Override escalation option"
  else
    pass "$f: no Override escalation option"
  fi
  assert_not_in "$f: no proceed-with-blockers wording" "$T" \
    'Proceed anyway' 'proceed anyway' 'known risks' 'technical debt' 'force-override' '<commit|another pass'
done

# Severity-rule escalations must not go through the free-form "@beads approve" request template (#68 review).
SEV_ESC='**Severity-rule escalations never use this template.**'
SEV_ESC_REST=('Escalation template' '**Revise**' '**Narrow scope**' '**Defer**' '**Cancel**' 'There is no `@beads approve` for an escalated review gate' 'still mark the task waiting' 'waiting:human')
assert_in "skills/start/SKILL.md: How to Escalate routes severity-rule escalations to the standard report" \
  "$(section "$REPO_ROOT/skills/start/SKILL.md" '^### How to Escalate')" "$SEV_ESC" "${SEV_ESC_REST[@]}"
assert_in "skills/start/SKILL.md: @beads approve is never for an escalated review gate" \
  "$(section "$REPO_ROOT/skills/start/SKILL.md" '^### Human Response Patterns')" 'never for an escalated review gate'
for a in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  assert_in "$a: Escalation Format routes severity-rule escalations to the standard report" \
    "$(section "$REPO_ROOT/$a" '^### Escalation Format')" "$SEV_ESC" "${SEV_ESC_REST[@]}"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
