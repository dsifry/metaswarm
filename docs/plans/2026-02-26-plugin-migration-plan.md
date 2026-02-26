# Plugin Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate metaswarm from npm package distribution to Claude Code plugin with marketplace support, zero Node.js install dependency, and automatic updates.

**Architecture:** Hub-and-spoke plugin with co-located resources. The repo root becomes the plugin root (`.claude-plugin/plugin.json`). Skills reference companion files via `./` relative paths. A sync-resources build script keeps co-located copies in sync with authoritative top-level sources.

**Tech Stack:** Shell (bash), Node.js (build scripts only), Markdown (skills/commands), JSON (plugin manifests)

**Design Document:** `docs/plans/2026-02-26-plugin-migration-design.md` (APPROVED — 5/5 agents, 3 iterations)

---

## Phase 1: Plugin Infrastructure

### Task 1: Create plugin.json manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

> Note: The old `.claude/plugins/metaswarm/.claude-plugin/plugin.json` is deleted later in Task 18 (cleanup).

**Step 1: Create the plugin manifest**

```json
{
  "name": "metaswarm",
  "version": "1.0.0",
  "description": "Multi-agent orchestration framework for Claude Code — 18 agents, 9-phase workflow, quality gates, TDD enforcement",
  "author": {
    "name": "David Sifry",
    "email": "david@sifry.com"
  },
  "homepage": "https://github.com/dsifry/metaswarm",
  "repository": "https://github.com/dsifry/metaswarm",
  "license": "MIT",
  "keywords": ["orchestration", "agents", "tdd", "quality-gates", "beads"]
}
```

Write to `.claude-plugin/plugin.json`.

**Step 2: Verify the manifest is valid JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json','utf-8')); console.log('valid')"`
Expected: `valid`

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add plugin.json manifest at repo root"
```

---

### Task 2: Create hooks infrastructure

**Files:**
- Create: `hooks/hooks.json`

**Step 1: Create hooks.json**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": false
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": false
          }
        ]
      }
    ]
  }
}
```

Write to `hooks/hooks.json`.

**Step 2: Verify valid JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('hooks/hooks.json','utf-8')); console.log('valid')"`
Expected: `valid`

**Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: add hooks.json for SessionStart and PreCompact hooks"
```

---

### Task 3: Write session-start.sh hook (TDD)

**Files:**
- Create: `hooks/session-start.sh`
- Create: `tests/hooks/test-session-start.sh`

The session-start.sh implements 4-phase detection:
1. BEADS dedup check
2. New project detection
3. Legacy install detection
4. Knowledge priming

**Step 1: Write the test script**

```bash
#!/usr/bin/env bash
# tests/hooks/test-session-start.sh
# Unit tests for session-start.sh hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# --- Test setup ---
TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

echo "Running session-start.sh tests..."
echo ""

# --- Test 1: New project (no .metaswarm/project-profile.json) ---
echo "Test 1: New project detection"
TEST_CWD="$TMPDIR_BASE/test1"
mkdir -p "$TEST_CWD"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains setup nudge" "$output" "metaswarm:setup"

# --- Test 2: Configured project (has .metaswarm/project-profile.json) ---
echo "Test 2: Configured project"
TEST_CWD="$TMPDIR_BASE/test2"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"plugin"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_not_contains "No setup nudge" "$output" "metaswarm:setup"

# --- Test 3: Legacy install detection ---
echo "Test 3: Legacy install detection"
TEST_CWD="$TMPDIR_BASE/test3"
mkdir -p "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin"
echo '{"name":"metaswarm","version":"0.8.0"}' > "$TEST_CWD/.claude/plugins/metaswarm/.claude-plugin/plugin.json"
mkdir -p "$TEST_CWD/.metaswarm"
echo '{"distribution":"npm"}' > "$TEST_CWD/.metaswarm/project-profile.json"
output=$(cd "$TEST_CWD" && bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_json_valid "Output is valid JSON" "$output"
assert_contains "Contains migrate message" "$output" "metaswarm:migrate"

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
# When BEADS is installed, metaswarm should skip its own bd prime
assert_not_contains "No bd prime when BEADS installed" "$output" "bd prime"

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

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
```

Write to `tests/hooks/test-session-start.sh` and `chmod +x`.

**Step 2: Run the test to verify it fails**

Run: `bash tests/hooks/test-session-start.sh`
Expected: FAIL (session-start.sh doesn't exist yet)

**Step 3: Write the session-start.sh implementation**

```bash
#!/usr/bin/env bash
# hooks/session-start.sh
# SessionStart + PreCompact hook for metaswarm plugin
# Outputs JSON with hookSpecificOutput.additionalContext

set -euo pipefail

# --- Phase 1: BEADS dedup check ---
# If standalone BEADS plugin is installed, skip knowledge priming (let BEADS handle it)
beads_standalone=false
beads_plugin_cache="${HOME}/.claude/plugins/cache"
if [ -d "$beads_plugin_cache" ]; then
  # Look for a BEADS plugin with name "beads" in plugin.json
  while IFS= read -r -d '' pjson; do
    if command -v jq >/dev/null 2>&1; then
      pname=$(jq -r '.name // empty' "$pjson" 2>/dev/null || true)
    elif command -v node >/dev/null 2>&1; then
      pname=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('$pjson','utf-8')).name||'')}catch{console.log('')}" 2>/dev/null || true)
    else
      # Neither jq nor node available — skip dedup check (safe default: allow both to prime)
      pname=""
    fi
    if [ "$pname" = "beads" ]; then
      beads_standalone=true
      break
    fi
  done < <(find "$beads_plugin_cache" -path "*/.claude-plugin/plugin.json" -print0 2>/dev/null || true)
fi

# --- Phase 2: New project detection ---
new_project=false
if [ ! -f ".metaswarm/project-profile.json" ]; then
  new_project=true
fi

# --- Phase 3: Legacy install detection ---
legacy_install=false
if [ -f ".claude/plugins/metaswarm/.claude-plugin/plugin.json" ]; then
  legacy_install=true
fi

# --- Phase 4: Build context message ---
context_parts=()

if [ "$new_project" = true ]; then
  context_parts+=("Metaswarm is installed but this project hasn't been set up yet. Run \`/metaswarm:setup\` to configure it, or \`/metaswarm:start-task\` to begin working.")
fi

if [ "$legacy_install" = true ]; then
  context_parts+=("This project has metaswarm installed via the old npm method. Run \`/metaswarm:migrate\` to switch to the marketplace plugin for automatic updates.")
fi

# Knowledge priming (only if project is set up and BEADS isn't separately priming)
if [ "$new_project" = false ] && [ "$beads_standalone" = false ]; then
  if command -v bd >/dev/null 2>&1; then
    bd_output=$(bd prime 2>/dev/null || true)
    if [ -n "$bd_output" ]; then
      context_parts+=("$bd_output")
    fi
  fi
fi

# --- Build and output JSON ---
# Use node for JSON escaping (works on macOS Bash 3.2 where bash parameter
# expansion with $'\n' is unreliable). Node is available on most systems and
# is already a soft dependency for the BEADS dedup check above.
if [ ${#context_parts[@]} -gt 0 ]; then
  # Join parts with double newline
  joined=""
  for part in "${context_parts[@]}"; do
    if [ -n "$joined" ]; then
      joined="${joined}

${part}"
    else
      joined="$part"
    fi
  done

  if command -v node >/dev/null 2>&1; then
    # Use node for reliable JSON escaping of arbitrary content
    escaped=$(printf '%s' "$joined" | node -e "let d='';process.stdin.on('data',c=>d+=c.toString());process.stdin.on('end',()=>process.stdout.write(JSON.stringify(d)))")
    # escaped includes surrounding quotes from JSON.stringify — strip them
    escaped="${escaped:1:${#escaped}-2}"
  else
    # Fallback: basic escaping via sed (covers \, ", newlines, tabs)
    escaped=$(printf '%s' "$joined" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' '\036' | sed 's/\036/\\n/g')
  fi

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${escaped}"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ""
  }
}
EOF
fi

exit 0
```

Write to `hooks/session-start.sh` and `chmod +x`.

**Step 4: Run the tests to verify they pass**

Run: `bash tests/hooks/test-session-start.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add hooks/session-start.sh tests/hooks/test-session-start.sh
git commit -m "feat: add session-start.sh hook with BEADS dedup, new project, and legacy detection"
```

---

## Phase 2: Repository Restructuring

### Task 4: Create skills/start/ (rename from beads/)

Move the main orchestration skill from the current split layout (`ORCHESTRATION.md` + `agents/`) into the unified `skills/start/` directory.

**Files:**
- Create: `skills/start/SKILL.md` (copy from `ORCHESTRATION.md`, update frontmatter + internal refs)
- Move: `agents/*.md` → `skills/start/agents/*.md`

**Step 1: Create skills/start/ directory and copy agents**

```bash
mkdir -p skills/start/agents
cp agents/*.md skills/start/agents/
```

**Step 2: Copy ORCHESTRATION.md to skills/start/SKILL.md**

```bash
cp ORCHESTRATION.md skills/start/SKILL.md
```

**Step 3: Update the YAML frontmatter in skills/start/SKILL.md**

Change the frontmatter from:
```yaml
---
name: beads-orchestration
description: Multi-agent orchestration for GitHub Issues using BEADS task tracking
auto_activate: true
triggers:
  - "work on issue"
  - "start issue"
  - "@beads"
  - "agent-ready label"
---
```

To:
```yaml
---
name: start
description: Use when starting work on any task, when the user mentions metaswarm, or when the user wants to begin tracked development work
auto_activate: true
triggers:
  - "work on issue"
  - "start issue"
  - "start task"
  - "use metaswarm"
  - "@metaswarm"
  - "agent-ready label"
---
```

**Step 4: Create references/ directory with tool mapping stubs**

Per the design, `skills/start/references/` holds per-CLI tool mappings for future multi-CLI support:

```bash
mkdir -p skills/start/references
```

Create `skills/start/references/codex-tools.md`:
```markdown
# Codex CLI Tool Mapping (Future)
This file maps Claude Code tool names to Codex CLI equivalents.
Implementation deferred — see design doc for details.
```

Create similar stubs for `opencode-tools.md` and `cursor-tools.md`.

**Step 5: Create future spoke directory stubs**

The design shows placeholder directories for future CLI integrations:

```bash
mkdir -p .cursor-plugin .codex .opencode
echo "# Future: Cursor integration" > .cursor-plugin/README.md
echo "# Future: Codex CLI integration" > .codex/README.md
echo "# Future: OpenCode integration" > .opencode/README.md
mkdir -p docs
echo "# Codex CLI Integration (Future)" > docs/README.codex.md
echo "# OpenCode Integration (Future)" > docs/README.opencode.md
```

**Step 6: Remove original ORCHESTRATION.md (now lives at skills/start/SKILL.md)**

Replace ORCHESTRATION.md with a redirect pointer:

```markdown
# ORCHESTRATION.md has moved

This file is now at `skills/start/SKILL.md` (the main metaswarm orchestration skill).

If you installed metaswarm via the plugin system, this file loads automatically.
If you're reading this in an npm-installed project, the content is at `.claude/plugins/metaswarm/skills/beads/SKILL.md`.
```

**Step 7: Verify the file structure**

Run: `ls skills/start/SKILL.md skills/start/agents/*.md skills/start/references/*.md | head -25`
Expected: SKILL.md, 18 agent files, and 3 reference stubs listed

**Step 8: Commit**

```bash
git add skills/start/ .cursor-plugin/ .codex/ .opencode/ docs/README.codex.md docs/README.opencode.md ORCHESTRATION.md
git commit -m "feat: create skills/start/ with SKILL.md, agents, references, and future spoke stubs"
```

> **Note on `.beads/`**: The project-local `.beads/` directory in user projects is NOT renamed or modified by this migration. It remains `.beads/` with subdirectories `knowledge/`, `plans/`, `context/`. All 55+ references to `.beads/` in skills and commands remain valid. Only the skill directory name changes (`skills/beads/` → `skills/start/`).

---

### Task 5: Co-locate rubrics into skill directories

Copy rubrics into the skill directories that reference them. The top-level `rubrics/` stays as the authoritative source.

**Files:**
- Create: `skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md`
- Create: `skills/orchestrated-execution/rubrics/adversarial-review-rubric.md`
- Create: `skills/external-tools/rubrics/external-tool-review-rubric.md`

**Step 1: Copy rubrics to co-located directories**

```bash
mkdir -p skills/plan-review-gate/rubrics
cp rubrics/plan-review-rubric-adversarial.md skills/plan-review-gate/rubrics/

mkdir -p skills/orchestrated-execution/rubrics
cp rubrics/adversarial-review-rubric.md skills/orchestrated-execution/rubrics/

mkdir -p skills/external-tools/rubrics
cp rubrics/external-tool-review-rubric.md skills/external-tools/rubrics/
```

**Step 2: Verify co-located rubrics exist and match authoritative copies**

Run: `diff rubrics/plan-review-rubric-adversarial.md skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md && echo "match" || echo "MISMATCH"`
Expected: `match`

Run the same for the other two rubrics.

**Step 3: Commit**

```bash
git add skills/plan-review-gate/rubrics/ skills/orchestrated-execution/rubrics/ skills/external-tools/rubrics/
git commit -m "feat: co-locate rubrics into skill directories that reference them"
```

---

### Task 6: Co-locate guides into skill directories

Copy `agent-coordination.md` into the 4 skill directories that reference it.

**Files:**
- Create: `skills/orchestrated-execution/guides/agent-coordination.md`
- Create: `skills/design-review-gate/guides/agent-coordination.md`
- Create: `skills/pr-shepherd/guides/agent-coordination.md`
- Create: `skills/start/guides/agent-coordination.md`

**Step 1: Copy guide to co-located directories**

```bash
mkdir -p skills/orchestrated-execution/guides
cp guides/agent-coordination.md skills/orchestrated-execution/guides/

mkdir -p skills/design-review-gate/guides
cp guides/agent-coordination.md skills/design-review-gate/guides/

mkdir -p skills/pr-shepherd/guides
cp guides/agent-coordination.md skills/pr-shepherd/guides/

mkdir -p skills/start/guides
cp guides/agent-coordination.md skills/start/guides/
```

**Step 2: Verify all copies match**

Run: `for d in skills/orchestrated-execution skills/design-review-gate skills/pr-shepherd skills/start; do diff guides/agent-coordination.md "$d/guides/agent-coordination.md" && echo "$d: match" || echo "$d: MISMATCH"; done`
Expected: All `match`

**Step 3: Commit**

```bash
git add skills/orchestrated-execution/guides/ skills/design-review-gate/guides/ skills/pr-shepherd/guides/ skills/start/guides/
git commit -m "feat: co-locate agent-coordination.md into skill directories that reference it"
```

---

### Task 7: Co-locate templates, knowledge, bin, scripts into skills/setup/

The setup skill needs all scaffolding resources accessible via `./` relative paths.

**Files:**
- Create: `skills/setup/templates/` (copy all from `templates/`)
- Create: `skills/setup/knowledge/` (copy all from `knowledge/`)
- Create: `skills/setup/bin/` (copy all from `bin/`)
- Create: `skills/setup/scripts/` (copy all from `scripts/`)

**Step 1: Copy resources into skills/setup/**

```bash
mkdir -p skills/setup/templates skills/setup/knowledge skills/setup/bin skills/setup/scripts

# Use rsync to include dotfiles (cp templates/* misses .env.example)
rsync -a templates/ skills/setup/templates/
rsync -a knowledge/ skills/setup/knowledge/
rsync -a bin/ skills/setup/bin/
rsync -a scripts/ skills/setup/scripts/
```

**Step 2: Verify file counts match**

Run: `echo "templates: $(ls -A templates/ | wc -l) vs $(ls -A skills/setup/templates/ | wc -l)"; echo "knowledge: $(ls -A knowledge/ | wc -l) vs $(ls -A skills/setup/knowledge/ | wc -l)"; echo "bin: $(ls -A bin/ | wc -l) vs $(ls -A skills/setup/bin/ | wc -l)"; echo "scripts: $(ls -A scripts/ | wc -l) vs $(ls -A skills/setup/scripts/ | wc -l)"`
Expected: Counts match for each pair

**Step 3: Commit**

```bash
git add skills/setup/
git commit -m "feat: co-locate templates, knowledge, bin, scripts into skills/setup/"
```

---

## Phase 3: Path Reference Updates

### Task 8: Update path references in all SKILL.md files

Update every hardcoded path in SKILL.md files to use `./` relative paths.

**Files:**
- Modify: `skills/plan-review-gate/SKILL.md` (4 references)
- Modify: `skills/orchestrated-execution/SKILL.md` (2 references)
- Modify: `skills/external-tools/SKILL.md` (1 reference)
- Modify: `skills/design-review-gate/SKILL.md` (1 reference)
- Modify: `skills/pr-shepherd/SKILL.md` (1 reference)
- Modify: `skills/create-issue/SKILL.md` (1 reference)
- Modify: `skills/handling-pr-comments/SKILL.md` (1 reference)

**Step 1: Update plan-review-gate/SKILL.md**

Replace all occurrences of:
- `.claude/rubrics/plan-review-rubric-adversarial.md` → `./rubrics/plan-review-rubric-adversarial.md`
- `.claude/rubrics/plan-review-rubric.md` → `./rubrics/plan-review-rubric.md` (if referenced as info)

4 replacements needed.

**Step 2: Update orchestrated-execution/SKILL.md**

Replace:
- `.claude/rubrics/adversarial-review-rubric.md` → `./rubrics/adversarial-review-rubric.md`
- `guides/agent-coordination.md` → `./guides/agent-coordination.md`

**Step 3: Update external-tools/SKILL.md**

Replace:
- `.claude/rubrics/external-tool-review-rubric.md` → `./rubrics/external-tool-review-rubric.md`

**Step 4: Update design-review-gate/SKILL.md**

Replace:
- `guides/agent-coordination.md` → `./guides/agent-coordination.md`

**Step 5: Update pr-shepherd/SKILL.md**

Replace:
- `guides/agent-coordination.md` → `./guides/agent-coordination.md`

**Step 6: Update create-issue/SKILL.md**

Replace:
- `.claude/commands/handle-pr-comments.md` → the `/metaswarm:handle-pr-comments` command reference (since commands are now plugin-namespaced, reference the command by name, not file path)

**Step 7: Update handling-pr-comments/SKILL.md**

Replace:
- `.claude/commands/handle-pr-comments.md` → reference the `/metaswarm:handle-pr-comments` command by name

**Step 8: Verify no old paths remain in skills**

Run: `grep -rn '\.claude/rubrics/\|\.claude/guides/\|\.claude/commands/' skills/*/SKILL.md || echo "clean"`
Expected: `clean`

**Step 9: Commit**

```bash
git add skills/*/SKILL.md
git commit -m "fix: update all SKILL.md path references to use relative paths"
```

---

### Task 9: Update path references in agent definitions

Update every hardcoded path in `skills/start/agents/*.md` files.

**Files:**
- Modify: `skills/start/agents/swarm-coordinator-agent.md` (1 reference)
- Modify: `skills/start/agents/security-auditor-agent.md` (1 reference)
- Modify: `skills/start/agents/issue-orchestrator.md` (2 references)
- Modify: `skills/start/agents/pr-shepherd-agent.md` (1 reference)
- Modify: `skills/start/agents/cto-agent.md` (1 reference)
- Modify: `skills/start/agents/code-review-agent.md` (4 references)
- Modify: `skills/start/agents/coder-agent.md` (1 reference — phantom typescript-patterns.md)

**Step 1: Update agent references**

For agents that reference rubrics, update to co-located paths relative to the start skill's base directory:
- `.claude/rubrics/security-review-rubric.md` → `./agents/../rubrics/security-review-rubric.md`

**Important note**: Agent definitions are loaded by Claude from the `skills/start/` base directory. However, agent `.md` files are under `skills/start/agents/`. When Claude reads an agent file, it resolves `./` relative to the skill base dir (`skills/start/`), not the agents subdirectory. So references should be relative to `skills/start/`:

For agents referencing rubrics, the agents need the rubrics co-located. We have two options:
- Option A: Co-locate rubrics under `skills/start/rubrics/` (since agents are part of the start skill)
- Option B: Update agent refs to point to the co-located rubric paths in other skills

**Option A is cleaner** — co-locate all agent-referenced rubrics under `skills/start/rubrics/`:

```bash
mkdir -p skills/start/rubrics
cp rubrics/security-review-rubric.md skills/start/rubrics/
cp rubrics/adversarial-review-rubric.md skills/start/rubrics/
cp rubrics/plan-review-rubric.md skills/start/rubrics/
cp rubrics/code-review-rubric.md skills/start/rubrics/
```

Then update agent references:
- `swarm-coordinator-agent.md`: `guides/agent-coordination.md` → `./guides/agent-coordination.md`
- `security-auditor-agent.md`: `.claude/rubrics/security-review-rubric.md` → `./rubrics/security-review-rubric.md`
- `issue-orchestrator.md`: `guides/agent-coordination.md` → `./guides/agent-coordination.md`, `.claude/rubrics/adversarial-review-rubric.md` → `./rubrics/adversarial-review-rubric.md`
- `pr-shepherd-agent.md`: `.claude/plugins/your-project/skills/pr-shepherd/SKILL.md` → reference via skill invocation (not path)
- `cto-agent.md`: `.claude/rubrics/plan-review-rubric.md` → `./rubrics/plan-review-rubric.md`
- `code-review-agent.md`: `.claude/rubrics/code-review-rubric.md` → `./rubrics/code-review-rubric.md`, `.claude/rubrics/adversarial-review-rubric.md` → `./rubrics/adversarial-review-rubric.md`

**Step 2: Fix phantom typescript-patterns.md (Design item #2/#15)**

`coder-agent.md` line 317 references `.claude/guides/typescript-patterns.md` which does not exist. Also referenced in `architecture-rubric.md`, `security-review-rubric.md`, `code-review-rubric.md`.

Search for all references:
Run: `grep -rn 'typescript-patterns' skills/ rubrics/ agents/`

For each reference, remove the broken reference line or replace with a note: "Follow TypeScript strict mode conventions as defined in the project's tsconfig.json and ESLint configuration."

**Step 3: Verify no old paths remain in agents**

Run: `grep -rn '\.claude/rubrics/\|\.claude/guides/\|\.claude/plugins/' skills/start/agents/*.md || echo "clean"`
Expected: `clean`

**Step 4: Commit**

```bash
git add skills/start/agents/ skills/start/rubrics/
git commit -m "fix: update all agent definition path references to relative paths"
```

---

### Task 10: Update skills/start/SKILL.md (formerly ORCHESTRATION.md) references

The main orchestration SKILL.md has many internal path references that need updating.

**Files:**
- Modify: `skills/start/SKILL.md`

**Step 1: Update all references**

Key replacements in `skills/start/SKILL.md`:
- `agents/` directory reference → `./agents/`
- `guides/agent-coordination.md` → `./guides/agent-coordination.md`
- `skills/plan-review-gate/SKILL.md` → reference via skill invocation
- `skills/external-tools/SKILL.md` → reference via skill invocation
- `skills/visual-review/SKILL.md` → reference via skill invocation
- `.claude/plugins/your-project/skills/beads/agents/issue-orchestrator.md` → `./agents/issue-orchestrator.md`
- `.claude/plugins/your-project/skills/beads/` → `./` (current skill directory)
- `.claude/plugins/your-project/skills/orchestrated-execution/` → reference via skill invocation
- `.claude/plugins/your-project/skills/design-review-gate/` → reference via skill invocation
- `.claude/plugins/your-project/skills/brainstorming-extension/` → reference via skill invocation
- `.claude/plugins/your-project/skills/plan-review-gate/` → reference via skill invocation
- `.claude/plugins/your-project/skills/external-tools/` → reference via skill invocation
- `.claude/plugins/your-project/skills/visual-review/` → reference via skill invocation
- `.claude/commands/` → reference via command names `/metaswarm:command-name`
- `.claude/rubrics/` → `./rubrics/` (since we co-located them in Task 9)
- `guides/` (in the directory listing section) → update to reflect plugin structure

**Step 2: Update the file tree diagram**

The SKILL.md contains a directory tree showing the plugin layout. Update it to match the new plugin structure from the design doc.

**Step 3: Verify no old paths remain**

Run: `grep -n '\.claude/plugins/your-project\|\.claude/plugins/metaswarm\|\.claude/rubrics/\|\.claude/commands/' skills/start/SKILL.md || echo "clean"`
Expected: `clean`

**Step 4: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "fix: update all path references in main orchestration SKILL.md"
```

---

## Phase 4: New Skills

### Task 11: Create setup skill

The setup skill replaces `npx metaswarm init` + `/metaswarm-setup`. It runs entirely inside Claude Code.

**Files:**
- Create: `skills/setup/SKILL.md`

**Step 1: Write the setup skill**

The SKILL.md should contain:

```yaml
---
name: setup
description: Interactive project setup — detects your project, configures metaswarm, writes project-local files
---
```

Content sections:
1. **Project Detection** — scan for package.json, pyproject.toml, Cargo.toml, go.mod, etc. Determine language, framework, test runner, linter, formatter
2. **Interactive Questions** — 3-5 AskUserQuestion calls: coverage threshold, external tools, visual review, CI pipeline, git hooks
3. **File Writing** — using Read tool on `./templates/*`, `./knowledge/*`, `./bin/*`, `./scripts/*` (co-located), then Write tool to project directories
4. **Command Shim Creation** — generate 6 thin `.claude/commands/*.md` shims
5. **CLAUDE.md Handling** — create or append metaswarm section
6. **Profile Creation** — write `.metaswarm/project-profile.json`
7. **Summary** — report what was done

Key constraints documented in the skill:
- All template paths are hardcoded — no user-provided filenames for path construction
- Node.js warning for scripts/*.ts if Node.js not detected
- Check for existing commands before overwriting
- `/start-task` auto-detects missing setup and routes here (Design item #18)

**Step 2: Verify SKILL.md is well-formed**

Run: `head -5 skills/setup/SKILL.md`
Expected: YAML frontmatter with `name: setup`

**Step 3: Commit**

```bash
git add skills/setup/SKILL.md
git commit -m "feat: add setup skill replacing npx metaswarm init"
```

---

### Task 12: Create migrate skill

Handles migration from npm-installed metaswarm to plugin distribution.

**Files:**
- Create: `skills/migrate/SKILL.md`

**Step 1: Write the migrate skill**

```yaml
---
name: migrate
description: Migrate from npm-installed metaswarm to the marketplace plugin — removes redundant files with safety checks
---
```

Content sections:
1. **Pre-flight Check** — verify marketplace plugin is loaded and functional
2. **Inventory** — scan for legacy files (`.claude/plugins/metaswarm/`, `.claude/rubrics/*`, `.claude/guides/*`, `.claude/commands/metaswarm-setup.md`, `.claude/commands/metaswarm-update-version.md`)
3. **Content Verification** — for each file, compute SHA-256 hash of LF-normalized, trailing-whitespace-stripped content. Compare against known metaswarm hashes. Flag modified files.
4. **Dry Run Preview** — display complete list of files that will be removed, flagging customized ones
5. **User Confirmation** — AskUserQuestion with explicit approval required
6. **Git Safety** — check for uncommitted changes, recommend stash/commit first
7. **Removal** — use `git rm` for tracked files (reversible), `rm` for untracked
8. **Shim Creation** — write 6 command shims
9. **Profile Update** — set `"distribution": "plugin"` in `.metaswarm/project-profile.json`
10. **Summary** — report what was removed and next steps
11. **Rollback Instructions** — document how to revert if needed

**Step 2: Verify SKILL.md is well-formed**

Run: `head -5 skills/migrate/SKILL.md`
Expected: YAML frontmatter with `name: migrate`

**Step 3: Commit**

```bash
git add skills/migrate/SKILL.md
git commit -m "feat: add migrate skill for npm-to-plugin transition"
```

---

### Task 13: Create status skill

Diagnostic command for troubleshooting.

**Files:**
- Create: `skills/status/SKILL.md`

**Step 1: Write the status skill**

```yaml
---
name: status
description: Diagnostic status report — shows metaswarm installation state, project setup, and potential issues
---
```

Reports:
- Installed plugin version (from plugin.json)
- Project setup state (`.metaswarm/project-profile.json` exists?)
- Command shims in place? (check `.claude/commands/start-task.md` etc.)
- Legacy embedded plugin detected? (conflict warning)
- BEADS plugin separately installed?
- `bd` CLI available?
- External tools configured and healthy?
- Coverage threshold configuration
- Node.js availability (for optional features)

**Step 2: Commit**

```bash
git add skills/status/SKILL.md
git commit -m "feat: add status skill for diagnostic reporting"
```

---

## Phase 5: Commands

### Task 14: Create and update all 11 commands

**Files:**
- Modify: `commands/start-task.md` (update to reference plugin skill)
- Modify: `commands/prime.md`
- Modify: `commands/review-design.md`
- Modify: `commands/self-reflect.md`
- Modify: `commands/pr-shepherd.md`
- Modify: `commands/handle-pr-comments.md`
- Modify: `commands/create-issue.md`
- Create: `commands/brainstorm.md`
- Create: `commands/external-tools-health.md` (move from `.claude/commands/`)
- Create: `commands/setup.md`
- Create: `commands/update.md`
- Delete: `commands/metaswarm-setup.md` (replaced by `setup.md`)
- Delete: `commands/metaswarm-update-version.md` (replaced by `update.md`)

**Step 1: Update existing commands**

Each existing command should be reviewed to ensure it invokes the right skill. Most commands are thin wrappers that invoke a skill — verify the skill references are correct for the new plugin namespace.

**Step 2: Create brainstorm.md**

```markdown
# Brainstorm

Invoke the metaswarm brainstorming extension skill, which wraps superpowers:brainstorming with metaswarm's design review gate handoff.

Use the `metaswarm:brainstorming-extension` skill. If superpowers is not installed, provide standalone brainstorming guidance.
```

**Step 3: Create external-tools-health.md**

Move content from `.claude/commands/external-tools-health.md` (currently only exists in the mirror) or write new:

```markdown
# External Tools Health Check

Check the status of external AI tools (Codex CLI, Gemini CLI) and their configuration.

1. Check if `codex` and `gemini` CLIs are installed
2. Check if `.metaswarm/external-tools.yaml` exists and is configured
3. Run verification scripts if available
4. Report status of each tool
```

**Step 4: Create setup.md**

```markdown
# Setup

Interactive project setup for metaswarm. Detects your project, configures metaswarm, and writes project-local files.

Invoke the `metaswarm:setup` skill.
```

**Step 5: Create update.md**

```markdown
# Update

Check for and apply metaswarm updates.

1. Check current plugin version
2. Check marketplace for latest version
3. Guide user through update if available
```

**Step 6: Create status.md (Design item #14)**

```markdown
# Status

Show metaswarm diagnostic information.

Invoke the `metaswarm:status` skill.
```

**Step 7: Verify all commands exist**

Run: `ls commands/*.md | wc -l`
Expected: 12 (11 commands + status.md)

**Step 8: Commit**

```bash
git add commands/
git commit -m "feat: create and update all plugin commands"
```

---

## Phase 6: Security Fixes

### Task 15: Fix CI template command injection (TDD)

**Files:**
- Modify: `templates/ci.yml`
- Modify: `skills/setup/templates/ci.yml` (co-located copy)

**Step 1: Write the test**

Create a test that validates the CI template doesn't use `eval`:

```bash
#!/usr/bin/env bash
# tests/templates/test-ci-template.sh

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_not_contains() {
  local desc="$1" file="$2" pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    grep -n "$pattern" "$file"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

assert_contains() {
  local desc="$1" file="$2" pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc — expected pattern: $pattern"
  fi
}

CI_FILE="templates/ci.yml"

echo "Testing CI template security..."

assert_not_contains "No eval in CI template" "$CI_FILE" 'eval "\$'
assert_contains "Uses array-based execution" "$CI_FILE" 'CMD_ARRAY'
assert_contains "Has allowlist check" "$CI_FILE" 'npm|pnpm|yarn|npx|bun|cargo|pytest|go|make'
assert_contains "Has metacharacter rejection" "$CI_FILE" 'grep.*shell metacharacters'

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Write to `tests/templates/test-ci-template.sh`.

**Step 2: Run test to verify it fails**

Run: `bash tests/templates/test-ci-template.sh`
Expected: FAIL (eval still present)

**Step 3: Update templates/ci.yml**

Replace the coverage step:

```yaml
      - name: Test with coverage
        run: |
          if [ -f .coverage-thresholds.json ]; then
            # Read command from coverage config
            CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
            echo "Running coverage command: $CMD"
            # Split into array for safe execution
            read -ra CMD_ARRAY <<< "$CMD"
            # Validate first word is a known package manager/runner
            case "${CMD_ARRAY[0]}" in
              npm|pnpm|yarn|npx|bun|cargo|pytest|go|make) ;;
              *) echo "Error: enforcement command must start with a known package manager/runner"; exit 1 ;;
            esac
            # Reject shell metacharacters in the full command string
            if echo "$CMD" | grep -qE '[;|&`$(){}<>\\]'; then
              echo "Error: enforcement command contains disallowed shell metacharacters"
              exit 1
            fi
            # Execute as array — prevents all shell metacharacter interpretation
            "${CMD_ARRAY[@]}"
          else
            npm test
          fi
```

**Step 4: Sync the co-located copy**

```bash
cp templates/ci.yml skills/setup/templates/ci.yml
```

**Step 5: Run test to verify it passes**

Run: `bash tests/templates/test-ci-template.sh`
Expected: All PASS

**Step 6: Commit**

```bash
git add templates/ci.yml skills/setup/templates/ci.yml tests/templates/test-ci-template.sh
git commit -m "fix: replace eval with array-based execution in CI template"
```

---

### Task 16: Fix estimate-cost.sh awk variable passing

**Files:**
- Modify: `bin/estimate-cost.sh`
- Modify: `skills/setup/bin/estimate-cost.sh` (co-located copy)

**Step 1: Find and fix the vulnerable awk patterns**

Search for: `awk "BEGIN {print $` in `bin/estimate-cost.sh`

Replace patterns like:
```bash
input_cost_per_token=$(awk "BEGIN {print $input_cost_rate / 1000000}")
```

With safe variable passing:
```bash
input_cost_per_token=$(awk -v rate="$input_cost_rate" 'BEGIN {print rate / 1000000}')
```

Apply to ALL awk invocations in the file.

**Step 2: Sync the co-located copy**

```bash
cp bin/estimate-cost.sh skills/setup/bin/estimate-cost.sh
```

**Step 3: Test the script still works**

Run: `bash bin/estimate-cost.sh --help` (or a simple invocation)
Expected: No errors

**Step 4: Commit**

```bash
git add bin/estimate-cost.sh skills/setup/bin/estimate-cost.sh
git commit -m "fix: use safe awk variable passing in estimate-cost.sh"
```

---

## Phase 7: Build Infrastructure

### Task 17: Create sync-resources.js build script (TDD)

This script ensures co-located copies stay in sync with authoritative top-level sources.

**Files:**
- Create: `lib/sync-resources.js`
- Create: `tests/lib/test-sync-resources.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
# tests/lib/test-sync-resources.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
  fi
}

echo "Testing sync-resources.js..."

# Test 1: Check mode (--check) should pass when files are in sync
echo "Test 1: Check mode passes when synced"
result=$(cd "$REPO_ROOT" && node lib/sync-resources.js --check 2>&1 && echo "PASS" || echo "FAIL")
assert_eq "Check mode passes" "PASS" "$result"

# Test 2: Sync mode updates co-located copies
echo "Test 2: Sync mode runs without error"
result=$(cd "$REPO_ROOT" && node lib/sync-resources.js --sync 2>&1 && echo "PASS" || echo "FAIL")
assert_eq "Sync mode succeeds" "PASS" "$result"

# Test 3: After syncing, check mode should still pass
echo "Test 3: Check after sync still passes"
result=$(cd "$REPO_ROOT" && node lib/sync-resources.js --check 2>&1 && echo "PASS" || echo "FAIL")
assert_eq "Check after sync passes" "PASS" "$result"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Write to `tests/lib/test-sync-resources.sh`.

**Step 2: Run test to verify it fails**

Run: `bash tests/lib/test-sync-resources.sh`
Expected: FAIL (sync-resources.js doesn't exist yet)

**Step 3: Write lib/sync-resources.js**

```javascript
#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');

// Mapping: authoritative source → co-located destinations
const SYNC_MAP = [
  // Rubrics
  {
    src: 'rubrics/plan-review-rubric-adversarial.md',
    dests: ['skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md']
  },
  {
    src: 'rubrics/adversarial-review-rubric.md',
    dests: [
      'skills/orchestrated-execution/rubrics/adversarial-review-rubric.md',
      'skills/start/rubrics/adversarial-review-rubric.md'
    ]
  },
  {
    src: 'rubrics/external-tool-review-rubric.md',
    dests: ['skills/external-tools/rubrics/external-tool-review-rubric.md']
  },
  {
    src: 'rubrics/security-review-rubric.md',
    dests: ['skills/start/rubrics/security-review-rubric.md']
  },
  {
    src: 'rubrics/plan-review-rubric.md',
    dests: ['skills/start/rubrics/plan-review-rubric.md']
  },
  {
    src: 'rubrics/code-review-rubric.md',
    dests: ['skills/start/rubrics/code-review-rubric.md']
  },
  // Guides
  {
    src: 'guides/agent-coordination.md',
    dests: [
      'skills/orchestrated-execution/guides/agent-coordination.md',
      'skills/design-review-gate/guides/agent-coordination.md',
      'skills/pr-shepherd/guides/agent-coordination.md',
      'skills/start/guides/agent-coordination.md'
    ]
  },
  // Templates (for setup skill)
  ...fs.readdirSync(path.join(ROOT, 'templates')).map(f => ({
    src: `templates/${f}`,
    dests: [`skills/setup/templates/${f}`]
  })),
  // Knowledge (for setup skill)
  ...fs.readdirSync(path.join(ROOT, 'knowledge')).map(f => ({
    src: `knowledge/${f}`,
    dests: [`skills/setup/knowledge/${f}`]
  })),
  // Bin scripts (for setup skill)
  ...fs.readdirSync(path.join(ROOT, 'bin')).map(f => ({
    src: `bin/${f}`,
    dests: [`skills/setup/bin/${f}`]
  })),
  // Scripts (for setup skill)
  ...fs.readdirSync(path.join(ROOT, 'scripts')).map(f => ({
    src: `scripts/${f}`,
    dests: [`skills/setup/scripts/${f}`]
  })),
];

function hashFile(filepath) {
  const content = fs.readFileSync(filepath, 'utf-8')
    .replace(/\r\n/g, '\n')     // LF normalize
    .replace(/[ \t]+$/gm, '');  // strip trailing whitespace
  return crypto.createHash('sha256').update(content).digest('hex');
}

function check() {
  let drifted = 0;
  for (const { src, dests } of SYNC_MAP) {
    const srcPath = path.join(ROOT, src);
    if (!fs.existsSync(srcPath)) continue;
    const srcHash = hashFile(srcPath);
    for (const dest of dests) {
      const destPath = path.join(ROOT, dest);
      if (!fs.existsSync(destPath)) {
        console.error(`MISSING: ${dest} (source: ${src})`);
        drifted++;
      } else {
        const destHash = hashFile(destPath);
        if (srcHash !== destHash) {
          console.error(`DRIFT: ${dest} differs from ${src}`);
          drifted++;
        }
      }
    }
  }
  if (drifted > 0) {
    console.error(`\n${drifted} file(s) out of sync. Run: node lib/sync-resources.js --sync`);
    process.exit(1);
  }
  console.log('All co-located resources are in sync.');
}

function sync() {
  let synced = 0;
  for (const { src, dests } of SYNC_MAP) {
    const srcPath = path.join(ROOT, src);
    if (!fs.existsSync(srcPath)) continue;
    for (const dest of dests) {
      const destPath = path.join(ROOT, dest);
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.copyFileSync(srcPath, destPath);
      synced++;
    }
  }
  console.log(`Synced ${synced} file(s).`);
}

const mode = process.argv[2];
if (mode === '--check') {
  check();
} else if (mode === '--sync') {
  sync();
} else {
  console.log('Usage: node lib/sync-resources.js [--check|--sync]');
  console.log('  --check   Verify co-located copies match authoritative sources');
  console.log('  --sync    Copy from authoritative sources to co-located destinations');
  process.exit(1);
}
```

Write to `lib/sync-resources.js`.

**Step 4: Run tests to verify they pass**

Run: `bash tests/lib/test-sync-resources.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/sync-resources.js tests/lib/test-sync-resources.sh
git commit -m "feat: add sync-resources.js build script with check and sync modes"
```

---

## Phase 8: Cleanup & Backward Compatibility

### Task 18: Remove old mirror directories

Remove the `.claude/plugins/metaswarm/` embedded plugin directory and other mirrors from the repo itself. These were created by the old CLI installer and are now redundant since the repo root IS the plugin.

**Files:**
- Delete: `.claude/plugins/metaswarm/` (entire directory)
- Delete: `.claude/rubrics/` (if present in repo — check first)
- Delete: `.claude/guides/` (if present in repo — check first)
- Delete: `.claude/templates/` (if present in repo — check first)

**Step 1: Verify what mirror directories exist in the repo**

Run: `ls -la .claude/plugins/metaswarm/ .claude/rubrics/ .claude/guides/ .claude/templates/ 2>/dev/null || echo "some dirs missing"`

**Step 2: Remove mirror directories**

Only remove directories that are mirrors of top-level dirs. Keep `.claude/commands/` (these are the command files auto-discovered by Claude Code) and `.claude/settings.local.json`.

```bash
rm -rf .claude/plugins/metaswarm/
# Only remove these if they exist and are mirrors:
rm -rf .claude/rubrics/
rm -rf .claude/guides/
rm -rf .claude/templates/
```

**Note**: The top-level `agents/` directory and `ORCHESTRATION.md` are kept for the v0.9.0 npm deprecation release (backward compatibility). The `agents/` dir content is now also at `skills/start/agents/`, and `ORCHESTRATION.md` has been replaced with a redirect pointer (Task 4 Step 6). Both can be fully removed after the npm deprecation period ends.

**Step 3: Verify .claude/commands/ still has the command files**

Run: `ls .claude/commands/*.md`
Expected: Command files still present

**Step 4: Commit**

```bash
# Stage only the specific directories being removed (avoid accidentally staging unrelated .claude/ changes)
git rm -rf .claude/plugins/metaswarm/ .claude/rubrics/ .claude/guides/ .claude/templates/ 2>/dev/null || true
git commit -m "chore: remove old mirror directories (repo root is now the plugin)"
```

---

### Task 19: Update package.json for v0.9.0 deprecation

**Files:**
- Modify: `package.json`
- Modify: `cli/metaswarm.js`

**Step 1: Update package.json version**

Change `"version": "0.8.0"` → `"version": "0.9.0"`

Add a deprecation note in description:
```json
"description": "DEPRECATED — Use the Claude Code plugin instead: /plugin marketplace add dsifry/metaswarm-marketplace"
```

**Step 2: Add deprecation notice to CLI**

At the top of `cli/metaswarm.js` (after `const VERSION = ...`), add:

```javascript
console.log('');
console.log('  ⚠  metaswarm has moved to a Claude Code plugin.');
console.log('  Install with: /plugin marketplace add dsifry/metaswarm-marketplace');
console.log('  See: https://github.com/dsifry/metaswarm for details.');
console.log('');
```

The CLI continues to work — this is just a deprecation notice, not a blocker.

**Step 3: Commit**

```bash
git add package.json cli/metaswarm.js
git commit -m "chore: add deprecation notice for npm distribution (v0.9.0)"
```

---

### Task 20: Update .gitignore and package.json files array

**Files:**
- Modify: `package.json` — update `files` array to include new directories
- Modify: `.gitignore` — ensure new directories are not ignored

**Step 1: Update package.json files array**

The `files` array in `package.json` controls what gets published to npm. For the npm deprecation release, it should still include everything. But we also need to add the new dirs:

```json
"files": [
  ".claude-plugin/",
  "hooks/",
  "lib/",
  "cli/",
  "agents/",
  "skills/",
  "commands/",
  "rubrics/",
  "knowledge/",
  "scripts/",
  "bin/",
  "templates/",
  "guides/",
  "ORCHESTRATION.md"
]
```

**Step 2: Commit**

```bash
git add package.json .gitignore
git commit -m "chore: update package.json files array for plugin structure"
```

---

### Task 21: Update CLAUDE.md template

The CLAUDE.md template that gets written to user projects needs to reference the new command namespace.

**Files:**
- Modify: `templates/CLAUDE.md`
- Modify: `skills/setup/templates/CLAUDE.md` (co-located copy)

**Step 1: Update command references in templates/CLAUDE.md**

Update the Available Commands table:
- `/metaswarm-setup` → `/metaswarm:setup` (or just `/setup` via shim)
- `/metaswarm-update-version` → `/metaswarm:update`
- Add `/brainstorm`
- Add `/metaswarm:external-tools-health`
- Add `/metaswarm:status`

Update the Quality Gates section:
- `.claude/plugins/metaswarm/skills/plan-review-gate/SKILL.md` → reference as the `plan-review-gate` skill (no file path needed since it loads from the plugin)

Update the Guides section:
- `.claude/guides/` references → these are now loaded from the plugin, so just reference by name

**Step 2: Sync the co-located copy**

```bash
cp templates/CLAUDE.md skills/setup/templates/CLAUDE.md
```

**Step 3: Commit**

```bash
git add templates/CLAUDE.md skills/setup/templates/CLAUDE.md
git commit -m "feat: update CLAUDE.md template for plugin command namespace"
```

---

### Task 22: Update project documentation

**Files:**
- Modify: `README.md` — new install instructions
- Modify: `INSTALL.md` — plugin install + migration guide
- Modify: `GETTING_STARTED.md` — updated for plugin workflow
- Modify: `CHANGELOG.md` — v1.0.0 release notes

**Step 1: Update README.md**

Update the installation section:
```markdown
## Installation

### Plugin (Recommended)
In Claude Code, run:
```
/plugin marketplace add dsifry/metaswarm-marketplace
```
Then in any project: `/metaswarm:setup`

### npm (Deprecated)
```
npx metaswarm init
```
```

**Step 2: Update INSTALL.md**

Add plugin installation as primary method. Add migration section for existing npm users.

**Step 3: Update GETTING_STARTED.md**

Reference `/metaswarm:setup` instead of `npx metaswarm init`.

**Step 4: Update CHANGELOG.md**

Add v1.0.0 entry with:
- Plugin distribution via marketplace
- Zero Node.js dependency for install and core usage
- Automatic updates
- `/metaswarm:setup` replaces `npx metaswarm init`
- `/metaswarm:migrate` for existing users
- `/metaswarm:status` diagnostic command
- Security fix: CI template eval → array execution
- Security fix: estimate-cost.sh awk variable passing
- All path references updated to relative `./` paths

**Step 5: Commit**

```bash
git add README.md INSTALL.md GETTING_STARTED.md CHANGELOG.md
git commit -m "docs: update documentation for plugin distribution"
```

---

## Phase 9: Marketplace & Validation

### Task 23: Create marketplace repository

This is a separate repo (`dsifry/metaswarm-marketplace`). Can be created later.

**Step 1: Note the marketplace.json content for later**

```json
{
  "name": "metaswarm-marketplace",
  "owner": {
    "name": "David Sifry",
    "email": "david@sifry.com"
  },
  "metadata": {
    "description": "Multi-agent orchestration framework for Claude Code",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "metaswarm",
      "source": {
        "source": "github",
        "repo": "dsifry/metaswarm",
        "ref": "v1.0.0"
      },
      "description": "18-agent orchestration with quality gates, TDD enforcement, and knowledge capture",
      "version": "1.0.0",
      "strict": true,
      "category": "productivity",
      "keywords": ["orchestration", "agents", "tdd", "quality-gates"]
    }
  ]
}
```

This goes in a new repo at `.claude-plugin/marketplace.json`.

**Step 2: Create the repo (manual or via gh CLI)**

```bash
# Create on GitHub
gh repo create dsifry/metaswarm-marketplace --public --description "Marketplace manifest for the metaswarm Claude Code plugin"

# Clone and add files
git clone git@github.com:dsifry/metaswarm-marketplace.git /tmp/metaswarm-marketplace
mkdir -p /tmp/metaswarm-marketplace/.claude-plugin
# Write marketplace.json
cd /tmp/metaswarm-marketplace
git add .claude-plugin/marketplace.json
git commit -m "feat: initial marketplace manifest for metaswarm v1.0.0"
git push
```

This task is done separately from the main repo work.

---

### Task 24: End-to-end validation

**Files:**
- No files created — this is a validation pass

**Step 1: Validate plugin structure**

Run: `ls .claude-plugin/plugin.json hooks/hooks.json hooks/session-start.sh`
Expected: All exist

**Step 2: Validate all skills are discoverable**

Run: `ls skills/*/SKILL.md | sort`
Expected: 13 skills listed (start + 9 existing + setup + migrate + status)

**Step 3: Validate all commands exist**

Run: `ls commands/*.md | sort`
Expected: 12 commands listed

**Step 4: Validate no broken path references**

Run: `grep -rn '\.claude/rubrics/\|\.claude/guides/\|\.claude/commands/\|\.claude/plugins/your-project\|\.claude/plugins/metaswarm' skills/ commands/ || echo "clean"`
Note: The top-level `agents/` directory is superseded by `skills/start/agents/`. The old `agents/` may still exist for backward compatibility but is not checked here.
Expected: `clean`

**Step 5: Validate co-located resources are in sync**

Run: `node lib/sync-resources.js --check`
Expected: "All co-located resources are in sync."

**Step 6: Run all test suites**

Run: `bash tests/hooks/test-session-start.sh && bash tests/templates/test-ci-template.sh && bash tests/lib/test-sync-resources.sh`
Expected: All pass

**Step 7: Validate hooks.json is valid**

Run: `node -e "JSON.parse(require('fs').readFileSync('hooks/hooks.json','utf-8')); console.log('valid')"`
Expected: `valid`

**Step 8: Validate plugin.json is valid**

Run: `node -e "JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json','utf-8')); console.log('valid')"`
Expected: `valid`

---

## Implementation Tracking Items (from design review)

These items from the design review must be addressed during the tasks above:

| # | Item | Addressed In |
|---|------|-------------|
| 1 | 11 broken paths in agent definitions | Task 9 |
| 2 | Phantom typescript-patterns.md | Task 9, Step 2 |
| 3 | BEADS dedup exact-match JSON parsing | Task 3 (jq/node parsing) |
| 4 | Migration content hashing SHA-256 | Task 12 (migrate skill) |
| 5 | Marketplace SHA pinning | Task 23 (document as known limitation if unsupported) |
| 6 | PreCompact hook idempotency | Task 3 (tested in Step 4) |
| 7 | lib/skills-core.js scope | Deferred — not needed for v1.0 |
| 8 | Test: BEADS dedup detection | Task 3 tests |
| 9 | Test: dual-plugin conflict | Task 24 (manual validation) |
| 10 | PreCompact matcher validation | Task 2 (empty string matches all) |
| 11 | rubrics/guides NOT auto-discovered | Task 5-6 (co-location solves this) |
| 12 | Use "source": "github" in marketplace.json | Task 23 |
| 13 | Hook output format | Task 3 (hookSpecificOutput.additionalContext) |
| 14 | Missing commands/status.md | Task 14 |
| 15 | typescript-patterns.md scope (4 files) | Task 9 |
| 16 | package.json disposition after v1.0.0 | Task 19 |
| 17 | session-start.sh fallback when neither jq nor node | Task 3 (safe default) |
| 18 | /start-task detect missing setup | Task 11 (setup skill) |

---

## Dependency Graph

```
Task 1 (plugin.json) ──┐
Task 2 (hooks.json) ───┤
Task 3 (session-start.sh) ──── depends on Task 2
                        │
Task 4 (skills/start/) ─┤
Task 5 (co-locate rubrics) ── depends on Task 4
Task 6 (co-locate guides) ─── depends on Task 4
Task 7 (co-locate setup resources) ── independent
                        │
Task 8 (update SKILL.md paths) ── depends on Tasks 5, 6
Task 9 (update agent paths) ──── depends on Tasks 4, 5, 6
Task 10 (update ORCHESTRATION refs) ── depends on Task 4
                        │
Task 11 (setup skill) ──── depends on Task 7
Task 12 (migrate skill) ── depends on Task 4
Task 13 (status skill) ─── independent
Task 14 (commands) ──────── depends on Tasks 11, 12, 13
                        │
Task 15 (CI security) ──── independent
Task 16 (awk security) ─── independent
Task 17 (sync-resources) ── depends on Tasks 5, 6, 7
                        │
Task 18 (cleanup mirrors) ── depends on Tasks 1-17
Task 19 (deprecation) ────── depends on Task 18
Task 20 (package.json) ────── depends on Task 18
Task 21 (CLAUDE.md template) ── depends on Task 14
Task 22 (documentation) ───── depends on all above
Task 23 (marketplace repo) ── independent (separate repo)
Task 24 (validation) ────── depends on all above
```

**Parallelizable groups:**
- Group A (independent): Tasks 1, 2, 4, 7, 13, 15, 16
- Group B (after Group A): Tasks 3, 5, 6, 8, 9, 10, 11, 12, 17
- Group C (after Group B): Tasks 14, 18
- Group D (after Group C): Tasks 19, 20, 21, 22, 24
- Separate track: Task 23

---

## Summary

- **24 tasks** across 9 phases
- **~50 files** modified or created
- **3 new skills** (setup, migrate, status) + 1 restructured (start, from ORCHESTRATION.md) = **13 total skills**
- **5 new commands** (brainstorm, external-tools-health, setup, update, status) = **12 total commands**
- **2 security fixes** (CI template, estimate-cost.sh)
- **1 build script** (sync-resources.js)
- **3 test suites** (session-start.sh, CI template, sync-resources.js) with **6 test cases** for the hook
- **18 design review items** tracked to specific tasks
- **`.beads/` project-local directory is UNCHANGED** — only the skill directory renames from `beads/` to `start/`
