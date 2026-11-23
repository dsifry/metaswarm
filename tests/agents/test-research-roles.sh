#!/usr/bin/env bash
# tests/agents/test-research-roles.sh
# Research roles: codebase-researcher (sonnet, code facts), deep-researcher (fable, design research)
# and the deprecated `researcher` alias. Covers agent frontmatter, the deep-research rubric and its
# lenses, the research-selection guide (evidence and default pattern), models.yaml resolution
# (including the legacy roles.researcher key), generation, wiring into brainstorming and the issue
# orchestrator, the role-type roster and the alias rule, docs, counts and the changelog.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TOOL="$ROOT/bin/metaswarm-agents.sh"
RUBRIC="rubrics/deep-research-rubric.md"
GUIDE="guides/research-selection.md"
COORD="guides/agent-coordination.md"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
# bash 3.2 exits with the trap status (0) when `set -u` aborts; DONE is set after the summary.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
has() { [ -f "$1" ] && grep -qF -- "$2" "$1" && pass "$1 has '$2'" || fail "$1 missing '$2'"; }
hasi() { [ -f "$1" ] && grep -qiF -- "$2" "$1" && pass "$1 has '$2' (any case)" || fail "$1 missing '$2' (any case)"; }
lacks() { [ -f "$1" ] && ! grep -qF -- "$2" "$1" && pass "$1 has no '$2'" || fail "$1 still has '$2'"; }

frontmatter() { [ -f "$1" ] || return 0; awk 'NR==1 { if ($0 != "---") exit; next } /^---[[:space:]]*$/ { exit } { print }' "$1"; }
fm_value() { frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
RO="Write, Edit, NotebookEdit"

echo "Test 1: agent frontmatter (both copies)"
for spec in "codebase-researcher|sonnet" "deep-researcher|fable" "deep-researcher-second|opus" "citation-checker|haiku" "researcher|sonnet"; do
  role="${spec%%|*}"; want="${spec#*|}"
  for dir in agents skills/start/agents; do
    f="$dir/$role.md"
    [ -f "$f" ] || { fail "$f missing"; continue; }
    [ "$(fm_value "$f" model)" = "$want" ] && pass "$f model=$want" || fail "$f model != $want"
    [ "$(fm_value "$f" disallowedTools)" = "$RO" ] && pass "$f is read-only" || fail "$f must disallow $RO"
    grep -q '^tools:' "$f" && fail "$f must not declare a tools: allow-list" || pass "$f has no tools: allow-list"
  done
done

echo "Test 2: codebase-researcher"
for dir in agents skills/start/agents; do
  f="$dir/codebase-researcher.md"
  d="$(fm_value "$f" description)"
  case "$d" in *haiku*) pass "$f description says a brief may ask for haiku" ;; *) fail "$f description must mention haiku for simple lookups" ;; esac
  has "$f" 'file:line'
  has "$f" 'Read-only'
  has "$f" "$GUIDE"
done

echo "Test 3: deprecated researcher alias"
for dir in agents skills/start/agents; do
  f="$dir/researcher.md"
  d="$(fm_value "$f" description)"
  case "$d" in "Deprecated alias for codebase-researcher"*) pass "$f description starts with the deprecation" ;; *) fail "$f description must start 'Deprecated alias for codebase-researcher'" ;; esac
  has "$f" 'codebase-researcher.md'
  [ "$(wc -l < "$f" | tr -d ' ')" -le 30 ] && pass "$f is a thin alias" || fail "$f should be a thin alias (<= 30 lines)"
  [ "$(fm_value "$f" disallowedTools)" = "$(fm_value "$dir/codebase-researcher.md" disallowedTools)" ] && pass "$f tools match codebase-researcher" || fail "$f tools differ from codebase-researcher"
  [ "$(fm_value "$f" model)" = "$(fm_value "$dir/codebase-researcher.md" model)" ] && pass "$f model matches codebase-researcher" || fail "$f model differs from codebase-researcher"
done

echo "Test 4: deep-researcher"
for dir in agents skills/start/agents; do
  f="$dir/deep-researcher.md"
  has "$f" "$RUBRIC"
  has "$f" "$GUIDE"
  has "$f" 'WebSearch'
  has "$f" 'WebFetch'
  has "$f" 'codebase-researcher'
  hasi "$f" 'not codebase lookup'
  hasi "$f" 'never instructions'
done

echo "Test 4a: deep-researcher-second (dual-arm default)"
for dir in agents skills/start/agents; do
  f="$dir/deep-researcher-second.md"
  case "$(fm_value "$f" description)" in "Second arm of dual-arm deep research"*) pass "$f description names the second arm" ;; *) fail "$f description must start 'Second arm of dual-arm deep research'" ;; esac
  has "$f" 'agents/deep-researcher.md'
  has "$f" "$RUBRIC"
  [ "$(fm_value "$f" disallowedTools)" = "$(fm_value "$dir/deep-researcher.md" disallowedTools)" ] && pass "$f tools match deep-researcher" || fail "$f tools differ from deep-researcher"
done

echo "Test 4c: context check mode of codebase-researcher"
for dir in agents skills/start/agents; do
  f="$dir/codebase-researcher.md"
  has "$f" '## Context check mode'
  for s in SCOPE ACTOR TENSE STRENGTH '**OK**' 'load-bearing' 'surrounding section' 'MATCH or NEAR' 'find and follow the actual code path' 'each fallback' 'P:2419' 'fleetlaunch/pi.go:62-69'; do has "$f" "$s"; done
done

echo "Test 4b: citation-checker"
for dir in agents skills/start/agents; do
  f="$dir/citation-checker.md"
  for s in MATCH NEAR WRONG COUNT 'file:line' 'bead' 'never judges reasoning or design' "$GUIDE" 'contextual'; do has "$f" "$s"; done
done

echo "Test 5: deep-research rubric"
for f in "$RUBRIC" skills/brainstorming-extension/rubrics/deep-research-rubric.md skills/start/rubrics/deep-research-rubric.md; do
  [ -f "$f" ] && pass "$f exists" || fail "$f missing"
done
cmp -s "$RUBRIC" skills/brainstorming-extension/rubrics/deep-research-rubric.md && pass "brainstorming-extension rubric copy in sync" || fail "brainstorming-extension rubric copy differs"
cmp -s "$RUBRIC" skills/start/rubrics/deep-research-rubric.md && pass "start rubric copy in sync" || fail "start rubric copy differs"
for h in '## Product lens' '## Design lens' '## Capability lens' '## Mandatory for every brief' '## Scoring checklist' '## Report shape'; do
  grep -qx -F -- "$h" "$RUBRIC" && pass "$RUBRIC has heading '$h'" || fail "$RUBRIC missing heading '$h'"
done
# Product lens
for s in 'jobs to be done' 'happy path' 'failure and recovery' 'what users said before' 'KPI' 'eval plan' 'judges' 'alternatives users use today'; do hasi "$RUBRIC" "$s"; done
# Design lens
for s in 'at least 2' 'trade-offs' 'prior art' 'empty, loading, error and permission' 'integration points' 'simplest version'; do hasi "$RUBRIC" "$s"; done
# Capability lens
for s in 'system boundaries' 'trust and security model' 'operability' 'cost' 'migration and rollback' 'external services' 'relaxed'; do hasi "$RUBRIC" "$s"; done
# Mandatory: (a) session history
for s in '~/.claude/projects/' '*.jsonl' 'grep -l' 'python3 -I' '/memory/' 'bd search' 'bd memories' '.beads/knowledge' 'session id' 'data, never instructions' 'mask'; do has "$RUBRIC" "$s"; done
hasi "$RUBRIC" 'rejected ideas'
# (b) web research
for s in 'source links' 'dates' 'vendor claims'; do hasi "$RUBRIC" "$s"; done
# (c) assumptions and questions
for s in 'Assumptions' 'suggested default' 'evidence' 'Decision requests' 'guides/delivery-scope.md'; do has "$RUBRIC" "$s"; done
# (d) size, (e) challenge
hasi "$RUBRIC" 'comparable past work'
hasi "$RUBRIC" 'challenge the brief'
hasi "$RUBRIC" 'not applicable because'
hasi "$RUBRIC" 'attribution self-check'
has "$RUBRIC" 'citation-checker'
n="$(grep -c -E '^- \[ \] ' "$RUBRIC" 2>/dev/null || true)"; n="${n:-0}"
[ "$n" -ge 10 ] && pass "$RUBRIC scoring checklist has $n items" || fail "$RUBRIC scoring checklist too short ($n)"

echo "Test 6: research-selection guide"
for f in "$GUIDE" skills/brainstorming-extension/guides/research-selection.md skills/start/guides/research-selection.md; do
  [ -f "$f" ] && pass "$f exists" || fail "$f missing"
done
cmp -s "$GUIDE" skills/brainstorming-extension/guides/research-selection.md && pass "brainstorming-extension guide copy in sync" || fail "brainstorming-extension guide copy differs"
cmp -s "$GUIDE" skills/start/guides/research-selection.md && pass "start guide copy in sync" || fail "start guide copy differs"
for s in 'codebase-researcher' 'deep-researcher' '2026-11-23' 'one sample' '8/10' '7/10' '7.5' '159k' '216k' 'in parallel' 'blind judge' 'roles.codebase-researcher' 'roles.deep-researcher' 'Deprecated alias'; do has "$GUIDE" "$s"; done
hasi "$GUIDE" 'complementary'
for s in 'citation-checker' '138k' '108 s' '132k' '65 s' '22/26' '24/29' '186k' '99k' '4 of' '5 more WRONG' 'mis-attribution' 'NEAR and WRONG corrections'; do has "$GUIDE" "$s"; done
hasi "$GUIDE" 'cannot spawn subagents'
PIPE='researcher(s) → citation check → context check → apply corrections → design'
for f in "$GUIDE" skills/brainstorming-extension/SKILL.md agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do has "$f" "$PIPE"; done
for s in '## Context check' 'SCOPE' 'ACTOR' 'TENSE' 'STRENGTH' 'test-fleet line' 'ops.env' '116k' '138 s' '47 claims' 'all 3 context errors' 'about 20 more' 'realCompany' 'log-only' 'P:2419' 'fleetlaunch/pi.go:62-69' 'find and follow the actual code path' 'Slack app' 'create without --import fails seat start' '## Dual-arm deep research (default)' 'two deep-researchers' 'roles.deep-researcher-second' 'Single arm' 'getting the facts right' 'deep-researcher-second'; do has "$GUIDE" "$s"; done
has guides/coder-selection.md 'research-selection.md'

echo "Test 7: models.yaml template, resolution and legacy alias"
grep -q '^  codebase-researcher:$' templates/models.yaml && pass "template has roles.codebase-researcher" || fail "template missing roles.codebase-researcher"
grep -q '^  deep-researcher:$' templates/models.yaml && pass "template has roles.deep-researcher" || fail "template missing roles.deep-researcher"
grep -q '^  researcher:$' templates/models.yaml && fail "template must not set roles.researcher (deprecated alias)" || pass "template does not set roles.researcher"
grep -q 'researcher.*deprecated alias' templates/models.yaml && pass "template documents the researcher alias" || fail "template missing alias note"
cmp -s templates/models.yaml skills/setup/templates/models.yaml && pass "setup template identical" || fail "setup template differs"
proj() { P="$TMP/$1"; mkdir -p "$P/.metaswarm"; git -C "$P" init -q; cat > "$P/.metaswarm/models.yaml"; }
resolve() { (cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" resolve "$@" 2>&1); }
proj tmpl < templates/models.yaml
[ "$(resolve codebase-researcher claude)" = sonnet ] && pass "template: codebase-researcher claude=sonnet" || fail "template: codebase-researcher claude"
[ "$(resolve deep-researcher claude)" = fable ] && pass "template: deep-researcher claude=fable" || fail "template: deep-researcher claude"
[ "$(resolve citation-checker claude)" = haiku ] && pass "template: citation-checker claude=haiku" || fail "template: citation-checker claude"
[ "$(resolve deep-researcher-second claude)" = opus ] && pass "template: deep-researcher-second claude=opus" || fail "template: deep-researcher-second claude"
grep -q '^  deep-researcher-second:$' templates/models.yaml && pass "template has roles.deep-researcher-second" || fail "template missing roles.deep-researcher-second"
grep -q '^  citation-checker:$' templates/models.yaml && pass "template has roles.citation-checker" || fail "template missing roles.citation-checker"
[ "$(resolve researcher claude)" = sonnet ] && pass "template: researcher alias resolves" || fail "template: researcher alias"
proj legacy <<'Y'
roles:
  researcher:
    claude: haiku
Y
[ "$(resolve codebase-researcher claude)" = haiku ] && pass "legacy roles.researcher maps to codebase-researcher" || fail "legacy mapping: $(resolve codebase-researcher claude)"
[ "$(resolve researcher claude)" = haiku ] && pass "legacy roles.researcher still sets the alias" || fail "legacy alias: $(resolve researcher claude)"
proj both <<'Y'
roles:
  researcher:
    claude: haiku
  codebase-researcher:
    claude: opus
Y
[ "$(resolve codebase-researcher claude)" = opus ] && pass "roles.codebase-researcher wins over roles.researcher" || fail "precedence: $(resolve codebase-researcher claude)"
[ "$(resolve researcher claude)" = haiku ] && pass "roles.researcher still sets the alias when both are set" || fail "alias own key"
proj newonly <<'Y'
roles:
  codebase-researcher:
    claude: haiku
Y
[ "$(resolve researcher claude)" = haiku ] && pass "alias follows roles.codebase-researcher" || fail "alias follows: $(resolve researcher claude)"
proj bare <<'Y'
roles:
  coder:
    claude: sonnet
Y
[ "$(resolve codebase-researcher claude)" = sonnet ] && pass "plugin default sonnet (codebase-researcher)" || fail "plugin default codebase-researcher"
[ "$(resolve deep-researcher claude)" = fable ] && pass "plugin default fable (deep-researcher)" || fail "plugin default deep-researcher"

echo "Test 8: generate renders the research roles"
proj gen < templates/models.yaml
(cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" generate >/dev/null 2>&1) && pass "generate ok" || fail "generate failed"
grep -q '^model: sonnet$' "$P/.claude/agents/metaswarm-codebase-researcher.md" 2>/dev/null && pass "codebase-researcher generated with sonnet" || fail "codebase-researcher generated"
grep -q '^model: fable$' "$P/.claude/agents/metaswarm-deep-researcher.md" 2>/dev/null && pass "deep-researcher generated with fable" || fail "deep-researcher generated"
grep -q '^model: opus$' "$P/.claude/agents/metaswarm-deep-researcher-second.md" 2>/dev/null && pass "deep-researcher-second generated with opus" || fail "deep-researcher-second generated"
grep -q '^model: haiku$' "$P/.claude/agents/metaswarm-citation-checker.md" 2>/dev/null && pass "citation-checker generated with haiku" || fail "citation-checker generated"
grep -q '^description: "Deprecated alias' "$P/.claude/agents/metaswarm-researcher.md" 2>/dev/null && pass "researcher alias generated" || fail "researcher alias generated"
(cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" check >/dev/null 2>&1) && pass "check clean after generate" || fail "check after generate"

echo "Test 9: role-type roster and alias rule"
SECTION="$(awk '/^## Role type resolution$/{on=1; next} on && /^## /{exit} on{print}' "$COORD")"
echo "$SECTION" | grep -q -E '^\| `codebase-researcher` \|.*\| sonnet \|$' && pass "roster: codebase-researcher sonnet" || fail "roster missing codebase-researcher sonnet"
echo "$SECTION" | grep -q -E '^\| `deep-researcher` \|.*\| fable \|$' && pass "roster: deep-researcher fable" || fail "roster missing deep-researcher fable"
echo "$SECTION" | grep -q -E '^\| `deep-researcher-second` \|.*\| opus \|$' && pass "roster: deep-researcher-second opus" || fail "roster missing deep-researcher-second opus"
echo "$SECTION" | grep -q -E '^\| `citation-checker` \|.*\| haiku \|$' && pass "roster: citation-checker haiku" || fail "roster missing citation-checker haiku"
echo "$SECTION" | grep -q -E '^\| `researcher` \|' && fail "roster must not list the deprecated researcher" || pass "roster does not list researcher"
echo "$SECTION" | grep -q -F 'Deprecated alias: the `researcher` role type resolves as `codebase-researcher`' && pass "alias rule stated" || fail "alias rule missing from Role type resolution"
for f in skills/orchestrated-execution/$COORD skills/design-review-gate/$COORD skills/pr-shepherd/$COORD skills/start/$COORD; do
  cmp -s "$COORD" "$f" && pass "$f in sync" || fail "$f differs"
done

echo "Test 10: no spawn site names the alias"
SCOPE="$( { find skills -name '*.md' -type f; ls agents/*.md guides/*.md commands/*.md templates/*.md CLAUDE.md AGENTS.md GEMINI.md 2>/dev/null; } | sort -u )"
BAD=""
while IFS= read -r f; do
  grep -q -F 'roleType("researcher")' "$f" && BAD="$BAD $f"
done <<< "$SCOPE"
[ -z "$BAD" ] && pass "no roleType(\"researcher\") anywhere in scope" || fail "roleType(\"researcher\") still used in:$BAD"

echo "Test 11: wiring"
for f in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md; do
  has "$f" 'roleType("codebase-researcher")'
  has "$f" 'roleType("deep-researcher")'
  hasi "$f" 'new user-facing feature or capability'
done
for f in agents/issue-orchestrator.md skills/start/agents/issue-orchestrator.md skills/brainstorming-extension/SKILL.md; do
  has "$f" 'roleType("citation-checker")'
  hasi "$f" 'citation check'
  has "$f" 'roleType("deep-researcher-second")'
  hasi "$f" 'context check'
done
BX=skills/brainstorming-extension/SKILL.md
has "$BX" '### Research before options'
has "$BX" 'roleType("deep-researcher")'
has "$BX" 'roleType("codebase-researcher")'
has "$BX" './rubrics/deep-research-rubric.md'
has "$BX" './guides/research-selection.md'
hasi "$BX" 'before options are presented'
has guides/workflow-enforcement.md 'deep-researcher'
has guides/workflow-enforcement.md 'codebase-researcher'
has skills/start/SKILL.md 'roleType("codebase-researcher")'
has skills/start/SKILL.md 'deep-researcher'
has CLAUDE.md 'deep-researcher'
for f in templates/CLAUDE.md templates/CLAUDE-append.md; do has "$f" 'deep-researcher'; done

echo "Test 12: agent lists, docs and counts"
for f in bin/metaswarm-agents.sh skills/setup/bin/metaswarm-agents.sh; do
  for r in codebase-researcher deep-researcher deep-researcher-second citation-checker researcher; do
    grep -q "^ROLES=.* $r " "$f" && pass "$f ROLES has $r" || fail "$f ROLES missing $r"
  done
done
for ref in codex-tools cursor-tools opencode-tools platform-adaptation; do
  f="skills/start/references/$ref.md"
  has "$f" 'codebase-researcher'
  has "$f" 'deep-researcher'
  has "$f" 'citation-checker'
  has "$f" 'deep-researcher-second'
done
has GEMINI.md 'citation-checker'
has README.md '`citation-checker`'
has USAGE.md 'agents/citation-checker.md'
has GEMINI.md 'codebase-researcher'
has GEMINI.md 'deep-researcher'
has README.md '`codebase-researcher`'
has README.md '`deep-researcher`'
has USAGE.md 'agents/codebase-researcher.md'
has USAGE.md 'agents/deep-researcher.md'
has USAGE.md 'agents/researcher.md'
# The repo counts agent definition files (the deprecated alias included; see test-design-gate-reviewers.sh).
ACTIVE="$(ls agents/*.md | wc -l | tr -d ' ')"
for f in README.md USAGE.md AGENTS.md CLAUDE.md GEMINI.md .claude-plugin/plugin.json .codex-plugin/plugin.json gemini-extension.json templates/CLAUDE.md docs/index.html; do
  grep -q -E "(^|[^0-9])$ACTIVE (AI )?agents" "$f" && pass "$f states $ACTIVE agents" || fail "$f does not state $ACTIVE agents"
done
grep -q -i 'deprecated `researcher` alias' README.md && pass "README mentions the deprecated alias" || fail "README missing deprecated alias note"

echo "Test 13: CHANGELOG"
UNREL="$(awk '/^## \[Unreleased\]/{on=1; next} on && /^## /{exit} on{print}' CHANGELOG.md)"
for s in 'codebase-researcher' 'deep-researcher' 'deep-researcher-second' 'citation-checker' 'context check' 'Deprecated alias' 'deep-research-rubric.md' 'research-selection.md'; do
  echo "$UNREL" | grep -q -F -- "$s" && pass "CHANGELOG Unreleased mentions $s" || fail "CHANGELOG Unreleased missing $s"
done

echo "Test 14: usage report classifies the research roles"
for t in codebase-researcher deep-researcher deep-researcher-second citation-checker metaswarm-codebase-researcher metaswarm:deep-researcher; do
  got="$(node -e "const u=require('./bin/metaswarm-usage'); process.stdout.write(u.classifyPhase('$t',''))" 2>/dev/null || true)"
  [ "$got" = research ] && pass "classifyPhase($t)=research" || fail "classifyPhase($t)='$got'"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
