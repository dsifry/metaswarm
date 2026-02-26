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

# External Tools Skill

## Purpose

This skill delegates implementation and review tasks to external AI CLI tools (OpenAI Codex CLI, Google Gemini CLI), enabling cost savings through cheaper models and cross-model adversarial review that eliminates single-model blind spots. Three core principles govern every interaction: **one job per invocation** (an external tool implements OR reviews, never self-validates), **minimal permissions** (sandboxed execution scoped to the task's working directory with only the tool's own API key), and **the orchestrator verifies independently** (external tools report facts only, the orchestrator judges pass/fail).

---

## Prerequisites

### Required Tools

| Tool | Install | Auth |
|------|---------|------|
| OpenAI Codex CLI | `npm i -g @openai/codex` | API key or ChatGPT subscription |
| Google Gemini CLI | `npm i -g @google/gemini-cli` | Google login (free 1K req/day) or API key |

Neither tool is strictly required. The skill adapts based on what is available (see Escalation Model below).

### Configuration

Per-project config at `.metaswarm/external-tools.yaml` (optional -- if absent, external tools are not used):

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

### Fallback Behavior

- **Both tools available**: Full cross-model delegation and review
- **One tool available**: Reduced chain with mutual review between the tool and Claude
- **No tools available**: Existing metaswarm behavior unchanged; skill is a no-op

---

## Quick Reference

### Health Check

```bash
# Check if Codex is installed, authenticated, and reachable
adapters/codex.sh health

# Check Gemini
adapters/gemini.sh health
```

Returns JSON with `status: "ready|degraded|unavailable"`.

### Implement

```bash
adapters/codex.sh implement \
  --worktree "/tmp/ext-codex-task-42" \
  --prompt-file "/private/tmp/xt-abc123/prompt.md" \
  --attempt 1 \
  --timeout 300
```

### Review

```bash
adapters/gemini.sh review \
  --worktree "/tmp/ext-codex-task-42" \
  --rubric-file "./rubrics/external-tool-review-rubric.md" \
  --spec-file "/private/tmp/xt-abc123/spec.md" \
  --timeout 300
```

All commands return a uniform JSON envelope with facts only (exit code, files changed, cost, duration). The orchestrator interprets results -- adapters never self-judge.

---

## Workflow: Routing & Dispatch

### Phase 0: Tool Discovery (Health Checks)

Before dispatching any task, the orchestrator runs health checks to determine which tools are available:

```bash
# Run health checks for all configured adapters
for adapter in adapters/*.sh; do
  result=$("$adapter" health)
  # Parse status: ready | degraded | unavailable
done
```

Health is checked **per task dispatch**, not just at session start. Auth tokens can expire mid-session, network conditions change, and rate limits reset. A tool that was `ready` five minutes ago may now be `unavailable`.

Build the available tools list:

```python
available_tools = [t for t in adapters if t.health() == "ready"]
```

### Phase 1: IMPLEMENT (External Tool or Claude)

If an external tool is selected as implementer:

1. **Create worktree** -- `git worktree add "$WORKTREE_PATH" -b "external/$TOOL/$TASK_ID"` for isolation
2. **Package context** -- Gather relevant files, spec, acceptance criteria into a prompt file in a secure temp dir (mode 700, trap cleanup). Token-budget the context to fit the model's window.
3. **Invoke** -- `safe_invoke()` with timeout wrapper; capture JSON output
4. **Scope check** -- Verify all file changes are within the declared file scope; revert any out-of-scope changes
5. **Capture output** -- Facts only: exit code, files changed, diff stats, cost, duration

If Claude is selected (escalation or no external tools), use the existing `Task()` mechanism unchanged.

### Phase 2: VALIDATE (Always Orchestrator -- Unchanged)

The orchestrator independently runs all quality gates:

- `npm test` / `npx vitest run`
- `npx tsc --noEmit`
- `npx eslint <changed-files>`
- Coverage enforcement via `.coverage-thresholds.json`
- File scope verification via `git diff --name-only`

This phase is identical whether the implementer was an external tool or Claude. **Never trust the implementer's self-report.**

### Phase 3: ADVERSARIAL REVIEW (Cross-Model)

The key advantage of external tools: the writer is always reviewed by a **different model**.

| Implementer | Reviewer 1 | Reviewer 2 |
|-------------|-----------|-----------|
| Codex | Gemini (via adapter) | Claude (via Task) |
| Gemini | Codex (via adapter) | Claude (via Task) |
| Claude | Codex (via adapter) | Gemini (via adapter) |

Review is invoked via the adapter's `review` command. The orchestrator reads the reviewer's raw log and evaluates it independently -- the adapter never returns a pass/fail verdict.

### Phase 4: COMMIT (Unchanged)

After passing adversarial review:

1. Merge the worktree branch into the working branch
2. Clean up the worktree (`git worktree remove`)
3. Log the session for self-reflection
4. Commit with DoD verification in the commit message

---

## Escalation Model (Availability-Aware)

The orchestrator adapts its escalation chain based on which tools passed their health checks.

### Scenario 1: Two External Tools Available (5 attempts max)

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

**Worst case: A(2) + B(2) + Claude(1) = 5 attempts before user alert.**

### Scenario 2: One External Tool Available (3 attempts max)

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

**Worst case: A(2) + Claude(1) = 3 attempts before user alert.**

### Scenario 3: No External Tools Available

```
Existing metaswarm behavior unchanged.
Claude implements via Task() mechanism.
Standard adversarial review (fresh Task() instance).
```

No change to the current workflow. The skill is a no-op.

---

## Routing Logic

The orchestrator selects the implementer for each task using cheapest-available selection:

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

**Selection criteria for `cheapest()`**:

1. Pick the tool with lower estimated cost per invocation (based on model pricing and average token usage from session logs)
2. On tie, prefer the tool with higher historical success rate for this task type
3. If no historical data, prefer Gemini (free tier) over Codex

---

## Prompt File Format

The prompt file is the key interface between the orchestrator and external tools. It must be **self-contained** -- the external tool has no access to BEADS, knowledge base, or conversation history.

```markdown
# Task: [task title]

## Acceptance Criteria
- [ ] criterion 1
- [ ] criterion 2
- [ ] criterion 3

## Context
[relevant file contents, token-budgeted]
[prioritized: changed files > test files > imports > surrounding context]

## Coding Standards
[extracted from project's CLAUDE.md / coding standards guide]
[language-specific rules, naming conventions, patterns]

## Test Expectations
[what tests should pass after implementation]
[coverage requirements from .coverage-thresholds.json]
[test runner command: e.g., npx vitest run]

## Previous Attempt (if retry)
[review feedback from last attempt -- what to fix]
[DO NOT include full prior output, only the actionable feedback summary]

## Prior Model's Attempt (if escalation)
[diff summary from previous model's branch -- what was tried, why it failed]
[DO NOT include full branch, only the relevant diff summary]
```

**Token budgeting rules** (handled by `package_context()` in `_common.sh`):

- Estimate tokens per file using chars/4 heuristic
- Prioritize context: changed files > test files > imports > surrounding context
- Truncate to the model's context budget (configurable per adapter)
- On retry: include review feedback summary, not full prior output
- On escalation: include prior branch diff summary, not full branch

---

## Error Handling

When an adapter returns `exit_code != 0`, the `error_type` field determines the orchestrator's response:

| Error Type | Meaning | Orchestrator Action |
|---|---|---|
| `tool_not_installed` | Binary not found | Skip adapter, try next in escalation chain |
| `auth_expired` | API key invalid or expired | Escalate to user with setup instructions |
| `auth_missing` | No API key configured | Escalate to user with setup instructions |
| `network_error` | Cannot reach API | Retry with exponential backoff, then skip adapter |
| `rate_limited` | API rate limit hit | Wait and retry (respect Retry-After if provided) |
| `timeout` | Tool exceeded time limit | Retry once with increased timeout, then skip adapter |
| `context_too_large` | Input exceeds context window | Reduce context via `package_context()`, retry |
| `cost_limit_exceeded` | Would exceed budget | Skip adapter, alert user about budget status |
| `tool_crash` | Unexpected exit | Retry once, then skip adapter |
| `output_parse_error` | Malformed JSON output | Log raw output for debugging, treat as failure |

**General rules:**

- "Skip adapter" means move to the next tool in the escalation chain, not abort the task
- All errors are logged to `~/.claude/sessions/` for self-reflection
- Auth errors always escalate to the user -- the orchestrator cannot fix credentials
- Network and rate-limit errors get transient-failure treatment (backoff + retry)

---

## Budget Enforcement

Two circuit breakers prevent runaway costs:

### Per-Task Budget (`per_task_usd`)

Before each adapter invocation, the orchestrator checks cumulative cost for the current task:

```
if task_cost_so_far + estimated_cost > per_task_usd:
    error_type = "cost_limit_exceeded"
    skip adapter, try next in escalation chain (or Claude)
```

Default: `$2.00` per task.

### Per-Session Budget (`per_session_usd`)

Before each adapter invocation, the orchestrator checks cumulative cost across all tasks in the session:

```
if session_cost_so_far + estimated_cost > per_session_usd:
    error_type = "cost_limit_exceeded"
    alert user: "Session budget exhausted. External tools disabled for remaining tasks."
    fall back to Claude for all remaining work
```

Default: `$20.00` per session.

### Cost Tracking

Cost is extracted post-execution from the adapter's JSON output (`cost.input_tokens`, `cost.output_tokens`) and converted to USD using known model pricing. Cost estimation is approximate (~15-30% variance due to different tokenizers per model). There is no pre-execution cost prediction in v1 -- cost is measured after execution, not capped before.

---

## Anti-Patterns

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
|---|---|---|---|
| 1 | **Trusting external tool self-reports** -- tool says "all tests pass" and orchestrator believes it | External tools can hallucinate, skip steps, or misinterpret results; same reasoning as the no-self-certification rule for subagents | Orchestrator runs Phase 2 (VALIDATE) independently; adapter output contains facts only, never verdicts |
| 2 | **Skipping cross-model review** -- "the external tool's code looks fine, committing directly" | Single-model blind spots are the whole reason this skill exists; bypassing review defeats the purpose | Always run Phase 3 with a different model as reviewer; cross-model review is mandatory |
| 3 | **Running without timeout** -- invoking an adapter without `safe_invoke()` timeout wrapper | External CLIs can hang on rate limits, network issues, or infinite loops; an unmonitored invocation blocks the entire pipeline | Always use `safe_invoke()` with the configured `timeout_seconds`; handle timeout as a retryable error |
| 4 | **Passing the full environment** -- running the external tool with the orchestrator's full env vars | Leaks API keys, session tokens, and internal state to an external process that only needs its own credentials | Use `env -i` to pass only `HOME`, `PATH`, and the tool's own API key; see Minimal Environment in the design doc |
| 5 | **Working in the main repo** -- running external tools directly in the project working directory instead of a worktree | Concurrent invocations corrupt each other's state; failed attempts leave dirty files; no clean rollback path | Always create an isolated git worktree per invocation; merge only after all phases pass |

---

## Logging

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

These logs feed the existing `/self-reflect` pipeline. Over time, the knowledge base accumulates routing intelligence:

- **Patterns**: "Codex excels at single-file TypeScript implementations"
- **Gotchas**: "Gemini tends to skip error handling in async functions"
- **Routing decisions**: "Route database migration tasks directly to Claude (external tools fail 80%)"

Future routing decisions improve automatically as the knowledge base grows from session log analysis.
