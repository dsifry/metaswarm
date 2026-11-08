#!/usr/bin/env bash
# tests/agents/test-agent-frontmatter.sh
# Validate agent frontmatter, phase roster, deprecation stubs, and old-name references

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Print the frontmatter block (between the first two --- lines); empty if none.
frontmatter() {
  [ -f "$1" ] || return 0
  awk 'NR==1 { if ($0 != "---") exit; next } /^---[[:space:]]*$/ { exit } { print }' "$1"
}
fm_value() { # file key
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'
}
fm_has_key() { frontmatter "$1" | grep -q "^$2:"; }

# Roster: type|model|disallowedTools ("-" means no disallowedTools)
RO="Write, Edit, NotebookEdit"
ROSTER="design-reviewer|opus|$RO
plan-reviewer|opus|$RO
researcher|sonnet|$RO
planner|opus|-
coder|sonnet|-
adversarial-reviewer|opus|$RO
pr-shepherd-agent|sonnet|-
knowledge-curator-agent|sonnet|-
issue-orchestrator|inherit|-
swarm-coordinator-agent|inherit|-"
# Removed in 0.14.0 (deprecated in 0.13.0): old name|successor
REMOVED="coder-agent|coder
researcher-agent|researcher
code-review-agent|adversarial-reviewer"

echo ""
echo "Agent Frontmatter Tests"
echo "======================="
echo ""

# 1. Required keys, name == stem
for dir in agents skills/start/agents; do
  for f in "$dir"/*.md; do
    stem="$(basename "$f" .md)"
    if [ "$(head -1 "$f")" != "---" ]; then fail "$f missing frontmatter"; continue; fi
    ok=1
    for k in name description model; do
      fm_has_key "$f" "$k" || { fail "$f missing $k"; ok=0; }
    done
    [ "$(fm_value "$f" name)" = "$stem" ] || { fail "$f name != $stem"; ok=0; }
    [ "$ok" = 1 ] && pass "$f frontmatter valid"
  done
done

# 2. Copies identical (both directions: same file set, same frontmatter)
for stem in $( { ls agents/*.md skills/start/agents/*.md; } | xargs -n1 basename | sort -u ); do
  f="agents/$stem"
  g="skills/start/agents/$stem"
  if [ ! -f "$f" ]; then fail "$f missing (exists only in skills/start/agents/)"; continue; fi
  if [ ! -f "$g" ]; then fail "$g missing"; continue; fi
  if [ "$(frontmatter "$f")" = "$(frontmatter "$g")" ] && [ -n "$(frontmatter "$f")" ]; then
    pass "$stem frontmatter identical in both copies"
  else
    fail "$stem frontmatter differs between agents/ and skills/start/agents/"
  fi
done

# 3. Roster model and disallowedTools
while IFS='|' read -r type model dis; do
  for dir in agents skills/start/agents; do
    f="$dir/$type.md"
    [ -f "$f" ] || { fail "$f missing"; continue; }
    [ "$(fm_value "$f" model)" = "$model" ] && pass "$f model=$model" || fail "$f model != $model"
    got="$(fm_value "$f" disallowedTools)"
    want="$dis"; [ "$dis" = "-" ] && want=""
    [ "$got" = "$want" ] && pass "$f disallowedTools='$want'" || fail "$f disallowedTools '$got' != '$want'"
  done
done <<< "$ROSTER"

# 4. Other personas inherit (both directories)
for f in agents/*.md skills/start/agents/*.md; do
  stem="$(basename "$f" .md)"
  echo "$ROSTER" | cut -d'|' -f1 | grep -qx "$stem" && continue
  [ "$(fm_value "$f" model)" = "inherit" ] && pass "$stem persona inherits" || fail "$stem persona should be model: inherit"
done

# 5. No tools: allowlist
for f in agents/*.md skills/start/agents/*.md; do
  if fm_has_key "$f" tools; then fail "$f declares tools:"; else pass "$f has no tools:"; fi
done

# 6. Deprecated stubs removed in 0.14.0 (both directories)
while IFS='|' read -r old new; do
  for dir in agents skills/start/agents; do
    [ -e "$dir/$old.md" ] && fail "$dir/$old.md should be removed (use $new)" || pass "$dir/$old.md removed"
  done
done <<< "$REMOVED"

# 7. Old-name references
STUB_RE='coder-agent|researcher-agent|code-review-agent'
FILES="$( { git ls-files; git ls-files --others --exclude-standard; } | sort -u )"
BAD=""
while IFS= read -r p; do
  [ -f "$p" ] || continue
  case "$p" in
    agents/coder-agent.md|agents/researcher-agent.md|agents/code-review-agent.md) continue ;;
    skills/start/agents/coder-agent.md|skills/start/agents/researcher-agent.md|skills/start/agents/code-review-agent.md) continue ;;
    CHANGELOG.md|docs/plans/*|tests/*|bin/metaswarm-usage|skills/setup/bin/metaswarm-usage) continue ;;
  esac
  if grep -Iq -E "$STUB_RE" "$p" 2>/dev/null; then BAD="$BAD $p"; fi
done <<< "$FILES"
if [ -z "$BAD" ]; then pass "no stale references to deprecated agent names"; else fail "stale references in:$BAD"; fi

# 8. No stale agent counts (pre-0.13.0 counts were 18/19)
# Scans tracked and untracked (non-ignored) files, case-insensitively.
TOTAL=$(ls agents/*.md | wc -l | tr -d ' ')
ACTIVE=$TOTAL
COUNT_FILES="$( { git ls-files; git ls-files --others --exclude-standard; } | sort -u | grep -v -E '^(CHANGELOG\.md|docs/plans/|tests/|\.playwright-mcp/|\.agents/|\.beads/)' )"
STALE=""; WRONG=""
while IFS= read -r p; do
  [ -f "$p" ] || continue
  hits="$(grep -n -I -i -E '(^|[^0-9.])1[89] ((ai|specialized|specialist) )?(agent|specialized)' "$p" 2>/dev/null || true)"
  [ -n "$hits" ] && STALE="$STALE
$p: $hits"
  # No "(+N deprecated)" agent counts remain after 0.14.0 (the stubs are gone)
  bad="$(grep -o -I -i -E '\(\+[0-9]+ deprecated\)' "$p" 2>/dev/null || true)"
  [ -n "$bad" ] && WRONG="$WRONG
$p: $bad"
done <<< "$COUNT_FILES"
if [ -z "$STALE" ]; then pass "no stale 18/19 agent counts"; else fail "stale agent counts:$STALE"; fi
if [ -z "$WRONG" ]; then pass "no (+N deprecated) agent counts remain"; else fail "stale (+N deprecated) agent counts:$WRONG"; fi

# 9. Roster agents run in the user's project (not the plugin dir): plugin-file references must be
#    resolvable there. Each such agent carries the locator line, references only files that exist in
#    the plugin, and never points at legacy .claude/rubrics/ paths.
LOC='**Plugin files:**'
for dir in agents skills/start/agents; do
  for r in design-reviewer plan-reviewer planner adversarial-reviewer; do
    f="$dir/$r.md"
    grep -q -F -- "$LOC" "$f" && pass "$f has plugin-file locator" || fail "$f missing plugin-file locator ('$LOC')"
    grep -q '\.claude/rubrics/' "$f" && fail "$f references legacy .claude/rubrics/" || pass "$f has no legacy .claude/rubrics/ refs"
    for ref in $(grep -o -E '`(agents|rubrics)/[a-z0-9-]+\.md`' "$f" | tr -d '`' | sort -u); do
      [ -f "$ref" ] && pass "$f -> $ref exists in plugin" || fail "$f -> $ref missing in plugin"
    done
  done
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
