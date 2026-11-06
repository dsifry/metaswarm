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
    if ! printf '%s' "$text" | grep -qF -- "$s"; then fail "$label: missing '$s'"; return; fi
  done
  pass "$label"
}

assert_not_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if printf '%s' "$text" | grep -qF -- "$s"; then fail "$label: contains '$s'"; return; fi
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
