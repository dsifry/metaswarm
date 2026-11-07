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

# PR #71 review: filters must output each fact's recommendation; a fixed fixture
# gives the pipeline tests a known match (not whatever the real stores contain).
PRIME_FIXTURE=tests/deps/fixtures/knowledge
PRIME_OUT='.fact + (if .recommendation then "\n  -> " + .recommendation else "" end)'
PRIME_KEYWORD_PIPELINE='grep -hv '"'"'^#'"'"' "$KB"/*.jsonl | jq -r --arg k "$K" '"'"'select((.fact | test($k; "i")) or ((.tags // []) | any(test($k; "i")))) | '"$PRIME_OUT"''"'"''
PRIME_TYPE_PIPELINE='grep -hv '"'"'^#'"'"' "$KB"/*.jsonl | jq -r --arg t "$T" '"'"'select(.type | test("^(" + $t + ")$")) | "[\(.type)] " + '"$PRIME_OUT"''"'"''

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
assert_not_matches "WU1 1.3: commands/prime.md has no broken cat|jq form" \
  commands/prime.md 'cat [^|]*\.jsonl *[|] *jq'
for kb in .beads/knowledge knowledge; do
  out=""
  if out="$(cd "$DRIFT_ROOT" && KB="$kb" K="test" bash -o pipefail -c "$PRIME_KEYWORD_PIPELINE" 2>&1)"; then
    pass "WU1 1.3: prime keyword pipeline exits 0 on $kb"
  else
    fail "WU1 1.3: prime keyword pipeline on $kb: ${out:0:200}"
  fi
done
# Known match on a fixed fixture (with a '#' comment line): the fact AND its recommendation.
assert_contains_fixed "PR #71: commands/prime.md documents the keyword pipeline with recommendations" \
  commands/prime.md "$PRIME_KEYWORD_PIPELINE"
assert_contains_fixed "PR #71: commands/prime.md documents the work-type pipeline with recommendations" \
  commands/prime.md "$PRIME_TYPE_PIPELINE"
out="$(cd "$DRIFT_ROOT" && KB="$PRIME_FIXTURE" K="fixturewidget" bash -o pipefail -c "$PRIME_KEYWORD_PIPELINE" 2>&1 || true)"
if grep -qF -e 'Fixturewidget tokens must never be logged.' <<<"$out" && grep -qF -e 'Redact fixturewidget tokens before logging.' <<<"$out"; then
  pass "PR #71: keyword pipeline returns the fixture fact and its recommendation"
else
  fail "PR #71: keyword pipeline on fixture: ${out:0:300}"
fi
REVIEW_TYPES="$(grep -E '^[|] *review *[|]' "$DRIFT_ROOT/commands/prime.md" | head -1 | sed -E 's/^[|] *review *[|] *//; s/ *[|] *$//; s/`//g; s/, */|/g')"
out="$(cd "$DRIFT_ROOT" && KB="$PRIME_FIXTURE" T="$REVIEW_TYPES" bash -o pipefail -c "$PRIME_TYPE_PIPELINE" 2>&1 || true)"
if grep -qF -e '[security] Fixturewidget tokens must never be logged.' <<<"$out"; then
  pass "PR #71: the review work type includes security facts"
else
  fail "PR #71: review work type ($REVIEW_TYPES) misses the security fixture: ${out:0:300}"
fi
# Every fact type in the knowledge schema is loaded by at least one work type.
TABLE="$(grep -E '^[|] *(planning|implementation|review|debugging|research) *[|]' "$DRIFT_ROOT/commands/prime.md" || true)"
for t in api_behavior code_quirk pattern gotcha decision dependency performance security; do
  if grep -qF -e "\`$t\`" <<<"$TABLE"; then pass "PR #71: work-type table loads $t"; else fail "PR #71: no work type loads $t"; fi
done

# 1.4 TOML prompts describe /prime filtering in plain words, without flags.
for f in commands/metaswarm/prime.toml commands/metaswarm/handoff.toml commands/prime.md .claude/commands/prime.md; do
  assert_not_matches "WU1 1.4: no --files/--keywords/--work-type in $f" "$f" '--(files|keywords|work-type)'
done
assert_contains_fixed "WU1 1.4: prime.toml describes keyword filtering" commands/metaswarm/prime.toml "keyword" -i
assert_contains_fixed "WU1 1.4: prime.toml describes work-type filtering" commands/metaswarm/prime.toml "work type" -i

# ===========================================================================
# WU2 (owned files): bd prime flags (P1) and priming claims (P2) in agents
# ===========================================================================
echo ""
echo "WU2: bd prime flags and priming claims (agents + skills/start/agents twins)"

WU2_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && WU2_FILES+=("$f")
done < <(git -C "$DRIFT_ROOT" ls-files -- 'agents/*.md' 'skills/start/agents/*.md')

if [ "${#WU2_FILES[@]}" -gt 0 ]; then
  pass "WU2: agent file list is non-empty (${#WU2_FILES[@]} files)"
  assert_no_hits "WU2 2.1: no bd prime flag usage in agents (P1)" P1 "${WU2_FILES[@]}"
  assert_no_hits "WU2 2.1: no stale bd/BEADS priming claims in agents (P2)" P2 "${WU2_FILES[@]}"
else
  fail "WU2: no tracked agents/*.md or skills/start/agents/*.md files"
fi

# 2.2 Twins differ only in ./ and .claude/ prefixes. coder.md and
# pr-shepherd-agent.md carry known pre-existing 2-line content differences;
# their normalised diff must equal that baseline exactly.
normalise_twin() { sed 's#\./##g;s#\.claude/##g'; }
WU2_CODER_BASELINE='323c323
< See `guides/typescript-patterns.md` for full guidance.
---
> Follow TypeScript strict mode conventions as defined in the project'"'"'s tsconfig.json and ESLint configuration.'
WU2_SHEPHERD_BASELINE='26c26
< **See**: `plugins/your-project/skills/pr-shepherd/SKILL.md` for detailed PR monitoring behavior.
---
> **See**: the `metaswarm:pr-shepherd` skill for detailed PR monitoring behavior.'

twin_diff() {
  # Strip the line-number header so the baseline survives line shifts above it.
  diff <(normalise_twin <"$DRIFT_ROOT/agents/$1") \
       <(normalise_twin <"$DRIFT_ROOT/skills/start/agents/$1") | sed '/^[0-9][0-9,]*[acd][0-9][0-9,]*$/d' || true
}
strip_hdr() { sed '/^[0-9][0-9,]*[acd][0-9][0-9,]*$/d'; }

while IFS= read -r a; do
  [ -n "$a" ] || continue
  b="${a#agents/}"
  if [ ! -f "$DRIFT_ROOT/skills/start/agents/$b" ]; then
    fail "WU2 2.2: $b has no twin in skills/start/agents/"
    continue
  fi
  got="$(twin_diff "$b")"
  case "$b" in
    coder.md) want="$(printf '%s\n' "$WU2_CODER_BASELINE" | strip_hdr)" ;;
    pr-shepherd-agent.md) want="$(printf '%s\n' "$WU2_SHEPHERD_BASELINE" | strip_hdr)" ;;
    *) want="" ;;
  esac
  if [ "$got" = "$want" ]; then
    pass "WU2 2.2: twin $b matches (prefix-normalised)"
  else
    fail "WU2 2.2: twin $b drifted (prefix-normalised diff differs from baseline)"
    while IFS= read -r line; do echo "      $line"; done <<<"$got"
  fi
done < <(git -C "$DRIFT_ROOT" ls-files -- 'agents/*.md')

# ===========================================================================
# WU3 (owned files): removed bd commands (P7), compact wording (P6), P2
# ===========================================================================
echo ""
echo "WU3: removed bd commands, compact wording and self-reflect (owned files + mirrors)"

WU3_AGENTS=(swarm-coordinator-agent issue-orchestrator architect-agent coder
            pr-shepherd-agent test-automator-agent metrics-agent)
WU3_TEMPLATES=(beads-readme beads-developer-setup task-completion-checklist
               todo-management CLAUDE)
WU3_FILES=(
  AGENTS.md CLAUDE.md USAGE.md guides/worktree-development.md
  commands/self-reflect.md
  skills/setup/SKILL.md skills/start/SKILL.md skills/orchestrated-execution/SKILL.md
  # generated mirror
  .claude/commands/self-reflect.md
)
for t in "${WU3_TEMPLATES[@]}"; do
  WU3_FILES+=("templates/$t.md" "skills/setup/templates/$t.md")
done
for a in "${WU3_AGENTS[@]}"; do
  WU3_FILES+=("agents/$a.md" "skills/start/agents/$a.md")
done

assert_tracked "WU3 owned files and mirrors are tracked" "${WU3_FILES[@]}"
assert_no_hits "WU3 3.1: no removed/invented bd commands or flags (P7)" P7 "${WU3_FILES[@]}"
assert_no_hits "WU3 3.1: no stale bd compact wording (P6)" P6 "${WU3_FILES[@]}"
assert_no_hits "WU3 3.1: no stale bd/BEADS priming claims (P2)" P2 "${WU3_FILES[@]}"

# .gitattributes (merge=beads / bd merge) is deleted.
if [ -e "$DRIFT_ROOT/.gitattributes" ]; then
  fail "WU3: .gitattributes (merge=beads driver) is removed"
else
  pass "WU3: .gitattributes (merge=beads driver) is removed"
fi

# 3.2 self-reflect has no compaction step, no bd compact, and no Step 8.
for f in commands/self-reflect.md .claude/commands/self-reflect.md; do
  assert_not_matches "WU3 3.2: no bd compact in $f" "$f" 'bd (admin )?compact'
  assert_not_matches "WU3 3.2: no compaction step in $f" "$f" '^#+ .*(compact|compaction)'
  assert_not_matches "WU3 3.2: no Step 8 in $f" "$f" 'step 8'
  assert_contains_fixed "WU3 3.2: Step 7 still exists in $f (renumbered)" "$f" "Step 7"
done

# 3.3 beads templates describe bd compact (Dolt history) and bd admin compact.
for f in templates/beads-readme.md skills/setup/templates/beads-readme.md; do
  assert_contains_fixed "WU3 3.3: $f documents bd admin compact --analyze" "$f" 'bd admin compact --analyze'
  assert_contains_fixed "WU3 3.3: $f documents bd admin compact --apply" "$f" 'bd admin compact --apply'
  assert_contains_fixed "WU3 3.3: $f describes plain bd compact as Dolt history" "$f" 'Dolt history' -i
done

# Presence: every bd dolt push/pull line carries "if a Dolt remote is configured"
# (on the same line, or the line just before it).
dolt_unconditioned() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$DRIFT_ROOT/$f" ] || continue
    FILE="$f" awk '
      { low[NR] = tolower($0); raw[NR] = $0 }
      END {
        cond = "if a dolt remote is configured"
        for (i = 1; i <= NR; i++) {
          if (low[i] !~ /bd dolt (push|pull)/) continue
          if (index(low[i], cond) || (i > 1 && index(low[i-1], cond))) continue
          print ENVIRON["FILE"] ":" i ":" raw[i]
        }
      }
    ' "$DRIFT_ROOT/$f"
  done < <(list_files "$@")
}
hits="$(dolt_unconditioned "${WU3_FILES[@]}")"
if [ -z "$hits" ]; then
  pass "WU3: every bd dolt push/pull line carries 'if a Dolt remote is configured'"
else
  fail "WU3: bd dolt push/pull without 'if a Dolt remote is configured'"
  while IFS= read -r line; do echo "      $line"; done <<<"$hits"
fi
# The sync replacements actually exist (not just deleted).
assert_contains_fixed "WU3: skills/start/SKILL.md uses bd dolt push" skills/start/SKILL.md 'bd dolt push'
assert_contains_fixed "WU3: skills/start/SKILL.md uses bd dolt pull" skills/start/SKILL.md 'bd dolt pull'

# ===========================================================================
# WU4: version claims
# ===========================================================================
echo ""
echo "WU4: version claims"

WU4_FILES=(
  INSTALL.md README.md docs/index.html skills/status/SKILL.md
  templates/beads-developer-setup.md
  # generated mirror
  skills/setup/templates/beads-developer-setup.md
)
assert_tracked "WU4 owned files and mirrors are tracked" "${WU4_FILES[@]}"
# 4.1 P5 repo-wide (in-scope tracked files; no pathspecs = whole tree).
assert_no_hits "WU4 4.1: no stale bd/beads version claims repo-wide (P5)" P5
assert_no_hits "WU4 4.1: no stale bd/BEADS priming claims (P2)" P2 "${WU4_FILES[@]}"
# 4.2 R4 verbatim in INSTALL.md and README.md.
R4_TEXT='bd ≥ 1.0.4 (tested with 1.3.4); the beads plugin version matching your bd; Dolt ≥ 2.4.0 only for server mode (`bd init --server`)'
for f in INSTALL.md README.md; do
  assert_contains_fixed "WU4 4.2: $f states R4 verbatim" "$f" "$R4_TEXT"
done
# The pinned phrase survives the version rewrite.
for f in templates/beads-developer-setup.md skills/setup/templates/beads-developer-setup.md; do
  assert_contains_fixed "WU4: $f keeps 'standalone beads plugin'" "$f" "standalone beads plugin"
done

# ===========================================================================
# WU5: repo-wide regression guard (every class over every in-scope file)
# ===========================================================================
echo ""
echo "WU5: repo-wide regression guard (all in-scope tracked files)"

# In-scope = tracked files minus EXCLUDES (docs/plans, CHANGELOG.md, .beads,
# tests, node_modules). No pathspecs below means "the whole in-scope tree".
WU5_COUNT="$(list_files | grep -c . || true)"
if [ "${WU5_COUNT:-0}" -gt 0 ]; then
  pass "WU5: in-scope file list is non-empty ($WU5_COUNT files)"
  assert_no_hits "WU5 5.1: no bd prime flag usage repo-wide (P1)" P1
  assert_no_hits "WU5 5.1: no stale bd/BEADS priming claims repo-wide (P2)" P2
  assert_no_hits "WU5 5.1: no stale bd/beads version claims repo-wide (P5)" P5
  assert_no_hits "WU5 5.1: no stale bd compact wording repo-wide (P6)" P6
  assert_no_hits "WU5 5.1: no removed/invented bd commands or flags repo-wide (P7)" P7
else
  fail "WU5: in-scope file list is empty (DRIFT_ROOT=$DRIFT_ROOT)"
fi

# ===========================================================================
# Results
# ===========================================================================
# PR #71 review: /prime's file filter is a substring match, so R2 "touching" arguments
# must be path fragments, not globs; recovery loads facts through a filter.
hits="$(cd "$DRIFT_ROOT" && { git grep -nE 'knowledge priming\) for .* touching [^ ]*[*]' -- agents skills/start/agents; git grep -nE '(^|`)/prime [^`]*[*]' -- commands/prime.md .claude/commands/prime.md; } || true)"
if [ -z "$hits" ]; then pass "PR #71: R2 touching arguments are path fragments, not globs"; else fail "PR #71: R2 touching argument uses a glob"; printf '      %s\n' "$hits"; fi
for f in commands/prime.md .claude/commands/prime.md; do
  rec="$(awk '/^### Context Recovery|^## Context Recovery/{on=1} on' "$DRIFT_ROOT/$f")"
  tline="$(grep -E '^T="[^"]+" *# e\.g\. resuming implementation' <<<"$rec" | head -1 || true)"
  pline="$(grep -F -e "grep -hv '^#' .beads/knowledge/*.jsonl | jq -r --arg t" <<<"$rec" | head -1 || true)"
  if [ -z "$tline" ] || [ -z "$pline" ]; then
    fail "PR #71: $f recovery step loads facts through the work-type filter (step missing)"
    continue
  fi
  out="$(cd "$DRIFT_ROOT" && bash -o pipefail -c "${tline%%#*}; ${pline//.beads\/knowledge/$PRIME_FIXTURE}" 2>&1 || true)"
  if grep -qF -e '[security] Fixturewidget tokens must never be logged.' <<<"$out" \
     && grep -qF -e 'Redact fixturewidget tokens before logging.' <<<"$out" \
     && ! grep -qF -e 'Fixturewidget decisions live in ADRs.' <<<"$out"; then
    pass "PR #71: $f recovery pipeline returns matching types with recommendations and filters others out"
  else
    fail "PR #71: $f recovery pipeline on fixture: ${out:0:300}"
  fi
done

USED_TYPES="$(cd "$DRIFT_ROOT" && git grep -hoE 'knowledge priming\) for [a-z]+ work' -- agents skills/start/agents | sed -E 's/.* for ([a-z]+) work/\1/' | sort -u || true)"
for t in $USED_TYPES; do
  if grep -qE "^[|] *$t *[|]" "$DRIFT_ROOT/commands/prime.md"; then pass "PR #71: work type '$t' used by agents is documented"; else fail "PR #71: work type '$t' used by agents is not in the prime.md table"; fi
done
REL_ROW="$(grep -E '^[|] *release *[|]' "$DRIFT_ROOT/commands/prime.md" || true)"
if grep -qF -e '`pattern`' <<<"$REL_ROW"; then pass "PR #71: release work type loads patterns (deploy/rollback procedures)"; else fail "PR #71: release work type misses pattern facts"; fi
# 4. bd admin compact needs server mode
for f in templates/beads-readme.md skills/setup/templates/beads-readme.md templates/beads-developer-setup.md skills/setup/templates/beads-developer-setup.md; do
  assert_contains_fixed "PR #71: $f says bd admin needs server mode" "$f" 'requires server mode (`bd init --server`)'
done

# PR #71 review: cross-actor reassignment differs between bd 1.0.4 and 1.3.4.
for f in agents/swarm-coordinator-agent.md skills/start/agents/swarm-coordinator-agent.md; do
  assert_contains_fixed "PR #71: $f hands off by release then atomic claim" "$f" 'bd update <task-id> --claim'
  assert_contains_fixed "PR #71: $f holder releases with an empty assignee" "$f" '--status open --assignee ""'
  assert_contains_fixed "PR #71: $f forbids overwriting --assignee" "$f" 'Never reassign by overwriting `--assignee`'
  assert_contains_fixed "PR #71: $f covers bd 1.0.4" "$f" 'On bd 1.0.4'
  assert_not_matches "PR #71: $f has no check-then-update transfer" "$f" 'then run the same `bd update` without'
done

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
