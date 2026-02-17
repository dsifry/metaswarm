#!/bin/bash
# gemini.sh — Google Gemini CLI adapter for external-tools
#
# Implements: health, implement, review, status, cleanup
# Requires:  gemini CLI (https://github.com/google-gemini/gemini-cli)
#
# Usage:
#   gemini.sh health
#   gemini.sh implement --worktree <path> --prompt-file <path> [--context-dir <dir>] [--timeout <secs>] [--attempt <n>]
#   gemini.sh review   --worktree <path> --rubric-file <path> --spec-file <path> [--timeout <secs>] [--attempt <n>]
#   gemini.sh status   <worktree-path>
#   gemini.sh cleanup  <worktree-path> [--keep-branch]

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

  # Copy prompt file into worktree so Gemini can read it directly
  # (avoids shell argument length limits for large prompts)
  local worktree_prompt="${XT_WORKTREE}/.gemini-prompt.md"
  local real_prompt real_dest
  real_prompt="$(realpath "$XT_PROMPT_FILE" 2>/dev/null || printf '%s' "$XT_PROMPT_FILE")"
  real_dest="$(realpath "$worktree_prompt" 2>/dev/null || printf '%s' "$worktree_prompt")"
  if [[ "$real_prompt" != "$real_dest" ]]; then
    cp "$XT_PROMPT_FILE" "$worktree_prompt"
  fi

  # Write adapter PID file so agents can reliably check if we're alive.
  local adapter_pidfile="${XT_WORKTREE}/.gemini-adapter.pid"
  local child_pidfile="${XT_WORKTREE}/.gemini-child.pid"
  printf '%d\n' "$$" > "$adapter_pidfile"

  # Trap to clean up on unexpected exit (SIGTERM, SIGINT, etc.)
  _implement_cleanup() {
    local _child
    _child="$(cat "$child_pidfile" 2>/dev/null || true)"
    [[ -n "$_child" ]] && kill "$_child" 2>/dev/null || true
    rm -f "$adapter_pidfile" "$child_pidfile" "$worktree_prompt"
    rm -rf "$tmp_dir"
  }
  trap _implement_cleanup EXIT TERM INT

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke gemini with minimal environment — point it at the file instead of
  # passing prompt content as a shell argument.
  local exit_code=0
  SAFE_INVOKE_PIDFILE="$child_pidfile" \
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      TERM="${TERM:-dumb}" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --yolo \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      -C "$XT_WORKTREE" \
      "Read and follow all instructions in the file .gemini-prompt.md in the current directory. This file contains your complete task specification." \
    || exit_code=$?

  # Disable trap — we handle cleanup explicitly below
  trap - EXIT TERM INT

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to log directory
  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-implement-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.json"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  # Clean up prompt file and PID files from worktree (don't leave in commits)
  rm -f "$worktree_prompt" "$adapter_pidfile" "$child_pidfile"

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

    # Clean worktree so it can be removed without --force
    scrub_worktree "$XT_WORKTREE"

    # Cleanup temp dir
    rm -rf "$tmp_dir"
    return 1
  fi

  # Success — commit changes in worktree
  local branch=""
  local git_sha=""

  branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"

  # Recover from stale index.lock left by sandboxed Gemini.
  # Without this, git add silently fails and all work is lost.
  recover_git_index "$XT_WORKTREE"

  # Stage all changes and commit (only if there are actual changes)
  if ! git -C "$XT_WORKTREE" add -A 2>/dev/null; then
    printf '[adapter] WARNING: git add -A failed in %s\n' "$XT_WORKTREE" >&2
  fi
  if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
    if ! git -C "$XT_WORKTREE" commit -m "${TOOL_NAME}: implement (attempt ${XT_ATTEMPT})" \
      --author="Gemini CLI <gemini@google.com>" \
      >/dev/null 2>&1; then
      printf '[adapter] WARNING: git commit failed in %s\n' "$XT_WORKTREE" >&2
    fi
  fi

  git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"

  # Verify scope — revert out-of-scope changes if context_dir is set
  if [[ -n "$XT_CONTEXT_DIR" ]]; then
    if ! verify_scope "$XT_WORKTREE" "$XT_CONTEXT_DIR"; then
      # Re-commit after reverting out-of-scope files
      recover_git_index "$XT_WORKTREE"
      git -C "$XT_WORKTREE" add -A 2>/dev/null || true
      if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
        git -C "$XT_WORKTREE" commit -m "fix: revert out-of-scope changes" \
          --author="Gemini CLI <gemini@google.com>" \
          >/dev/null 2>&1 || true
      fi
      git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"
    fi
  fi

  # Extract cost/stats (before scrub, which resets working tree)
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

  # Clean worktree of build artifacts so it can be removed without --force.
  scrub_worktree "$XT_WORKTREE"

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

  # Build review prompt and write to file (avoids ARG_MAX for large diffs)
  local worktree_prompt="${XT_WORKTREE}/.gemini-review-prompt.md"
  cat > "$worktree_prompt" <<'PROMPT_TEMPLATE'
You are a code reviewer. Review the following code changes against the specification and rubric.

PROMPT_TEMPLATE
  # Append dynamic content safely (no shell expansion)
  {
    printf '## Specification\n%s\n\n' "$spec_content"
    printf '## Review Rubric\n%s\n\n' "$rubric_content"
    printf '## Code Diff\n```diff\n%s\n```\n\n' "$diff_content"
    cat <<'PROMPT_FOOTER'
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
PROMPT_FOOTER
  } >> "$worktree_prompt"

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke gemini in sandbox mode — point it at the file
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      TERM="${TERM:-dumb}" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}" \
    "$TOOL_CMD" \
      --sandbox \
      --output-format json \
      --model "$DEFAULT_MODEL" \
      -C "$XT_WORKTREE" \
      "Read and follow all instructions in the file .gemini-review-prompt.md in the current directory. It contains the diff, rubric, and spec for your code review." \
    || exit_code=$?

  # Clean up prompt file
  rm -f "$worktree_prompt"

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to log directory
  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-review-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.json"
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
  cleanup)
    # Safely remove a worktree without triggering Safety Net.
    _cleanup_wt="${1:?cleanup: pass the worktree path as first argument}"
    _cleanup_keep="${2:-}"
    if [[ ! -d "$_cleanup_wt" ]]; then
      printf '{"ok":true,"message":"worktree already gone: %s"}\n' "$_cleanup_wt"
      exit 0
    fi
    # Detect repo root from the worktree's git config
    _cleanup_repo="$(git -C "$_cleanup_wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || true)"
    if [[ -z "$_cleanup_repo" ]]; then
      rm -rf "$_cleanup_wt" 2>/dev/null || true
      printf '{"ok":true,"message":"removed via rm -rf (no git root found)"}\n'
      exit 0
    fi
    cleanup_worktree "$_cleanup_repo" "$_cleanup_wt" "$_cleanup_keep"
    printf '{"ok":true,"message":"worktree cleaned up: %s"}\n' "$_cleanup_wt"
    exit 0
    ;;
  status)
    # Quick status check for a worktree — is the adapter/gemini still alive?
    _wt="${1:?status: pass the worktree path as first argument}"
    _adapter_pid="$(cat "${_wt}/.gemini-adapter.pid" 2>/dev/null || true)"
    _child_pid="$(cat "${_wt}/.gemini-child.pid" 2>/dev/null || true)"
    if [[ -z "$_adapter_pid" && -z "$_child_pid" ]]; then
      printf '{"status":"not_running","reason":"no PID files found in %s"}\n' "$_wt"
      exit 1
    fi
    _adapter_alive="false"; _child_alive="false"
    [[ -n "$_adapter_pid" ]] && kill -0 "$_adapter_pid" 2>/dev/null && _adapter_alive="true"
    [[ -n "$_child_pid" ]] && kill -0 "$_child_pid" 2>/dev/null && _child_alive="true"
    printf '{"status":"%s","adapter_pid":%s,"adapter_alive":%s,"child_pid":%s,"child_alive":%s}\n' \
      "$( [[ "$_child_alive" == "true" ]] && echo "running" || echo "not_running" )" \
      "${_adapter_pid:-null}" "$_adapter_alive" \
      "${_child_pid:-null}" "$_child_alive"
    [[ "$_child_alive" == "true" ]] && exit 0 || exit 1
    ;;
  *)
    cat >&2 <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  health      Check if Gemini CLI is installed and authenticated
  implement   Run Gemini to implement code in a worktree
  review      Run Gemini to review code changes (sandboxed)
  status      Check if a Gemini run is alive for a given worktree
  cleanup     Safely remove a worktree (avoids Safety Net blocks)

Options (implement):
  --worktree <path>       Path to the git worktree (required)
  --prompt-file <path>    Path to the prompt file (required)
  --context-dir <dir>     Restrict changes to this directory
  --timeout <seconds>     Command timeout (default: 3600)
  --attempt <n>           Attempt number (default: 1)

Options (review):
  --worktree <path>       Path to the git worktree (required)
  --rubric-file <path>    Path to the review rubric (required)
  --spec-file <path>      Path to the task specification (required)
  --timeout <seconds>     Command timeout (default: 3600)
  --attempt <n>           Attempt number (default: 1)

Options (status):
  <worktree-path>         Path to the worktree to check

Options (cleanup):
  <worktree-path>         Path to the worktree to remove
  [--keep-branch]         Keep the git branch (default: delete it)

Environment variables:
  GEMINI_API_KEY                    Gemini API key for authentication
  GOOGLE_APPLICATION_CREDENTIALS    Google ADC file path (alternative)
USAGE
    exit 1
    ;;
esac
