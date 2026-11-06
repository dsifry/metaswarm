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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
