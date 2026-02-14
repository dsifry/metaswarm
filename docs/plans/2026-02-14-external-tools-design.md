# External Tools: Cross-Model Delegation & Adversarial Review

**Date**: 2026-02-14
**Status**: Approved design
**Version**: 1.0 (v1 scope)

## Problem

The metaswarm orchestrator (Claude) consumes expensive tokens on every task, including simple ones that cheaper models handle well. Meanwhile, using a single model for both implementation and review creates blind spots — shared reasoning patterns mean shared failure modes.

## Solution

A skill and adapter system that delegates implementation and review tasks to external AI CLI tools (OpenAI Codex CLI, Google Gemini CLI), enabling:

1. **Cost savings** — route simple tasks to cheaper models
2. **Cross-model adversarial review** — writer is always reviewed by different models
3. **Graceful degradation** — works with 0, 1, or 2 external tools available

## Core Principles

1. **One job, one invocation** — an external tool implements OR reviews, never self-validates
2. **Minimal permissions** — sandboxed execution, scoped to the task's working directory
3. **Orchestrator verifies independently** — external tools never gate their own output
4. **Trust nothing, verify everything** — consistent with metaswarm's existing philosophy

## External Tools Targeted (v1)

| Tool | Install | Non-Interactive | Full-Auto | JSON Output | Auth |
|------|---------|-----------------|-----------|-------------|------|
| OpenAI Codex CLI | `npm i -g @openai/codex` | `codex exec "prompt"` | `--full-auto` | `--json` + `--output-schema` | API key or ChatGPT subscription |
| Google Gemini CLI | `npm i -g @google/gemini-cli` | `gemini "prompt"` | `--yolo` | `--output-format json` | Google login (free 1K req/day) or API key |

Both tools support:
- Working directory scoping (`-C` / `--include-directories`)
- Stdin piping for context
- Project instruction files (`AGENTS.md` / `GEMINI.md`)
- MCP server integration

## Architecture

```
metaswarm/
├── skills/
│   └── external-tools/
│       ├── skill.md                  # Orchestration skill (routing, escalation, 4-phase integration)
│       └── adapters/
│           ├── _common.sh            # Shared: safe_invoke(), worktree ops, logging, cost tracking
│           ├── codex.sh              # OpenAI Codex CLI adapter
│           └── gemini.sh             # Google Gemini CLI adapter
├── templates/
│   └── external-tools-setup.md      # User setup guide (install, auth, config)
└── .claude/
    └── rubrics/
        └── external-tool-review-rubric.md  # Cross-model review standard
```

### Configuration

Per-project config at `.metaswarm/external-tools.yaml` (optional — if absent, external tools are not used):

```yaml
adapters:
  codex:
    enabled: true
    model: "gpt-5.3-codex"
    timeout_seconds: 300
    sandbox: docker          # docker | platform | none
  gemini:
    enabled: true
    model: "pro"
    timeout_seconds: 300
    sandbox: docker

routing:
  default_implementer: "cheapest-available"
  escalation_order: ["codex", "gemini", "claude"]

budget:
  per_task_usd: 2.00        # circuit breaker per task
  per_session_usd: 20.00    # circuit breaker per session
```

## Adapter Protocol

Each adapter implements three commands with a uniform interface.

### Command 1: `health` — Preflight Check

```bash
adapters/codex.sh health
```

Returns:

```json
{
  "tool": "codex",
  "status": "ready|degraded|unavailable",
  "version": "2.1.0",
  "auth_valid": true,
  "model": "gpt-5.3-codex"
}
```

Called before task dispatch and on auth expiration to determine available tools.

### Command 2: `implement` — Write Code

```bash
adapters/codex.sh implement \
  --worktree "/tmp/ext-codex-task-42" \
  --prompt-file "/private/tmp/xt-abc123/prompt.md" \
  --attempt 1 \
  --timeout 300
```

### Command 3: `review` — Review Code (as independent reviewer)

```bash
adapters/codex.sh review \
  --worktree "/tmp/ext-codex-task-42" \
  --rubric-file "./rubrics/external-tool-review-rubric.md" \
  --spec-file "/private/tmp/xt-abc123/spec.md" \
  --timeout 300
```

### Output Format (v1 — facts only, no self-judgments)

Both `implement` and `review` return:

```json
{
  "tool": "codex",
  "command": "implement",
  "model": "gpt-5.3-codex",
  "attempt": 1,
  "exit_code": 0,
  "branch": "external/codex/task-42",
  "git_sha": "abc123f",
  "files_changed": ["src/auth/login.ts"],
  "diff_stats": { "additions": 42, "deletions": 7 },
  "duration_seconds": 85,
  "cost": { "input_tokens": 12000, "output_tokens": 3400 },
  "raw_log": "~/.claude/sessions/ext-codex-task-42-attempt-1.log",
  "error_type": null,
  "schema_version": "1"
}
```

For `review` commands, the raw log contains the reviewer's analysis. The orchestrator reads and evaluates it — the adapter never self-judges.

### Error Types

When `exit_code != 0`, `error_type` is one of:

| Error Type | Meaning | Orchestrator Action |
|---|---|---|
| `tool_not_installed` | Binary not found | Skip adapter, try next |
| `auth_expired` | API key invalid/expired | Escalate to user |
| `auth_missing` | No API key configured | Escalate to user |
| `network_error` | Cannot reach API | Retry with backoff, then skip |
| `rate_limited` | API rate limit hit | Wait and retry |
| `timeout` | Tool exceeded time limit | Retry once, then skip |
| `context_too_large` | Input exceeds context window | Reduce context, retry |
| `cost_limit_exceeded` | Would exceed budget | Skip, alert user |
| `tool_crash` | Unexpected exit | Retry once, then skip |
| `output_parse_error` | Malformed output | Log raw output, treat as failure |

## Integration with 4-Phase Loop

External tools slot into the **existing** orchestrated execution loop:

```
Orchestrator receives work unit
    |
    v
Routing: pick implementer based on availability, cost, complexity
    |
    v
Phase 1 -- IMPLEMENT:
  If external tool:
    - health check (skip if unavailable)
    - create worktree (git worktree add)
    - package context into prompt file (secure temp dir)
    - safe_invoke() with timeout wrapper
    - scope check: verify all changes within context-dir
    - capture output JSON (facts only)
  If Claude:
    - existing Task() mechanism (unchanged)
    |
    v
Phase 2 -- VALIDATE (always orchestrator, unchanged):
    - npm test / npm run lint / npm run test:coverage
    - scope verification
    - PASS/FAIL (orchestrator decides)
    |
    v
Phase 3 -- ADVERSARIAL REVIEW (cross-model):
    - Reviewer 1: one of the other two models (via adapter review command)
    - Reviewer 2: the remaining model (via adapter review command or Claude Task())
    - Orchestrator evaluates review output independently
    |
    v
Phase 4 -- COMMIT (unchanged):
    - merge branch, cleanup worktree, log session
```

## Escalation Model (Availability-Aware)

The orchestrator adapts based on which tools are available.

### Two external models available (full chain):

```
Model A implements (attempt 1)
  Orchestrator validates + cross-model review (B + Claude)
  FAIL -> feedback to Model A

Model A implements (attempt 2, with review feedback)
  Orchestrator validates + cross-model review
  FAIL -> escalate to Model B

Model B implements (attempt 1, with Model A's branch as reference)
  Orchestrator validates + cross-model review (A + Claude)
  FAIL -> feedback to Model B

Model B implements (attempt 2, with review feedback)
  Orchestrator validates + cross-model review
  FAIL -> escalate to Claude

Claude implements (with both branches as reference)
  Orchestrator validates + cross-model review (A + B)
  FAIL -> alert user with all branches, findings, CI results
```

Worst case: 5 attempts (2 + 2 + 1) before user alert.

### One external model available (reduced chain):

```
Model A implements (attempt 1)
  Orchestrator validates + review (Claude reviews)
  FAIL -> feedback to Model A

Model A implements (attempt 2, with review feedback)
  Orchestrator validates + review (Claude reviews)
  FAIL -> escalate to Claude

Claude implements (with Model A's branch as reference)
  Orchestrator validates + review (Model A reviews)
  FAIL -> alert user
```

Worst case: 3 attempts before user alert.

### No external models available:

```
Existing metaswarm behavior unchanged.
Claude implements via Task() mechanism.
Standard adversarial review (fresh Task() instance).
```

### Routing Logic

```python
available_tools = [t for t in adapters if t.health() == "ready"]

if len(available_tools) == 2:
    implementer = cheapest(available_tools)
    reviewers = [other_tool, claude]
    escalation = [implementer, other_tool, claude, user]
elif len(available_tools) == 1:
    implementer = available_tools[0]
    reviewers = [implementer, claude]  # mutual review
    escalation = [implementer, claude, user]
else:
    # pure metaswarm, no change
    implementer = claude
    reviewers = [claude_fresh_task]
    escalation = [claude, user]
```

Health is checked per task dispatch, not just session start (auth can expire mid-session).

## Safety & Sandboxing

### Worktree Isolation

Every adapter invocation runs in an isolated git worktree:

```bash
# _common.sh: create_worktree()
git worktree add "$WORKTREE_PATH" -b "external/$TOOL/$TASK_ID"
# External tool runs scoped to $WORKTREE_PATH
# After completion: git worktree remove "$WORKTREE_PATH"
```

This prevents workspace contamination and enables concurrent execution.

### Secure Temp Files

```bash
# _common.sh: create_secure_tmp()
TMPDIR=$(mktemp -d -t "xt-XXXXXX")
chmod 700 "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT
```

Prompt files, spec files, and rubric files live in the secure temp dir.

### Sandbox Execution (configurable per adapter)

**Docker sandbox (default)**:

```bash
docker run --rm \
  -v "$WORKTREE_PATH:/workspace" \
  -e "OPENAI_API_KEY" \
  --network=host \
  --read-only \
  codex-adapter:latest \
  codex exec --full-auto -C /workspace "..."
```

**Platform sandbox (macOS fallback)**:

```bash
sandbox-exec -f adapter.sb codex exec --full-auto ...
```

**None (user's choice, for trusted environments)**:

```bash
codex exec --full-auto -C "$WORKTREE_PATH" "..."
```

### Minimal Environment

Only pass the tool's own API key; strip everything else:

```bash
env -i HOME="$HOME" PATH="$PATH" OPENAI_API_KEY="$KEY" codex exec ...
```

### Post-Run Scope Verification

```bash
# _common.sh: verify_scope()
git -C "$WORKTREE_PATH" diff --name-only | while read file; do
  if [[ "$file" != "$CONTEXT_DIR"* ]]; then
    git -C "$WORKTREE_PATH" checkout HEAD -- "$file"
    log_warning "SCOPE VIOLATION: $file reverted"
  fi
done
```

## Shared Helpers (_common.sh)

| Helper | Purpose |
|---|---|
| `safe_invoke()` | Timeout-wrapped invocation with exit code handling and dead-process detection |
| `create_worktree()` / `cleanup_worktree()` | Git worktree lifecycle |
| `create_secure_tmp()` | Secure temp directory (mode 700, trap cleanup) |
| `package_context()` | Gather relevant files, spec, acceptance criteria into prompt file with token budgeting |
| `verify_scope()` | Reject file changes outside context-dir |
| `extract_cost()` | Post-execution token/cost extraction from tool output |
| `log_session()` | Structured entry to ~/.claude/sessions/ for self-reflection |
| `check_health()` | Verify tool installed, authenticated, and reachable |

### safe_invoke() — Timeout & Error Handling

```bash
safe_invoke() {
  local timeout=$1; shift
  local output
  output=$(timeout "$timeout" "$@" 2>/tmp/adapter-stderr)
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo '{"error_type": "timeout", "exit_code": 124}'
    return 1
  elif [ $exit_code -ne 0 ]; then
    # Parse stderr for known error patterns
    classify_error "$exit_code" /tmp/adapter-stderr
    return 1
  fi

  echo "$output"
}
```

### package_context() — Token-Budgeted Context

Addresses the Codex 10KB file truncation issue:

- Estimates token count per file (chars/4 heuristic)
- Prioritizes: changed files > test files > imports > surrounding context
- Truncates to model's context budget (configurable per adapter)
- On retry: includes review feedback summary, not full prior output
- On escalation: includes prior branch diff summary, not full branch

## Logging & Self-Reflection

All adapter invocations produce structured session log entries in `~/.claude/sessions/`:

```
Session log entry:
  - timestamp, tool, command, model, attempt
  - prompt content hash (what we asked)
  - output JSON (facts: exit code, files changed, cost)
  - CI gate results (from orchestrator's Phase 2)
  - review output (from cross-model Phase 3)
  - outcome: success | retry | escalated | user_alert
  - cost (tokens used, estimated USD)
```

This feeds the existing `/self-reflect` pipeline. Over time, the knowledge base accumulates entries like:

- **pattern**: "Codex excels at single-file TypeScript implementations"
- **gotcha**: "Gemini tends to skip error handling in async functions"
- **decision**: "Route database migration tasks directly to Claude (external tools fail 80%)"

These learnings improve future routing decisions automatically.

## Context Packaging: The Prompt File

The prompt file is the key interface between metaswarm and external tools. It must be self-contained — the external tool has no access to BEADS, knowledge base, or conversation history.

### Prompt File Structure

```markdown
# Task: [task title]

## Acceptance Criteria
- [ ] criterion 1
- [ ] criterion 2

## Context
[relevant file contents, token-budgeted]

## Coding Standards
[extracted from project's CLAUDE.md / coding standards guide]

## Test Expectations
[what tests should pass, coverage requirements]

## Previous Attempt (if retry)
[review feedback from last attempt — what to fix]

## Prior Model's Attempt (if escalation)
[diff summary from previous model's branch — what was tried, why it failed]
```

## Adding a New Adapter

To add support for a new external tool (e.g., `cursor`, `aider`, `cline`):

1. Create `adapters/newtool.sh` implementing `health`, `implement`, and `review`
2. Use `_common.sh` helpers for worktree, temp files, logging, scope verification
3. Handle tool-specific CLI flags and output parsing internally
4. Return the standard JSON output format
5. Add the tool to `.metaswarm/external-tools.yaml`
6. Add a Docker image or sandbox profile if needed

The adapter is responsible for translating between the uniform protocol and the tool's specific CLI. All tool-specific quirks stay inside the adapter.

## Known Limitations (v1)

1. **Gemini CLI lacks custom structured output schemas** (GitHub issue #13388) — the gemini adapter must parse free-text responses, which is less reliable than Codex's `--output-schema`
2. **Both CLIs can hang on rate limits** — mitigated by `safe_invoke()` timeout wrapping, but some edge cases may slip through
3. **Cost estimation is approximate** — based on token counts from tool output, not actual billing; different tokenizers per model add ~15-30% variance
4. **No pre-execution cost prediction** — we can only measure cost after execution, not cap it before

## Future Enhancements (post-v1)

- Cross-model escalation metrics dashboard
- Per-language model preference learning (auto-routing based on historical success)
- Parallel implementation: two models implement simultaneously, pick the better result
- External tools as design/plan review gate participants
- Budget forecasting based on historical cost data

## Adversarial Review Findings (incorporated)

This design was reviewed by three adversarial reviewers (feasibility, completeness, security & scope). Key findings incorporated:

1. **No self-certification** — external tools report facts only, orchestrator judges
2. **Worktree isolation** — prevents workspace contamination between concurrent invocations
3. **Timeout wrapping** — handles CLI hang/crash on rate limits
4. **Token budgeting in context packaging** — handles Codex's 10KB truncation
5. **Sandbox execution** — prevents filesystem access beyond the working directory
6. **Minimal environment** — only the tool's own API key is passed
7. **Scope verification** — rejects out-of-scope file changes post-execution
8. **Structured error taxonomy** — enables automated recovery decisions
9. **Circuit breaker** — per-task and per-session cost budgets
10. **Simplified escalation** — 5 attempts max (2+2+1), not 9
