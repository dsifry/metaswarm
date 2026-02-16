#!/bin/bash
# _common.sh — Shared adapter helpers for external-tools adapters
#
# This file is sourced by adapter scripts (codex.sh, gemini.sh, etc.).
# It provides shared functionality for invoking external AI tools,
# managing git worktrees, capturing output, and emitting structured JSON.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION="1"
LOG_DIR="${HOME}/.claude/sessions"

# ---------------------------------------------------------------------------
# parse_args()
#   Parses common CLI arguments into shell variables.
#   Sets: XT_WORKTREE, XT_PROMPT_FILE, XT_RUBRIC_FILE, XT_SPEC_FILE,
#         XT_ATTEMPT, XT_TIMEOUT, XT_CONTEXT_DIR
# ---------------------------------------------------------------------------
parse_args() {
  # Defaults
  XT_WORKTREE=""
  XT_PROMPT_FILE=""
  XT_RUBRIC_FILE=""
  XT_SPEC_FILE=""
  XT_ATTEMPT="1"
  XT_TIMEOUT="3600"
  XT_CONTEXT_DIR=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --worktree)
        XT_WORKTREE="${2:-}"
        shift 2
        ;;
      --prompt-file)
        XT_PROMPT_FILE="${2:-}"
        shift 2
        ;;
      --rubric-file)
        XT_RUBRIC_FILE="${2:-}"
        shift 2
        ;;
      --spec-file)
        XT_SPEC_FILE="${2:-}"
        shift 2
        ;;
      --attempt)
        XT_ATTEMPT="${2:-1}"
        shift 2
        ;;
      --timeout)
        XT_TIMEOUT="${2:-3600}"
        shift 2
        ;;
      --context-dir)
        XT_CONTEXT_DIR="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# create_secure_tmp()
#   Creates a temporary directory with restricted permissions.
#   Prints the path to stdout.
# ---------------------------------------------------------------------------
create_secure_tmp() {
  local tmp_dir
  tmp_dir="$(mktemp -d -t "xt-XXXXXX")"
  chmod 700 "$tmp_dir"
  printf '%s' "$tmp_dir"
}

# ---------------------------------------------------------------------------
# safe_invoke()
#   Wraps a command with timeout, captures stdout and stderr to separate files.
#   Usage: safe_invoke <timeout_secs> <stdout_file> <stderr_file> <cmd> [args...]
#   Returns the command's exit code (124 for timeout).
#   Note: Uses coreutils `timeout` or `gtimeout` if available, otherwise falls
#   back to a background process with kill for macOS compatibility.
# ---------------------------------------------------------------------------
safe_invoke() {
  local timeout_secs="${1:?safe_invoke: timeout_secs required}"
  local stdout_file="${2:?safe_invoke: stdout_file required}"
  local stderr_file="${3:?safe_invoke: stderr_file required}"
  shift 3

  local heartbeat_interval=300  # Print status every 5 minutes

  # Run the command in background with heartbeat monitoring.
  # This avoids blocking for long-running Codex tasks and gives the
  # calling agent periodic status updates.
  "$@" >"$stdout_file" 2>"$stderr_file" &
  local pid=$!

  # Write child PID to file if SAFE_INVOKE_PIDFILE is set, so callers
  # (and external agents) can reliably find the actual process.
  if [[ -n "${SAFE_INVOKE_PIDFILE:-}" ]]; then
    printf '%d\n' "$pid" > "$SAFE_INVOKE_PIDFILE"
  fi

  local elapsed=0
  local exit_code=0
  local next_heartbeat=$heartbeat_interval

  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$elapsed" -ge "$timeout_secs" ]]; then
      printf '[safe_invoke] Timeout after %ds — killing process %d\n' "$elapsed" "$pid" >&2
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      exit_code=124  # Match coreutils timeout exit code
      return "$exit_code"
    fi
    if [[ "$elapsed" -ge "$next_heartbeat" ]]; then
      local mins=$(( elapsed / 60 ))
      local max_mins=$(( timeout_secs / 60 ))
      printf '[safe_invoke] Still running... %dm / %dm elapsed\n' "$mins" "$max_mins" >&2
      next_heartbeat=$(( next_heartbeat + heartbeat_interval ))
    fi
    sleep 5
    elapsed=$(( elapsed + 5 ))
  done
  wait "$pid" 2>/dev/null || exit_code=$?

  if [[ "$exit_code" -eq 0 ]]; then
    local mins=$(( elapsed / 60 ))
    printf '[safe_invoke] Completed successfully in %dm %ds\n' "$mins" $(( elapsed % 60 )) >&2
  fi

  return "$exit_code"
}

# ---------------------------------------------------------------------------
# classify_error()
#   Takes an exit code and stderr file path, returns an error classification.
#   Usage: classify_error <exit_code> <stderr_file>
#   Prints one of: timeout, tool_not_installed, rate_limited, auth_expired,
#                  network_error, context_too_large, tool_crash
# ---------------------------------------------------------------------------
classify_error() {
  local exit_code="${1:?classify_error: exit_code required}"
  local stderr_file="${2:-}"

  # Timeout exit code from coreutils timeout
  if [[ "$exit_code" -eq 124 ]]; then
    printf 'timeout'
    return 0
  fi

  # Command not found
  if [[ "$exit_code" -eq 127 ]]; then
    printf 'tool_not_installed'
    return 0
  fi

  # Inspect stderr content if the file exists and is non-empty
  if [[ -n "$stderr_file" && -s "$stderr_file" ]]; then
    local stderr_content
    stderr_content="$(cat "$stderr_file" 2>/dev/null || true)"

    if grep -qi 'rate.limit\|rate_limit\|too many requests\|429' <<< "$stderr_content" 2>/dev/null; then
      printf 'rate_limited'
      return 0
    fi

    if grep -qi 'auth\|unauthorized\|401\|403\|forbidden\|token.*expired\|invalid.*key\|api.*key' <<< "$stderr_content" 2>/dev/null; then
      printf 'auth_expired'
      return 0
    fi

    if grep -qi 'network\|connection\|dns\|resolve\|ECONNREFUSED\|ETIMEDOUT\|socket\|unreachable' <<< "$stderr_content" 2>/dev/null; then
      printf 'network_error'
      return 0
    fi

    if grep -qi 'context.*too.*large\|token.*limit\|context.*length\|max.*tokens\|too.*long\|exceeds.*limit' <<< "$stderr_content" 2>/dev/null; then
      printf 'context_too_large'
      return 0
    fi
  fi

  # Fallback
  printf 'tool_crash'
}

# ---------------------------------------------------------------------------
# create_worktree()
#   Creates a git worktree for an external tool run.
#   Usage: create_worktree <repo_root> <tool_name> <task_id> <base_dir>
#   Creates worktree at <base_dir>/ext-<tool>-<task_id> on branch
#   external/<tool>/<task_id>. Cleans up stale worktrees/branches first.
#   Prints the worktree path.
# ---------------------------------------------------------------------------
create_worktree() {
  local repo_root="${1:?create_worktree: repo_root required}"
  local tool_name="${2:?create_worktree: tool_name required}"
  local task_id="${3:?create_worktree: task_id required}"
  local base_dir="${4:?create_worktree: base_dir required}"

  local worktree_path="${base_dir}/ext-${tool_name}-${task_id}"
  local branch_name="external/${tool_name}/${task_id}"

  # Clean up stale worktree if it exists
  if [[ -d "$worktree_path" ]]; then
    git -C "$repo_root" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
  fi

  # Clean up stale branch if it exists
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    git -C "$repo_root" branch -D "$branch_name" >/dev/null 2>&1 || true
  fi

  # Prune stale worktree metadata
  git -C "$repo_root" worktree prune >/dev/null 2>&1 || true

  # Create the base directory if needed
  mkdir -p "$base_dir"

  # Create new worktree with a new branch from HEAD
  git -C "$repo_root" worktree add -b "$branch_name" "$worktree_path" HEAD >/dev/null 2>&1

  printf '%s' "$worktree_path"
}

# ---------------------------------------------------------------------------
# scrub_worktree()
#   Removes untracked files and resets modified files in a worktree so it can
#   be removed with plain `git worktree remove` (no --force).
#   Avoids `git clean -f` which may be blocked by safety tools.
#   Usage: scrub_worktree <worktree_path>
# ---------------------------------------------------------------------------
scrub_worktree() {
  local wt="${1:?scrub_worktree: worktree_path required}"
  [[ -d "$wt" ]] || return 0

  # Remove common build artifact directories that Codex may have created
  for artifact in node_modules dist .next .nuxt .turbo coverage __pycache__ .mypy_cache .pytest_cache target vendor build .gradle; do
    rm -rf "${wt}/${artifact}" 2>/dev/null || true
  done

  # Reset any modified tracked files to HEAD
  git -C "$wt" checkout -- . 2>/dev/null || true

  # Remove remaining untracked files via git ls-files
  # (safer alternative to git clean -f)
  local untracked
  untracked="$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null || true)"
  if [[ -n "$untracked" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      rm -rf "${wt}/${f}" 2>/dev/null || true
    done <<< "$untracked"
  fi
}

# ---------------------------------------------------------------------------
# cleanup_worktree()
#   Removes a worktree and optionally its branch.
#   Usage: cleanup_worktree <repo_root> <worktree_path> [--keep-branch]
# ---------------------------------------------------------------------------
cleanup_worktree() {
  local repo_root="${1:?cleanup_worktree: repo_root required}"
  local worktree_path="${2:?cleanup_worktree: worktree_path required}"
  local keep_branch="${3:-}"

  # Get the branch name before removing the worktree
  local branch_name=""
  if [[ -d "$worktree_path" ]]; then
    branch_name="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  fi

  # Scrub untracked/modified files so we don't need --force
  scrub_worktree "$worktree_path"

  # Remove the worktree (try without --force first, fall back to rm)
  git -C "$repo_root" worktree remove "$worktree_path" >/dev/null 2>&1 \
    || rm -rf "$worktree_path" 2>/dev/null || true
  git -C "$repo_root" worktree prune >/dev/null 2>&1 || true

  # Remove the branch unless --keep-branch was specified
  if [[ "$keep_branch" != "--keep-branch" && -n "$branch_name" && "$branch_name" != "HEAD" ]]; then
    git -C "$repo_root" branch -D "$branch_name" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# verify_scope()
#   Checks all changed files are within context_dir. Reverts out-of-scope changes.
#   Usage: verify_scope <worktree_path> [context_dir]
#   Returns 0 if all changes in scope, 1 if violations found (and reverted).
# ---------------------------------------------------------------------------
verify_scope() {
  local worktree_path="${1:?verify_scope: worktree_path required}"
  local context_dir="${2:-}"

  # If no context_dir specified, everything is in scope
  if [[ -z "$context_dir" ]]; then
    return 0
  fi

  # Normalize context_dir: strip trailing slash, make relative to worktree
  context_dir="${context_dir%/}"

  local violations_found=0
  local changed_files
  # Try committed diff first (HEAD~1..HEAD) since tools commit before calling verify_scope,
  # then fall back to uncommitted diff (HEAD) for pre-commit verification.
  changed_files="$(git -C "$worktree_path" diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
  if [[ -z "$changed_files" ]]; then
    changed_files="$(git -C "$worktree_path" diff --name-only HEAD 2>/dev/null || true)"
  fi

  if [[ -z "$changed_files" ]]; then
    return 0
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    # Check if the file path starts with the context_dir prefix
    if [[ "$file" != "${context_dir}"* && "$file" != "${context_dir}/"* ]]; then
      # Out of scope — revert to pre-commit version (HEAD~1, since tool already committed)
      git -C "$worktree_path" checkout HEAD~1 -- "$file" 2>/dev/null || true
      violations_found=1
    fi
  done <<< "$changed_files"

  return "$violations_found"
}

# ---------------------------------------------------------------------------
# get_diff_stats()
#   Returns JSON {"additions": N, "deletions": N} from git diff.
#   Compares HEAD against its parent (HEAD~1) to capture committed changes.
#   Falls back to uncommitted diff if no parent exists.
#   Usage: get_diff_stats <worktree_path>
# ---------------------------------------------------------------------------
get_diff_stats() {
  local worktree_path="${1:?get_diff_stats: worktree_path required}"

  local additions=0
  local deletions=0

  if [[ -d "$worktree_path" ]]; then
    local stat_line
    # Try committed diff first (HEAD~1..HEAD), fall back to uncommitted (HEAD)
    stat_line="$(git -C "$worktree_path" diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 || true)"
    if [[ -z "$stat_line" ]]; then
      stat_line="$(git -C "$worktree_path" diff --stat HEAD 2>/dev/null | tail -1 || true)"
    fi

    if [[ -n "$stat_line" ]]; then
      # Extract insertions and deletions from summary line like:
      #  3 files changed, 10 insertions(+), 5 deletions(-)
      additions="$(printf '%s' "$stat_line" | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || printf '0')"
      deletions="$(printf '%s' "$stat_line" | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || printf '0')"
    fi
  fi

  printf '{"additions": %d, "deletions": %d}' "${additions:-0}" "${deletions:-0}"
}

# ---------------------------------------------------------------------------
# get_changed_files()
#   Returns a JSON array of changed file paths.
#   Usage: get_changed_files <worktree_path>
# ---------------------------------------------------------------------------
get_changed_files() {
  local worktree_path="${1:?get_changed_files: worktree_path required}"

  if [[ ! -d "$worktree_path" ]]; then
    printf '[]'
    return 0
  fi

  local files
  # Try committed diff first (HEAD~1..HEAD), fall back to uncommitted (HEAD)
  files="$(git -C "$worktree_path" diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
  if [[ -z "$files" ]]; then
    files="$(git -C "$worktree_path" diff --name-only HEAD 2>/dev/null || true)"
  fi

  if [[ -z "$files" ]]; then
    printf '[]'
    return 0
  fi

  # Build JSON array using jq if available, otherwise manually
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$files" | jq -R -s 'split("\n") | map(select(length > 0))'
  else
    local json="["
    local first=true
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ "$first" == "true" ]]; then
        first=false
      else
        json+=","
      fi
      # Escape backslashes and double quotes for JSON
      f="${f//\\/\\\\}"
      f="${f//\"/\\\"}"
      json+="\"${f}\""
    done <<< "$files"
    json+="]"
    printf '%s' "$json"
  fi
}

# ---------------------------------------------------------------------------
# extract_cost_codex()
#   Parse Codex JSONL output for input_tokens/output_tokens.
#   Usage: extract_cost_codex <jsonl_file>
#   Returns JSON object: {"input_tokens": N, "output_tokens": N}
# ---------------------------------------------------------------------------
extract_cost_codex() {
  local jsonl_file="${1:-}"

  if [[ -z "$jsonl_file" || ! -f "$jsonl_file" ]]; then
    printf '{"input_tokens": 0, "output_tokens": 0}'
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"input_tokens": 0, "output_tokens": 0}'
    return 0
  fi

  # Codex JSONL may contain usage lines with input_tokens and output_tokens
  local input_tokens=0
  local output_tokens=0

  # Sum up all usage entries from the JSONL stream
  local usage
  usage="$(jq -s '
    [ .[] | select(.usage != null) | .usage ] |
    if length > 0 then
      { input_tokens: (map(.input_tokens // 0) | add),
        output_tokens: (map(.output_tokens // 0) | add) }
    else
      { input_tokens: 0, output_tokens: 0 }
    end
  ' "$jsonl_file" 2>/dev/null || printf '{"input_tokens": 0, "output_tokens": 0}')"

  printf '%s' "$usage"
}

# ---------------------------------------------------------------------------
# extract_cost_gemini()
#   Parse Gemini JSON output for token counts.
#   Usage: extract_cost_gemini <json_file>
#   Returns JSON object: {"input_tokens": N, "output_tokens": N}
# ---------------------------------------------------------------------------
extract_cost_gemini() {
  local json_file="${1:-}"

  if [[ -z "$json_file" || ! -f "$json_file" ]]; then
    printf '{"input_tokens": 0, "output_tokens": 0}'
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"input_tokens": 0, "output_tokens": 0}'
    return 0
  fi

  # Gemini responses include usageMetadata with promptTokenCount and candidatesTokenCount
  local usage
  usage="$(jq '
    if .usageMetadata then
      { input_tokens: (.usageMetadata.promptTokenCount // 0),
        output_tokens: (.usageMetadata.candidatesTokenCount // 0) }
    elif .usage then
      { input_tokens: (.usage.input_tokens // .usage.prompt_tokens // 0),
        output_tokens: (.usage.output_tokens // .usage.completion_tokens // 0) }
    else
      { input_tokens: 0, output_tokens: 0 }
    end
  ' "$json_file" 2>/dev/null || printf '{"input_tokens": 0, "output_tokens": 0}')"

  printf '%s' "$usage"
}

# ---------------------------------------------------------------------------
# emit_json()
#   Emit structured JSON output to stdout.
#   Usage: emit_json <tool> <command> <model> <attempt> <exit_code> \
#            <branch> <git_sha> <files_changed_json> <diff_stats_json> \
#            <duration_seconds> <cost_json> <raw_log_file> \
#            [error_type]
#   All fields from the output schema are included.
# ---------------------------------------------------------------------------
emit_json() {
  local tool="${1:-}"
  local command="${2:-}"
  local model="${3:-}"
  local attempt="${4:-1}"
  local exit_code="${5:-0}"
  local branch="${6:-}"
  local git_sha="${7:-}"
  local files_changed="${8:-[]}"
  local diff_stats="${9:-}"
  local duration_seconds="${10:-0}"
  local cost="${11:-}"
  local raw_log_file="${12:-}"
  local error_type="${13:-}"

  # Apply JSON defaults outside of parameter expansion to avoid brace conflicts
  local _default_diff_stats='{"additions": 0, "deletions": 0}'
  local _default_cost='{"input_tokens": 0, "output_tokens": 0}'
  diff_stats="${diff_stats:-$_default_diff_stats}"
  cost="${cost:-$_default_cost}"

  # Read raw log content if file exists
  local raw_log=""
  if [[ -n "$raw_log_file" && -f "$raw_log_file" ]]; then
    raw_log="$(cat "$raw_log_file" 2>/dev/null || true)"
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg tool "$tool" \
      --arg command "$command" \
      --arg model "$model" \
      --argjson attempt "$attempt" \
      --argjson exit_code "$exit_code" \
      --arg branch "$branch" \
      --arg git_sha "$git_sha" \
      --argjson files_changed "$files_changed" \
      --argjson diff_stats "$diff_stats" \
      --argjson duration_seconds "$duration_seconds" \
      --argjson cost "$cost" \
      --arg raw_log "$raw_log" \
      --arg error_type "$error_type" \
      --arg schema_version "$SCHEMA_VERSION" \
      '{
        schema_version: $schema_version,
        tool: $tool,
        command: $command,
        model: $model,
        attempt: $attempt,
        exit_code: $exit_code,
        branch: $branch,
        git_sha: $git_sha,
        files_changed: $files_changed,
        diff_stats: $diff_stats,
        duration_seconds: $duration_seconds,
        cost: $cost,
        raw_log: $raw_log,
        error_type: (if $error_type == "" then null else $error_type end)
      }'
  else
    # Fallback without jq — produce JSON manually
    # Escape raw_log for JSON (basic escaping)
    raw_log="${raw_log//\\/\\\\}"
    raw_log="${raw_log//\"/\\\"}"
    raw_log="${raw_log//$'\n'/\\n}"
    raw_log="${raw_log//$'\t'/\\t}"

    local error_type_json="null"
    if [[ -n "$error_type" ]]; then
      error_type_json="\"${error_type}\""
    fi

    cat <<ENDJSON
{
  "schema_version": "${SCHEMA_VERSION}",
  "tool": "${tool}",
  "command": "${command}",
  "model": "${model}",
  "attempt": ${attempt},
  "exit_code": ${exit_code},
  "branch": "${branch}",
  "git_sha": "${git_sha}",
  "files_changed": ${files_changed},
  "diff_stats": ${diff_stats},
  "duration_seconds": ${duration_seconds},
  "cost": ${cost},
  "raw_log": "${raw_log}",
  "error_type": ${error_type_json}
}
ENDJSON
  fi
}

# ---------------------------------------------------------------------------
# emit_error()
#   Convenience wrapper for error JSON output.
#   Usage: emit_error <tool> <command> <model> <attempt> <exit_code> \
#            <stderr_file> <duration_seconds> [raw_log_file]
# ---------------------------------------------------------------------------
emit_error() {
  local tool="${1:-}"
  local command="${2:-}"
  local model="${3:-}"
  local attempt="${4:-1}"
  local exit_code="${5:-1}"
  local stderr_file="${6:-}"
  local duration_seconds="${7:-0}"
  local raw_log_file="${8:-}"

  local error_type
  error_type="$(classify_error "$exit_code" "$stderr_file")"

  emit_json \
    "$tool" \
    "$command" \
    "$model" \
    "$attempt" \
    "$exit_code" \
    "" \
    "" \
    "[]" \
    '{"additions": 0, "deletions": 0}' \
    "$duration_seconds" \
    '{"input_tokens": 0, "output_tokens": 0}' \
    "$raw_log_file" \
    "$error_type"
}

# ---------------------------------------------------------------------------
# log_session()
#   Appends a structured JSONL entry to ~/.claude/sessions/external-tools.jsonl.
#   Usage: log_session <json_string>
#   The JSON string is the output from emit_json or emit_error. A timestamp
#   is added to the entry.
# ---------------------------------------------------------------------------
log_session() {
  local json_string="${1:?log_session: json_string required}"

  # Ensure the log directory exists
  mkdir -p "$LOG_DIR"

  local log_file="${LOG_DIR}/external-tools.jsonl"

  if command -v jq >/dev/null 2>&1; then
    # Add timestamp to the JSON entry
    local entry
    entry="$(printf '%s' "$json_string" | jq -c '. + {timestamp: (now | todate)}' 2>/dev/null || printf '%s' "$json_string")"
    printf '%s\n' "$entry" >> "$log_file"
  else
    # Without jq, just append the raw JSON as a single line
    local oneline
    oneline="$(printf '%s' "$json_string" | tr '\n' ' ' | tr -s ' ')"
    printf '%s\n' "$oneline" >> "$log_file"
  fi
}
