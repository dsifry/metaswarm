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
T_TRIGGER='Run the Design Review Gate only for project-sized work: brainstorming sized the work as a project (superpowers 6.4.x Architectural path; 7.x "a project", the full written design) and committed its design doc. Quick tasks, chat-only designs and short design docs for small changes (superpowers 7.0.1+) skip the gate.'
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
echo "WU2: design-doc locations and --latest"
# ---------------------------------------------------------------------------

RD="$REPO_ROOT/commands/review-design.md"
SNIPPET=""
if [ -f "$RD" ]; then
  SNIPPET="$(awk '
    /<!-- latest-design-doc:start -->/ { inblk = 1; next }
    /<!-- latest-design-doc:end -->/ { inblk = 0; next }
    inblk && /^```/ { next }
    inblk { print }
  ' "$RD")"
fi
if [ -n "$SNIPPET" ]; then pass "review-design.md has latest-design-doc snippet"; else fail "review-design.md has latest-design-doc snippet"; fi

WU2_TMP="$(mktemp -d)"
NEG=""
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "$WU2_TMP" ${NEG:+"$NEG"}; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT
WU2_N=0
NOFOUND='No design doc found in docs/plans/ or docs/superpowers/specs/'

mk() { # <fixture-root> <relative-file>...
  local root="$1" f; shift
  for f in "$@"; do mkdir -p "$root/$(dirname "$f")"; : >"$root/$f"; done
}

SNIPPET_PREFIX=""  # set to run the snippet in a strict calling shell
run_snippet() { # <shell> <dir>; sets RUN_OUT, RUN_RC
  RUN_RC=0
  RUN_OUT="$(cd "$2" && "$1" -c "$SNIPPET_PREFIX$SNIPPET" 2>&1)" || RUN_RC=$?
}

expect_pick() { # <shell> <label> <expected> <file>...
  local sh="$1" label="$2" expected="$3"; shift 3
  WU2_N=$((WU2_N + 1))
  local root="$WU2_TMP/$WU2_N"
  mkdir -p "$root"
  [ "$#" -gt 0 ] && mk "$root" "$@"
  run_snippet "$sh" "$root"
  if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$expected" ]; then
    pass "[$sh] $label"
  else
    fail "[$sh] $label (rc=$RUN_RC, got '$RUN_OUT', want '$expected')"
  fi
}

expect_none() { # <shell> <label> <mkdir-spec: dirs...>
  local sh="$1" label="$2" d; shift 2
  WU2_N=$((WU2_N + 1))
  local root="$WU2_TMP/$WU2_N"
  mkdir -p "$root"
  for d in "$@"; do mkdir -p "$root/$d"; done
  run_snippet "$sh" "$root"
  if [ "$RUN_RC" -ne 0 ] && grep -qF -e "$NOFOUND" <<<"$RUN_OUT"; then
    pass "[$sh] $label"
  else
    fail "[$sh] $label (rc=$RUN_RC, out '$RUN_OUT')"
  fi
}

P=docs/plans
S=docs/superpowers/specs
for SH in bash zsh; do
  if ! command -v "$SH" >/dev/null 2>&1; then echo "  SKIP: $SH not installed"; continue; fi
  if [ -z "$SNIPPET" ]; then fail "[$SH] snippet missing, cases not run"; continue; fi
  expect_pick "$SH" "a: specs newer than plans" "$S/2026-03-01-b-design.md" "$S/2026-03-01-b-design.md" "$P/2026-02-01-a-design.md"
  expect_pick "$SH" "b: plans newer than specs" "$P/2026-03-01-b-design.md" "$P/2026-03-01-b-design.md" "$S/2026-02-01-a-design.md"
  expect_pick "$SH" "c: only specs, plans absent" "$S/2026-03-01-b-design.md" "$S/2026-03-01-b-design.md"
  expect_pick "$SH" "d: only plans, specs absent" "$P/2026-02-01-a-design.md" "$P/2026-02-01-a-design.md"
  expect_pick "$SH" "e: non-design and undated files ignored" "$P/2026-01-01-a-design.md" \
    "$P/2026-01-01-a-design.md" "$P/2026-05-01-x-plan.md" "$P/notes.md" "$P/api-design.md" "$S/zzz-design.md"
  expect_pick "$SH" "f: same date, basename decides" "$P/2026-04-01-zeta-design.md" \
    "$P/2026-04-01-zeta-design.md" "$S/2026-04-01-alpha-design.md"
  expect_pick "$SH" "g: same basename, full-path tiebreak" "$S/2026-04-01-same-design.md" \
    "$P/2026-04-01-same-design.md" "$S/2026-04-01-same-design.md"
  # g (repeat): deterministic across runs
  WU2_N=$((WU2_N + 1)); root="$WU2_TMP/$WU2_N"; mkdir -p "$root"
  mk "$root" "$P/2026-04-01-same-design.md" "$S/2026-04-01-same-design.md"
  run_snippet "$SH" "$root"; r1="$RUN_OUT"; run_snippet "$SH" "$root"; r2="$RUN_OUT"
  if [ "$r1" = "$r2" ] && [ "$r1" = "$S/2026-04-01-same-design.md" ]; then
    pass "[$SH] g: same basename, stable across runs"
  else
    fail "[$SH] g: same basename, stable across runs ('$r1' vs '$r2')"
  fi
  expect_none "$SH" "h: empty tree, both folders exist" "$P" "$S"
  expect_none "$SH" "h: no folders at all"
  # Strict calling shell (set -e + pipefail): a missing folder must not abort the lookup.
  SNIPPET_PREFIX='set -e; set -o pipefail; '
  expect_pick "$SH" "strict: only specs, plans absent" "$S/2026-03-01-b-design.md" "$S/2026-03-01-b-design.md"
  expect_pick "$SH" "strict: only plans, specs absent" "$P/2026-02-01-a-design.md" "$P/2026-02-01-a-design.md"
  expect_pick "$SH" "strict: both folders" "$S/2026-03-01-b-design.md" "$S/2026-03-01-b-design.md" "$P/2026-02-01-a-design.md"
  expect_none "$SH" "strict: no folders at all"
  SNIPPET_PREFIX=""
  # An existing but unreadable folder must fail loudly, not fall back to the other folder.
  WU2_N=$((WU2_N + 1)); root="$WU2_TMP/$WU2_N"; mkdir -p "$root"
  mk "$root" "$P/2026-02-01-a-design.md" "$S/2026-03-01-b-design.md"
  chmod 000 "$root/$S"
  if [ -r "$root/$S" ]; then
    echo "  SKIP: [$SH] unreadable folder (running as root)"
  else
    for pre in "" 'set -e; set -o pipefail; '; do
      SNIPPET_PREFIX="$pre"; run_snippet "$SH" "$root"; SNIPPET_PREFIX=""
      if [ "$RUN_RC" -ne 0 ] && grep -qF -e "Cannot read $S" <<<"$RUN_OUT" && ! grep -qF -e "$P/2026-02-01-a-design.md" <<<"$RUN_OUT"; then
        pass "[$SH] unreadable folder fails loudly${pre:+ (strict)}"
      else
        fail "[$SH] unreadable folder fails loudly${pre:+ (strict)} (rc=$RUN_RC, out '$RUN_OUT')"
      fi
    done
  fi
  chmod 755 "$root/$S"
done

assert_in "design-review-gate names both locations" "$(cat "$REPO_ROOT/skills/design-review-gate/SKILL.md")" \
  'docs/plans/*-design.md' 'docs/superpowers/specs/*-design.md'
for f in commands/brainstorm.md skills/handoff/SKILL.md agents/designer-agent.md skills/start/agents/designer-agent.md; do
  if grep -qF -e 'docs/superpowers/specs/' "$REPO_ROOT/$f"; then
    pass "$f mentions docs/superpowers/specs/"
  else
    fail "$f mentions docs/superpowers/specs/"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "WU3: Design Review Gate trigger guard"
# ---------------------------------------------------------------------------

# Class A: forbidden on any line. Later work units may append.
FORBIDDEN=(
  'after:superpowers:brainstorming'
  'after:brainstorming'
  'MANDATORY HANDOFF'
  'triggered automatically after brainstorming'
  'after any design document'
  '"design document created"'
  '"design document committed"'
  'after:writing-plans'
  'wrote and committed a design doc file'
  'given only in chat'
  'brainstorming committed a design doc'
  'Parallel session'
  'separate session with batch checkpoints'
  'skip the review gate'
)
# Class A2: forbidden regexes (any line). WU4 adds the Plan Review Gate trigger.
FORBIDDEN_RE=(
  '(^|[^[:alnum:]_])after writing-plans'
)
# Class B: allowed only when the same line also says project-sized.
CONDITIONAL=(
  '(^|[^[:alnum:]_])after brainstorming'
  'commits a design (doc|document)'
  'brainstorming[^.]{0,20}(completes|commits)'
  'design (doc|document) (is )?(created|committed)'
  'brainstorming[^→]{0,30}→[^→]{0,10}design review gate'
)

WU3_EXCLUDES=(
  ':!guides/workflow-enforcement.md'
  ':!skills/*/guides/workflow-enforcement.md'
  ':!CHANGELOG.md'
  ':!docs/plans/'
  ':!docs/handoffs/'
  ':!docs/superpowers/'
  ':!.beads/'
  ':!tests/'
)

# trigger_hits <git-repo> <pathspec>...  sets TH_OUT to offending "file:line:text" lines
# and TH_RC (0 ok, 2 if git grep itself errored; never swallowed).
TH_OUT=""; TH_RC=0
trigger_hits() {
  local repo="$1" pat out rc line; shift
  TH_RC=0; TH_OUT=""
  for pat in ${FORBIDDEN[@]+"${FORBIDDEN[@]}"}; do
    rc=0; out=$(git -C "$repo" grep -n -i -F -e "$pat" -- "$@") || rc=$?
    if [ "$rc" -ge 2 ]; then TH_RC=2; TH_OUT="$TH_OUT"$'\n'"git grep error rc=$rc for '$pat'"
    elif [ "$rc" -eq 0 ]; then TH_OUT="$TH_OUT"$'\n'"$out"; fi
  done
  for pat in ${FORBIDDEN_RE[@]+"${FORBIDDEN_RE[@]}"}; do
    rc=0; out=$(git -C "$repo" grep -n -i -E -e "$pat" -- "$@") || rc=$?
    if [ "$rc" -ge 2 ]; then TH_RC=2; TH_OUT="$TH_OUT"$'\n'"git grep error rc=$rc for '$pat'"
    elif [ "$rc" -eq 0 ]; then TH_OUT="$TH_OUT"$'\n'"$out"; fi
  done
  for pat in ${CONDITIONAL[@]+"${CONDITIONAL[@]}"}; do
    rc=0; out=$(git -C "$repo" grep -n -i -E -e "$pat" -- "$@") || rc=$?
    if [ "$rc" -ge 2 ]; then
      TH_RC=2; TH_OUT="$TH_OUT"$'\n'"git grep error rc=$rc for '$pat'"
    elif [ "$rc" -eq 0 ]; then
      while IFS= read -r line; do
        if ! grep -qi -F -e 'project-sized' <<<"$line"; then TH_OUT="$TH_OUT"$'\n'"$line"; fi
      done <<<"$out"
    fi
  done
  TH_OUT="$(printf '%s\n' "$TH_OUT" | sed '/^$/d' | sort -u)"
}

trigger_hits "$REPO_ROOT" . "${WU3_EXCLUDES[@]}"
if [ "$TH_RC" -ne 0 ]; then
  fail "trigger guard: git grep failed: $TH_OUT"
elif [ -z "$TH_OUT" ]; then
  pass "no stale Design Review Gate trigger wording"
else
  fail "stale Design Review Gate trigger wording ($(printf '%s\n' "$TH_OUT" | wc -l | tr -d ' ') lines): $(printf '%s\n' "$TH_OUT" | cut -d: -f1,2 | tr '\n' ' ')"
fi

# Negative self-test: the matcher must flag known-bad lines in a scratch git repo.
# One fixture line per guard pattern. Each BAD line must be flagged by exactly one
# pattern (so deleting any pattern fails), every pattern must flag at least one
# BAD line (so a new pattern without a fixture fails), and no ALLOWED line may be
# flagged. Forbidden-phrase fixtures carry "project-sized" so the conditional
# class can't also match them.
NEG_BAD=(
  'project-sized triggers: after:superpowers:brainstorming'
  'project-sized triggers: after:brainstorming'
  'project-sized **MANDATORY HANDOFF**: run the gate'
  'project-sized: triggered automatically after brainstorming'
  'project-sized: runs after any design document'
  'project-sized trigger "design document created"'
  'project-sized trigger "design document committed"'
  'project-sized frontmatter after:writing-plans'
  'Project-sized means brainstorming wrote and committed a design doc file'
  'project-sized: designs given only in chat skip the gate'
  'For project-sized features (brainstorming committed a design doc), run the gate'
  'project-sized 3. **Parallel session** (superpowers:executing-plans)'
  'project-sized: execute in a separate session with batch checkpoints'
  'project-sized: the user may skip the review gate'
  'project-sized gate runs after writing-plans finishes'
  'After brainstorming, run the gate'
  'The skill commits a design doc and stops'
  'When brainstorming completes, run it'
  'Once the design doc is created, run it'
  'brainstorming → design review gate'
)
NEG_ALLOWED=(
  'After brainstorming of a project-sized design, run the gate'
  'brainstorming → design review gate (project-sized design doc only)'
)
NEG="$(mktemp -d)"
git -C "$NEG" init -q
printf '%s\n' "${NEG_BAD[@]}" "${NEG_ALLOWED[@]}" >"$NEG/bad.md"
git -C "$NEG" add bad.md
NEVER='zz-never-matches-zz'
neg_ok=1; neg_msg=""
# Full matcher: every BAD line flagged, no ALLOWED line flagged.
trigger_hits "$NEG" .; neg="$TH_OUT"
[ "$TH_RC" -eq 0 ] || { neg_ok=0; neg_msg="$neg_msg rc=$TH_RC"; }
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
# Per pattern: run the matcher with only that pattern; count hits per BAD line.
NEG_COUNTS=""
neg_one() { # <class> <pattern>: prints the flagged line numbers for one pattern
  (
    FORBIDDEN=("$NEVER"); FORBIDDEN_RE=("$NEVER"); CONDITIONAL=("$NEVER")
    case "$1" in
      F) FORBIDDEN=("$2") ;;
      R) FORBIDDEN_RE=("$2") ;;
      C) CONDITIONAL=("$2") ;;
    esac
    trigger_hits "$NEG" .
    printf '%s\n' "$TH_OUT" | sed -n 's/^bad\.md:\([0-9]*\):.*/\1/p'
  )
}
for cls in F R C; do
  case "$cls" in
    F) pats=(${FORBIDDEN[@]+"${FORBIDDEN[@]}"}) ;;
    R) pats=(${FORBIDDEN_RE[@]+"${FORBIDDEN_RE[@]}"}) ;;
    C) pats=(${CONDITIONAL[@]+"${CONDITIONAL[@]}"}) ;;
  esac
  for pat in ${pats[@]+"${pats[@]}"}; do
    hits="$(neg_one "$cls" "$pat")"
    [ -n "$hits" ] || { neg_ok=0; neg_msg="$neg_msg no-fixture:'$pat'"; }
    NEG_COUNTS="$NEG_COUNTS"$'\n'"$hits"
  done
done
i=0
while [ "$i" -lt "${#NEG_BAD[@]}" ]; do
  n=$((i + 1))
  c=$(printf '%s\n' "$NEG_COUNTS" | grep -cx -e "$n" || true)
  [ "$c" -eq 1 ] || { neg_ok=0; neg_msg="$neg_msg line$n-matched-by-$c"; }
  i=$((i + 1))
done
if [ "$neg_ok" -eq 1 ]; then
  pass "trigger guard self-test: each pattern has its own fixture, project-sized lines allowed"
else
  fail "trigger guard self-test:$neg_msg"
fi
rm -rf "${NEG:?}"; NEG=""

# #73: pipeline order statements. Full orchestration runs Plan → Plan Review Gate
# → Design Review Gate, so a chain that goes straight from the plan to the
# Design Review Gate (in any separator style) has dropped the Plan Review Gate.
# #89: a regex can't see an intermediate step or the reverse mistake, so each
# candidate line is split into steps on its separators and classified:
#   plan step    "Plan", "Planning", "the plan" (not a Plan Review Gate)
#   plan review  "Plan Review Gate", "plan-review-gate"
#   design       "Design Review Gate", "design-review-gate", "/review-design"
#   brainstorm   "brainstorming"
# Flagged: a plan step reaches a design step with no plan review in between
# (skip), or after brainstorming a plan review comes before the first design
# step (reverse: the brainstorming path reviews the design doc first).
# A line with an arrow is a chain and is split on arrows. A comma-only line may
# be prose, so only the #73 regex judges it (an adjacent "plan, design review");
# "Plan validation: checks (a, b, c) before design review" is fine.
# The #73 regex also runs on every line, so the guard is never weaker than it.
ORDER_SEP='──→|→|⇒|⟶|➜|➔|—>|->|=>'
ORDER_LEGACY='plan(ning)?[ \t]*(→|->|──→|,)[ \t]*design review'
IFS= read -r -d '' ORDER_AWK <<'AWK' || true
{
  line = $0
  # git grep -n prints path:lineno:content; keep the content only.
  p = index(line, ":"); rest = substr(line, p + 1); q = index(rest, ":")
  content = tolower(substr(rest, q + 1))
  bad = (content ~ legacy)
  if (content !~ sep) { if (bad) print line; next }
  gsub(sep, "\001", content)
  n = split(content, step, "\001")
  state = ""; brain = 0; pending = 0
  for (k = 1; k <= n; k++) {
    s = step[k]
    isdesign = (s ~ /design[- ]review|review-design/)
    isreview = (s ~ /plan[- ]review/)
    t = s; gsub(/^[^a-z]+|[^a-z]+$/, "", t)
    isplan = (!isreview && !isdesign && (t ~ /^plan(ning)?([^a-z]|$)/ || t ~ /(^|[^a-z])plan(ning)?$/))
    # A brainstorming step starts the brainstorming path; a later plan step
    # means the line has moved on to full orchestration.
    if (t ~ /^brainstorm/ && brain == 0) brain = 1
    if (isplan && brain == 1) { brain = 0; pending = 0 }
    # "Plan Review Gate / Design Review Gate" in one step: the review came first.
    if (isdesign && isreview && match(s, /plan[- ]review/) < match(s, /design[- ]review|review-design/)) {
      state = "review"; if (brain == 1) pending = 1
    }
    if (isdesign) {
      if (state == "plan") bad = 1
      if (brain == 1 && pending) bad = 1
      if (brain == 1) brain = 2
      state = "design"
    }
    if (isreview) { state = "review"; if (brain == 1 && !isdesign) pending = 1 }
    else if (isplan) state = "plan"
  }
  if (bad) print line
}
AWK
order_hits() { # <git-repo> <pathspec>...  sets OH_OUT and OH_RC like trigger_hits
  local repo="$1" out rc; shift
  OH_RC=0; OH_OUT=""
  rc=0; out=$(git -C "$repo" grep -n -i -E -e 'design[- ]review|review-design' -- "$@") || rc=$?
  if [ "$rc" -ge 2 ]; then OH_RC=2; OH_OUT="git grep error rc=$rc"; return; fi
  [ "$rc" -eq 0 ] || return 0
  OH_OUT="$(printf '%s\n' "$out" | awk -v sep="$ORDER_SEP" -v legacy="$ORDER_LEGACY" "$ORDER_AWK" | sort -u)"
}
order_hits "$REPO_ROOT" . "${WU3_EXCLUDES[@]}"
if [ "$OH_RC" -ne 0 ]; then
  fail "order guard: git grep failed: $OH_OUT"
elif [ -z "$OH_OUT" ]; then
  pass "no pipeline order statement skips the Plan Review Gate"
else
  fail "pipeline order skips the Plan Review Gate ($(printf '%s\n' "$OH_OUT" | wc -l | tr -d ' ') lines): $(printf '%s\n' "$OH_OUT" | cut -d: -f1,2 | tr '\n' ' ')"
fi
# Self-test: one BAD fixture per separator the pattern covers, and the correct
# forms (and the INSTALL.md table's "the plan), Design Review Gate") allowed.
ORDER_BAD=(
  'Research → Plan → Design Review Gate → Work Unit Decomposition'
  'Research -> Plan -> Design Review Gate -> PR'
  'Research ──→ Planning ──→ Design Review Gate ──→ Work Unit Decomposition'
  'Research, Plan, Design Review Gate, Work Unit Decomposition'
  'research, plan, design review gate, decompose into work units'
  # #89 variants: emphasis, other arrows, the command name, an intermediate
  # step, and the reverse mistake on the brainstorming path.
  'Research → Plan → **Design Review Gate** → Work Unit Decomposition'
  'Research ⇒ Plan ⇒ Design Review Gate ⇒ PR'
  'Research → Plan → /review-design → Work Unit Decomposition'
  'Research → Plan → Plan Validation → Design Review Gate → PR'
  '/start-task → brainstorming → Plan Review Gate → Design Review Gate → execution'
  'Research => Plan => Design Review Gate => PR'
  # An arrow elsewhere on the line must not hide the #73 comma form.
  'Research → plan, design review → PR'
  'Two pipelines (research, plan, design review gate) → PR'
)
ORDER_OK=(
  'Research → Plan → Plan Review Gate → Design Review Gate (reviews the plan)'
  'Research, Plan, Plan Review Gate, Design Review Gate (reviews the plan)'
  '| `superpowers:writing-plans` | Plan Review Gate (intercepts before it presents the plan), Design Review Gate |'
  'Research → Plan (with its Plan Review Gate) → Design Review Gate'
  'Research → Plan → Plan Validation → Plan Review Gate → **Design Review Gate** → PR'
  '/start-task → brainstorming → Design Review Gate (project-sized design doc only) → writing-plans → Plan Review Gate'
  'Research → Plan → Plan Review Gate → Design Review Gate. On the brainstorming path the gate reviews the design doc.'
  '- **Plan validation (pre-flight)**: Checklist catches issues (architecture, security, UI/UX) before design review'
  'Phase 2 plan, then design review, then ship'
  'Plan → Plan Review Gate / Design Review Gate'
  'Plan → Plan Review Gate. Design Review Gate (reviews the plan)'
  'After brainstorming, the plan goes to the Plan Review Gate → Design Review Gate in full orchestration'
  'brainstorming (optional) → Plan → Plan Review Gate → Design Review Gate'
)
ONEG="$(mktemp -d)"
git -C "$ONEG" init -q
printf '%s\n' "${ORDER_BAD[@]}" "${ORDER_OK[@]}" >"$ONEG/order.md"
git -C "$ONEG" add order.md
order_hits "$ONEG" .
o_ok=1; o_msg=""
[ "$OH_RC" -eq 0 ] || { o_ok=0; o_msg="$o_msg rc=$OH_RC"; }
i=0
while [ "$i" -lt "${#ORDER_BAD[@]}" ]; do
  n=$((i + 1)); grep -qF "order.md:$n:" <<<"$OH_OUT" || { o_ok=0; o_msg="$o_msg unflagged:$n"; }
  i=$((i + 1))
done
j=0
while [ "$j" -lt "${#ORDER_OK[@]}" ]; do
  n=$((${#ORDER_BAD[@]} + j + 1)); ! grep -qF "order.md:$n:" <<<"$OH_OUT" || { o_ok=0; o_msg="$o_msg allowed-flagged:$n"; }
  j=$((j + 1))
done
[ "$o_ok" -eq 1 ] && pass "order guard self-test: every separator style flagged, correct orders allowed" || fail "order guard self-test:$o_msg"
rm -rf "${ONEG:?}"; ONEG=""

# #89: the issue-orchestrator's Phase 2 runs both gates, Plan Review Gate first.
for orch in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  phase2="$(awk '/^### Phase 2: /{f=1; next} f && /^### /{exit} f' "$REPO_ROOT/$orch")"
  # Key on the gate task lines, not comments that merely name the skills.
  pr_line="$(printf '%s\n' "$phase2" | grep -n '^bd create "Plan Review Gate"' | head -1 | cut -d: -f1 || true)"
  dr_line="$(printf '%s\n' "$phase2" | grep -n '^bd create "Design Review Gate"' | head -1 | cut -d: -f1 || true)"
  if [ -n "$pr_line" ] && [ -n "$dr_line" ] && [ "$pr_line" -lt "$dr_line" ]; then
    pass "$orch Phase 2 runs plan-review-gate before design-review-gate"
  else
    fail "$orch Phase 2 must run plan-review-gate, then design-review-gate (plan-review-gate line: ${pr_line:-none}, design-review-gate line: ${dr_line:-none})"
  fi
done

# The guide is the canonical statement of both pipelines (#73).
# Each row must carry its order AND the artifact the Design Review Gate reviews.
GUIDE="$REPO_ROOT/guides/workflow-enforcement.md"
if grep -E '^\| Full orchestration \|' "$GUIDE" | grep -F "Research → Plan → Plan Review Gate → Design Review Gate → Work Unit Decomposition" | grep -qE '\| the plan; there is no separate design doc \|$' \
  && grep -E '^\| Brainstorming path \|' "$GUIDE" | grep -F "brainstorming → Design Review Gate (project-sized design doc only) → writing-plans → Plan Review Gate" | grep -qE '\| the committed design doc \|$'; then
  pass "guide states both pipelines and what the Design Review Gate reviews in each"
else
  fail "guide does not state both pipelines with the artifact each Design Review Gate reviews"
fi

# Pointer check: every sweep source points at the canonical guide.
WU3_SOURCES=(
  CLAUDE.md AGENTS.md GEMINI.md
  templates/CLAUDE.md templates/AGENTS.md templates/GEMINI.md
  templates/CLAUDE-append.md templates/AGENTS-append.md templates/GEMINI-append.md
  skills/brainstorming-extension/SKILL.md skills/design-review-gate/SKILL.md skills/start/SKILL.md
  skills/orchestrated-execution/SKILL.md
  commands/start-task.md commands/brainstorm.md commands/review-design.md
  lib/sync-resources.js docs/index.html
)
for f in "${WU3_SOURCES[@]}"; do
  if grep -qF -e 'workflow-enforcement.md' "$REPO_ROOT/$f"; then
    pass "$f points at workflow-enforcement.md"
  else
    fail "$f points at workflow-enforcement.md"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "WU4: Plan Review Gate intercept"
# ---------------------------------------------------------------------------

WU4_SOURCES=(
  skills/plan-review-gate/SKILL.md
  CLAUDE.md AGENTS.md GEMINI.md
  templates/CLAUDE.md templates/AGENTS.md templates/GEMINI.md
  templates/CLAUDE-append.md templates/AGENTS-append.md templates/GEMINI-append.md
  skills/orchestrated-execution/SKILL.md skills/brainstorming-extension/SKILL.md
  docs/index.html
)
for f in "${WU4_SOURCES[@]}"; do
  if grep -qiF -e 'before writing-plans presents the plan' "$REPO_ROOT/$f" && grep -qF -e 'workflow-enforcement.md' "$REPO_ROOT/$f"; then
    pass "$f states the plan-gate intercept and points at the guide"
  else
    fail "$f states the plan-gate intercept and points at the guide"
  fi
done
assert_in "plan-review-gate activation item" "$(cat "$REPO_ROOT/skills/plan-review-gate/SKILL.md")" \
  'writing-plans has written the plan, before its Execution Handoff'

# ---------------------------------------------------------------------------
echo ""
echo "WU-R: 7.0.2 short design docs"
# ---------------------------------------------------------------------------

assert_in "guide has 7.0.1+ small change row and short-doc wording" "$G" \
  '7.0.1+ small change' 'short design docs for small changes'

# ---------------------------------------------------------------------------
echo ""
echo "WU5: execution menu and INSTALL.md"
# ---------------------------------------------------------------------------

for f in CLAUDE.md templates/CLAUDE.md; do
  assert_in "$f has the Native inline execution option" "$(cat "$REPO_ROOT/$f")" "$T_NATIVE"
done

SP_SKILLS=(
  brainstorming writing-plans executing-plans subagent-driven-development
  finishing-a-development-branch test-driven-development systematic-debugging
  using-git-worktrees verification-before-completion
)
INSTALL_TEXT="$(cat "$REPO_ROOT/INSTALL.md")"
for sk in "${SP_SKILLS[@]}"; do
  assert_in "INSTALL.md lists superpowers:$sk" "$INSTALL_TEXT" "superpowers:$sk"
done
assert_in "INSTALL.md states versions and guide" "$INSTALL_TEXT" "6.4.1" "7.0.2" "workflow-enforcement.md"
assert_in "CHANGELOG.md mentions guide and minimum version" "$(cat "$REPO_ROOT/CHANGELOG.md")" "workflow-enforcement.md" "6.4.1"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
