#!/usr/bin/env bash
# tests/agents/test-coder-tiers.sh
# Coder tiers: mechanical-coder (haiku), coder (sonnet, default), supercoder (opus).
# Covers agent frontmatter, models.yaml resolution (including the legacy escalation.coder mapping),
# the rubric guide and its links, and the fresh-coder rule.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TOOL="$ROOT/bin/metaswarm-agents.sh"
SKILL="skills/orchestrated-execution/SKILL.md"
GUIDE="guides/coder-selection.md"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
# bash 3.2 exits with the trap status (0) when `set -u` aborts; DONE is set after the summary.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
has() { grep -qF -- "$2" "$1" && pass "$1 has '$2'" || fail "$1 missing '$2'"; }

fm_model() { awk 'NR==1{ if ($0!="---") exit; next } /^---[[:space:]]*$/ { exit } /^model:/ { sub(/^model:[[:space:]]*/,""); print; exit }' "$1"; }

echo "Test 1: agent frontmatter"
for pair in "mechanical-coder:haiku" "coder:sonnet" "supercoder:opus" "debugger:fable"; do
  role="${pair%%:*}"; want="${pair#*:}"
  for dir in agents skills/start/agents; do
    f="$dir/$role.md"
    [ -f "$f" ] || { fail "$f missing"; continue; }
    [ "$(fm_model "$f")" = "$want" ] && pass "$f model=$want" || fail "$f model != $want"
  done
done
has agents/mechanical-coder.md 'needs coder'
has agents/mechanical-coder.md 'STOP'
has agents/mechanical-coder.md "$GUIDE"
has agents/supercoder.md "$GUIDE"
has agents/coder.md "$GUIDE"
has agents/debugger.md "$GUIDE"
has agents/debugger.md 'Never guess'
has agents/debugger.md 'scratch directory'
has agents/debugger.md 'superpowers:systematic-debugging'
grep -q '^disallowedTools:' agents/debugger.md && fail "debugger must not declare disallowedTools (it writes to scratch)" || pass "debugger declares no disallowedTools"

echo "Test 2: models.yaml resolution"
proj() { # name, models.yaml body on stdin
  P="$TMP/$1"; mkdir -p "$P/.metaswarm"; git -C "$P" init -q; cat > "$P/.metaswarm/models.yaml"
}
resolve() { (cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" resolve "$@" 2>&1); }

proj tmpl < templates/models.yaml
[ "$(resolve mechanical-coder claude)" = haiku ] && pass "template: mechanical-coder claude=haiku" || fail "template: mechanical-coder claude"
[ "$(resolve supercoder claude)" = opus ] && pass "template: supercoder claude=opus" || fail "template: supercoder claude"
[ "$(resolve debugger claude)" = fable ] && pass "template: debugger claude=fable" || fail "template: debugger claude"
[ "$(resolve debugger codex)" = gpt-5.3-codex ] && pass "template: debugger codex strongest" || fail "template: debugger codex"
[ "$(resolve debugger gemini)" = pro ] && pass "template: debugger gemini=pro" || fail "template: debugger gemini"
[ "$(resolve coder claude)" = sonnet ] && pass "template: coder claude=sonnet" || fail "template: coder claude"
for r in mechanical-coder supercoder; do
  for h in codex gemini; do
    [ -n "$(resolve $r $h)" ] && pass "template: $r $h set" || fail "template: $r $h unset"
  done
done
[ "$(resolve supercoder gemini)" = pro ] && pass "template: supercoder gemini=pro" || fail "template: supercoder gemini"
[ "$(resolve mechanical-coder gemini)" = flash ] && pass "template: mechanical-coder gemini=flash" || fail "template: mechanical-coder gemini"
cmp -s templates/models.yaml skills/setup/templates/models.yaml && pass "setup template identical" || fail "setup template differs"

# Legacy: only escalation.coder.claude set -> supercoder follows it
proj legacy <<'Y'
roles:
  coder:
    claude: sonnet
escalation:
  coder:
    after_failures: 3
    claude: claude-opus-4-5
Y
[ "$(resolve supercoder claude)" = claude-opus-4-5 ] && pass "legacy escalation.coder.claude maps to supercoder" || fail "legacy escalation mapping: $(resolve supercoder claude)"
# Explicit roles.supercoder wins over the legacy key
proj explicit <<'Y'
roles:
  supercoder:
    claude: fable
escalation:
  coder:
    claude: opus
Y
[ "$(resolve supercoder claude)" = fable ] && pass "roles.supercoder wins over escalation.coder" || fail "roles.supercoder precedence"
# No models.yaml keys at all -> plugin default
proj bare <<'Y'
roles:
  coder:
    claude: sonnet
Y
[ "$(resolve supercoder claude)" = opus ] && pass "no config falls back to plugin default opus" || fail "plugin default supercoder"
[ "$(resolve debugger claude)" = fable ] && pass "no config falls back to plugin default fable" || fail "plugin default debugger"
[ "$(resolve mechanical-coder claude)" = haiku ] && pass "no config falls back to plugin default haiku" || fail "plugin default mechanical"

echo "Test 3: generate renders both new roles"
proj gen < templates/models.yaml
(cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" generate >/dev/null 2>&1) && pass "generate ok" || fail "generate failed"
grep -q '^name: metaswarm-supercoder$' "$P/.claude/agents/metaswarm-supercoder.md" && pass "supercoder generated" || fail "supercoder not generated"
grep -q '^model: opus$' "$P/.claude/agents/metaswarm-supercoder.md" && pass "supercoder generated with opus" || fail "supercoder model"
grep -q '^model: fable$' "$P/.claude/agents/metaswarm-debugger.md" && pass "debugger generated with fable" || fail "debugger model"
grep -q '^model: haiku$' "$P/.claude/agents/metaswarm-mechanical-coder.md" && pass "mechanical-coder generated with haiku" || fail "mechanical model"
proj gen2 <<'Y'
roles:
  coder:
    claude: sonnet
escalation:
  coder:
    claude: claude-opus-4-5
Y
(cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" generate >/dev/null 2>&1)
grep -q '^model: claude-opus-4-5$' "$P/.claude/agents/metaswarm-supercoder.md" && pass "generated supercoder honours legacy escalation.coder.claude" || fail "generated supercoder legacy model"
(cd "$P" && CLAUDE_PLUGIN_ROOT="$ROOT" bash "$TOOL" check >/dev/null 2>&1) && pass "check clean after generate" || fail "check not clean"

echo "Test 4: rubric guide and links"
[ -f "$GUIDE" ] && pass "$GUIDE exists" || fail "$GUIDE missing"
for s in '## debugger: ANY of these' 'C4 signal' 'flaky' 'cannot reach a root cause' '2x Opus' 'Do NOT use `debugger`' 'one narrow question' 'mechanical-coder' 'supercoder' 'When unsure, use `coder`' 'Never step down within a round' 'C3'; do has "$GUIDE" "$s"; done
for f in "$SKILL" skills/orchestrated-execution/guides/coder-selection.md; do
  [ -f "$f" ] && pass "$f exists" || fail "$f missing"
done
cmp -s "$GUIDE" skills/orchestrated-execution/guides/coder-selection.md && pass "guide mirrored into the skill" || fail "guide mirror differs"
impl="$(awk '/^### Phase 1: IMPLEMENT/{on=1;next} /^### Phase 2/{on=0} on' "$SKILL")"
iter="$(awk '/^When the rule says iterate:/{on=1;next} /^Track each round visibly/{on=0} on' "$SKILL")"
grep -qF './guides/coder-selection.md' <<<"$impl" && pass "IMPLEMENT phase links the rubric" || fail "IMPLEMENT phase does not link the rubric"
grep -qF './guides/coder-selection.md' <<<"$iter" && pass "iterate step links the rubric" || fail "iterate step does not link the rubric"

echo "Test 5: escalation re-spawns supercoder, fresh-coder rule"
grep -qF 'roleType("supercoder")' <<<"$iter" && pass "iterate step spawns supercoder" || fail "iterate step missing roleType(\"supercoder\")"
grep -qF 'escalation.coder.after_failures' <<<"$iter" && pass "iterate step keeps escalation.coder.after_failures" || fail "iterate step lost after_failures"
grep -qF 'escalation.coder.claude' <<<"$iter" && pass "iterate step documents legacy escalation.coder.claude" || fail "iterate step lost escalation.coder.claude"
coord="$(awk '/^## Coordination Mode Note/{on=1;next} /^---/{if(on) exit} on' "$SKILL")"
grep -qF 'may be a persistent teammate' <<<"$coord" && fail "coordination note still says coder may be persistent" || pass "coordination note no longer says persistent coder"
for s in 'FRESH coder' 'never resumed' 'start SHA' 'verbatim' 'minors' 'validation commands' 'resend a lost report'; do
  grep -qiF -- "$s" "$SKILL" && pass "skill fix-brief rule has '$s'" || fail "skill missing '$s'"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
