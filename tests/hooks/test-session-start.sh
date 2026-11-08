#!/usr/bin/env bash
# tests/hooks/test-session-start.sh
# Unit tests for session-start.sh hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../hooks/session-start.sh"
PASS=0
FAIL=0
TOTAL=0

assert_json_valid() {
  local desc="$1"
  local output="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{JSON.parse(d);process.exit(0)})" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — output was not valid JSON"
    echo "  Output: $output"
  fi
}

assert_contains() {
  local desc="$1"
  local output="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected to contain: $expected"
  fi
}

assert_not_contains() {
  local desc="$1"
  local output="$2"
  local unexpected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — should NOT contain: $unexpected"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

assert_file_exists() {
  local desc="$1"
  local file="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$file" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected file: $file"
  fi
}

assert_file_not_exists() {
  local desc="$1"
  local file="$2"
  TOTAL=$((TOTAL + 1))
  if [ -e "$file" ]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — should NOT exist: $file"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

# --- Test setup ---
TMPDIR_BASE=$(mktemp -d)
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "$TMPDIR_BASE"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

echo "Running session-start.sh tests..."
echo ""

# --- Test 1: New project (no .metaswarm/project-profile.json) ---
echo "Test 1: New project detection"
TEST_CWD="$TMPDIR_BASE/test1"
mkdir -p "$TEST_CWD"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains Claude setup nudge" "$output" '/setup'

# --- Test 1b: Codex new project uses Codex skill names ---
echo "Test 1b: Codex new project command names"
TEST_CWD="$TMPDIR_BASE/test1b"
mkdir -p "$TEST_CWD"
output=$(cd "$TEST_CWD" && PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains Codex setup nudge" "$output" '$setup'
assert_contains "Contains Codex start nudge" "$output" '$start'

# --- Test 1c: Gemini new project uses Gemini command names ---
echo "Test 1c: Gemini new project command names"
TEST_CWD="$TMPDIR_BASE/test1c"
mkdir -p "$TEST_CWD"
output=$(cd "$TEST_CWD" && extensionPath="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains Gemini setup nudge" "$output" '/metaswarm:setup'
assert_contains "Contains Gemini start nudge" "$output" '/metaswarm:start-task'

# --- Test 2: Configured project (has .metaswarm/project-profile.json) ---
echo "Test 2: Configured project"
TEST_CWD="$TMPDIR_BASE/test2"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_not_contains "No setup nudge" "$output" '/setup'

# --- Test 2b: Codex self-heal writes Codex files only ---
echo "Test 2b: Codex self-heal is platform-aware"
TEST_CWD="$TMPDIR_BASE/test2b"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin","coverage":{"threshold":93},"commands":{"coverage":"npm test -- --coverage"}}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_file_exists "Creates AGENTS.md" "$TEST_CWD/AGENTS.md"
assert_file_exists "Creates coverage thresholds" "$TEST_CWD/.coverage-thresholds.json"
assert_file_not_exists "Does not create Claude shims" "$TEST_CWD/.claude/commands/start-task.md"

# --- Test 2c: Claude self-heal still writes Claude command shims ---
echo "Test 2c: Claude self-heal keeps Claude support"
TEST_CWD="$TMPDIR_BASE/test2c"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin","coverage":{"threshold":88},"commands":{"coverage":"npm test -- --coverage"}}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_file_exists "Creates CLAUDE.md" "$TEST_CWD/CLAUDE.md"
assert_file_exists "Creates Claude command shims" "$TEST_CWD/.claude/commands/start-task.md"
assert_file_exists "Creates coverage thresholds" "$TEST_CWD/.coverage-thresholds.json"

# --- Test 3: Legacy install detection ---
echo "Test 3: Legacy install detection"
TEST_CWD="$TMPDIR_BASE/test3"
mkdir -p "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin"
echo '{"name":"metaswarm","version":"0.8.0"}' > "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin/plugin.json"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"npm"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains Claude migrate message" "$output" '/migrate'

# --- Test 4: BEADS dedup detection ---
echo "Test 4: BEADS dedup detection"
TEST_CWD="$TMPDIR_BASE/test4"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Simulate a BEADS plugin in the cache
MOCK_CACHE="$TMPDIR_BASE/.claude/plugins/cache/beads-marketplace/beads/1.0.0/.claude-plugin"
mkdir -p "$MOCK_CACHE"
echo '{"name":"beads","version":"1.0.0"}' > "$MOCK_CACHE/plugin.json"
output=$(cd "$TEST_CWD" && HOME="$TMPDIR_BASE" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"

# --- Test 4b: BEADS dedup skips bd prime when standalone beads is installed ---
echo "Test 4b: BEADS dedup skips bd prime when standalone plugin detected"
TEST_CWD="$TMPDIR_BASE/test4b"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Reuse MOCK_CACHE from test 4 (beads plugin present)
# Create a mock bd that outputs a sentinel value
MOCK_BIN_4B="$TMPDIR_BASE/mock-bin-4b"
mkdir -p "$MOCK_BIN_4B"
cat > "$MOCK_BIN_4B/bd" << 'MOCKBD'
#!/bin/bash
echo "BEADS_PRIME_SENTINEL_SHOULD_NOT_APPEAR"
MOCKBD
chmod +x "$MOCK_BIN_4B/bd"
output=$(cd "$TEST_CWD" && HOME="$TMPDIR_BASE" PATH="$MOCK_BIN_4B:$PATH" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_not_contains "bd prime NOT called when standalone beads detected" "$output" "BEADS_PRIME_SENTINEL_SHOULD_NOT_APPEAR"

# --- Test 4c: bd prime IS called when standalone beads is NOT installed ---
echo "Test 4c: bd prime IS called when standalone beads is NOT detected"
TEST_CWD="$TMPDIR_BASE/test4c"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Use an empty HOME with no beads plugin cache
EMPTY_HOME="$TMPDIR_BASE/empty-home"
mkdir -p "$EMPTY_HOME"
MOCK_BIN_4C="$TMPDIR_BASE/mock-bin-4c"
mkdir -p "$MOCK_BIN_4C"
cat > "$MOCK_BIN_4C/bd" << 'MOCKBD'
#!/bin/bash
echo "BEADS_PRIME_SENTINEL_SHOULD_APPEAR"
MOCKBD
chmod +x "$MOCK_BIN_4C/bd"
output=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" PATH="$MOCK_BIN_4C:$PATH" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "bd prime IS called when no standalone beads" "$output" "BEADS_PRIME_SENTINEL_SHOULD_APPEAR"

# --- Test 5: Multi-line bd prime output produces valid JSON ---
echo "Test 5: Multi-line content produces valid JSON"
TEST_CWD="$TMPDIR_BASE/test5"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
# Create a mock bd that outputs multi-line content
MOCK_BIN="$TMPDIR_BASE/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/bd" << 'MOCKBD'
#!/bin/bash
echo "Line 1 with \"quotes\""
echo "Line 2 with backslash \\"
echo "Line 3 with tabs	here"
MOCKBD
chmod +x "$MOCK_BIN/bd"
output=$(cd "$TEST_CWD" && PATH="$MOCK_BIN:$PATH" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Multi-line output produces valid JSON" "$output"

# --- Test 6: Idempotency (run twice, same output) ---
echo "Test 6: Idempotency"
TEST_CWD="$TMPDIR_BASE/test6"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output1=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
output2=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
TOTAL=$((TOTAL + 1))
if [ "$output1" = "$output2" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: Same output on repeated runs"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Output differs between runs"
fi

# --- Test 7: Stale generated agent files ---
echo "Test 7: Stale generated agents line"
PLUGIN_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/.claude-plugin/plugin.json" | head -1)
write_agent() { # dir, version
  mkdir -p "$1/.claude/agents"
  printf -- '---\nname: metaswarm-coder\n---\n<!-- generated-by: metaswarm v%s sha256:abc — edit .metaswarm/models.yaml, not this file -->\nbody\n' "$2" > "$1/.claude/agents/metaswarm-coder.md"
}
TEST_CWD="$TMPDIR_BASE/test7a"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
write_agent "$TEST_CWD" "0.0.1"
output=$(cd "$TEST_CWD" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Stale: output is valid JSON" "$output"
assert_contains "Stale: warns in additionalContext" "$output" 'metaswarm agents are stale — run /update'
TOTAL=$((TOTAL + 1))
if echo "$output" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{process.exit(JSON.parse(d).hookSpecificOutput.additionalContext.includes('metaswarm agents are stale — run /update')?0:1)})" 2>/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: Stale line is inside additionalContext"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: Stale line is not inside additionalContext"
fi

TEST_CWD="$TMPDIR_BASE/test7b"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
write_agent "$TEST_CWD" "$PLUGIN_VERSION"
output=$(cd "$TEST_CWD" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Current: output is valid JSON" "$output"
assert_not_contains "Current: no stale line when versions match" "$output" 'agents are stale'

TEST_CWD="$TMPDIR_BASE/test7c"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_not_contains "None: no stale line without generated files" "$output" 'agents are stale'

# --- Test 8: metaswarm knowledge base surfaced in both setups (#70) ---
echo "Test 8: Knowledge base summary + /prime pointer"
ctx() { # extract additionalContext from hook JSON on stdin
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{process.stdout.write(JSON.parse(d).hookSpecificOutput.additionalContext)})"
}
mk_store() { # <cwd>: configured project with a knowledge store; facts on stdin
  mkdir -p "$1/.metaswarm" "$1/.beads/knowledge"
  echo '{"distribution":"plugin"}' > "$1/.metaswarm/project-profile.json"
  cat > "$1/.beads/knowledge/gotchas.jsonl"
}
fact() { # <id> <type> <fact> [recommendation]
  node -e 'const [id,type,fact,rec]=process.argv.slice(1);const o={id,type,fact};if(rec)o.recommendation=rec;console.log(JSON.stringify(o))' "$@"
}
MOCK_BIN_8="$TMPDIR_BASE/mock-bin-8"
mkdir -p "$MOCK_BIN_8"
printf '#!/bin/bash\necho "BEADS_PRIME_SENTINEL_8"\n' > "$MOCK_BIN_8/bd"; chmod +x "$MOCK_BIN_8/bd"

KB_FACTS=$(
  echo '# comment line, ignored'
  fact must-1 pattern 'NEVER use "as any" casts \ they hide bugs'
  fact must-2 gotcha 'Truthy checks drop zero values' 'ALWAYS compare with !== undefined'
  fact must-3 decision 'Every migration MUST be reversible'
  fact plain-1 pattern 'Use mock factories for test data'
  fact plain-2 gotcha 'never mind lowercase never, this is not a rule'
  echo '{ this line is not valid json'
)

# 8a: without the beads plugin — knowledge AND bd prime both appear.
TEST_CWD="$TMPDIR_BASE/test8a"
printf '%s\n' "$KB_FACTS" | mk_store "$TEST_CWD"
output=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" PATH="$MOCK_BIN_8:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "8a: output is valid JSON" "$output"
c8a=$(printf '%s' "$output" | ctx)
assert_contains "8a: NEVER rule surfaced" "$c8a" 'NEVER use "as any" casts \ they hide bugs'
assert_contains "8a: ALWAYS in recommendation surfaced" "$c8a" 'ALWAYS compare with !== undefined'
assert_contains "8a: MUST rule surfaced" "$c8a" 'Every migration MUST be reversible'
assert_not_contains "8a: non-rule fact not inlined" "$c8a" 'Use mock factories'
assert_not_contains "8a: lowercase never is not a rule" "$c8a" 'never mind lowercase'
assert_contains "8a: pointer counts remaining valid facts" "$c8a" '2 more facts in .beads/knowledge/'
assert_contains "8a: pointer names /prime" "$c8a" '/prime <topic>'
assert_contains "8a: bd prime still runs without the plugin" "$c8a" 'BEADS_PRIME_SENTINEL_8'

# 8b: with the beads plugin — knowledge still appears, bd prime skipped.
TEST_CWD="$TMPDIR_BASE/test8b"
printf '%s\n' "$KB_FACTS" | mk_store "$TEST_CWD"
output=$(cd "$TEST_CWD" && HOME="$TMPDIR_BASE" PATH="$MOCK_BIN_8:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "8b: output is valid JSON" "$output"
c8b=$(printf '%s' "$output" | ctx)
assert_contains "8b: MUST rule surfaced with beads plugin" "$c8b" 'Every migration MUST be reversible'
assert_contains "8b: pointer surfaced with beads plugin" "$c8b" '2 more facts in .beads/knowledge/'
assert_not_contains "8b: bd prime still skipped with the plugin" "$c8b" 'BEADS_PRIME_SENTINEL_8'

# 8c: count cap — at most 10 rules inlined.
TEST_CWD="$TMPDIR_BASE/test8c"
i=1; facts8c=""
while [ "$i" -le 15 ]; do facts8c="$facts8c$(fact "m$i" pattern "Rule $i: NEVER do thing number $i")"$'\n'; i=$((i + 1)); done
printf '%s' "$facts8c" | mk_store "$TEST_CWD"
c8c=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
n8c=$(printf '%s\n' "$c8c" | grep -c 'NEVER do thing number' || true)
TOTAL=$((TOTAL + 1))
if [ "$n8c" -eq 10 ]; then PASS=$((PASS + 1)); echo "  PASS: 8c: count cap inlines 10 rules"; else FAIL=$((FAIL + 1)); echo "  FAIL: 8c: count cap inlines 10 rules (got $n8c)"; fi
assert_contains "8c: pointer counts the rest" "$c8c" '5 more facts in .beads/knowledge/'

# 8d: byte cap — long rules stop before the knowledge section passes ~2 KB.
TEST_CWD="$TMPDIR_BASE/test8d"
long=$(printf 'x%.0s' $(seq 1 600)); facts8d=""
i=1; while [ "$i" -le 6 ]; do facts8d="$facts8d$(fact "L$i" pattern "LONG$i NEVER $long")"$'\n'; i=$((i + 1)); done
printf '%s' "$facts8d" | mk_store "$TEST_CWD"
c8d=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
n8d=$(printf '%s\n' "$c8d" | grep -c 'LONG[0-9] NEVER' || true)
b8d=$(printf '%s' "$c8d" | wc -c | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [ "$n8d" -ge 1 ] && [ "$n8d" -le 3 ] && [ "$b8d" -le 2600 ]; then PASS=$((PASS + 1)); echo "  PASS: 8d: byte cap bounds the section ($n8d rules, $b8d bytes)"; else FAIL=$((FAIL + 1)); echo "  FAIL: 8d: byte cap bounds the section ($n8d rules, $b8d bytes)"; fi
assert_contains "8d: pointer counts the facts left out" "$c8d" "$((6 - n8d)) more facts in .beads/knowledge/"

# 8e: no rules in the store — pointer only, with the total.
TEST_CWD="$TMPDIR_BASE/test8e"
{ fact p1 pattern 'Use mock factories'; fact p2 gotcha 'Prisma findMany returns []'; } | mk_store "$TEST_CWD"
c8e=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
assert_contains "8e: pointer with total when no rules" "$c8e" '2 facts in .beads/knowledge/'
assert_not_contains "8e: no rules header when none" "$c8e" 'MUST FOLLOW'

# 8f: broken jq — falls back to the pointer, hook output stays valid.
TEST_CWD="$TMPDIR_BASE/test8f"
printf '%s\n' "$KB_FACTS" | mk_store "$TEST_CWD"
MOCK_BIN_8F="$TMPDIR_BASE/mock-bin-8f"; mkdir -p "$MOCK_BIN_8F"
printf '#!/bin/bash\nexit 3\n' > "$MOCK_BIN_8F/jq"; chmod +x "$MOCK_BIN_8F/jq"
output=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" PATH="$MOCK_BIN_8F:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "8f: output is valid JSON without working jq" "$output"
c8f=$(printf '%s' "$output" | ctx)
assert_contains "8f: pointer without jq" "$c8f" 'facts in .beads/knowledge/'
assert_contains "8f: pointer names /prime without jq" "$c8f" '/prime <topic>'
assert_not_contains "8f: no rules inlined without jq" "$c8f" 'Every migration MUST be reversible'

# 8g: empty or missing store — no knowledge line.
TEST_CWD="$TMPDIR_BASE/test8g"
echo '# only a comment' | mk_store "$TEST_CWD"
c8g=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
assert_not_contains "8g: comment-only store adds nothing" "$c8g" '.beads/knowledge/'
TEST_CWD="$TMPDIR_BASE/test8h"
mkdir -p "$TEST_CWD/.metaswarm"; echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
c8h=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
assert_not_contains "8h: missing store adds nothing" "$c8h" '.beads/knowledge/'

# 8i: platform command names in the pointer.
TEST_CWD="$TMPDIR_BASE/test8i"
printf '%s\n' "$KB_FACTS" | mk_store "$TEST_CWD"
c8i=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" extensionPath="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
assert_contains "8i: Gemini pointer uses /metaswarm:prime" "$c8i" '/metaswarm:prime <topic>'
c8j=$(cd "$TEST_CWD" && HOME="$EMPTY_HOME" PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null | ctx || true)
assert_contains "8j: Codex pointer uses \$start" "$c8j" '$start'

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
DONE=1
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
