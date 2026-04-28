#!/bin/bash
# opencode.sh — OpenCode adapter for external-tools
#
# Commands:
#   health     Preflight check: binary exists, version, auth status
#   implement  Write code on a worktree branch via `opencode run`
#   review     Review code changes against a rubric/spec via `opencode run`
#
# Usage:
#   opencode.sh health
#   opencode.sh implement --worktree <path> --prompt-file <path> [--attempt N] [--timeout S] [--context-dir <dir>] [--model <provider/model>]
#   opencode.sh review   --worktree <path> --rubric-file <path> --spec-file <path> [--attempt N] [--timeout S] [--model <provider/model>]
#
# Notes:
#   OpenCode supports many providers (Anthropic, OpenAI, Google, OpenRouter, etc.)
#   via `--model provider/model`. The model is configurable per project via
#   `.metaswarm/external-tools.yaml`. The default below is a reasonable baseline;
#   adjust per project.

set -euo pipefail

# ---------------------------------------------------------------------------
# Source shared helpers
# ---------------------------------------------------------------------------
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TOOL_NAME="opencode"
TOOL_CMD="opencode"
DEFAULT_MODEL="anthropic/claude-opus-4.7"

# Allow override via environment (read by caller from external-tools.yaml)
if [[ -n "${METASWARM_OPENCODE_MODEL:-}" ]]; then
  DEFAULT_MODEL="$METASWARM_OPENCODE_MODEL"
fi

# ===========================================================================
# health — Preflight check
# ===========================================================================
cmd_health() {
  local status="ready"
  local version="unknown"
  local auth_valid=false

  # Check if opencode binary exists
  if ! command -v "$TOOL_CMD" >/dev/null 2>&1; then
    printf '{"tool":"%s","status":"unavailable","version":"not_installed","auth_valid":false,"model":"%s"}\n' \
      "$TOOL_NAME" "$DEFAULT_MODEL"
    return 0
  fi

  # Get version
  version="$("$TOOL_CMD" --version 2>/dev/null || printf 'unknown')"
  version="$(printf '%s' "$version" | tr -d '\n' | xargs)"

  # Auth: OpenCode supports many providers. Treat as auth_valid if any of the
  # well-known provider env vars is present, OR if `opencode providers` lists
  # at least one configured provider.
  if [[ -n "${ANTHROPIC_API_KEY:-}" \
     || -n "${OPENAI_API_KEY:-}" \
     || -n "${GEMINI_API_KEY:-}" \
     || -n "${GOOGLE_API_KEY:-}" \
     || -n "${OPENROUTER_API_KEY:-}" \
     || -n "${GROQ_API_KEY:-}" \
     || -n "${MISTRAL_API_KEY:-}" \
     || -n "${OPENCODE_API_KEY:-}" ]]; then
    auth_valid=true
  elif "$TOOL_CMD" providers list >/dev/null 2>&1; then
    # If at least one provider is configured, treat as valid (best effort)
    if "$TOOL_CMD" providers list 2>/dev/null | grep -qE '^[[:space:]]*[a-z]+'; then
      auth_valid=true
    fi
  fi

  if [[ "$auth_valid" == "false" ]]; then
    status="unavailable"
  fi

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

  local model="${XT_MODEL:-$DEFAULT_MODEL}"

  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.jsonl"
  local stderr_file="${tmp_dir}/stderr.log"

  local prompt_content
  prompt_content="$(cat "$XT_PROMPT_FILE")"

  local start_time
  start_time="$(date +%s)"

  # Invoke opencode with minimal environment. `--dangerously-skip-permissions`
  # is required for non-interactive runs that need to write files. The worktree
  # provides isolation; scope is verified post-run via verify_scope.
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_API_KEY="${GOOGLE_API_KEY:-}" \
      OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
      GROQ_API_KEY="${GROQ_API_KEY:-}" \
      MISTRAL_API_KEY="${MISTRAL_API_KEY:-}" \
      OPENCODE_API_KEY="${OPENCODE_API_KEY:-}" \
    "$TOOL_CMD" run --pure --format json --dir "$XT_WORKTREE" --model "$model" \
      --dangerously-skip-permissions "$prompt_content" \
    || exit_code=$?

  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-implement-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.jsonl"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    local error_json
    error_json="$(emit_error \
      "$TOOL_NAME" \
      "implement" \
      "$model" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"
    log_session "$error_json"
    printf '%s\n' "$error_json"
    rm -rf "$tmp_dir"
    return 1
  fi

  # Success: stage and commit changes in worktree
  local branch=""
  local git_sha=""

  if [[ -d "$XT_WORKTREE" ]]; then
    git -C "$XT_WORKTREE" add -A 2>/dev/null || true

    if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
      git -C "$XT_WORKTREE" commit -m "feat: opencode implement (attempt ${XT_ATTEMPT}, model ${model})" \
        --author="OpenCode <opencode@opencode.ai>" \
        >/dev/null 2>&1 || true
    fi

    if [[ -n "$XT_CONTEXT_DIR" ]]; then
      if ! verify_scope "$XT_WORKTREE" "$XT_CONTEXT_DIR"; then
        git -C "$XT_WORKTREE" add -A 2>/dev/null || true
        if ! git -C "$XT_WORKTREE" diff --cached --quiet 2>/dev/null; then
          git -C "$XT_WORKTREE" commit -m "fix: revert out-of-scope changes" \
            --author="OpenCode <opencode@opencode.ai>" \
            >/dev/null 2>&1 || true
        fi
      fi
    fi

    branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || true)"
  fi

  local cost_json
  cost_json="$(extract_cost_opencode "$stdout_file")"

  local files_changed_json
  files_changed_json="$(get_changed_files "$XT_WORKTREE")"

  local diff_stats_json
  diff_stats_json="$(get_diff_stats "$XT_WORKTREE")"

  local result_json
  result_json="$(emit_json \
    "$TOOL_NAME" \
    "implement" \
    "$model" \
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

  rm -rf "$tmp_dir"
}

# ===========================================================================
# review — Review code changes (read-only)
# ===========================================================================
cmd_review() {
  parse_args "$@"

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

  local model="${XT_MODEL:-$DEFAULT_MODEL}"

  local tmp_dir
  tmp_dir="$(create_secure_tmp)"
  local stdout_file="${tmp_dir}/stdout.jsonl"
  local stderr_file="${tmp_dir}/stderr.log"

  local diff_content
  diff_content="$(git -C "$XT_WORKTREE" diff HEAD 2>/dev/null || true)"
  if [[ -z "$diff_content" ]]; then
    diff_content="$(git -C "$XT_WORKTREE" diff HEAD~1 HEAD 2>/dev/null || true)"
  fi

  local rubric_content
  rubric_content="$(cat "$XT_RUBRIC_FILE")"

  local spec_content
  spec_content="$(cat "$XT_SPEC_FILE")"

  local review_prompt
  review_prompt="$(cat <<'PROMPT_TEMPLATE'
You are a code reviewer. Review the following code changes against the provided rubric and specification. Do NOT modify any files — this is a read-only review.

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

  local start_time
  start_time="$(date +%s)"

  # For review we want a read-only invocation. OpenCode does not yet expose a
  # dedicated read-only sandbox flag like Codex, so we run without
  # --dangerously-skip-permissions; the model will be unable to execute writes
  # interactively in headless mode and will fall through to producing the
  # requested JSON review output.
  local exit_code=0
  safe_invoke "$XT_TIMEOUT" "$stdout_file" "$stderr_file" \
    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
      GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
      GOOGLE_API_KEY="${GOOGLE_API_KEY:-}" \
      OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
      GROQ_API_KEY="${GROQ_API_KEY:-}" \
      MISTRAL_API_KEY="${MISTRAL_API_KEY:-}" \
      OPENCODE_API_KEY="${OPENCODE_API_KEY:-}" \
    "$TOOL_CMD" run --pure --format json --dir "$XT_WORKTREE" --model "$model" \
      "$review_prompt" \
    || exit_code=$?

  local end_time
  end_time="$(date +%s)"
  local duration=$(( end_time - start_time ))

  mkdir -p "$LOG_DIR"
  local session_id
  session_id="${TOOL_NAME}-review-$(date +%Y%m%dT%H%M%S)-$$"
  local raw_log_file="${LOG_DIR}/${session_id}.jsonl"
  if [[ -f "$stdout_file" ]]; then
    cp "$stdout_file" "$raw_log_file"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    local error_json
    error_json="$(emit_error \
      "$TOOL_NAME" \
      "review" \
      "$model" \
      "$XT_ATTEMPT" \
      "$exit_code" \
      "$stderr_file" \
      "$duration" \
      "$raw_log_file")"
    log_session "$error_json"
    printf '%s\n' "$error_json"
    rm -rf "$tmp_dir"
    return 1
  fi

  local cost_json
  cost_json="$(extract_cost_opencode "$stdout_file")"

  local branch=""
  local git_sha=""
  if [[ -d "$XT_WORKTREE" ]]; then
    branch="$(git -C "$XT_WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git_sha="$(git -C "$XT_WORKTREE" rev-parse HEAD 2>/dev/null || true)"
  fi

  local result_json
  result_json="$(emit_json \
    "$TOOL_NAME" \
    "review" \
    "$model" \
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
  health      Check if OpenCode is installed, authenticated, and ready
  implement   Run OpenCode on a worktree to implement changes
  review      Run OpenCode to review code changes (read-only intent)

Options (implement):
  --worktree <path>       Path to the git worktree (required)
  --prompt-file <path>    Path to the prompt file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 300)
  --context-dir <dir>     Restrict changes to this directory
  --model <p/m>           provider/model (default: $DEFAULT_MODEL)

Options (review):
  --worktree <path>       Path to the git worktree (required)
  --rubric-file <path>    Path to the review rubric file (required)
  --spec-file <path>      Path to the specification file (required)
  --attempt <N>           Attempt number (default: 1)
  --timeout <seconds>     Timeout in seconds (default: 300)
  --model <p/m>           provider/model (default: $DEFAULT_MODEL)

Environment variables (any one is sufficient for auth):
  ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, GOOGLE_API_KEY,
  OPENROUTER_API_KEY, GROQ_API_KEY, MISTRAL_API_KEY, OPENCODE_API_KEY

  METASWARM_OPENCODE_MODEL  Override default model
USAGE
    exit 1
    ;;
esac
