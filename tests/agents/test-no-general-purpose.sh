#!/usr/bin/env bash
# tests/agents/test-no-general-purpose.sh
# Every Task() spawn uses a metaswarm role type (roleType("<role>")), never general-purpose.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Allowlist of "file|description" spawn entries that may stay general-purpose (starts empty).
ALLOWLIST=""

# Scope: skills/**/*.md agents/*.md guides/*.md commands/*.md templates/*.md + root CLAUDE/AGENTS/GEMINI
SCOPE="$( { find skills -name '*.md' -type f; ls agents/*.md guides/*.md commands/*.md templates/*.md CLAUDE.md AGENTS.md GEMINI.md 2>/dev/null; } | sort -u )"

echo ""
echo "No general-purpose Spawn Tests"
echo "=============================="
echo ""

# 1. Every Task({ block has a subagent_type (within the next 6 lines)
MISSING=""
while IFS= read -r f; do
  out="$(awk -v F="$f" '
    /Task\(\{/ { if (pend) print F ":" pend; pend = NR; left = 6 }
    pend && /subagent_type/ { pend = 0 }
    pend && NR > pend { left--; if (left < 0) { print F ":" pend; pend = 0 } }
    END { if (pend) print F ":" pend }
  ' "$f")"
  [ -n "$out" ] && MISSING="$MISSING
$out"
done <<< "$SCOPE"
if [ -z "$MISSING" ]; then pass "every Task({ block has a subagent_type"; else fail "Task({ without subagent_type:$MISSING"; fi

# 2 + 3. No general-purpose; every value is roleType("<existing role>")
GP=""; INVALID=""
while IFS= read -r f; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"; text="${line#*:}"
    val="$(echo "$text" | sed -E "s/.*subagent_type[\"']?[[:space:]]*[:=][[:space:]]*//; s/[[:space:]]*,?[[:space:]]*\$//")"
    if echo "$val" | grep -q 'general-purpose'; then
      desc="$(sed -n "$((n)),$((n + 4))p" "$f" | sed -n 's/.*description:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      echo "$ALLOWLIST" | grep -qxF "$f|$desc" && [ -n "$ALLOWLIST" ] || GP="$GP
$f:$n"
      continue
    fi
    role="$(echo "$val" | sed -n 's/^roleType("\([a-z0-9-]*\)")$/\1/p')"
    if [ -z "$role" ] || [ ! -f "agents/$role.md" ]; then INVALID="$INVALID
$f:$n ($val)"; fi
  done < <(grep -n -E "subagent_type[\"']?[[:space:]]*[:=]" "$f" || true)
done <<< "$SCOPE"
if [ -z "$GP" ]; then pass "no general-purpose subagent_type outside allowlist"; else fail "general-purpose spawns:$GP"; fi
if [ -z "$INVALID" ]; then pass "every subagent_type is roleType(\"<role>\") with an existing agents/<role>.md"; else fail "invalid subagent_type values:$INVALID"; fi

# 3b. Literal "general-purpose" anywhere in scope (prose included), apart from the allowlist
LIT=""
while IFS= read -r f; do
  hits="$(grep -n -i -F 'general-purpose' "$f" || true)"
  [ -n "$hits" ] || continue
  if [ -n "$ALLOWLIST" ]; then
    while IFS= read -r h; do
      echo "$ALLOWLIST" | grep -qxF "$f|${h#*:}" || LIT="$LIT
$f:$h"
    done <<< "$hits"
  else
    LIT="$LIT
$f:$(echo "$hits" | head -1)"
  fi
done <<< "$SCOPE"
if [ -z "$LIT" ]; then pass "no literal general-purpose anywhere in scope"; else fail "literal general-purpose text:$LIT"; fi

# 4. Prose spawn sites: anchor phrase -> role type named in the same section
# Format: file|anchor phrase (fixed string)|role
SITES='skills/orchestrated-execution/SKILL.md|Spawn a coding subagent|coder
commands/review-design.md|Spawns six review agents in parallel|design-reviewer
skills/brainstorming-extension/SKILL.md|Spawning reviews|design-reviewer
skills/orchestrated-execution/SKILL.md|Spawn a **new** review subagent in adversarial mode|adversarial-reviewer
skills/orchestrated-execution/SKILL.md|the Architect is spawned as|planner
skills/external-tools/SKILL.md|If Claude is selected (escalation|coder
skills/external-tools/SKILL.md|Standard adversarial review (fresh Task() instance, role type|adversarial-reviewer
agents/swarm-coordinator-agent.md|Fire-and-forget `Task()` subagents per worktree orchestrator|issue-orchestrator
agents/swarm-coordinator-agent.md|Spawn Issue Orchestrators as named teammates|issue-orchestrator
agents/swarm-coordinator-agent.md|Adversarial reviewers are ALWAYS fresh `Task()` instances|adversarial-reviewer
skills/start/agents/swarm-coordinator-agent.md|Fire-and-forget `Task()` subagents per worktree orchestrator|issue-orchestrator
skills/start/agents/swarm-coordinator-agent.md|Spawn Issue Orchestrators as named teammates|issue-orchestrator
skills/start/agents/swarm-coordinator-agent.md|Adversarial reviewers are ALWAYS fresh `Task()` instances|adversarial-reviewer
skills/design-review-gate/SKILL.md|**Task Mode** (default): Spawn 6 parallel|design-reviewer
skills/design-review-gate/SKILL.md|**Team Mode**: `TeamCreate|design-reviewer
skills/pr-shepherd/SKILL.md|**Task Mode** (default): Runs as|pr-shepherd-agent
skills/pr-shepherd/SKILL.md|**Team Mode**: Runs as a persistent `shepherd` teammate|pr-shepherd-agent
CLAUDE.md|spawn a fresh `Task()` reviewer|adversarial-reviewer
templates/CLAUDE.md|spawn a fresh `Task()` reviewer|adversarial-reviewer
skills/setup/templates/CLAUDE.md|spawn a fresh `Task()` reviewer|adversarial-reviewer
agents/issue-orchestrator.md|— persistent across research phase|researcher
agents/issue-orchestrator.md|— persistent across planning phase|planner
agents/issue-orchestrator.md|— **persistent across work units**|coder
agents/issue-orchestrator.md|— persistent through PR lifecycle|pr-shepherd-agent
agents/issue-orchestrator.md|Adversarial reviewers are ALWAYS fresh `Task()`|adversarial-reviewer
agents/issue-orchestrator.md|# 5. Spawn Researcher Agent|researcher
agents/issue-orchestrator.md|# 7. Spawn Architect Agent|planner
agents/issue-orchestrator.md|ALL must PASS under the severity rule|plan-reviewer
agents/issue-orchestrator.md|UX Reviewer, CTO; role type|design-reviewer
agents/issue-orchestrator.md|├── Spawn Coder Agent|coder
agents/issue-orchestrator.md|├── Spawn FRESH Code Review Agent|adversarial-reviewer
agents/issue-orchestrator.md|**Coder Agent spawn template|coder
agents/issue-orchestrator.md|**Adversarial Reviewer spawn template|adversarial-reviewer
agents/issue-orchestrator.md|Spawn a NEW adversarial reviewer (role type|adversarial-reviewer
agents/issue-orchestrator.md|# 19. Spawn Knowledge Curator|knowledge-curator-agent
skills/start/agents/issue-orchestrator.md|— persistent across research phase|researcher
skills/start/agents/issue-orchestrator.md|— persistent across planning phase|planner
skills/start/agents/issue-orchestrator.md|— **persistent across work units**|coder
skills/start/agents/issue-orchestrator.md|— persistent through PR lifecycle|pr-shepherd-agent
skills/start/agents/issue-orchestrator.md|Adversarial reviewers are ALWAYS fresh `Task()`|adversarial-reviewer
skills/start/agents/issue-orchestrator.md|# 5. Spawn Researcher Agent|researcher
skills/start/agents/issue-orchestrator.md|# 7. Spawn Architect Agent|planner
skills/start/agents/issue-orchestrator.md|ALL must PASS under the severity rule|plan-reviewer
skills/start/agents/issue-orchestrator.md|UX Reviewer, CTO; role type|design-reviewer
skills/start/agents/issue-orchestrator.md|├── Spawn Coder Agent|coder
skills/start/agents/issue-orchestrator.md|├── Spawn FRESH Code Review Agent|adversarial-reviewer
skills/start/agents/issue-orchestrator.md|**Coder Agent spawn template|coder
skills/start/agents/issue-orchestrator.md|**Adversarial Reviewer spawn template|adversarial-reviewer
skills/start/agents/issue-orchestrator.md|Spawn a NEW adversarial reviewer (role type|adversarial-reviewer
skills/start/agents/issue-orchestrator.md|# 19. Spawn Knowledge Curator|knowledge-curator-agent
skills/orchestrated-execution/SKILL.md|a fresh `Task()` per work unit|coder
skills/orchestrated-execution/SKILL.md|**Phase 3 (ADVERSARIAL REVIEW)**: ALWAYS a fresh|adversarial-reviewer
skills/plan-review-gate/SKILL.md|2. Spawn 3 adversarial reviewers in PARALLEL|plan-reviewer
skills/plan-review-gate/SKILL.md|c. Spawn 3 NEW reviewer instances|plan-reviewer
skills/plan-review-gate/SKILL.md|4. Spawn 3 entirely new|plan-reviewer
skills/design-review-gate/SKILL.md|1. Spawn all six agents in parallel|design-reviewer
skills/orchestrated-execution/SKILL.md|**Subagent spawn template|coder
skills/orchestrated-execution/SKILL.md|**Reviewer spawn template|adversarial-reviewer
skills/orchestrated-execution/SKILL.md|Fan-out implementations|coder
skills/orchestrated-execution/SKILL.md|Fan-out reviews|adversarial-reviewer
skills/orchestrated-execution/SKILL.md|- [ ] Spawn coding subagent|coder
skills/orchestrated-execution/SKILL.md|- [ ] Spawn **fresh** adversarial reviewer|adversarial-reviewer
skills/start/SKILL.md|spawn **fresh** reviewer (role type|adversarial-reviewer
agents/swarm-coordinator-agent.md|5. Spawn Issue Orchestrator (role type|issue-orchestrator
skills/start/agents/swarm-coordinator-agent.md|5. Spawn Issue Orchestrator (role type|issue-orchestrator
guides/agent-coordination.md|Spawn reviewers as named teammates|design-reviewer
guides/agent-coordination.md|2. Spawn specialists:|pr-shepherd-agent
skills/pr-shepherd/SKILL.md|When spawning an agent to work in a worktree|coder
skills/external-tools/SKILL.md|Claude implements via Task()|coder
skills/external-tools/SKILL.md|Claude (via Task) reviewers are spawned as|adversarial-reviewer
guides/worktree-development.md|3. **Launch agents in parallel**|coder
guides/worktree-development.md|launch layer N+1 agents|coder'
while IFS='|' read -r f anchor role; do
  if [ ! -f "$f" ]; then fail "$f missing"; continue; fi
  ln="$(grep -n -F -- "$anchor" "$f" | head -1 | cut -d: -f1 || true)"
  if [ -z "$ln" ]; then fail "$f: anchor not found: $anchor"; continue; fi
  # the role type must be on the anchor line itself (not merely somewhere in the section)
  section="$(sed -n "${ln}p" "$f")"
  if echo "$section" | grep -q -F "roleType(\"$role\")"; then pass "$f names roleType(\"$role\") on the line of: $anchor"; else fail "$f: roleType(\"$role\") missing on the anchor line: $anchor"; fi
done <<< "$SITES"

# 3a. Each Task({ block's role type is the CORRECT one for that spawn (keyed by description).
# A block whose description is not listed here fails, so new spawns must declare their role.
EXPECT='Research for issue #123|researcher
Implement feature X in worktree|coder
PM review|design-reviewer
Architect review|design-reviewer
Designer review|design-reviewer
Security design review|design-reviewer
UX review|design-reviewer
CTO review|design-reviewer
Feasibility review|plan-reviewer
Completeness review|plan-reviewer
Scope & Alignment review|plan-reviewer
Issue Orchestrator for #123|issue-orchestrator
Planning for issue #123|planner
Code review for #123|adversarial-reviewer
Security audit for #123|adversarial-reviewer
Extract learnings from epic|knowledge-curator-agent'
WRONG=""
while IFS= read -r f; do
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    blk="$(sed -n "${ln},$((ln + 6))p" "$f")"
    desc="$(echo "$blk" | sed -n 's/.*description:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    got="$(echo "$blk" | sed -n 's/.*subagent_type:[[:space:]]*roleType("\([a-z0-9-]*\)").*/\1/p' | head -1)"
    want="$(echo "$EXPECT" | awk -F'|' -v d="$desc" '$1==d {print $2; exit}')"
    if [ -z "$want" ]; then WRONG="$WRONG
$f:$ln Task block '$desc' has no expected role in the test (add it to EXPECT)"
    elif [ "$got" != "$want" ]; then WRONG="$WRONG
$f:$ln '$desc' uses roleType(\"$got\"), expected roleType(\"$want\")"; fi
  done < <(grep -n -F 'Task({' "$f" | cut -d: -f1)
done <<< "$SCOPE"
if [ -z "$WRONG" ]; then pass "every Task({ block uses the correct role type for its spawn"; else fail "wrong or undeclared role types:$WRONG"; fi

# 3b. Every roleType("x") anywhere in scope names an active (non-deprecated) agent
BADROLE=""
while IFS= read -r f; do
  for r in $(grep -o -E 'roleType\("[^"]*"\)' "$f" | sed -E 's/roleType\("([^"]*)"\)/\1/' | sort -u); do
    [ "$r" = "<role>" ] && continue
    a="agents/$r.md"
    if [ ! -f "$a" ] || grep -q -E '^description:.*DEPRECATED' "$a"; then BADROLE="$BADROLE
$f: roleType(\"$r\")"; fi
  done
done <<< "$SCOPE"
if [ -z "$BADROLE" ]; then pass "every roleType() names an active agent"; else fail "roleType() names a missing or deprecated agent:$BADROLE"; fi

# 3c. Role-type manifest: per file, how many times each roleType("x") appears must match
# tests/agents/role-type-manifest.txt exactly. Dropping, swapping or adding a role type anywhere
# fails until the manifest is deliberately regenerated:  bash tests/agents/test-no-general-purpose.sh --write-manifest
MANIFEST="tests/agents/role-type-manifest.txt"
current_manifest() {
  while IFS= read -r f; do
    { grep -o -E 'roleType\("[a-z0-9-]+"\)' "$f" 2>/dev/null || true; } | sed -E 's/roleType\("([^"]*)"\)/\1/' | sort | uniq -c | awk -v f="$f" '{print f "|" $2 "|" $1}'
  done <<< "$SCOPE" | LC_ALL=C sort
}
if [ "${1:-}" = "--write-manifest" ]; then current_manifest > "$MANIFEST"; echo "wrote $MANIFEST"; exit 0; fi
if [ -f "$MANIFEST" ] && [ "$(current_manifest)" = "$(LC_ALL=C sort "$MANIFEST")" ]; then
  pass "role-type manifest matches (no role type dropped, swapped or added)"
else
  fail "role-type manifest mismatch (< manifest, > current):
$(diff <(LC_ALL=C sort "$MANIFEST" 2>/dev/null) <(current_manifest) | grep '^[<>]' || true)"
fi

# 5. No built-in Plan subagent type/agent for planning (whole scope, case-insensitive)
PLAN=""
while IFS= read -r f; do
  hits="$(sed -E 's/[Pp]lanner|[Pp]lan[- ][Rr]eview(er)?s?//g' "$f" | grep -n -i -E 'subagent_type["'"'"']?[[:space:]]*[:=]?[[:space:]]*["'"'"']?Plan["'"'"']?([^a-z-]|$)|`?\bPlan`? ((sub)?agent|type)|built-in .?Plan' 2>/dev/null || true)"
  [ -n "$hits" ] && PLAN="$PLAN
$f: $hits"
done <<< "$SCOPE"
if [ -z "$PLAN" ]; then pass "no instruction to use the built-in Plan type/agent"; else fail "built-in Plan type/agent referenced:$PLAN"; fi

# 6. Guide: Role type resolution + roster table
G=guides/agent-coordination.md
grep -q -x '## Role type resolution' "$G" && pass "$G defines Role type resolution" || fail "$G missing Role type resolution"
RULE='> **Role type resolution**: use `metaswarm-<role>` if `.claude/agents/metaswarm-<role>.md` exists, otherwise `metaswarm:<role>`.'
SECTION="$(awk '/^## Role type resolution$/{on=1; next} on && /^## /{exit} on{print}' "$G")"
echo "$SECTION" | grep -q -x -F -- "$RULE" && pass "$G has the exact resolution rule line inside its section" || fail "$G: exact rule line missing from the Role type resolution section"
[ "$(grep -c -F -- 'metaswarm-<role>` if' "$G")" = 1 ] && pass "$G states the rule exactly once" || fail "$G states the rule more than once or not at all"
echo "$SECTION" | grep -q -i 'degrades to the plugin defaults' && pass "$G says missing the rule degrades to plugin defaults" || fail "$G missing degrade-to-defaults statement"
echo "$SECTION" | grep -q -F 'Adversarial reviewers are always fresh `Task()` instances in both modes, using the `adversarial-reviewer` type.' && pass "$G says adversarial reviewers are always fresh Task() instances" || fail "$G missing fresh adversarial-reviewer statement"
echo "$SECTION" | grep -q -i 'Team Mode teammates use the same role types' && pass "$G says Team Mode teammates use role types" || fail "$G missing Team Mode role-type statement"
# Roster model column must equal the agent's frontmatter model
roster_model() { awk -F'|' -v r="$1" '{ k=$2; gsub(/[ `]/,"",k) } k==r { m=$4; gsub(/[ `]/,"",m); print m }' "$G" | sort -u | paste -sd, -; }
fm_model() { awk 'NR==1{ if ($0!="---") exit; next } /^---[[:space:]]*$/ { exit } /^model:/ { sub(/^model:[[:space:]]*/,""); print; exit }' "agents/$1.md"; }
for role in design-reviewer plan-reviewer researcher planner coder adversarial-reviewer pr-shepherd-agent knowledge-curator-agent issue-orchestrator swarm-coordinator-agent; do
  rm_="$(roster_model "$role")"; fm_="$(fm_model "$role")"
  if [ -n "$fm_" ] && [ "$rm_" = "$fm_" ]; then pass "roster model for $role matches frontmatter ($fm_)"; else fail "roster model for $role ('$rm_') != frontmatter ('$fm_')"; fi
done
ROWS="$(echo "$SECTION" | awk -F'|' '/^\| `/ { k=$2; gsub(/[ `]/,"",k); print k }')"
BADROW=""; for r in $ROWS; do { [ -f "agents/$r.md" ] && ! grep -q '^description:.*DEPRECATED' "agents/$r.md"; } || BADROW="$BADROW $r"; done
[ -z "$BADROW" ] && pass "every roster row names an active agent" || fail "roster rows for missing/deprecated agents:$BADROW"
for role in design-reviewer plan-reviewer researcher planner coder adversarial-reviewer pr-shepherd-agent knowledge-curator-agent issue-orchestrator swarm-coordinator-agent; do
  grep -q -E "^\| \`?$role\`? \|" "$G" && pass "$G roster lists $role" || fail "$G roster missing $role"
done

# 7. Every markdown link to agent-coordination.md resolves (file and heading anchor) from the linking file
BADLINK=""
anchor_ok() { # file anchor -> heading exists (GitHub slug)
  awk '/^#+ /{ h=$0; sub(/^#+ /,"",h); h=tolower(h); gsub(/[^a-z0-9 -]/,"",h); gsub(/ /,"-",h); print h }' "$1" | grep -q -x -F -- "$2"; }
while IFS= read -r f; do
  for l in $(grep -o -E '\]\([^)]*agent-coordination\.md[^)]*\)' "$f" | sed -E 's/^\]\(//; s/\)$//' || true); do
    case "$l" in http*) continue ;; esac
    case "$f" in templates/*|CLAUDE.md|AGENTS.md|GEMINI.md) BADLINK="$BADLINK
$f -> $l (user-installed file must not link into plugin guides/)"; continue ;; esac
    path="${l%%#*}"; anc=""; case "$l" in *#*) anc="${l#*#}" ;; esac
    t="$(dirname "$f")/$path"
    if [ ! -f "$t" ]; then BADLINK="$BADLINK
$f -> $l (missing file)"; continue; fi
    if [ -n "$anc" ] && ! anchor_ok "$t" "$anc"; then BADLINK="$BADLINK
$f -> $l (missing anchor)"; fi
  done
done <<< "$SCOPE"
if [ -z "$BADLINK" ]; then pass "all links to agent-coordination.md resolve (file and anchor)"; else fail "broken links:$BADLINK"; fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
