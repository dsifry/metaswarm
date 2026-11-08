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
T_TRIGGER='Run the Design Review Gate only for project-sized work: brainstorming wrote and committed a design doc file (superpowers 6.4.x Architectural path; 7.x project size). Designs given only in chat (quick tasks, small or bounded changes) skip the gate.'
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
trap 'rm -rf "$WU2_TMP"' EXIT
WU2_N=0
NOFOUND='No design doc found in docs/plans/ or docs/superpowers/specs/'

mk() { # <fixture-root> <relative-file>...
  local root="$1" f; shift
  for f in "$@"; do mkdir -p "$root/$(dirname "$f")"; : >"$root/$f"; done
}

run_snippet() { # <shell> <dir>; sets RUN_OUT, RUN_RC
  RUN_RC=0
  RUN_OUT="$(cd "$2" && "$1" -c "$SNIPPET" 2>&1)" || RUN_RC=$?
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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
