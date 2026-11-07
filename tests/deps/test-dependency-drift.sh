#!/usr/bin/env bash
# tests/deps/test-dependency-drift.sh
# Regression guard for bd/beads dependency drift (issue #62).
#
# Each "class" is a set of case-insensitive, portable-ERE patterns (no \b; word
# boundaries are spelled (^|[^[:alnum:]_]) and ([^[:alnum:]_]|$); a literal pipe
# is [|]). A class passes over a set of files when none of its patterns, nor its
# multi-line rules, produce a hit. Classes are defined ONCE below; each work unit
# appends its own section asserting the classes over the files it owns.
#
# DRIFT_ROOT (default: this repo) selects the git work tree to scan, so a scratch
# `git init` copy can be used to prove each class fails when reintroduced.
#
# Scope exclusions (every search): docs/plans, CHANGELOG.md, .beads, tests,
# node_modules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_ROOT="${DRIFT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PASS=0
FAIL=0
TOTAL=0

EXCLUDES=(':!docs/plans' ':!CHANGELOG.md' ':!.beads' ':!tests' ':!node_modules')

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required (command -v jq)"
  exit 1
fi
if [ -z "$(git -C "$DRIFT_ROOT" ls-files 2>/dev/null || true)" ]; then
  echo "FAIL: no tracked files under DRIFT_ROOT=$DRIFT_ROOT (git ls-files is empty)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Class patterns (single-line, case-insensitive ERE)
# ---------------------------------------------------------------------------
# P1: bd prime flags that have never existed. Multi-line rule: p1cont.
P1=(
  'bd prime[^|]*--(work-type|keywords|files)'
  '--work-type recovery'
)
# P2: stale "bd / BEADS / bd prime loads or supplies metaswarm knowledge" claims.
# Explicit stale-phrase list. Multi-line rule: p2adj.
P2=(
  'selective retrieval'
  'bd prime[^.]{0,60}(load|filter|retriev|select)'
  '(knowledge priming|prime)[^.]{0,60}(requires?|needs?)[^.]{0,20}(bd|beads)([^[:alnum:]_]|$)'
  'defers? priming to beads'
  'install .?bd.? for[^.]{0,40}priming'
  '# *(general prime|load all relevant knowledge)'
  'prime command outputs relevant facts'
  'Manual Knowledge Priming'
  '(^|[^[:alnum:]_])bd([^[:alnum:]_]|$)[^.]{0,60}knowledge (priming|base)'
  'BEADS[^.]{0,60}knowledge priming'
  'for knowledge base\)'
  '\(--files, --keywords, --work-type\)'
  'bd prime.? runs before'
  'new session begins with .?bd prime'
  # Added by the WU1 prose hand review (phrases fixed there must not return):
  'dependenc(y tracking|ies),? and knowledge priming'
  'defers? priming'
  '[(]let beads handle it[)]'
  'beads isn.t separately priming'
  'queries the beads knowledge base'
  'beads system should auto-prime'
  'handles context priming'
  'skips its own priming'
  'beads plugin will re-prime'
  'prime command loads additional context'
  'knowledge, if beads present'
)
# P5: stale bd/beads version claims (WU4).
P5=(
  '(bd|beads)[^.]{0,30}v?0\.[0-9]+(\.[0-9]+)?\+'
  'v0\.63\.3'
  'bd CLI[^|]*[|] *Available \(v0\.'
)
# P6: stale compact wording (WU3). Multi-line rule only: p6.
P6=()
# P7: removed or invented bd commands and flags (WU3).
P7=(
  'bd sync([^[:alnum:]_-]|$)'
  'bd decision([^[:alnum:]_]|$)'
  'bd start [0-9]'
  'bd swarm (assignments|conflicts|pause|reassign|rebalance|resume|worktrees)'
  'bd create.*--issue[ =]'
  'bd list.*--since'
  '--status[ =](completed|done)'
  '--priority 1-5'
  'merge=beads'
  'bd merge'
  'scripts/beads-prime\.ts'
  'bd update.*--notes[= ]'
)

# Multi-line rules per class (names understood by scan_rule below).
rules_for() {
  case "$1" in
    P1) echo "p1cont" ;;
    P2) echo "p2adj" ;;
    P6) echo "p6" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# search CLASSNAME PATTERN [git-pathspecs...]
# Prints file:line:text for every hit of PATTERN (case-insensitive ERE) in the
# tracked, in-scope files matched by the pathspecs (whole tree when none).
search() {
  local _class="$1" pattern="$2"
  shift 2
  git -C "$DRIFT_ROOT" grep -I -n -i -E -e "$pattern" -- "$@" "${EXCLUDES[@]}" || true
}

# list_files [git-pathspecs...] -> tracked in-scope files, one per line.
list_files() {
  git -C "$DRIFT_ROOT" ls-files -- "$@" "${EXCLUDES[@]}" || true
}

# scan_rule RULE [git-pathspecs...]
# Multi-line rules, applied per file (case-insensitive):
#   p1cont: inside a block that begins with a line ending in `bd prime \`, any
#           continuation line containing --work-type/--keywords/--files (the
#           block is followed until a line no longer ends in a backslash).
#   p2adj:  a bare `bd prime` line whose previous line is a comment that
#           mentions "knowledge".
#   p6:     a line containing plain `bd compact` (after removing
#           `bd admin compact`) with semantic/summar/"compact closed issues" on
#           the previous, same or next line.
scan_rule() {
  local rule="$1"
  shift
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$DRIFT_ROOT/$f" ] || continue
    RULE="$rule" FILE="$f" awk '
      { raw[NR] = $0; low[NR] = tolower($0) }
      END {
        rule = ENVIRON["RULE"]; file = ENVIRON["FILE"]
        if (rule == "p1cont") {
          incont = 0
          for (i = 1; i <= NR; i++) {
            l = low[i]
            if (!incont && l ~ /bd prime[[:space:]]*\\[[:space:]]*$/) { incont = 1; continue }
            if (incont) {
              if (l ~ /--(work-type|keywords|files)/) print file ":" i ":" raw[i]
              if (l !~ /\\[[:space:]]*$/) incont = 0
            }
          }
        } else if (rule == "p2adj") {
          for (i = 2; i <= NR; i++) {
            if (low[i] ~ /^[[:space:]]*bd prime[[:space:]]*$/ &&
                low[i-1] ~ /^[[:space:]]*(#|\/\/|<!--)/ &&
                low[i-1] ~ /knowledge/) print file ":" i ":" raw[i]
          }
        } else if (rule == "p6") {
          re = "semantic|summar|compact closed issues"
          for (i = 1; i <= NR; i++) {
            l = low[i]
            gsub(/bd admin compact/, "", l)
            if (l !~ /bd compact/) continue
            if (low[i] ~ re || (i > 1 && low[i-1] ~ re) || (i < NR && low[i+1] ~ re))
              print file ":" i ":" raw[i]
          }
        }
      }
    ' "$DRIFT_ROOT/$f"
  done < <(list_files "$@")
}

# class_hits CLASS [git-pathspecs...] -> every hit of every pattern and rule.
class_hits() {
  local class="$1"
  shift
  local arr_name="${class}[@]" pattern rule
  # Arrays may be empty (P6); guard for bash 3.2 + set -u.
  eval "local n=\${#${class}[@]}"
  if [ "$n" -gt 0 ]; then
    for pattern in "${!arr_name}"; do
      search "$class" "$pattern" "$@"
    done
  fi
  for rule in $(rules_for "$class"); do
    scan_rule "$rule" "$@"
  done
}

pass() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# assert_no_hits DESC CLASS [git-pathspecs...]
assert_no_hits() {
  local desc="$1" class="$2"
  shift 2
  local hits
  hits="$(class_hits "$class" "$@" | sort -u)"
  if [ -z "$hits" ]; then
    pass "$desc"
  else
    fail "$desc"
    while IFS= read -r line; do echo "      $line"; done <<<"$hits"
  fi
}

# assert_tracked DESC PATHSPEC... — every pathspec matches >= 1 tracked file.
assert_tracked() {
  local desc="$1"
  shift
  local spec missing=""
  for spec in "$@"; do
    if [ -z "$(git -C "$DRIFT_ROOT" ls-files -- "$spec" || true)" ]; then
      missing="$missing $spec"
    fi
  done
  if [ -z "$missing" ]; then pass "$desc"; else fail "$desc — untracked/missing:$missing"; fi
}

# assert_contains_fixed DESC FILE TEXT [-i]
assert_contains_fixed() {
  local desc="$1" file="$2" text="$3" flags="-qF"
  [ "${4:-}" = "-i" ] && flags="-qiF"
  if [ -f "$DRIFT_ROOT/$file" ] && grep $flags -- "$text" "$DRIFT_ROOT/$file"; then
    pass "$desc"
  else
    fail "$desc — $file lacks: $text"
  fi
}

# assert_not_matches DESC FILE ERE
assert_not_matches() {
  local desc="$1" file="$2" re="$3" hits
  hits="$(grep -niE -e "$re" "$DRIFT_ROOT/$file" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    pass "$desc"
  else
    fail "$desc"
    while IFS= read -r line; do echo "      $file:$line"; done <<<"$hits"
  fi
}

# ---------------------------------------------------------------------------
# Canonical texts (verbatim from the approved plan)
# ---------------------------------------------------------------------------
R1='**Note:** The standalone beads plugin (matching your bd version, bd ≥ 1.0.4) runs `bd prime` automatically on SessionStart and PreCompact. `bd prime` restores only the bd workflow reference and any `bd remember` memories. It does **not** load metaswarm'"'"'s plan, execution state or knowledge base. To recover after compaction or in a new session, read them directly: `.beads/plans/active-plan.md` (resume only if `status: in-progress`), `.beads/context/project-context.md` and `.beads/context/execution-state.md`. Then run `/prime` to load the relevant knowledge-base facts.'
R1_KEY='does **not** load metaswarm'"'"'s plan, execution state or knowledge base'
R3='if bd is installed, `bd prime` (bd context); then read `.beads/plans/active-plan.md` and `.beads/context/*.md`; then `/prime` for knowledge'
# The documented /prime keyword pipeline (commands/prime.md), run against both
# knowledge stores. Expects $KB (store dir) and $K (keyword).
PRIME_PIPELINE='grep -hv '"'"'^#'"'"' "$KB"/*.jsonl | jq -r --arg k "$K" '"'"'select((.fact | test($k; "i")) or ((.tags // []) | any(test($k; "i")))) | .fact'"'"''

# ===========================================================================
# WU1 (owned files): bd prime flags (P1) and stale priming claims (P2)
# ===========================================================================
echo "WU1: bd prime flags and priming claims (owned files + mirrors)"

WU1_FILES=(
  CLAUDE.md README.md GETTING_STARTED.md USAGE.md INSTALL.md docs/index.html
  templates/CLAUDE.md templates/CLAUDE-append.md templates/beads-developer-setup.md
  commands/prime.md commands/start-task.md commands/handoff.md
  skills/handoff/SKILL.md skills/orchestrated-execution/SKILL.md
  skills/start/SKILL.md skills/status/SKILL.md
  guides/agent-coordination.md hooks/session-start.sh
  # generated mirrors
  skills/setup/templates/CLAUDE.md skills/setup/templates/CLAUDE-append.md
  skills/setup/templates/beads-developer-setup.md
  .claude/commands/prime.md .claude/commands/start-task.md .claude/commands/handoff.md
  commands/metaswarm/prime.toml commands/metaswarm/handoff.toml
  'skills/*/guides/agent-coordination.md'
)

assert_tracked "WU1 owned files and mirrors are tracked" "${WU1_FILES[@]}"
assert_no_hits "WU1 1.1: no bd prime flag usage (P1)" P1 "${WU1_FILES[@]}"
assert_no_hits "WU1 1.1: no stale bd/BEADS priming claims (P2)" P2 "${WU1_FILES[@]}"

# 1.2 R1 verbatim; CLAUDE-append key sentence.
for f in CLAUDE.md templates/CLAUDE.md skills/setup/templates/CLAUDE.md; do
  assert_contains_fixed "WU1 1.2: R1 recovery note verbatim in $f" "$f" "$R1"
done
for f in templates/CLAUDE-append.md skills/setup/templates/CLAUDE-append.md; do
  assert_contains_fixed "WU1 1.2: R1 key sentence in $f" "$f" "$R1_KEY"
done

# R3 recovery step.
for f in skills/orchestrated-execution/SKILL.md skills/handoff/SKILL.md \
         skills/start/SKILL.md commands/handoff.md .claude/commands/handoff.md; do
  assert_contains_fixed "WU1: R3 recovery step in $f" "$f" "$R3" -i
done

# 1.3 commands/prime.md documents the working pipeline, and it runs on both stores.
assert_contains_fixed "WU1 1.3: commands/prime.md documents the keyword pipeline" \
  commands/prime.md "$PRIME_PIPELINE"
assert_not_matches "WU1 1.3: commands/prime.md has no broken cat|jq form" \
  commands/prime.md 'cat [^|]*\.jsonl *[|] *jq'
for kb in .beads/knowledge knowledge; do
  out=""
  if out="$(cd "$DRIFT_ROOT" && KB="$kb" K="test" bash -o pipefail -c "$PRIME_PIPELINE" 2>&1)" && [ -n "$out" ]; then
    pass "WU1 1.3: prime pipeline exits 0 with output on $kb"
  else
    fail "WU1 1.3: prime pipeline on $kb (exit/empty): ${out:0:200}"
  fi
done

# 1.4 TOML prompts describe /prime filtering in plain words, without flags.
for f in commands/metaswarm/prime.toml commands/metaswarm/handoff.toml commands/prime.md .claude/commands/prime.md; do
  assert_not_matches "WU1 1.4: no --files/--keywords/--work-type in $f" "$f" '--(files|keywords|work-type)'
done
assert_contains_fixed "WU1 1.4: prime.toml describes keyword filtering" commands/metaswarm/prime.toml "keyword" -i
assert_contains_fixed "WU1 1.4: prime.toml describes work-type filtering" commands/metaswarm/prime.toml "work type" -i

# ===========================================================================
# Results
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
