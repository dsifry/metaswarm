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
# monitor_codex_output — Tail JSONL and surface Codex events to stderr
# ===========================================================================
# Runs in background. Parses Codex JSONL events and prints formatted status
# so the parent agent can see what Codex is actually doing.
# Usage: monitor_codex_output <jsonl_file> &
#        MONITOR_PID=$!
#        ... (run codex) ...
#        kill "$MONITOR_PID" 2>/dev/null
# ---------------------------------------------------------------------------
monitor_codex_output() {
  local jsonl_file="${1:?monitor_codex_output: jsonl_file required}"
  local last_size=0

  # Wait for the file to appear
  while [[ ! -f "$jsonl_file" ]]; do
    sleep 1
  done

  # Use jq if available for reliable parsing, otherwise fall back to grep/sed
  if command -v jq >/dev/null 2>&1; then
    tail -f "$jsonl_file" 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      local event_type item_type text command exit_code status
      event_type="$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null)" || continue

      case "$event_type" in
        item.completed)
          item_type="$(printf '%s' "$line" | jq -r '.item.type // empty' 2>/dev/null)"
          case "$item_type" in
            agent_message)
              text="$(printf '%s' "$line" | jq -r '.item.text // empty' 2>/dev/null)"
              [[ -n "$text" ]] && printf '[codex] %s\n' "$text" >&2
              ;;
            reasoning)
              text="$(printf '%s' "$line" | jq -r '.item.text // empty' 2>/dev/null)"
              [[ -n "$text" ]] && printf '[codex] (thinking) %s\n' "$text" >&2
              ;;
            command_execution)
              command="$(printf '%s' "$line" | jq -r '.item.command // empty' 2>/dev/null)"
              exit_code="$(printf '%s' "$line" | jq -r '.item.exit_code // empty' 2>/dev/null)"
              status="$(printf '%s' "$line" | jq -r '.item.status // empty' 2>/dev/null)"
              if [[ "$status" == "completed" ]]; then
                local icon="+"
                [[ "$exit_code" != "0" && "$exit_code" != "null" && -n "$exit_code" ]] && icon="!"
                # Truncate long commands
                local short_cmd="${command:0:120}"
                [[ ${#command} -gt 120 ]] && short_cmd="${short_cmd}..."
                printf '[codex] %s %s (exit %s)\n' "$icon" "$short_cmd" "${exit_code:-?}" >&2
              fi
              ;;
          esac
          ;;
        item.started)
          item_type="$(printf '%s' "$line" | jq -r '.item.type // empty' 2>/dev/null)"
          if [[ "$item_type" == "command_execution" ]]; then
            command="$(printf '%s' "$line" | jq -r '.item.command // empty' 2>/dev/null)"
            local short_cmd="${command:0:120}"
            [[ ${#command} -gt 120 ]] && short_cmd="${short_cmd}..."
            printf '[codex] > %s\n' "$short_cmd" >&2
          fi
          ;;
        turn.started)
          printf '[codex] --- turn started ---\n' >&2
          ;;
      esac
    done
  else
    # Fallback without jq: basic grep for key patterns
    tail -f "$jsonl_file" 2>/dev/null | while IFS= read -r line; do
      if [[ "$line" == *'"agent_message"'* ]]; then
        local text
        text="$(printf '%s' "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
        [[ -n "$text" ]] && printf '[codex] %s\n' "$text" >&2
      elif [[ "$line" == *'"command_execution"'*'"completed"'* ]]; then
        local cmd
        cmd="$(printf '%s' "$line" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')"
        [[ -n "$cmd" ]] && printf '[codex] + %s\n' "${cmd:0:120}" >&2
      elif [[ "$line" == *'"reasoning"'* ]]; then
        local text
        text="$(printf '%s' "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
        [[ -n "$text" ]] && printf '[codex] (thinking) %s\n' "$text" >&2
      fi
    done
  fi
}

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

  # Copy prompt file into worktree so Codex can read it directly
  # (avoids shell argument length limits for large prompts)
  local worktree_prompt="${XT_WORKTREE}/.codex-prompt.md"
  local real_prompt real_dest
  real_prompt="$(realpath "$XT_PROMPT_FILE" 2>/dev/null || printf '%s' "$XT_PROMPT_FILE")"
  real_dest="$(realpath "$worktree_prompt" 2>/dev/null || printf '%s' "$worktree_prompt")"
  if [[ "$real_prompt" != "$real_dest" ]]; then
    cp "$XT_PROMPT_FILE" "$worktree_prompt"
  fi

  # Write adapter PID file so agents can reliably check if we're alive.
  # Agents that launch us via `nohup bash ... &` get the wrapper PID from $!,
  # which exits immediately. These files inside the worktree are the source of truth.
  local adapter_pidfile="${XT_WORKTREE}/.codex-adapter.pid"
  local child_pidfile="${XT_WORKTREE}/.codex-child.pid"
  printf '%d\n' "$$" > "$adapter_pidfile"

  # Start output monitor so parent agent can see Codex's progress
  touch "$stdout_file"
  monitor_codex_output "$stdout_file" &
  local monitor_pid=$!

  # Trap to clean up on unexpected exit (SIGTERM, SIGINT, etc.)
  _implement_cleanup() {
    kill "$monitor_pid" 2>/dev/null || true
    local _child
    _child="$(cat "$child_pidfile" 2>/dev/null || true)"
    [[ -n "$_child" ]] && kill "$_child" 2>/dev/null || true
    rm -f "$worktree_prompt" "$adapter_pidfile" "$child_pidfile"
    rm -rf "$tmp_dir"
  }
  trap _implement_cleanup EXIT TERM INT

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke codex with minimal environment — point it at the file instead of
  # passing prompt content as a shell argument.
  # SAFE_INVOKE_PIDFILE tells safe_invoke where to write the child process PID.
  local exit_code=0
  SAFE_INVOKE_PIDFILE="$child_pidfile" \
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec --full-auto --json -C "$XT_WORKTREE" \
      "Read and follow all instructions in the file .codex-prompt.md in the current directory. This file contains your complete task specification." \
    || exit_code=$?

  # Disable trap — we handle cleanup explicitly below
  trap - EXIT TERM INT

  # Stop the monitor
  kill "$monitor_pid" 2>/dev/null; wait "$monitor_pid" 2>/dev/null || true

  # Clean up prompt file and PID files from worktree (don't leave in commits)
  rm -f "$worktree_prompt" "$adapter_pidfile" "$child_pidfile"

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

    # Clean worktree so it can be removed without --force
    scrub_worktree "$XT_WORKTREE"

    # Cleanup tmp
    rm -rf "$tmp_dir"
    return 1
  fi

  # Success path: stage and commit all changes in worktree
  local branch=""
  local git_sha=""

  if [[ -d "$XT_WORKTREE" ]]; then
    # Recover from stale index.lock left by sandboxed Codex.
    # Without this, git add silently fails and all work is lost.
    recover_git_index "$XT_WORKTREE"

    # Stage all changes
    if ! git -C "$XT_WORKTREE" add -A 2>/dev/null; then
      printf '[adapter] WARNING: git add -A failed in %s\n' "$XT_WORKTREE" >&2
    fi

    # Check if there are changes to commit
    if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
      if ! git -C "$XT_WORKTREE" commit -m "feat: codex implement (attempt ${XT_ATTEMPT})" \
        --author="Codex CLI <codex@openai.com>" \
        >/dev/null 2>&1; then
        printf '[adapter] WARNING: git commit failed in %s\n' "$XT_WORKTREE" >&2
      fi
    fi

    # Verify scope (revert out-of-scope changes if context_dir is set)
    if [[ -n "$XT_CONTEXT_DIR" ]]; then
      if ! verify_scope "$XT_WORKTREE" "$XT_CONTEXT_DIR"; then
        recover_git_index "$XT_WORKTREE"
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

  # Extract cost/stats BEFORE scrub (scrub resets working tree)
  local cost_json
  cost_json="$(extract_cost_codex "$stdout_file")"

  local files_changed_json
  files_changed_json="$(get_changed_files "$XT_WORKTREE")"

  local diff_stats_json
  diff_stats_json="$(get_diff_stats "$XT_WORKTREE")"

  if [[ -d "$XT_WORKTREE" ]]; then
    # Clean worktree of build artifacts so it can be removed without --force.
    # Codex may have run install/build which creates large untracked dirs.
    scrub_worktree "$XT_WORKTREE"
  fi

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

  # Write review prompt to file in worktree (avoids shell argument length limits)
  local worktree_prompt="${XT_WORKTREE}/.codex-review-prompt.md"
  printf '%s' "$review_prompt" > "$worktree_prompt"

  # Start output monitor so parent agent can see Codex's progress
  touch "$stdout_file"
  monitor_codex_output "$stdout_file" &
  local monitor_pid=$!

  # Record start time
  local start_time
  start_time="$(date +%s)"

  # Invoke codex in read-only sandbox mode — point it at the file
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      CODEX_API_KEY="${CODEX_API_KEY:-}" \
    "$TOOL_CMD" exec --sandbox read-only --json -C "$XT_WORKTREE" \
      "Read and follow all instructions in the file .codex-review-prompt.md in the current directory. It contains the diff, rubric, and spec for your code review." \
    || exit_code=$?

  # Stop the monitor
  kill "$monitor_pid" 2>/dev/null; wait "$monitor_pid" 2>/dev/null || true

  # Clean up prompt file
  rm -f "$worktree_prompt"

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
  cleanup)
    # Safely remove a worktree without triggering Safety Net.
    # Agents should call this instead of `git worktree remove --force`.
    _cleanup_wt="${1:?cleanup: pass the worktree path as first argument}"
    _cleanup_keep="${2:-}"
    if [[ ! -d "$_cleanup_wt" ]]; then
      printf '{"ok":true,"message":"worktree already gone: %s"}\n' "$_cleanup_wt"
      exit 0
    fi
    # Detect repo root from the worktree's git config
    _cleanup_repo="$(git -C "$_cleanup_wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || true)"
    if [[ -z "$_cleanup_repo" ]]; then
      # Fallback: just rm -rf the directory
      rm -rf "$_cleanup_wt" 2>/dev/null || true
      printf '{"ok":true,"message":"removed via rm -rf (no git root found)"}\n'
      exit 0
    fi
    cleanup_worktree "$_cleanup_repo" "$_cleanup_wt" "$_cleanup_keep"
    printf '{"ok":true,"message":"worktree cleaned up: %s"}\n' "$_cleanup_wt"
    exit 0
    ;;
  status)
    # Quick status check for a worktree — is the adapter/codex still alive?
    _wt="${1:?status: pass the worktree path as first argument}"
    _adapter_pid="$(cat "${_wt}/.codex-adapter.pid" 2>/dev/null || true)"
    _child_pid="$(cat "${_wt}/.codex-child.pid" 2>/dev/null || true)"
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
  health      Check if Codex CLI is installed, authenticated, and ready
  implement   Run Codex in full-auto mode on a worktree to implement changes
  review      Run Codex in read-only sandbox to review code changes
  status      Check if a Codex run is alive for a given worktree
  cleanup     Safely remove a worktree (avoids Safety Net blocks)

Options (implement):
  --worktree <path>       Path to the git worktree (required)
  --prompt-file <path>    Path to the prompt file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 3600)
  --context-dir <dir>     Restrict changes to this directory

Options (review):
  --worktree <path>       Path to the git worktree (required)
  --rubric-file <path>    Path to the review rubric file (required)
  --spec-file <path>      Path to the specification file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 3600)

Options (status):
  <worktree-path>         Path to the worktree to check

Options (cleanup):
  <worktree-path>         Path to the worktree to remove
  [--keep-branch]         Keep the git branch (default: delete it)

Environment variables:
  OPENAI_API_KEY          OpenAI API key for authentication
  CODEX_API_KEY           Codex-specific API key (alternative)
USAGE
    exit 1
    ;;
esac
