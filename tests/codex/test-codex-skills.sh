#!/usr/bin/env bash
# tests/codex/test-codex-skills.sh
# Validate Codex CLI skill structure and install script

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Codex CLI Skills Tests"
echo "======================"
echo ""

# 1. Install script exists and is executable
if [ -f "$ROOT/.codex/install.sh" ]; then
  pass ".codex/install.sh exists"
  if [ -x "$ROOT/.codex/install.sh" ]; then
    pass ".codex/install.sh is executable"
  else
    fail ".codex/install.sh is not executable"
  fi
else
  fail ".codex/install.sh not found"
fi

# 2. Install script has proper shebang
if head -1 "$ROOT/.codex/install.sh" | grep -q '^#!/usr/bin/env bash'; then
  pass "install.sh has proper shebang"
else
  fail "install.sh missing proper shebang"
fi

# 3. AGENTS.md exists at repo root
if [ -f "$ROOT/AGENTS.md" ]; then
  pass "AGENTS.md exists at repo root"
else
  fail "AGENTS.md not found at repo root"
fi

# 4. AGENTS.md references metaswarm
if grep -q "metaswarm" "$ROOT/AGENTS.md" 2>/dev/null; then
  pass "AGENTS.md references metaswarm"
else
  fail "AGENTS.md does not reference metaswarm"
fi

# 5. All skills have SKILL.md with YAML frontmatter
for skill_dir in "$ROOT/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"

  if [ -f "$skill_md" ]; then
    pass "skills/$skill_name/SKILL.md exists"
    # Check for YAML frontmatter (starts with ---)
    if head -1 "$skill_md" | grep -q '^---'; then
      pass "skills/$skill_name/SKILL.md has YAML frontmatter"
    else
      fail "skills/$skill_name/SKILL.md missing YAML frontmatter"
    fi
  else
    fail "skills/$skill_name/SKILL.md not found"
  fi
done

# 6. README exists
if [ -f "$ROOT/.codex/README.md" ]; then
  pass ".codex/README.md exists"
  if grep -q "metaswarm" "$ROOT/.codex/README.md"; then
    pass ".codex/README.md references metaswarm"
  else
    fail ".codex/README.md does not reference metaswarm"
  fi
else
  fail ".codex/README.md not found"
fi

# 7. Template files exist
for tmpl in AGENTS.md AGENTS-append.md; do
  if [ -f "$ROOT/templates/$tmpl" ]; then
    pass "templates/$tmpl exists"
  else
    fail "templates/$tmpl not found"
  fi
done

# 8. Symlink creation dry run
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for skill_dir in "$ROOT/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="metaswarm-$(basename "$skill_dir")"
  ln -sf "$skill_dir" "$TMP_DIR/$skill_name"
done

linked=$(ls -1 "$TMP_DIR" | wc -l | tr -d ' ')
if [ "$linked" -gt 0 ]; then
  pass "Symlink dry run: $linked skills linked successfully"
else
  fail "Symlink dry run: no skills linked"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
