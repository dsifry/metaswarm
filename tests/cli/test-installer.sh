#!/usr/bin/env bash
# tests/cli/test-installer.sh
# Validate cross-platform installer and platform detection

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Cross-Platform Installer Tests"
echo "=============================="
echo ""

# 1. CLI entry point exists
if [ -f "$ROOT/cli/metaswarm.js" ]; then
  pass "cli/metaswarm.js exists"
else
  fail "cli/metaswarm.js not found"
fi

# 2. Platform detection module exists
if [ -f "$ROOT/lib/platform-detect.js" ]; then
  pass "lib/platform-detect.js exists"
else
  fail "lib/platform-detect.js not found"
fi

# 3. Platform detection runs without error
if node "$ROOT/lib/platform-detect.js" >/dev/null 2>&1; then
  pass "platform-detect.js runs successfully"
else
  fail "platform-detect.js failed to run"
fi

# 4. Platform detection returns valid JSON-like output
detect_output=$(node "$ROOT/lib/platform-detect.js" 2>&1)
if echo "$detect_output" | grep -q "Claude Code\|Codex CLI\|Gemini CLI"; then
  pass "platform-detect.js detects known platforms"
else
  fail "platform-detect.js output doesn't mention known platforms"
fi

# 5. CLI help works
if node "$ROOT/cli/metaswarm.js" --help 2>&1 | grep -q "metaswarm"; then
  pass "metaswarm --help works"
else
  fail "metaswarm --help failed"
fi

# 6. CLI version works
pkg_ver=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ROOT/package.json','utf-8')).version)")
cli_ver=$(node "$ROOT/cli/metaswarm.js" --version 2>&1)
if [ "$pkg_ver" = "$cli_ver" ]; then
  pass "CLI version ($cli_ver) matches package.json ($pkg_ver)"
else
  fail "CLI version ($cli_ver) != package.json ($pkg_ver)"
fi

# 7. CLI detect command works
if node "$ROOT/cli/metaswarm.js" detect 2>&1 | grep -q "platform detection"; then
  pass "metaswarm detect runs"
else
  fail "metaswarm detect failed"
fi

# 8. Project setup dry run (in temp dir)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"
git init -q .

# Run setup for claude platform
node "$ROOT/cli/metaswarm.js" setup --claude 2>&1 | grep -q "setup complete" && \
  pass "metaswarm setup --claude works" || \
  fail "metaswarm setup --claude failed"

# Check files were created
if [ -f "$TMP_DIR/CLAUDE.md" ]; then
  pass "setup created CLAUDE.md"
else
  fail "setup did not create CLAUDE.md"
fi

if [ -f "$TMP_DIR/.coverage-thresholds.json" ]; then
  pass "setup created .coverage-thresholds.json"
else
  fail "setup did not create .coverage-thresholds.json"
fi

# 9. Version sync across manifests
versions_match=true
first_ver=""

for manifest in "$ROOT/package.json" "$ROOT/.claude-plugin/plugin.json" "$ROOT/gemini-extension.json"; do
  if [ -f "$manifest" ]; then
    ver=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$manifest','utf-8')).version)")
    if [ -n "$first_ver" ] && [ "$ver" != "$first_ver" ]; then
      versions_match=false
    fi
    first_ver="${first_ver:-$ver}"
  fi
done

if [ "$versions_match" = true ]; then
  pass "All manifests have matching versions ($first_ver)"
else
  fail "Manifest versions are out of sync"
fi

# 10. sync-resources.js --check passes
cd "$ROOT"
if node "$ROOT/lib/sync-resources.js" --check 2>&1 | grep -q "in sync"; then
  pass "sync-resources.js --check passes"
else
  fail "sync-resources.js --check found issues"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
