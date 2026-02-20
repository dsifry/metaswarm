# External Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the adapter system that delegates implementation and review tasks to external AI CLI tools (Codex, Gemini) with cross-model adversarial review, sandboxed execution, and availability-aware escalation.

**Architecture:** Shell-script adapters behind a uniform protocol, orchestrated by a metaswarm skill that plugs into the existing 4-phase execution loop. Each adapter translates between the protocol and a specific tool's CLI.

**Tech Stack:** Bash (adapters + helpers), Markdown (skill + rubric + docs), YAML (config)

**Design Doc:** `docs/plans/2026-02-14-external-tools-design.md`

---

### Task 1: Install and Verify Codex CLI

**Files:**
- Create: `templates/external-tools-setup.md` (started here, expanded in Task 10)

**Step 1: Install Codex CLI globally**

Run: `npm install -g @openai/codex`
Expected: `added N packages` with no errors

**Step 2: Verify installation**

Run: `codex --version`
Expected: Version string (e.g., `0.55.x` or higher)

**Step 3: Authenticate**

Run: `codex login --with-api-key` (paste OPENAI_API_KEY when prompted)
Or set env var: `export OPENAI_API_KEY="sk-..."`

**Step 4: Verify auth works**

Run: `codex login status`
Expected: Exit code 0 (logged in)

**Step 5: Smoke test non-interactive mode**

Run: `codex exec "echo hello world in bash" --ephemeral`
Expected: A bash command that prints hello world, streamed to stdout

**Step 6: Document what worked/failed**

Note any issues encountered during setup for inclusion in `templates/external-tools-setup.md`.

---

### Task 2: Install and Verify Gemini CLI

**Step 1: Install Gemini CLI globally**

Run: `npm install -g @google/gemini-cli`
Expected: `added N packages` with no errors

**Step 2: Verify installation**

Run: `gemini --version`
Expected: Version string

**Step 3: Authenticate**

Run: `gemini` (interactive, select "Login with Google" for free tier)
Or set env var: `export GEMINI_API_KEY="AIza..."`

**Step 4: Smoke test non-interactive mode**

Run: `gemini "echo hello world in bash" --output-format json`
Expected: JSON response with a `response` field containing bash code

**Step 5: Document what worked/failed**

Note any issues for the setup guide.

---

### Task 3: Create Directory Structure and Example Config

**Files:**
- Create: `skills/external-tools/adapters/` (directory)
- Create: `templates/external-tools.yaml` (example config)

**Step 1: Create the adapter directory**

Run: `mkdir -p skills/external-tools/adapters`

**Step 2: Write the example config template**

Create `templates/external-tools.yaml`:

```yaml
# External Tools Configuration
# Copy to .metaswarm/external-tools.yaml in your project root to enable.
# If this file is absent, external tools are not used (pure metaswarm behavior).

adapters:
  codex:
    enabled: true
    model: "gpt-5.3-codex"          # Model to use for Codex CLI invocations
    timeout_seconds: 300             # Max seconds per invocation before kill
    sandbox: none                    # docker | platform | none
    auth_env_var: "OPENAI_API_KEY"   # Environment variable holding the API key
  gemini:
    enabled: true
    model: "pro"                     # Model alias: pro | flash | flash-lite
    timeout_seconds: 300
    sandbox: none
    auth_env_var: "GEMINI_API_KEY"   # Or use Google login (no key needed)

routing:
  # How to pick the implementer for a task:
  #   cheapest-available: prefer the cheapest tool that passes health check
  #   round-robin: alternate between tools
  #   <tool-name>: always use a specific tool
  default_implementer: "cheapest-available"

  # Order for escalation when a tool fails after max retries
  escalation_order: ["codex", "gemini", "claude"]

budget:
  per_task_usd: 2.00               # Circuit breaker: max spend per task before user alert
  per_session_usd: 20.00           # Circuit breaker: max total spend per session
```

**Step 3: Verify directory structure**

Run: `ls -la skills/external-tools/adapters/`
Expected: Empty directory exists

**Step 4: Commit scaffolding**

```bash
git add skills/external-tools/adapters/.gitkeep templates/external-tools.yaml
git commit -m "chore: scaffold external-tools directory and config template"
```

---

### Task 4: Write _common.sh — Core Safety Helpers

**Files:**
- Create: `skills/external-tools/adapters/_common.sh`

**Step 1: Write the core helpers**

Create `skills/external-tools/adapters/_common.sh`:

```bash
#!/bin/bash
# _common.sh — Shared helpers for external tool adapters
# Source this file from adapter scripts: source "$(dirname "$0")/_common.sh"
#
# Provides: safe_invoke, create_worktree, cleanup_worktree, create_secure_tmp,
#           verify_scope, extract_cost, log_session, check_tool_exists,
#           classify_error, emit_json, emit_error

set -euo pipefail

# --- Constants ---
SCHEMA_VERSION="1"
LOG_DIR="${HOME}/.claude/sessions"

# --- JSON Output Helpers ---

# Emit a structured JSON result to stdout.
# Usage: emit_json "codex" "implement" "gpt-5.3-codex" 1 0 "branch" "sha" '["f1"]' '{"a":1,"d":0}' 85 '{"input_tokens":0,"output_tokens":0}' "/path/log" null
emit_json() {
  local tool="$1" command="$2" model="$3" attempt="$4" exit_code="$5"
  local branch="$6" git_sha="$7" files_changed="$8" diff_stats="$9"
  local duration="${10}" cost="${11}" raw_log="${12}" error_type="${13}"

  cat <<ENDJSON
{
  "tool": "${tool}",
  "command": "${command}",
  "model": "${model}",
  "attempt": ${attempt},
  "exit_code": ${exit_code},
  "branch": "${branch}",
  "git_sha": "${git_sha}",
  "files_changed": ${files_changed},
  "diff_stats": ${diff_stats},
  "duration_seconds": ${duration},
  "cost": ${cost},
  "raw_log": "${raw_log}",
  "error_type": ${error_type},
  "schema_version": "${SCHEMA_VERSION}"
}
ENDJSON
}

# Emit a structured error JSON to stdout.
# Usage: emit_error "codex" "implement" "timeout" 124
emit_error() {
  local tool="$1" command="$2" error_type="$3" exit_code="$4"
  local model="${5:-unknown}" attempt="${6:-0}" raw_log="${7:-}"

  emit_json "$tool" "$command" "$model" "$attempt" "$exit_code" \
    "" "" "[]" '{"additions":0,"deletions":0}' 0 \
    '{"input_tokens":0,"output_tokens":0}' "$raw_log" "\"${error_type}\""
}

# --- Timeout & Error Handling ---

# Classify an error exit code + stderr into a structured error type.
# Usage: classify_error <exit_code> <stderr_file>
# Prints: one of the error_type enum values
classify_error() {
  local exit_code="$1"
  local stderr_file="$2"
  local stderr_content=""

  if [ -f "$stderr_file" ]; then
    stderr_content=$(cat "$stderr_file" 2>/dev/null || true)
  fi

  case "$exit_code" in
    124) echo "timeout" ;;
    127) echo "tool_not_installed" ;;
    *)
      if echo "$stderr_content" | grep -qi "rate.limit\|429\|too many requests"; then
        echo "rate_limited"
      elif echo "$stderr_content" | grep -qi "auth\|unauthorized\|401\|forbidden\|403\|invalid.*key"; then
        echo "auth_expired"
      elif echo "$stderr_content" | grep -qi "network\|connection\|ECONNREFUSED\|ETIMEDOUT\|DNS"; then
        echo "network_error"
      elif echo "$stderr_content" | grep -qi "context.*too.*large\|token.*limit\|exceeds.*maximum"; then
        echo "context_too_large"
      else
        echo "tool_crash"
      fi
      ;;
  esac
}

# Invoke a command with a timeout. Captures stdout and stderr separately.
# Usage: safe_invoke <timeout_seconds> <stdout_file> <stderr_file> <command...>
# Returns: the command's exit code (or 124 for timeout)
safe_invoke() {
  local timeout_secs="$1"; shift
  local stdout_file="$1"; shift
  local stderr_file="$1"; shift

  local exit_code=0
  timeout "$timeout_secs" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

  return $exit_code
}

# --- Git Worktree Helpers ---

# Create an isolated git worktree for an external tool invocation.
# Usage: create_worktree <repo_root> <tool_name> <task_id> <worktree_base_dir>
# Prints: the worktree path
create_worktree() {
  local repo_root="$1"
  local tool_name="$2"
  local task_id="$3"
  local base_dir="${4:-/tmp}"

  local branch_name="external/${tool_name}/${task_id}"
  local worktree_path="${base_dir}/ext-${tool_name}-${task_id}"

  # Clean up any stale worktree at this path
  if [ -d "$worktree_path" ]; then
    git -C "$repo_root" worktree remove "$worktree_path" --force 2>/dev/null || true
    rm -rf "$worktree_path" 2>/dev/null || true
  fi

  # Clean up stale branch if it exists
  git -C "$repo_root" branch -D "$branch_name" 2>/dev/null || true

  # Create the worktree
  git -C "$repo_root" worktree add "$worktree_path" -b "$branch_name" 2>/dev/null

  echo "$worktree_path"
}

# Remove a worktree and its branch.
# Usage: cleanup_worktree <repo_root> <worktree_path> <branch_name> [keep_branch]
cleanup_worktree() {
  local repo_root="$1"
  local worktree_path="$2"
  local branch_name="$3"
  local keep_branch="${4:-false}"

  git -C "$repo_root" worktree remove "$worktree_path" --force 2>/dev/null || true
  rm -rf "$worktree_path" 2>/dev/null || true

  if [ "$keep_branch" != "true" ]; then
    git -C "$repo_root" branch -D "$branch_name" 2>/dev/null || true
  fi
}

# --- Secure Temp Files ---

# Create a secure temporary directory (mode 700) with trap cleanup.
# Usage: TMPDIR=$(create_secure_tmp)
# Note: caller should set their own trap if needed.
create_secure_tmp() {
  local tmpdir
  tmpdir=$(mktemp -d -t "xt-XXXXXX")
  chmod 700 "$tmpdir"
  echo "$tmpdir"
}

# --- Scope Verification ---

# Check that all file changes are within the allowed context directory.
# Reverts any out-of-scope changes and logs warnings.
# Usage: verify_scope <worktree_path> [context_dir]
# Returns: 0 if all in scope, 1 if out-of-scope changes were reverted
verify_scope() {
  local worktree_path="$1"
  local context_dir="${2:-}"  # empty = allow all changes
  local violations=0

  if [ -z "$context_dir" ]; then
    return 0
  fi

  local changed_files
  changed_files=$(git -C "$worktree_path" diff --name-only HEAD 2>/dev/null || true)

  if [ -z "$changed_files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    if [[ "$file" != "${context_dir}"* ]]; then
      echo "SCOPE VIOLATION: ${file} is outside ${context_dir} — reverting" >&2
      git -C "$worktree_path" checkout HEAD -- "$file" 2>/dev/null || true
      violations=$((violations + 1))
    fi
  done <<< "$changed_files"

  if [ $violations -gt 0 ]; then
    return 1
  fi
  return 0
}

# --- Cost Extraction ---

# Extract token usage from a Codex CLI JSONL output file.
# Usage: extract_cost_codex <raw_log_file>
# Prints: JSON object {"input_tokens": N, "output_tokens": N}
extract_cost_codex() {
  local log_file="$1"
  if [ ! -f "$log_file" ]; then
    echo '{"input_tokens": 0, "output_tokens": 0}'
    return
  fi

  # Codex JSONL has turn.completed events with usage data
  local input_tokens output_tokens
  input_tokens=$(grep -o '"input_tokens":[0-9]*' "$log_file" | tail -1 | grep -o '[0-9]*' || echo "0")
  output_tokens=$(grep -o '"output_tokens":[0-9]*' "$log_file" | tail -1 | grep -o '[0-9]*' || echo "0")

  echo "{\"input_tokens\": ${input_tokens:-0}, \"output_tokens\": ${output_tokens:-0}}"
}

# Extract token usage from a Gemini CLI JSON output.
# Usage: extract_cost_gemini <raw_log_file>
# Prints: JSON object {"input_tokens": N, "output_tokens": N}
extract_cost_gemini() {
  local log_file="$1"
  if [ ! -f "$log_file" ]; then
    echo '{"input_tokens": 0, "output_tokens": 0}'
    return
  fi

  local input_tokens output_tokens
  input_tokens=$(jq -r '.stats.models[0].inputTokens // 0' "$log_file" 2>/dev/null || echo "0")
  output_tokens=$(jq -r '.stats.models[0].outputTokens // 0' "$log_file" 2>/dev/null || echo "0")

  echo "{\"input_tokens\": ${input_tokens:-0}, \"output_tokens\": ${output_tokens:-0}}"
}

# --- Git Diff Stats ---

# Get diff stats (additions/deletions) for the current branch vs its base.
# Usage: get_diff_stats <worktree_path>
# Prints: JSON object {"additions": N, "deletions": N}
get_diff_stats() {
  local worktree_path="$1"
  local stats
  stats=$(git -C "$worktree_path" diff --shortstat HEAD 2>/dev/null || echo "")

  local additions=0 deletions=0
  if [ -n "$stats" ]; then
    additions=$(echo "$stats" | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || echo "0")
    deletions=$(echo "$stats" | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || echo "0")
  fi

  echo "{\"additions\": ${additions:-0}, \"deletions\": ${deletions:-0}}"
}

# Get list of changed files as JSON array.
# Usage: get_changed_files <worktree_path>
# Prints: JSON array ["file1", "file2"]
get_changed_files() {
  local worktree_path="$1"
  local files
  files=$(git -C "$worktree_path" diff --name-only HEAD 2>/dev/null || echo "")

  if [ -z "$files" ]; then
    echo "[]"
    return
  fi

  echo "$files" | jq -R -s 'split("\n") | map(select(length > 0))'
}

# --- Session Logging ---

# Log a structured session entry for self-reflection.
# Usage: log_session <tool> <command> <model> <attempt> <outcome> <cost_json> <duration> <task_id>
log_session() {
  local tool="$1" command="$2" model="$3" attempt="$4"
  local outcome="$5" cost_json="$6" duration="$7" task_id="${8:-}"

  mkdir -p "$LOG_DIR"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local log_file="${LOG_DIR}/external-tools.jsonl"

  cat >> "$log_file" <<LOGENTRY
{"timestamp":"${timestamp}","tool":"${tool}","command":"${command}","model":"${model}","attempt":${attempt},"outcome":"${outcome}","cost":${cost_json},"duration_seconds":${duration},"task_id":"${task_id}"}
LOGENTRY
}

# --- Argument Parsing Helpers ---

# Parse standard adapter arguments.
# Usage: parse_args "$@"
# Sets: WORKTREE, PROMPT_FILE, RUBRIC_FILE, SPEC_FILE, ATTEMPT, TIMEOUT, CONTEXT_DIR
parse_args() {
  WORKTREE=""
  PROMPT_FILE=""
  RUBRIC_FILE=""
  SPEC_FILE=""
  ATTEMPT=1
  TIMEOUT=300
  CONTEXT_DIR=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree)     WORKTREE="$2"; shift 2 ;;
      --prompt-file)  PROMPT_FILE="$2"; shift 2 ;;
      --rubric-file)  RUBRIC_FILE="$2"; shift 2 ;;
      --spec-file)    SPEC_FILE="$2"; shift 2 ;;
      --attempt)      ATTEMPT="$2"; shift 2 ;;
      --timeout)      TIMEOUT="$2"; shift 2 ;;
      --context-dir)  CONTEXT_DIR="$2"; shift 2 ;;
      *)              shift ;;
    esac
  done
}
```

**Step 2: Make it sourceable and verify syntax**

Run: `bash -n skills/external-tools/adapters/_common.sh`
Expected: No output (syntax is valid)

**Step 3: Verify key functions parse correctly**

Run: `source skills/external-tools/adapters/_common.sh && type safe_invoke && type create_worktree && type emit_json`
Expected: Each prints "safe_invoke is a function" etc.

**Step 4: Test classify_error with mock stderr**

Run:
```bash
source skills/external-tools/adapters/_common.sh
echo "rate limit exceeded" > /tmp/test-stderr.txt
result=$(classify_error 1 /tmp/test-stderr.txt)
echo "classify_error result: $result"
rm /tmp/test-stderr.txt
```
Expected: `classify_error result: rate_limited`

**Step 5: Test create_secure_tmp**

Run:
```bash
source skills/external-tools/adapters/_common.sh
tmpdir=$(create_secure_tmp)
ls -la "$tmpdir"
stat -f "%OLp" "$tmpdir"  # macOS: show permissions
rm -rf "$tmpdir"
```
Expected: Directory exists with permissions `700`

**Step 6: Commit**

```bash
git add skills/external-tools/adapters/_common.sh
git commit -m "feat(external-tools): add _common.sh shared adapter helpers

Provides: safe_invoke, create_worktree, cleanup_worktree, create_secure_tmp,
verify_scope, extract_cost, classify_error, emit_json, log_session, parse_args"
```

---

### Task 5: Write Codex Adapter

**Files:**
- Create: `skills/external-tools/adapters/codex.sh`

**Step 1: Write the Codex adapter**

Create `skills/external-tools/adapters/codex.sh`:

```bash
#!/bin/bash
# codex.sh — OpenAI Codex CLI adapter for metaswarm external-tools
# Usage:
#   codex.sh health
#   codex.sh implement --worktree <path> --prompt-file <path> [--attempt N] [--timeout N]
#   codex.sh review --worktree <path> --rubric-file <path> --spec-file <path> [--timeout N]
#
# Requires: codex CLI installed (npm i -g @openai/codex)
# Auth: OPENAI_API_KEY or CODEX_API_KEY environment variable, or codex login

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

TOOL_NAME="codex"
TOOL_CMD="codex"
DEFAULT_MODEL="gpt-5.3-codex"

# --- Health Check ---
cmd_health() {
  # Check if binary exists
  if ! command -v "$TOOL_CMD" &>/dev/null; then
    echo '{"tool":"codex","status":"unavailable","version":null,"auth_valid":false,"model":null,"error":"codex CLI not installed. Run: npm i -g @openai/codex"}'
    return 0
  fi

  # Get version
  local version
  version=$("$TOOL_CMD" --version 2>/dev/null || echo "unknown")

  # Check auth — codex login status exits 0 if logged in
  local auth_valid=false
  if "$TOOL_CMD" login status &>/dev/null; then
    auth_valid=true
  elif [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${CODEX_API_KEY:-}" ]; then
    auth_valid=true
  fi

  local status="ready"
  if [ "$auth_valid" != "true" ]; then
    status="unavailable"
  fi

  cat <<ENDJSON
{"tool":"codex","status":"${status}","version":"${version}","auth_valid":${auth_valid},"model":"${DEFAULT_MODEL}"}
ENDJSON
}

# --- Implement ---
cmd_implement() {
  parse_args "$@"

  if [ -z "$WORKTREE" ] || [ -z "$PROMPT_FILE" ]; then
    echo "ERROR: --worktree and --prompt-file are required" >&2
    emit_error "$TOOL_NAME" "implement" "tool_crash" 1
    return 1
  fi

  local secure_tmp
  secure_tmp=$(create_secure_tmp)
  trap "rm -rf $secure_tmp" EXIT

  local stdout_file="${secure_tmp}/stdout.log"
  local stderr_file="${secure_tmp}/stderr.log"
  local raw_log="${LOG_DIR}/ext-codex-implement-attempt-${ATTEMPT}.log"
  mkdir -p "$LOG_DIR"

  local start_time
  start_time=$(date +%s)

  # Read the prompt file content
  local prompt_content
  prompt_content=$(cat "$PROMPT_FILE")

  # Invoke Codex CLI in non-interactive mode
  local exit_code=0
  safe_invoke "$TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i HOME="$HOME" PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec \
      --full-auto \
      --json \
      -C "$WORKTREE" \
      "$prompt_content" \
    || exit_code=$?

  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Save raw output for debugging
  cp "$stdout_file" "$raw_log" 2>/dev/null || true

  # Handle errors
  if [ $exit_code -ne 0 ]; then
    local error_type
    error_type=$(classify_error "$exit_code" "$stderr_file")
    log_session "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" "failure" \
      '{"input_tokens":0,"output_tokens":0}' "$duration"
    emit_error "$TOOL_NAME" "implement" "$error_type" "$exit_code" "$DEFAULT_MODEL" "$ATTEMPT" "$raw_log"
    return 1
  fi

  # Commit any changes the tool made
  git -C "$WORKTREE" add -A 2>/dev/null || true
  local git_sha=""
  if ! git -C "$WORKTREE" diff --cached --quiet 2>/dev/null; then
    git -C "$WORKTREE" commit -m "external(codex): implement attempt ${ATTEMPT}" --no-verify 2>/dev/null || true
    git_sha=$(git -C "$WORKTREE" rev-parse --short HEAD 2>/dev/null || echo "")
  fi

  # Scope verification
  verify_scope "$WORKTREE" "$CONTEXT_DIR" || true

  # Extract results
  local branch_name
  branch_name=$(git -C "$WORKTREE" branch --show-current 2>/dev/null || echo "")
  local files_changed
  files_changed=$(get_changed_files "$WORKTREE")
  local diff_stats
  diff_stats=$(get_diff_stats "$WORKTREE")
  local cost
  cost=$(extract_cost_codex "$raw_log")

  log_session "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" "success" "$cost" "$duration"

  emit_json "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" 0 \
    "$branch_name" "$git_sha" "$files_changed" "$diff_stats" \
    "$duration" "$cost" "$raw_log" "null"
}

# --- Review ---
cmd_review() {
  parse_args "$@"

  if [ -z "$WORKTREE" ] || [ -z "$RUBRIC_FILE" ] || [ -z "$SPEC_FILE" ]; then
    echo "ERROR: --worktree, --rubric-file, and --spec-file are required" >&2
    emit_error "$TOOL_NAME" "review" "tool_crash" 1
    return 1
  fi

  local secure_tmp
  secure_tmp=$(create_secure_tmp)
  trap "rm -rf $secure_tmp" EXIT

  local stdout_file="${secure_tmp}/stdout.log"
  local stderr_file="${secure_tmp}/stderr.log"
  local raw_log="${LOG_DIR}/ext-codex-review-attempt-${ATTEMPT}.log"
  mkdir -p "$LOG_DIR"

  # Build the review prompt
  local diff_content rubric_content spec_content
  diff_content=$(git -C "$WORKTREE" diff HEAD~1 2>/dev/null || git -C "$WORKTREE" diff HEAD 2>/dev/null || echo "No changes detected")
  rubric_content=$(cat "$RUBRIC_FILE")
  spec_content=$(cat "$SPEC_FILE")

  local review_prompt
  review_prompt=$(cat <<PROMPT
You are an adversarial code reviewer. Review the following code changes against the spec and rubric.

## Rubric
${rubric_content}

## Spec
${spec_content}

## Code Changes (diff)
\`\`\`diff
${diff_content}
\`\`\`

Provide your review with:
1. A clear PASS or FAIL verdict
2. For each finding, cite the specific file:line
3. Classify each finding as BLOCKING (causes FAIL) or WARNING (does not cause FAIL)
PROMPT
  )

  local start_time
  start_time=$(date +%s)

  # Invoke Codex for review (read-only sandbox)
  local exit_code=0
  safe_invoke "$TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i HOME="$HOME" PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec \
      --sandbox read-only \
      --json \
      -C "$WORKTREE" \
      "$review_prompt" \
    || exit_code=$?

  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Save raw output
  cp "$stdout_file" "$raw_log" 2>/dev/null || true

  if [ $exit_code -ne 0 ]; then
    local error_type
    error_type=$(classify_error "$exit_code" "$stderr_file")
    log_session "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" "failure" \
      '{"input_tokens":0,"output_tokens":0}' "$duration"
    emit_error "$TOOL_NAME" "review" "$error_type" "$exit_code" "$DEFAULT_MODEL" "$ATTEMPT" "$raw_log"
    return 1
  fi

  local cost
  cost=$(extract_cost_codex "$raw_log")

  log_session "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" "success" "$cost" "$duration"

  # For review, files_changed and diff_stats refer to what was reviewed
  local files_changed
  files_changed=$(get_changed_files "$WORKTREE")
  local diff_stats
  diff_stats=$(get_diff_stats "$WORKTREE")
  local branch_name
  branch_name=$(git -C "$WORKTREE" branch --show-current 2>/dev/null || echo "")

  emit_json "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" 0 \
    "$branch_name" "" "$files_changed" "$diff_stats" \
    "$duration" "$cost" "$raw_log" "null"
}

# --- Main Dispatch ---
case "${1:-}" in
  health)     cmd_health ;;
  implement)  shift; cmd_implement "$@" ;;
  review)     shift; cmd_review "$@" ;;
  *)
    echo "Usage: codex.sh {health|implement|review} [options]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  health                          Check if Codex CLI is ready" >&2
    echo "  implement --worktree <p> ...    Implement code on a branch" >&2
    echo "  review --worktree <p> ...       Review code changes" >&2
    exit 1
    ;;
esac
```

**Step 2: Make executable and verify syntax**

Run: `chmod +x skills/external-tools/adapters/codex.sh && bash -n skills/external-tools/adapters/codex.sh`
Expected: No output (valid syntax)

**Step 3: Test health command**

Run: `skills/external-tools/adapters/codex.sh health`
Expected: JSON with `"status": "ready"` (if installed) or `"status": "unavailable"`

**Step 4: Verify health output is valid JSON**

Run: `skills/external-tools/adapters/codex.sh health | jq .`
Expected: Pretty-printed JSON, no parse errors

**Step 5: Commit**

```bash
git add skills/external-tools/adapters/codex.sh
git commit -m "feat(external-tools): add Codex CLI adapter

Implements health, implement, and review commands with timeout wrapping,
minimal environment, scope verification, and structured JSON output."
```

---

### Task 6: Write Gemini Adapter

**Files:**
- Create: `skills/external-tools/adapters/gemini.sh`

**Step 1: Write the Gemini adapter**

Create `skills/external-tools/adapters/gemini.sh`:

```bash
#!/bin/bash
# gemini.sh — Google Gemini CLI adapter for metaswarm external-tools
# Usage:
#   gemini.sh health
#   gemini.sh implement --worktree <path> --prompt-file <path> [--attempt N] [--timeout N]
#   gemini.sh review --worktree <path> --rubric-file <path> --spec-file <path> [--timeout N]
#
# Requires: gemini CLI installed (npm i -g @google/gemini-cli)
# Auth: GEMINI_API_KEY env var, or Google account login

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

TOOL_NAME="gemini"
TOOL_CMD="gemini"
DEFAULT_MODEL="pro"

# --- Health Check ---
cmd_health() {
  if ! command -v "$TOOL_CMD" &>/dev/null; then
    echo '{"tool":"gemini","status":"unavailable","version":null,"auth_valid":false,"model":null,"error":"gemini CLI not installed. Run: npm i -g @google/gemini-cli"}'
    return 0
  fi

  local version
  version=$("$TOOL_CMD" --version 2>/dev/null || echo "unknown")

  # Gemini auth check: if GEMINI_API_KEY is set, assume valid.
  # Google account login is persisted in ~/.gemini/ and harder to validate without an API call.
  local auth_valid=false
  if [ -n "${GEMINI_API_KEY:-}" ]; then
    auth_valid=true
  elif [ -d "${HOME}/.gemini" ]; then
    # Google login credentials are stored here
    auth_valid=true
  fi

  local status="ready"
  if [ "$auth_valid" != "true" ]; then
    status="unavailable"
  fi

  cat <<ENDJSON
{"tool":"gemini","status":"${status}","version":"${version}","auth_valid":${auth_valid},"model":"${DEFAULT_MODEL}"}
ENDJSON
}

# --- Implement ---
cmd_implement() {
  parse_args "$@"

  if [ -z "$WORKTREE" ] || [ -z "$PROMPT_FILE" ]; then
    echo "ERROR: --worktree and --prompt-file are required" >&2
    emit_error "$TOOL_NAME" "implement" "tool_crash" 1
    return 1
  fi

  local secure_tmp
  secure_tmp=$(create_secure_tmp)
  trap "rm -rf $secure_tmp" EXIT

  local stdout_file="${secure_tmp}/stdout.json"
  local stderr_file="${secure_tmp}/stderr.log"
  local raw_log="${LOG_DIR}/ext-gemini-implement-attempt-${ATTEMPT}.log"
  mkdir -p "$LOG_DIR"

  local start_time
  start_time=$(date +%s)

  # Read prompt and invoke Gemini CLI in non-interactive mode
  local prompt_content
  prompt_content=$(cat "$PROMPT_FILE")

  local exit_code=0
  safe_invoke "$TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i HOME="$HOME" PATH="$PATH" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --yolo \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      --include-directories "$WORKTREE" \
      "$prompt_content" \
    || exit_code=$?

  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  cp "$stdout_file" "$raw_log" 2>/dev/null || true

  if [ $exit_code -ne 0 ]; then
    local error_type
    error_type=$(classify_error "$exit_code" "$stderr_file")
    log_session "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" "failure" \
      '{"input_tokens":0,"output_tokens":0}' "$duration"
    emit_error "$TOOL_NAME" "implement" "$error_type" "$exit_code" "$DEFAULT_MODEL" "$ATTEMPT" "$raw_log"
    return 1
  fi

  # Commit any changes
  git -C "$WORKTREE" add -A 2>/dev/null || true
  local git_sha=""
  if ! git -C "$WORKTREE" diff --cached --quiet 2>/dev/null; then
    git -C "$WORKTREE" commit -m "external(gemini): implement attempt ${ATTEMPT}" --no-verify 2>/dev/null || true
    git_sha=$(git -C "$WORKTREE" rev-parse --short HEAD 2>/dev/null || echo "")
  fi

  verify_scope "$WORKTREE" "$CONTEXT_DIR" || true

  local branch_name
  branch_name=$(git -C "$WORKTREE" branch --show-current 2>/dev/null || echo "")
  local files_changed
  files_changed=$(get_changed_files "$WORKTREE")
  local diff_stats
  diff_stats=$(get_diff_stats "$WORKTREE")
  local cost
  cost=$(extract_cost_gemini "$raw_log")

  log_session "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" "success" "$cost" "$duration"

  emit_json "$TOOL_NAME" "implement" "$DEFAULT_MODEL" "$ATTEMPT" 0 \
    "$branch_name" "$git_sha" "$files_changed" "$diff_stats" \
    "$duration" "$cost" "$raw_log" "null"
}

# --- Review ---
cmd_review() {
  parse_args "$@"

  if [ -z "$WORKTREE" ] || [ -z "$RUBRIC_FILE" ] || [ -z "$SPEC_FILE" ]; then
    echo "ERROR: --worktree, --rubric-file, and --spec-file are required" >&2
    emit_error "$TOOL_NAME" "review" "tool_crash" 1
    return 1
  fi

  local secure_tmp
  secure_tmp=$(create_secure_tmp)
  trap "rm -rf $secure_tmp" EXIT

  local stdout_file="${secure_tmp}/stdout.json"
  local stderr_file="${secure_tmp}/stderr.log"
  local raw_log="${LOG_DIR}/ext-gemini-review-attempt-${ATTEMPT}.log"
  mkdir -p "$LOG_DIR"

  # Build review prompt with diff, rubric, and spec
  local diff_content rubric_content spec_content
  diff_content=$(git -C "$WORKTREE" diff HEAD~1 2>/dev/null || git -C "$WORKTREE" diff HEAD 2>/dev/null || echo "No changes detected")
  rubric_content=$(cat "$RUBRIC_FILE")
  spec_content=$(cat "$SPEC_FILE")

  local review_prompt
  review_prompt=$(cat <<PROMPT
You are an adversarial code reviewer. Review the following code changes against the spec and rubric.

## Rubric
${rubric_content}

## Spec
${spec_content}

## Code Changes (diff)
\`\`\`diff
${diff_content}
\`\`\`

Provide your review with:
1. A clear PASS or FAIL verdict
2. For each finding, cite the specific file:line
3. Classify each finding as BLOCKING (causes FAIL) or WARNING (does not cause FAIL)
PROMPT
  )

  local start_time
  start_time=$(date +%s)

  # Gemini review uses sandbox mode (no file edits)
  local exit_code=0
  safe_invoke "$TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i HOME="$HOME" PATH="$PATH" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --sandbox \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      "$review_prompt" \
    || exit_code=$?

  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  cp "$stdout_file" "$raw_log" 2>/dev/null || true

  if [ $exit_code -ne 0 ]; then
    local error_type
    error_type=$(classify_error "$exit_code" "$stderr_file")
    log_session "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" "failure" \
      '{"input_tokens":0,"output_tokens":0}' "$duration"
    emit_error "$TOOL_NAME" "review" "$error_type" "$exit_code" "$DEFAULT_MODEL" "$ATTEMPT" "$raw_log"
    return 1
  fi

  local cost
  cost=$(extract_cost_gemini "$raw_log")

  log_session "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" "success" "$cost" "$duration"

  local files_changed
  files_changed=$(get_changed_files "$WORKTREE")
  local diff_stats
  diff_stats=$(get_diff_stats "$WORKTREE")
  local branch_name
  branch_name=$(git -C "$WORKTREE" branch --show-current 2>/dev/null || echo "")

  emit_json "$TOOL_NAME" "review" "$DEFAULT_MODEL" "$ATTEMPT" 0 \
    "$branch_name" "" "$files_changed" "$diff_stats" \
    "$duration" "$cost" "$raw_log" "null"
}

# --- Main Dispatch ---
case "${1:-}" in
  health)     cmd_health ;;
  implement)  shift; cmd_implement "$@" ;;
  review)     shift; cmd_review "$@" ;;
  *)
    echo "Usage: gemini.sh {health|implement|review} [options]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  health                          Check if Gemini CLI is ready" >&2
    echo "  implement --worktree <p> ...    Implement code on a branch" >&2
    echo "  review --worktree <p> ...       Review code changes" >&2
    exit 1
    ;;
esac
```

**Step 2: Make executable and verify syntax**

Run: `chmod +x skills/external-tools/adapters/gemini.sh && bash -n skills/external-tools/adapters/gemini.sh`
Expected: No output (valid syntax)

**Step 3: Test health command**

Run: `skills/external-tools/adapters/gemini.sh health`
Expected: JSON with status

**Step 4: Verify both adapters have identical output schema**

Run:
```bash
codex_keys=$(skills/external-tools/adapters/codex.sh health | jq -S 'keys')
gemini_keys=$(skills/external-tools/adapters/gemini.sh health | jq -S 'keys')
diff <(echo "$codex_keys") <(echo "$gemini_keys")
```
Expected: No diff (same JSON keys)

**Step 5: Commit**

```bash
git add skills/external-tools/adapters/gemini.sh
git commit -m "feat(external-tools): add Gemini CLI adapter

Implements health, implement, and review commands with timeout wrapping,
minimal environment, scope verification, and structured JSON output."
```

---

### Task 7: Write the External Tool Review Rubric

**Files:**
- Create: `.claude/rubrics/external-tool-review-rubric.md`

**Step 1: Write the rubric**

Create `.claude/rubrics/external-tool-review-rubric.md`:

```markdown
# External Tool Cross-Model Review Rubric

**Used By**: External tool adapters (Codex CLI, Gemini CLI, Claude) acting as adversarial reviewers
**Purpose**: Evaluate code changes produced by a different AI model against the task spec
**Version**: 1.0

---

## Overview

This rubric is used when one AI model reviews code written by a different AI model.
The reviewer has no shared context with the writer — it sees only the diff, spec, and
this rubric. The reviewer must be adversarial: assume nothing works until proven otherwise.

## Verdict

| Verdict | Meaning | Criteria |
|---------|---------|----------|
| **PASS** | Code meets the spec | All acceptance criteria satisfied, no BLOCKING issues found |
| **FAIL** | Code does not meet the spec | One or more BLOCKING issues found |

## Issue Classification

| Classification | Meaning | Impact |
|----------------|---------|--------|
| **BLOCKING** | Contract violation, missing requirement, broken functionality | Causes FAIL |
| **WARNING** | Style issue, minor improvement, non-critical concern | Does NOT cause FAIL |

## Review Checklist

The reviewer MUST check each of these against the spec:

### 1. Acceptance Criteria Coverage
- [ ] Every acceptance criterion in the spec has corresponding code
- [ ] No criterion is partially implemented or stubbed out

### 2. Functional Correctness
- [ ] Logic handles the stated requirements
- [ ] Edge cases mentioned in the spec are handled
- [ ] Error paths produce reasonable behavior (not crashes or silent failures)

### 3. Test Coverage
- [ ] Tests exist for the new/changed functionality
- [ ] Tests actually assert the acceptance criteria (not just smoke tests)
- [ ] Tests would fail if the implementation were removed (not tautological)

### 4. Scope Discipline
- [ ] Changes are limited to what the spec requires (no gold-plating)
- [ ] No unrelated refactoring or formatting changes
- [ ] No new dependencies added without justification in the spec

### 5. Security (BLOCKING if violated)
- [ ] No hardcoded secrets, credentials, or API keys
- [ ] No command injection, SQL injection, or XSS vectors
- [ ] No unsafe file operations (path traversal, world-writable files)

## Evidence Requirements

Every finding (BLOCKING or WARNING) MUST include:
- **File and line reference**: `src/auth/login.ts:42`
- **What is wrong**: Specific description of the issue
- **What the spec requires**: Quote the relevant acceptance criterion

## Output Format

```markdown
## Cross-Model Review: [task-id]

### Verdict: PASS | FAIL

### Acceptance Criteria Verification
| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | [criterion text] | PASS/FAIL | [file:line reference] |

### BLOCKING Issues
1. **[issue-title]**: [description] (`file:line`) — Spec requires: "[quoted criterion]"

### WARNINGS
1. **[issue-title]**: [description] (`file:line`)
```
```

**Step 2: Verify the rubric follows existing rubric conventions**

Run: Compare structure with existing rubric:
```bash
head -20 .claude/rubrics/adversarial-review-rubric.md
head -20 .claude/rubrics/external-tool-review-rubric.md
```
Expected: Similar structure (header, verdict table, classification table, output format)

**Step 3: Commit**

```bash
git add .claude/rubrics/external-tool-review-rubric.md
git commit -m "feat(external-tools): add cross-model review rubric

Binary PASS/FAIL verdict with BLOCKING/WARNING classification,
file:line evidence requirements, and spec-anchored findings."
```

---

### Task 8: Write the Orchestration Skill

**Files:**
- Create: `skills/external-tools/SKILL.md`

**Step 1: Write the skill definition**

Create `skills/external-tools/SKILL.md`:

````markdown
---
name: external-tools
description: Delegate implementation and review tasks to external AI CLI tools (Codex, Gemini) with cross-model adversarial review
auto_activate: false
triggers:
  - "use external tools"
  - "delegate to codex"
  - "delegate to gemini"
  - "cross-model review"
---

# External Tools: Cross-Model Delegation & Adversarial Review

## Purpose

Delegate coding tasks to external AI CLI tools (OpenAI Codex, Google Gemini) and use cross-model adversarial review — the writer is always reviewed by different models. External tools do ONE job per invocation (implement OR review), never self-validate. The orchestrator verifies everything independently through the existing 4-phase loop.

## Prerequisites

- At least one external tool installed and authenticated:
  - Codex CLI: `npm i -g @openai/codex` + `OPENAI_API_KEY` or `codex login`
  - Gemini CLI: `npm i -g @google/gemini-cli` + `GEMINI_API_KEY` or Google login
- Config file (optional): `.metaswarm/external-tools.yaml` — see `templates/external-tools.yaml`
- If no external tools are available, this skill is skipped entirely (pure metaswarm behavior)

## Quick Reference

```bash
# Check which tools are available
skills/external-tools/adapters/codex.sh health
skills/external-tools/adapters/gemini.sh health

# Implement a task (called by orchestrator, not manually)
skills/external-tools/adapters/codex.sh implement \
  --worktree <path> --prompt-file <path> [--attempt N] [--timeout 300]

# Review code changes (called by orchestrator, not manually)
skills/external-tools/adapters/codex.sh review \
  --worktree <path> --rubric-file <path> --spec-file <path> [--timeout 300]
```

## Workflow: Routing & Dispatch

### Phase 0: Tool Discovery

Before dispatching any work unit to an external tool, the orchestrator MUST:

1. Run `adapters/codex.sh health` and `adapters/gemini.sh health`
2. Parse JSON output — only tools with `"status": "ready"` are available
3. Determine the escalation chain based on availability:

| Available Tools | Escalation Chain | Max Attempts |
|-----------------|-----------------|--------------|
| Codex + Gemini | Model A (2) → Model B (2) → Claude (1) → User | 5 |
| One tool only | Model A (2) → Claude (1) → User | 3 |
| None | Claude only (existing behavior, no change) | N/A |

The cheapest available tool is the default implementer. Claude is always the final escalation before the user.

### Phase 1: IMPLEMENT (via external tool)

When the orchestrator decides to use an external tool for implementation:

1. **Create a worktree**: `git worktree add /tmp/ext-<tool>-<task-id> -b external/<tool>/<task-id>`
2. **Package context** into a prompt file (see Prompt File Format below)
3. **Invoke the adapter**: `adapters/<tool>.sh implement --worktree ... --prompt-file ... --attempt N`
4. **Parse the JSON output** — check `exit_code` and `error_type`
5. **Verify scope** — the adapter does this automatically, but the orchestrator should confirm

The adapter returns facts only (files changed, diff stats, cost). It does NOT return a verdict — the orchestrator determines success/failure via Phase 2 and Phase 3.

### Phase 2: VALIDATE (orchestrator, unchanged)

The orchestrator runs validation independently, exactly as it does for Claude-implemented code:

- `npm test` / `npm run lint` / `npm run test:coverage`
- Type checking, scope verification
- PASS/FAIL decision made by the orchestrator

### Phase 3: ADVERSARIAL REVIEW (cross-model)

The orchestrator dispatches review to the OTHER models:

| Writer | Reviewer 1 | Reviewer 2 |
|--------|------------|------------|
| Codex | Gemini (`adapters/gemini.sh review`) | Claude (`Task()`) |
| Gemini | Codex (`adapters/codex.sh review`) | Claude (`Task()`) |
| Claude | Codex (`adapters/codex.sh review`) | Gemini (`adapters/gemini.sh review`) |

If only one external tool is available, the review pair is that tool + Claude.

The orchestrator reads each reviewer's raw log, evaluates the findings, and makes the PASS/FAIL decision. The reviewer's self-reported verdict is informational, not authoritative.

### Phase 4: COMMIT (unchanged)

On PASS: merge the external branch, cleanup the worktree, log the session.
On FAIL: feed review findings back to the writer for retry (or escalate).

## Escalation Chain

### Two external tools available:

```
Model A implements (attempt 1)
  → Orchestrator validates (Phase 2) + cross-model review (Phase 3)
  → FAIL: feedback to Model A

Model A implements (attempt 2, with review feedback in prompt)
  → Orchestrator validates + cross-model review
  → FAIL: escalate to Model B

Model B implements (attempt 1, with Model A's branch as reference)
  → Orchestrator validates + cross-model review
  → FAIL: feedback to Model B

Model B implements (attempt 2, with review feedback)
  → Orchestrator validates + cross-model review
  → FAIL: escalate to Claude

Claude implements (with both branches as reference)
  → Orchestrator validates + cross-model review (Model A + Model B review)
  → FAIL: alert user with all branches, findings, CI results
```

### One external tool available:

```
Model A implements (attempt 1)
  → Orchestrator validates + Claude reviews
  → FAIL: feedback to Model A

Model A implements (attempt 2)
  → Orchestrator validates + Claude reviews
  → FAIL: escalate to Claude

Claude implements (with Model A's branch as reference)
  → Orchestrator validates + Model A reviews
  → FAIL: alert user
```

## Prompt File Format

The prompt file is the key interface. It must be self-contained — the external tool has no access to BEADS, the knowledge base, or conversation history.

```markdown
# Task: [task title]

## Acceptance Criteria
- [ ] criterion 1
- [ ] criterion 2
- [ ] criterion 3

## Context
[relevant source files, token-budgeted — prioritize: changed files > test files > imports]

## Coding Standards
[extracted from project's CLAUDE.md or coding-standards guide]

## Test Expectations
[what tests should pass, coverage requirements]

## Previous Attempt (on retry only)
[review feedback from last attempt — specific issues to fix]

## Prior Model's Attempt (on escalation only)
[diff summary from prior model's branch — what was tried, what failed and why]
```

## Error Handling

The adapter returns structured error types. The orchestrator responds based on the error:

| Error Type | Orchestrator Action |
|---|---|
| `tool_not_installed` | Skip this adapter, use next in escalation chain |
| `auth_expired` / `auth_missing` | Alert user: "Codex/Gemini auth needs renewal" |
| `network_error` | Retry once with 30s backoff, then skip |
| `rate_limited` | Wait 60s, retry once, then skip |
| `timeout` | Retry once with 1.5x timeout, then skip |
| `context_too_large` | Reduce context (fewer files), retry once |
| `cost_limit_exceeded` | Alert user: "Budget exceeded for this task" |
| `tool_crash` | Retry once, then skip |
| `output_parse_error` | Log raw output, treat as failure |

## Budget Enforcement

If `.metaswarm/external-tools.yaml` defines budget limits:
- Track cumulative cost across all adapter invocations in the session
- Before each invocation, check if budget remains
- If `per_task_usd` exceeded: skip remaining retries, escalate immediately
- If `per_session_usd` exceeded: disable external tools for the rest of the session

## Anti-Patterns

1. **Trusting external tool self-reports** — NEVER use the tool's output to determine PASS/FAIL. The orchestrator validates and reviews independently.
2. **Skipping cross-model review** — Every implementation MUST be reviewed by at least one different model. This is the entire point of the system.
3. **Running without timeout** — Always use the adapter's `--timeout` flag. External tools can hang indefinitely on rate limits.
4. **Passing full environment** — Adapters use `env -i` to strip all env vars except the tool's own API key. Never leak credentials.
5. **Working in the main repo** — Always use worktrees. Never let external tools modify the primary working directory.

## Logging

All adapter invocations are logged to `~/.claude/sessions/external-tools.jsonl`. This feeds the self-reflection pipeline (`/self-reflect`) to accumulate learnings like:

- "Codex excels at single-file TypeScript implementations"
- "Gemini tends to skip error handling in async functions"
- "Route database migration tasks directly to Claude"
````

**Step 2: Verify YAML front matter parses correctly**

Run: `head -8 skills/external-tools/SKILL.md`
Expected: Valid YAML between `---` delimiters

**Step 3: Commit**

```bash
git add skills/external-tools/SKILL.md
git commit -m "feat(external-tools): add orchestration skill

Defines routing, escalation, 4-phase loop integration, prompt file format,
error handling, budget enforcement, and anti-patterns."
```

---

### Task 9: Write the Setup Guide

**Files:**
- Create: `templates/external-tools-setup.md`

**Step 1: Write the setup guide**

Create `templates/external-tools-setup.md`:

```markdown
# External Tools Setup Guide

This guide helps you install and configure external AI CLI tools for use with
metaswarm's cross-model delegation and adversarial review system.

## Overview

metaswarm can delegate implementation and review tasks to external AI models,
enabling cost savings and cross-model adversarial review. Supported tools:

| Tool | Cost | Best For |
|------|------|----------|
| OpenAI Codex CLI | ChatGPT subscription or API key | Fast implementation, structured output |
| Google Gemini CLI | Free (1K req/day with Google login) | Cost-effective review, large context |

You can install one or both. metaswarm adapts automatically based on what's available.

## 1. Install OpenAI Codex CLI

```bash
npm install -g @openai/codex
```

**Verify**: `codex --version`

### Authentication (choose one):

**Option A: API Key (recommended for scripting)**
```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc):
export OPENAI_API_KEY="sk-your-key-here"
# Get a key at: https://platform.openai.com/api-keys
```

**Option B: ChatGPT Subscription Login**
```bash
codex login --device-auth
# Follow browser prompts. Works with Plus ($20/mo) or Pro ($200/mo).
```

**Verify auth**: `codex login status` (exit code 0 = logged in)

**Smoke test**:
```bash
codex exec "print hello world in python" --ephemeral
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `command not found: codex` | Ensure npm global bin is in PATH: `npm bin -g` |
| `rate_limit_exceeded` | Upgrade plan or wait. Free/Go plans have low limits. |
| Hangs indefinitely | Update to latest version: `npm update -g @openai/codex` |

## 2. Install Google Gemini CLI

```bash
npm install -g @google/gemini-cli
```

**Verify**: `gemini --version`

### Authentication (choose one):

**Option A: Google Account Login (recommended — free, high limits)**
```bash
gemini
# Select "Login with Google" → complete browser OAuth
# Gets you 1,000 requests/day, 60/min with Gemini 2.5 Pro
```

**Option B: API Key**
```bash
# Add to your shell profile:
export GEMINI_API_KEY="AIza-your-key-here"
# Get a key at: https://aistudio.google.com/app/apikey
# Note: Free API key tier is limited to 250 req/day, Flash model only
```

**Smoke test**:
```bash
gemini "print hello world in python" --output-format json | jq .response
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `command not found: gemini` | Ensure npm global bin is in PATH |
| Rate limit loop (CLI freezes) | Ctrl+C, wait a few minutes, try again |
| Node.js version error | Gemini CLI requires Node.js 20+: `node --version` |

## 3. Configure metaswarm

Copy the example config to your project:

```bash
mkdir -p .metaswarm
cp /path/to/metaswarm/templates/external-tools.yaml .metaswarm/external-tools.yaml
```

Edit `.metaswarm/external-tools.yaml` to:
- Enable/disable specific tools
- Set timeout and sandbox preferences
- Configure cost budgets

If this file is absent, metaswarm works normally without external tools.

## 4. Verify Setup

Run health checks for all installed tools:

```bash
# From your metaswarm installation:
skills/external-tools/adapters/codex.sh health | jq .
skills/external-tools/adapters/gemini.sh health | jq .
```

Both should show `"status": "ready"`. If a tool shows `"unavailable"`, check auth.

## 5. How It Works

Once configured, the orchestrator automatically:
1. Checks which tools are available (health check per task)
2. Routes simple tasks to the cheapest available tool
3. Has the other models review the output (cross-model adversarial review)
4. Escalates through the chain if a tool fails: Model A → Model B → Claude → You

You do not need to manually invoke adapters. The orchestrated execution skill
handles routing, context packaging, review dispatch, and escalation automatically.
```

**Step 2: Commit**

```bash
git add templates/external-tools-setup.md
git commit -m "docs(external-tools): add setup guide for Codex and Gemini CLI

Covers installation, authentication, configuration, verification, and
troubleshooting for both tools."
```

---

### Task 10: Add Slash Command for External Tools

**Files:**
- Create: `.claude/commands/external-tools-health.md`

**Step 1: Write the slash command**

Create `.claude/commands/external-tools-health.md`:

```markdown
# External Tools Health Check

Run health checks on all configured external AI tools and report their status.

## Steps

1. Run `skills/external-tools/adapters/codex.sh health` and capture JSON output
2. Run `skills/external-tools/adapters/gemini.sh health` and capture JSON output
3. Report status of each tool (ready/unavailable) with version and auth info
4. If any tools are unavailable, suggest setup steps from `templates/external-tools-setup.md`
5. Check for `.metaswarm/external-tools.yaml` config file — report if present and summarize settings
```

**Step 2: Commit**

```bash
git add .claude/commands/external-tools-health.md
git commit -m "feat(external-tools): add /external-tools-health slash command"
```

---

### Task 11: Update CLAUDE.md Template with External Tools Reference

**Files:**
- Modify: `templates/CLAUDE.md`

**Step 1: Read the current CLAUDE.md template**

Run: Read `templates/CLAUDE.md` to find where to add the external tools reference.

**Step 2: Add external tools section**

Add to the "Available Commands" section:
```markdown
- `/external-tools-health` — Check status of external AI tools (Codex, Gemini)
```

Add a new section after "Quality Gates":
```markdown
## External Tools (Optional)

If external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator
can delegate implementation and review tasks to Codex CLI and Gemini CLI for cost savings
and cross-model adversarial review. See `templates/external-tools-setup.md` for setup.
```

**Step 3: Commit**

```bash
git add templates/CLAUDE.md
git commit -m "docs: reference external-tools in CLAUDE.md template"
```

---

### Task 12: End-to-End Verification Script

**Files:**
- Create: `bin/external-tools-verify.sh`

**Step 1: Write the verification script**

Create `bin/external-tools-verify.sh`:

```bash
#!/bin/bash
# external-tools-verify.sh — Verify external tool adapters work end-to-end
# Usage: bin/external-tools-verify.sh
# Returns: 0 if all checks pass, 1 if any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTERS_DIR="${REPO_ROOT}/skills/external-tools/adapters"

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  if [ "$result" = "0" ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== External Tools Verification ==="
echo ""

# --- _common.sh ---
echo "--- _common.sh helpers ---"

bash -n "${ADAPTERS_DIR}/_common.sh"
check "_common.sh syntax valid" $?

source "${ADAPTERS_DIR}/_common.sh"

# Test create_secure_tmp
tmpdir=$(create_secure_tmp)
perms=$(stat -f "%OLp" "$tmpdir" 2>/dev/null || stat -c "%a" "$tmpdir" 2>/dev/null)
rm -rf "$tmpdir"
[ "$perms" = "700" ] && check "create_secure_tmp permissions" 0 || check "create_secure_tmp permissions" 1

# Test classify_error
echo "rate limit exceeded" > /tmp/xt-test-stderr.txt
result=$(classify_error 1 /tmp/xt-test-stderr.txt)
rm -f /tmp/xt-test-stderr.txt
[ "$result" = "rate_limited" ] && check "classify_error: rate_limited" 0 || check "classify_error: rate_limited" 1

result=$(classify_error 124 /dev/null)
[ "$result" = "timeout" ] && check "classify_error: timeout" 0 || check "classify_error: timeout" 1

result=$(classify_error 127 /dev/null)
[ "$result" = "tool_not_installed" ] && check "classify_error: tool_not_installed" 0 || check "classify_error: tool_not_installed" 1

# Test emit_error produces valid JSON
output=$(emit_error "test" "implement" "timeout" 124)
echo "$output" | jq . >/dev/null 2>&1
check "emit_error produces valid JSON" $?

echo ""

# --- Codex Adapter ---
echo "--- Codex adapter ---"

bash -n "${ADAPTERS_DIR}/codex.sh"
check "codex.sh syntax valid" $?

health_output=$("${ADAPTERS_DIR}/codex.sh" health)
echo "$health_output" | jq . >/dev/null 2>&1
check "codex health produces valid JSON" $?

codex_status=$(echo "$health_output" | jq -r '.status')
echo "  INFO: Codex status = ${codex_status}"

echo ""

# --- Gemini Adapter ---
echo "--- Gemini adapter ---"

bash -n "${ADAPTERS_DIR}/gemini.sh"
check "gemini.sh syntax valid" $?

health_output=$("${ADAPTERS_DIR}/gemini.sh" health)
echo "$health_output" | jq . >/dev/null 2>&1
check "gemini health produces valid JSON" $?

gemini_status=$(echo "$health_output" | jq -r '.status')
echo "  INFO: Gemini status = ${gemini_status}"

echo ""

# --- Config Template ---
echo "--- Configuration ---"

[ -f "${REPO_ROOT}/templates/external-tools.yaml" ]
check "external-tools.yaml template exists" $?

echo ""

# --- Summary ---
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
```

**Step 2: Make executable and run**

Run: `chmod +x bin/external-tools-verify.sh && bin/external-tools-verify.sh`
Expected: All checks PASS

**Step 3: Commit**

```bash
git add bin/external-tools-verify.sh
git commit -m "test(external-tools): add end-to-end verification script

Validates _common.sh helpers, adapter syntax, health commands, JSON output,
and config template existence."
```

---

### Task 13: Final Integration Commit

**Step 1: Run the full verification**

Run: `bin/external-tools-verify.sh`
Expected: All checks pass

**Step 2: Verify git log shows clean commit history**

Run: `git log --oneline -15`
Expected: Clean series of commits for each task

**Step 3: Update the plan status**

Mark the plan as implemented in `docs/plans/2026-02-14-external-tools-design.md`:
Change `**Status**: Approved design` to `**Status**: Implemented (v1)`

**Step 4: Final commit**

```bash
git add docs/plans/2026-02-14-external-tools-design.md
git commit -m "docs: mark external-tools design as implemented (v1)"
```

---

## Summary

| Task | Files | Description |
|------|-------|-------------|
| 1 | (install) | Install and verify Codex CLI |
| 2 | (install) | Install and verify Gemini CLI |
| 3 | `templates/external-tools.yaml` | Directory structure + config template |
| 4 | `adapters/_common.sh` | Core safety + context helpers |
| 5 | `adapters/codex.sh` | Codex CLI adapter (health/implement/review) |
| 6 | `adapters/gemini.sh` | Gemini CLI adapter (health/implement/review) |
| 7 | `.claude/rubrics/external-tool-review-rubric.md` | Cross-model review rubric |
| 8 | `skills/external-tools/SKILL.md` | Orchestration skill definition |
| 9 | `templates/external-tools-setup.md` | User setup guide |
| 10 | `.claude/commands/external-tools-health.md` | Slash command |
| 11 | `templates/CLAUDE.md` | Add external tools reference |
| 12 | `bin/external-tools-verify.sh` | End-to-end verification script |
| 13 | (integration) | Final verification + status update |
