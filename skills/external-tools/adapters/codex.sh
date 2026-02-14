#!/bin/bash
# codex.sh — OpenAI Codex CLI adapter for external-tools
#
# Commands:
#   health     Preflight check: binary exists, version, auth status
#   implement  Write code on a worktree branch via Codex full-auto mode
#   review     Review code changes (read-only sandbox) against a rubric/spec
#
# Usage:
#   codex.sh health
#   codex.sh implement --worktree <path> --prompt-file <path> [--attempt N] [--timeout S] [--context-dir <dir>]
#   codex.sh review   --worktree <path> --rubric-file <path> --spec-file <path> [--attempt N] [--timeout S]

set -euo pipefail

# ---------------------------------------------------------------------------
# Source shared helpers
# ---------------------------------------------------------------------------
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TOOL_NAME="codex"
TOOL_CMD="codex"
DEFAULT_MODEL="gpt-5.3-codex"

# ===========================================================================
# health — Preflight check
# ===========================================================================
cmd_health() {
  local status="ready"
  local version="unknown"
  local auth_valid=false

  # Check if codex binary exists
  if ! command -v "$TOOL_CMD" >/dev/null 2>&1; then
    printf '{"tool":"%s","status":"unavailable","version":"not_installed","auth_valid":false,"model":"%s"}\n' \
      "$TOOL_NAME" "$DEFAULT_MODEL"
    return 0
  fi

  # Get version
  version="$("$TOOL_CMD" --version 2>/dev/null || printf 'unknown')"
  # Trim whitespace
  version="$(printf '%s' "$version" | tr -d '\n' | xargs)"

  # Check auth: try `codex login status` first, then fall back to env vars
  if "$TOOL_CMD" login status >/dev/null 2>&1; then
    auth_valid=true
  elif [[ -n "${OPENAI_API_KEY:-}" || -n "${CODEX_API_KEY:-}" ]]; then
    auth_valid=true
  fi

  if [[ "$auth_valid" == "false" ]]; then
    status="unavailable"
  fi

  # Emit JSON — use jq if available for proper escaping, else manual
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

# ===========================================================================
# implement — Write code on a worktree branch
# ===========================================================================
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
  if [[ ! -d "$XT_WORKTREE" ]]; then
    printf 'Error: worktree directory does not exist: %s\n' "$XT_WORKTREE" >&2
    return 1
  fi
  if [[ ! -f "$XT_PROMPT_FILE" ]]; then
    printf 'Error: prompt file does not exist: %s\n' "$XT_PROMPT_FILE" >&2
    return 1
  fi

  # Create secure tmp dir for capturing output
  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.jsonl"
  local stderr_file="${tmp_dir}/stderr.log"

  # Read prompt file content
  local prompt_content
  prompt_content="$(cat "$XT_PROMPT_FILE")"

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke codex with minimal environment
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec --full-auto --json -C "$XT_WORKTREE" "$prompt_content" \
    || exit_code=$?

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to LOG_DIR
  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-implement-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.jsonl"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  # Handle error
  if [[ "$exit_code" -ne 0 ]]; then
    local error_type
    error_type="$(classify_error "$exit_code" "$stderr_file")"

    # Log and emit error
    local error_json
    error_json="$(emit_error \
      "$TOOL_NAME" \
      "implement" \
      "$DEFAULT_MODEL" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"
    log_session "$error_json"
    printf '%s\n' "$error_json"

    # Cleanup tmp
    rm -rf "$tmp_dir"
    return 1
  fi

  # Success path: stage and commit all changes in worktree
  local branch=""
  local git_sha=""

  if [[ -d "$XT_WORKTREE" ]]; then
    # Stage all changes
    git -C "$XT_WORKTREE" add -A 2>/dev/null || true

    # Check if there are changes to commit
    if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
      git -C "$XT_WORKTREE" commit -m "feat: codex implement (attempt ${XT_ATTEMPT})" \
        --author="Codex CLI <codex@openai.com>" \
        >/dev/null 2>&1 || true
    fi

    # Verify scope (revert out-of-scope changes if context_dir is set)
    if [[ -n "$XT_CONTEXT_DIR" ]]; then
      if ! verify_scope "$XT_WORKTREE" "$XT_CONTEXT_DIR"; then
        # Re-commit after reverting out-of-scope files
        git -C "$XT_WORKTREE" add -A 2>/dev/null || true
        if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
          git -C "$XT_WORKTREE" commit -m "fix: revert out-of-scope changes" \
            --author="Codex CLI <codex@openai.com>" \
            >/dev/null 2>&1 || true
        fi
      fi
    fi

    # Capture branch and SHA
    branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || true)"
  fi

  # Extract cost/stats
  local cost_json
  cost_json="$(extract_cost_codex "$stdout_file")"

  local files_changed_json
  files_changed_json="$(get_changed_files "$XT_WORKTREE")"

  local diff_stats_json
  diff_stats_json="$(get_diff_stats "$XT_WORKTREE")"

  # Emit structured output
  local result_json
  result_json="$(emit_json \
    "$TOOL_NAME" \
    "implement" \
    "$DEFAULT_MODEL" \
    "$XT_ATTEMPT" \
    "$exit_code" \
    "$branch" \
    "$git_sha" \
    "$files_changed_json" \
    "$diff_stats_json" \
    "$duration" \
    "$cost_json" \
    "$raw_log_file")"

  log_session "$result_json"
  printf '%s\n' "$result_json"

  # Cleanup tmp
  rm -rf "$tmp_dir"
}

# ===========================================================================
# review — Review code changes (read-only)
# ===========================================================================
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
  if [[ ! -d "$XT_WORKTREE" ]]; then
    printf 'Error: worktree directory does not exist: %s\n' "$XT_WORKTREE" >&2
    return 1
  fi
  if [[ ! -f "$XT_RUBRIC_FILE" ]]; then
    printf 'Error: rubric file does not exist: %s\n' "$XT_RUBRIC_FILE" >&2
    return 1
  fi
  if [[ ! -f "$XT_SPEC_FILE" ]]; then
    printf 'Error: spec file does not exist: %s\n' "$XT_SPEC_FILE" >&2
    return 1
  fi

  # Create secure tmp dir
  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.jsonl"
  local stderr_file="${tmp_dir}/stderr.log"

  # Build review prompt from git diff + rubric + spec
  local diff_content
  diff_content="$(git -C "$XT_WORKTREE" diff HEAD 2>/dev/null || true)"
  if [[ -z "$diff_content" ]]; then
    # If no unstaged diff, try staged diff or diff against parent
    diff_content="$(git -C "$XT_WORKTREE" diff HEAD~1 HEAD 2>/dev/null || true)"
  fi

  local rubric_content
  rubric_content="$(cat "$XT_RUBRIC_FILE")"

  local spec_content
  spec_content="$(cat "$XT_SPEC_FILE")"

  local review_prompt
  review_prompt="$(cat <<'PROMPT_TEMPLATE'
You are a code reviewer. Review the following code changes against the provided rubric and specification.

## Git Diff
PROMPT_TEMPLATE
)"
  review_prompt+=$'\n```diff\n'"${diff_content}"$'\n```\n'
  review_prompt+=$'\n## Review Rubric\n'"${rubric_content}"$'\n'
  review_prompt+=$'\n## Specification\n'"${spec_content}"$'\n'
  review_prompt+="$(cat <<'PROMPT_FOOTER'

## Instructions
1. Evaluate each criterion in the rubric against the diff and spec.
2. For each finding, provide:
   - Verdict: PASS or FAIL
   - Classification: BLOCKING or WARNING
   - Citation: file:line reference(s)
   - Explanation: why the finding was made
3. At the end, provide an overall verdict: PASS or FAIL.
   - FAIL if any BLOCKING issue is found.
   - PASS if only WARNING issues or no issues.
4. Output your review as structured JSON with keys: "verdict", "findings" (array), "summary".
PROMPT_FOOTER
)"

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke codex in read-only sandbox mode
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec --sandbox read-only --json -C "$XT_WORKTREE" "$review_prompt" \
    || exit_code=$?

  # Calculate duration
  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  # Save raw output to LOG_DIR
  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-review-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.jsonl"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  # Handle error
  if [[ "$exit_code" -ne 0 ]]; then
    local error_json
    error_json="$(emit_error \
      "$TOOL_NAME" \
      "review" \
      "$DEFAULT_MODEL" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"
    log_session "$error_json"
    printf '%s\n' "$error_json"

    # Cleanup tmp
    rm -rf "$tmp_dir"
    return 1
  fi

  # Extract cost
  local cost_json
  cost_json="$(extract_cost_codex "$stdout_file")"

  # For review, capture branch/sha for context but no file changes expected
  local branch=""
  local git_sha=""
  if [[ -d "$XT_WORKTREE" ]]; then
    branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || true)"
  fi

  # Emit structured output
  local result_json
  result_json="$(emit_json \
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
    "$cost_json" \
    "$raw_log_file")"

  log_session "$result_json"
  printf '%s\n' "$result_json"

  # Cleanup tmp
  rm -rf "$tmp_dir"
}

# ===========================================================================
# Command dispatch
# ===========================================================================
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
    cat >&2 <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  health      Check if Codex CLI is installed, authenticated, and ready
  implement   Run Codex in full-auto mode on a worktree to implement changes
  review      Run Codex in read-only sandbox to review code changes

Options (implement):
  --worktree <path>       Path to the git worktree (required)
  --prompt-file <path>    Path to the prompt file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 300)
  --context-dir <dir>     Restrict changes to this directory

Options (review):
  --worktree <path>       Path to the git worktree (required)
  --rubric-file <path>    Path to the review rubric file (required)
  --spec-file <path>      Path to the specification file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 300)

Environment variables:
  OPENAI_API_KEY          OpenAI API key for authentication
  CODEX_API_KEY           Codex-specific API key (alternative)
USAGE
    exit 1
    ;;
esac
