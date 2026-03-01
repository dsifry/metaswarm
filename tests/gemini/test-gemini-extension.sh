#!/usr/bin/env bash
# tests/gemini/test-gemini-extension.sh
# Validate Gemini CLI extension structure and content

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Gemini CLI Extension Tests"
echo "=========================="
echo ""

# 1. gemini-extension.json exists and is valid JSON
if [ -f "$ROOT/gemini-extension.json" ]; then
  if node -e "JSON.parse(require('fs').readFileSync('$ROOT/gemini-extension.json','utf-8'))" 2>/dev/null; then
    pass "gemini-extension.json is valid JSON"
  else
    fail "gemini-extension.json is not valid JSON"
  fi
else
  fail "gemini-extension.json not found"
fi

# 2. gemini-extension.json has required fields
if [ -f "$ROOT/gemini-extension.json" ]; then
  for field in name version description contextFileName; do
    if node -e "const j=JSON.parse(require('fs').readFileSync('$ROOT/gemini-extension.json','utf-8'));if(!j.$field)process.exit(1)" 2>/dev/null; then
      pass "gemini-extension.json has '$field'"
    else
      fail "gemini-extension.json missing '$field'"
    fi
  done
fi

# 3. GEMINI.md exists at repo root
if [ -f "$ROOT/GEMINI.md" ]; then
  pass "GEMINI.md exists at repo root"
else
  fail "GEMINI.md not found at repo root"
fi

# 4. GEMINI.md references metaswarm
if grep -q "metaswarm" "$ROOT/GEMINI.md" 2>/dev/null; then
  pass "GEMINI.md references metaswarm"
else
  fail "GEMINI.md does not reference metaswarm"
fi

# 5. TOML commands exist
TOML_DIR="$ROOT/commands/metaswarm"
expected_commands=(
  start-task prime review-design self-reflect pr-shepherd brainstorm
  setup update status handle-pr-comments create-issue external-tools-health
)

for cmd in "${expected_commands[@]}"; do
  if [ -f "$TOML_DIR/$cmd.toml" ]; then
    pass "commands/metaswarm/$cmd.toml exists"
  else
    fail "commands/metaswarm/$cmd.toml not found"
  fi
done

# 6. TOML files have required fields (description and prompt)
for toml_file in "$TOML_DIR"/*.toml; do
  [ -f "$toml_file" ] || continue
  name=$(basename "$toml_file")
  if grep -q '^description' "$toml_file" && grep -q '^prompt' "$toml_file"; then
    pass "$name has description and prompt"
  else
    fail "$name missing description or prompt"
  fi
done

# 7. Version in gemini-extension.json matches package.json
if [ -f "$ROOT/gemini-extension.json" ] && [ -f "$ROOT/package.json" ]; then
  gem_ver=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ROOT/gemini-extension.json','utf-8')).version)")
  pkg_ver=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ROOT/package.json','utf-8')).version)")
  if [ "$gem_ver" = "$pkg_ver" ]; then
    pass "Version sync: gemini-extension.json ($gem_ver) == package.json ($pkg_ver)"
  else
    fail "Version mismatch: gemini-extension.json ($gem_ver) != package.json ($pkg_ver)"
  fi
fi

# 8. Template files exist
for tmpl in GEMINI.md GEMINI-append.md; do
  if [ -f "$ROOT/templates/$tmpl" ]; then
    pass "templates/$tmpl exists"
  else
    fail "templates/$tmpl not found"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
