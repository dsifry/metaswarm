#!/bin/bash
# gemini.sh — Google Gemini CLI adapter for external-tools
#
# Implements: health, implement, review
# Requires:  gemini CLI (https://github.com/google-gemini/gemini-cli)
#
# Usage:
#   gemini.sh health
#   gemini.sh implement --worktree <path> --prompt-file <path> [--context-dir <dir>] [--timeout <secs>] [--attempt <n>]
#   gemini.sh review   --worktree <path> --rubric-file <path> --spec-file <path> [--timeout <secs>] [--attempt <n>]

set -euo pipefail

# ---------------------------------------------------------------------------
# Source shared helpers
# ---------------------------------------------------------------------------
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TOOL_NAME="gemini"
TOOL_CMD="gemini"
DEFAULT_MODEL="pro"

# =========================================================================
# health — Preflight check
# =========================================================================
cmd_health() {
  local status="ready"
  local version="unknown"
  local auth_valid=false

  # Check if gemini binary exists
  if ! command -v "$TOOL_CMD" >/dev/null 2>&1; then
    printf '{"tool":"%s","status":"unavailable","version":"not_installed","auth_valid":false,"model":"%s"}\n' \
      "$TOOL_NAME" "$DEFAULT_MODEL"
    return 0
  fi

  # Get version
  version="$("$TOOL_CMD" --version 2>/dev/null || printf 'unknown')"
  # Clean up version string — take first line, strip whitespace
  version="$(printf '%s' "$version" | head -1 | tr -d '\n\r')"

  # Check authentication
  # Method 1: GEMINI_API_KEY environment variable
  if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    auth_valid=true
  fi

  # Method 2: Google login credentials in ~/.gemini/
  if [[ -d "${HOME}/.gemini" ]]; then
    auth_valid=true
  fi

  # Method 3: Google Application Default Credentials
  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
    auth_valid=true
  fi

  # If auth is not valid, mark as unavailable
  if [[ "$auth_valid" == "false" ]]; then
    status="unavailable"
  fi

  # Emit health JSON
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg tool "$TOOL_NAME" \
      --arg status "$status" \
      --arg version "$version" \
      --argjson auth_valid "$auth_valid" \
      --arg model "$DEFAULT_MODEL" \
      '{tool: $tool, status: $status, version: $version, auth_valid: $auth_valid, model: $model}'
  else
    printf '{"tool":"%s","status":"%s","version":"%s","auth_valid":%s,"model":"%s"}\n' \
      "$TOOL_NAME" "$status" "$version" "$auth_valid" "$DEFAULT_MODEL"
  fi
}

# =========================================================================
# implement — Write code on a worktree branch
# =========================================================================
cmd_implement() {
  parse_args "$@"

  # Validate required arguments
  if [[ -z "$XT_WORKTREE" ]]; then
    printf 'Error: --worktree is required for implement\n' >&2
    return 1
  fi
  if [[ -z "$XT_PROMPT_FILE" ]]; then
    printf 'Error: --prompt-file is required for implement\n' >&2
    return 1
  fi
  if [[ ! -f "$XT_PROMPT_FILE" ]]; then
    printf 'Error: prompt file not found: %s\n' "$XT_PROMPT_FILE" >&2
    return 1
  fi
  if [[ ! -d "$XT_WORKTREE" ]]; then
    printf 'Error: worktree directory not found: %s\n' "$XT_WORKTREE" >&2
    return 1
  fi

  # Create secure temp directory for output capture
  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.json"
  local stderr_file="${tmp_dir}/stderr.log"

  # Read prompt file content
  local prompt_content
  prompt_content="$(cat "$XT_PROMPT_FILE")"

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke gemini with minimal environment
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --yolo \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      --include-directories "$XT_WORKTREE" \
      "$prompt_content" \
    || exit_code=$?

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to log directory
  mkdir -p "$LOG_DIR"
  local log_timestamp
  log_timestamp="$(date +%Y%m%dT%H%M%S)"
  local raw_log_file="${LOG_DIR}/${TOOL_NAME}-implement-${log_timestamp}.json"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  # Handle errors
  if [[ "$exit_code" -ne 0 ]]; then
    local error_type
    error_type="$(classify_error "$exit_code" "$stderr_file")"

    local result
    result="$(emit_error \
      "$TOOL_NAME" \
      "implement" \
      "$DEFAULT_MODEL" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"

    log_session "$result"
    printf '%s\n' "$result"

    # Cleanup temp dir
    rm -rf "$tmp_dir"
    return 1
  fi

  # Success — commit changes in worktree
  local branch=""
  local git_sha=""

  branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"

  # Stage all changes and commit
  git -C "$XT_WORKTREE" add -A 2>/dev/null || true
  git -C "$XT_WORKTREE" commit -m "${TOOL_NAME}: implement (attempt ${XT_ATTEMPT})" --allow-empty 2>/dev/null || true

  git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"

  # Verify scope — revert out-of-scope changes if context_dir is set
  local scope_clean=0
  verify_scope "$XT_WORKTREE" "$XT_CONTEXT_DIR" || scope_clean=$?
  if [[ "$scope_clean" -ne 0 ]]; then
    # Re-commit after reverting out-of-scope files
    git -C "$XT_WORKTREE" add -A 2>/dev/null || true
    git -C "$XT_WORKTREE" commit -m "${TOOL_NAME}: implement (attempt ${XT_ATTEMPT}) — scope-trimmed" --allow-empty 2>/dev/null || true
    git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"
  fi

  # Extract cost/stats
  local cost
  cost="$(extract_cost_gemini "$stdout_file")"

  local diff_stats
  diff_stats="$(get_diff_stats "$XT_WORKTREE")"

  local files_changed
  files_changed="$(get_changed_files "$XT_WORKTREE")"

  # Emit structured JSON output
  local result
  result="$(emit_json \
    "$TOOL_NAME" \
    "implement" \
    "$DEFAULT_MODEL" \
    "$XT_ATTEMPT" \
    "$exit_code" \
    "$branch" \
    "$git_sha" \
    "$files_changed" \
    "$diff_stats" \
    "$duration" \
    "$cost" \
    "$raw_log_file")"

  log_session "$result"
  printf '%s\n' "$result"

  # Cleanup temp dir
  rm -rf "$tmp_dir"
}

# =========================================================================
# review — Review code changes (sandboxed)
# =========================================================================
cmd_review() {
  parse_args "$@"

  # Validate required arguments
  if [[ -z "$XT_WORKTREE" ]]; then
    printf 'Error: --worktree is required for review\n' >&2
    return 1
  fi
  if [[ -z "$XT_RUBRIC_FILE" ]]; then
    printf 'Error: --rubric-file is required for review\n' >&2
    return 1
  fi
  if [[ -z "$XT_SPEC_FILE" ]]; then
    printf 'Error: --spec-file is required for review\n' >&2
    return 1
  fi
  if [[ ! -f "$XT_RUBRIC_FILE" ]]; then
    printf 'Error: rubric file not found: %s\n' "$XT_RUBRIC_FILE" >&2
    return 1
  fi
  if [[ ! -f "$XT_SPEC_FILE" ]]; then
    printf 'Error: spec file not found: %s\n' "$XT_SPEC_FILE" >&2
    return 1
  fi
  if [[ ! -d "$XT_WORKTREE" ]]; then
    printf 'Error: worktree directory not found: %s\n' "$XT_WORKTREE" >&2
    return 1
  fi

  # Create secure temp directory
  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.json"
  local stderr_file="${tmp_dir}/stderr.log"

  # Gather git diff from worktree
  local diff_content
  diff_content="$(git -C "$XT_WORKTREE" diff HEAD 2>/dev/null || printf '')"
  if [[ -z "$diff_content" ]]; then
    # Try diff against parent commit
    diff_content="$(git -C "$XT_WORKTREE" diff HEAD~1 HEAD 2>/dev/null || printf '')"
  fi

  # Read rubric and spec
  local rubric_content
  rubric_content="$(cat "$XT_RUBRIC_FILE")"
  local spec_content
  spec_content="$(cat "$XT_SPEC_FILE")"

  # Build review prompt
  local review_prompt
  review_prompt="$(cat <<PROMPT_EOF
You are a code reviewer. Review the following code changes against the specification and rubric.

## Specification
${spec_content}

## Review Rubric
${rubric_content}

## Code Diff
\`\`\`diff
${diff_content}
\`\`\`

## Instructions
1. Evaluate the diff against the specification and rubric.
2. For each issue found, provide:
   - file:line citation
   - Classification: BLOCKING or WARNING
   - Description of the issue
3. Provide a final verdict: PASS or FAIL
   - FAIL if any BLOCKING issues exist
   - PASS if only WARNING issues or no issues

Respond in JSON format:
{
  "verdict": "PASS|FAIL",
  "issues": [
    {
      "file": "path/to/file",
      "line": 42,
      "classification": "BLOCKING|WARNING",
      "description": "Description of the issue"
    }
  ],
  "summary": "Brief overall assessment"
}
PROMPT_EOF
)"

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke gemini in sandbox mode
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --sandbox \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      "$review_prompt" \
    || exit_code=$?

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to log directory
  mkdir -p "$LOG_DIR"
  local log_timestamp
  log_timestamp="$(date +%Y%m%dT%H%M%S)"
  local raw_log_file="${LOG_DIR}/${TOOL_NAME}-review-${log_timestamp}.json"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  # Handle errors
  if [[ "$exit_code" -ne 0 ]]; then
    local result
    result="$(emit_error \
      "$TOOL_NAME" \
      "review" \
      "$DEFAULT_MODEL" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"

    log_session "$result"
    printf '%s\n' "$result"

    # Cleanup temp dir
    rm -rf "$tmp_dir"
    return 1
  fi

  # Extract cost
  local cost
  cost="$(extract_cost_gemini "$stdout_file")"

  # For review, get branch/sha from the worktree being reviewed
  local branch=""
  local git_sha=""
  branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"

  # Emit structured JSON output
  local result
  result="$(emit_json \
    "$TOOL_NAME" \
    "review" \
    "$DEFAULT_MODEL" \
    "$XT_ATTEMPT" \
    "$exit_code" \
    "$branch" \
    "$git_sha" \
    "[]" \
    '{"additions": 0, "deletions": 0}' \
    "$duration" \
    "$cost" \
    "$raw_log_file")"

  log_session "$result"
  printf '%s\n' "$result"

  # Cleanup temp dir
  rm -rf "$tmp_dir"
}

# =========================================================================
# Command dispatch
# =========================================================================
command="${1:-}"
shift || true

case "$command" in
  health)
    cmd_health
    ;;
  implement)
    cmd_implement "$@"
    ;;
  review)
    cmd_review "$@"
    ;;
  *)
    cat <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  health      Check if Gemini CLI is installed and authenticated
  implement   Run Gemini to implement code in a worktree
  review      Run Gemini to review code changes (sandboxed)

Options (implement):
  --worktree <path>       Path to the git worktree (required)
  --prompt-file <path>    Path to the prompt file (required)
  --context-dir <dir>     Restrict changes to this directory
  --timeout <seconds>     Command timeout (default: 300)
  --attempt <n>           Attempt number (default: 1)

Options (review):
  --worktree <path>       Path to the git worktree (required)
  --rubric-file <path>    Path to the review rubric (required)
  --spec-file <path>      Path to the task specification (required)
  --timeout <seconds>     Command timeout (default: 300)
  --attempt <n>           Attempt number (default: 1)
USAGE
    exit 1
    ;;
esac
