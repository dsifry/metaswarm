#!/usr/bin/env bash
# tests/opencode/test-opencode-discovery.sh
# Validate OpenCode integration: command files, skill discovery, platform detection.
#
# OpenCode auto-discovers SKILL.md from .claude/skills/, .agents/skills/, and
# .opencode/skills/ — so metaswarm doesn't need a separate install path. We do
# need to generate .opencode/commands/*.md (markdown commands with frontmatter)
# from the same source that generates Gemini TOML.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "OpenCode Integration Tests"
echo "=========================="
echo ""

# 1. Project-level OpenCode directory exists
if [ -d "$ROOT/.opencode" ]; then
  pass ".opencode/ exists"
else
  fail ".opencode/ not found"
fi

# 2. .opencode/README.md exists and references metaswarm
if [ -f "$ROOT/.opencode/README.md" ]; then
  pass ".opencode/README.md exists"
  if grep -qi "metaswarm" "$ROOT/.opencode/README.md"; then
    pass ".opencode/README.md references metaswarm"
  else
    fail ".opencode/README.md does not reference metaswarm"
  fi
else
  fail ".opencode/README.md not found"
fi

# 3. .opencode/commands/ directory exists with at least one command
if [ -d "$ROOT/.opencode/commands" ]; then
  pass ".opencode/commands/ exists"
  cmd_count=$(find "$ROOT/.opencode/commands" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  if [ "$cmd_count" -ge 12 ]; then
    pass ".opencode/commands/ has $cmd_count command files (>= 12 expected)"
  else
    fail ".opencode/commands/ has only $cmd_count command files (>= 12 expected)"
  fi
else
  fail ".opencode/commands/ not found"
fi

# 4. Commands have valid YAML frontmatter with description field
for cmd_file in "$ROOT/.opencode/commands"/*.md; do
  [ -f "$cmd_file" ] || continue
  cmd_name=$(basename "$cmd_file" .md)
  # README.md documents the directory itself; it is not a slash command.
  [ "$cmd_name" = "README" ] && continue
  if head -1 "$cmd_file" | grep -q '^---$'; then
    fence_count=$(head -10 "$cmd_file" | grep -c '^---$' || true)
    if [ "$fence_count" -ge 2 ]; then
      if head -10 "$cmd_file" | grep -q '^description:'; then
        pass ".opencode/commands/$cmd_name.md has valid frontmatter with description"
      else
        fail ".opencode/commands/$cmd_name.md frontmatter missing description"
      fi
    else
      fail ".opencode/commands/$cmd_name.md frontmatter not closed"
    fi
  else
    fail ".opencode/commands/$cmd_name.md missing YAML frontmatter"
  fi
done

# 5. Commands use OpenCode's $ARGUMENTS placeholder (not Gemini's {{args}})
for cmd_file in "$ROOT/.opencode/commands"/*.md; do
  [ -f "$cmd_file" ] || continue
  cmd_name=$(basename "$cmd_file" .md)
  [ "$cmd_name" = "README" ] && continue
  if grep -q '{{args}}' "$cmd_file"; then
    fail ".opencode/commands/$cmd_name.md contains Gemini-style {{args}} (should be \$ARGUMENTS)"
  fi
done

# 6. AGENTS.md exists at root (shared with Codex; OpenCode reads it too)
if [ -f "$ROOT/AGENTS.md" ]; then
  pass "AGENTS.md exists at root (read by both Codex and OpenCode)"
else
  fail "AGENTS.md not found at root"
fi

# 7. AGENTS.md mentions OpenCode (so OpenCode users know the project supports them)
if grep -qi "opencode" "$ROOT/AGENTS.md"; then
  pass "AGENTS.md mentions OpenCode"
else
  fail "AGENTS.md does not mention OpenCode"
fi

# 8. All skills have SKILL.md with valid frontmatter (same standard OpenCode reads)
#    OpenCode requires: name regex ^[a-z0-9]+(-[a-z0-9]+)*$ and 1-1024 char description
for skill_dir in "$ROOT/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"

  if [ ! -f "$skill_md" ]; then
    fail "skills/$skill_name/SKILL.md not found"
    continue
  fi

  # name field present
  declared_name=$(awk '/^name:/{print $2; exit}' "$skill_md" | tr -d '"' | tr -d "'")
  if [ -z "$declared_name" ]; then
    fail "skills/$skill_name/SKILL.md missing name field"
    continue
  fi

  # name matches OpenCode regex
  if echo "$declared_name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    :
  else
    fail "skills/$skill_name/SKILL.md name '$declared_name' does not match OpenCode regex ^[a-z0-9]+(-[a-z0-9]+)*$"
    continue
  fi

  # description present and within length
  desc=$(awk '/^description:/{sub(/^description:[ ]*/, ""); print; exit}' "$skill_md" | tr -d '"')
  if [ -z "$desc" ]; then
    fail "skills/$skill_name/SKILL.md missing description"
    continue
  fi
  desc_len=${#desc}
  if [ "$desc_len" -lt 1 ] || [ "$desc_len" -gt 1024 ]; then
    fail "skills/$skill_name/SKILL.md description length $desc_len outside 1-1024"
    continue
  fi

  pass "skills/$skill_name OpenCode-compatible (name='$declared_name', desc=$desc_len chars)"
done

# 9. lib/platform-detect.js detects OpenCode
detect_output=$(node "$ROOT/lib/platform-detect.js" 2>&1)
if echo "$detect_output" | grep -qi "opencode"; then
  pass "platform-detect.js mentions OpenCode"
else
  fail "platform-detect.js does not mention OpenCode"
fi

# 10. cli/metaswarm.js help mentions --opencode
if node "$ROOT/cli/metaswarm.js" --help 2>&1 | grep -q -- "--opencode"; then
  pass "metaswarm --help documents --opencode flag"
else
  fail "metaswarm --help does not document --opencode flag"
fi

# 11. metaswarm setup --opencode runs in a temp dir and writes AGENTS.md
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"
git init -q .

if node "$ROOT/cli/metaswarm.js" setup --opencode 2>&1 | grep -q "setup complete"; then
  pass "metaswarm setup --opencode completes"
else
  fail "metaswarm setup --opencode failed"
fi

if [ -f "$TMP_DIR/AGENTS.md" ]; then
  pass "setup --opencode created AGENTS.md (shared with Codex)"
else
  fail "setup --opencode did not create AGENTS.md"
fi

cd "$ROOT"

# 12. sync-resources.js --check still passes (commands are kept in sync)
if node "$ROOT/lib/sync-resources.js" --check 2>&1 | grep -q "in sync"; then
  pass "sync-resources.js --check still passes"
else
  fail "sync-resources.js --check found issues"
fi

# 13. docs/README.opencode.md is no longer the stub
if [ -f "$ROOT/docs/README.opencode.md" ]; then
  line_count=$(wc -l < "$ROOT/docs/README.opencode.md" | tr -d ' ')
  if [ "$line_count" -gt 5 ]; then
    pass "docs/README.opencode.md has real content ($line_count lines)"
  else
    fail "docs/README.opencode.md is still a stub ($line_count lines)"
  fi
else
  fail "docs/README.opencode.md not found"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
