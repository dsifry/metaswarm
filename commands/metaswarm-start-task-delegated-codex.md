# Start Task — Delegated to Codex

A variant of `start-task` that forces all implementation work through OpenAI Codex CLI via agent teams. Use this for backend-heavy, multi-issue parallel execution where cost savings matter.

Requires Team Mode (`TeamCreate`/`SendMessage` tools). If Team tools are not available, use `/project:start-task` instead.

## Usage

```text
/project:metaswarm-start-task-delegated-codex <task-description-or-issue-url>
```

## When to Use

- Parallel swarms: multiple issues implemented simultaneously via Codex
- Backend / infrastructure / SDK / CLI tasks (Codex's strength)
- When you want Claude to orchestrate but not write the code itself
- Cost optimization: Codex is significantly cheaper for implementation

## Steps

### 0. Pre-Flight Checks (BLOCKING)

Before anything else, verify the tool stack is ready. ALL checks must pass.

#### 0.1 — External Tools Health

Run via Bash:

```bash
.claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh health
```

Parse the JSON output. If `status` is NOT `"ready"`:
- **STOP** — Tell the user: "Codex CLI is not available. Status: {status}. Fix this before using delegated mode."
- Suggest: "Run `/project:external-tools-health` for diagnostics, or install with `npm i -g @openai/codex`."

#### 0.2 — Check for Existing Worktrees (CRITICAL — Context-Loss Resilience)

**Before starting ANY new work**, check for an existing orchestrator scratchpad first:

```bash
cat /tmp/orchestrator-state-*.json 2>/dev/null || echo "no scratchpad"
```

If a scratchpad exists, read it to recover the full state of the swarm (work units, worktree paths, statuses) without re-polling every agent. This is dramatically cheaper than scanning each worktree individually after context compaction.

If no scratchpad exists, fall back to scanning worktrees:

Run via Bash:

```bash
ls -d /tmp/worktree-* 2>/dev/null || echo "NONE"
```

For each worktree found:

1. Check for agent state:
   ```bash
   cat <worktree>/.agent-state.json 2>/dev/null || echo "no state file"
   ```

2. Check if Codex is still running:
   ```bash
   .claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh status <worktree>
   ```

3. Check for existing commits:
   ```bash
   git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"
   ```

**Decision logic:**
- If a worktree has a **running Codex process**: DO NOT restart. Resume monitoring from where it left off (skip to Step 4 monitoring loop for that work unit).
- If a worktree has **commits but no running process**: Codex finished. Skip to Step 5 validation for that work unit.
- If a worktree has **no commits and no running process**: Abandoned. Clean it up with `codex.sh cleanup <path>` and proceed normally.

Report findings to the user before continuing:

> Found {N} existing worktrees: {M} running, {K} completed, {J} abandoned. Resuming monitoring for running instances.

#### 0.3 — Knowledge Priming

Run BEADS prime if available:

```bash
bd prime --keywords "<task-keywords>" --work-type planning 2>/dev/null || true
```

Review any MUST FOLLOW rules and GOTCHAS before proceeding.

### 1. Task Assessment

Same as `/project:start-task` — use extended thinking to analyze the task:

- Parse the issue URL or task description
- If an issue URL: fetch the issue body with `gh issue view <number> --json title,body,labels`
- Assess complexity and break into work units
- Each work unit should be a self-contained, independently testable piece
- **Task sizing rule**: Each work unit should target **1-4 files** and produce a prompt under **6 KB**. Sessions under 100K tokens (small, focused prompts) are 10-40x cheaper and have 90-100% command success rates vs 87-89% for large sessions. If a work unit touches more than 6 files, split it further.

Ask the user to confirm:

> **Task**: {summary}
> **Work units**: {N} units identified
> **Delegation**: All implementation via Codex CLI
> **Estimated time**: {N} units x ~10-20 min each (Codex running in parallel)
>
> Proceed?

### 2. Work Unit Decomposition

For each work unit, prepare:

- **Scope**: Which files/directories this unit touches
- **Definition of Done**: Specific, testable criteria
- **Context files**: List of files the implementer needs to read
- **Test expectations**: What tests should exist after implementation

### 3. Prompt Preparation & Codex Launch

For each work unit, spawn a sub-agent (via Task tool with `subagent_type: "general-purpose"` and `model: "opus"`) that does the following.

**CRITICAL — Worktree Isolation**: The sub-agent's prompt MUST include this directive:

> Your working directory is `$WORKTREE` (e.g., `/tmp/worktree-<unit-id>`). ALL file reads, edits, writes, and git commands MUST target this worktree path. Do NOT read, edit, or write any files in the main repo (`$REPO_ROOT`). The main repo is off-limits until the orchestrator performs the final merge in Step 8. If you need to read context files, read them from the worktree (they are a full checkout). Use `git -C $WORKTREE` for all git operations.

#### 3.1 — Write the Prompt File

Create a self-contained markdown prompt at `/tmp/codex-prompt-<unit-id>.md` with:

```markdown
# Task: <work unit title>

## Context
<Issue body or task description>
<Relevant CLAUDE.md sections - coding standards, test patterns>

## Files to Modify
<List of files with brief description of needed changes>

## Current Code
<Paste relevant code snippets from context files - Codex can't read your repo without this>

## Definition of Done
<Specific criteria from work unit decomposition>

## Testing Requirements
- Write tests FIRST (TDD)
- Test command: <from project profile>
- Coverage command: <from project profile>
- All tests must pass before committing

## Coding Standards
<From CLAUDE.md - language-specific rules, lint, format requirements>

## Known Gotchas
<Include any project-specific pitfalls discovered from prior runs. Examples:>
- <If TypeScript + ESM: "Use .mjs-compatible syntax: no `catch (e: any)`, use `as any` for untyped imports">
- <If sandbox restrictions: "npm registry may not be reachable. Do NOT run `npm install` or `pnpm install`. Dependencies are pre-installed.">
- <If specific tool limitations: "tsx IPC sockets may be blocked. Use `node --import tsx/esm` instead of `npx tsx`.">
- <If known test patterns: "Tests use vitest, not jest. Do not add jest imports.">

Check `.metaswarm/known-gotchas.md` in the project root if it exists — paste its contents here.

## IMPORTANT
- Only modify files listed above. Do not touch other files.
- Commit your changes with a descriptive message when done.
- Run tests and fix any failures before committing.
- Do NOT commit prompt files (*.codex-prompt*.md) — they are ephemeral.
```

#### 3.2 — Create Worktree & Launch Codex

First, clean up any stale worktree or branch from a previous run:

```bash
ADAPTER=".claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="/tmp/worktree-<unit-id>"
BRANCH="external/codex/<unit-id>"

# Clean up stale worktree/branch if they exist
if [ -d "$WORKTREE" ]; then
  $ADAPTER cleanup "$WORKTREE"
fi
git branch -D "$BRANCH" 2>/dev/null || true
git worktree prune 2>/dev/null || true

# Create fresh worktree
git worktree add -b "$BRANCH" "$WORKTREE" HEAD

# Record the base SHA for later reset/diff operations
BASE_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"

# Install dependencies so Codex can run tests without hitting the registry
# Detect package manager from lock file and install
if [ -f "$WORKTREE/pnpm-lock.yaml" ]; then
  (cd "$WORKTREE" && pnpm install --frozen-lockfile 2>/dev/null) || true
elif [ -f "$WORKTREE/yarn.lock" ]; then
  (cd "$WORKTREE" && yarn install --frozen-lockfile 2>/dev/null) || true
elif [ -f "$WORKTREE/package-lock.json" ]; then
  (cd "$WORKTREE" && npm ci 2>/dev/null) || true
elif [ -f "$WORKTREE/bun.lockb" ]; then
  (cd "$WORKTREE" && bun install --frozen-lockfile 2>/dev/null) || true
fi
```

Write the agent state file for discoverability. Use actual values, not template placeholders:

```bash
# Write .agent-state.json with real values (not a heredoc template)
printf '{"issue":"%s","unit":"%s","status":"codex_running","base_sha":"%s","started_at":"%s","log_path":"","agent":"codex-delegated","attempt":1,"updated_at":"%s","last_check":""}\n' \
  "$ISSUE_NUM" "$UNIT_ID" "$BASE_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$WORKTREE/.agent-state.json"
```

Launch Codex:

```bash
$ADAPTER implement \
  --worktree "$WORKTREE" \
  --prompt-file "/tmp/codex-prompt-<unit-id>.md" \
  --timeout 3600
```

#### 3.3 — Update Agent State

After launching, update `.agent-state.json` with the actual log path from the adapter's output.

### 4. Active Monitoring Loop (CRITICAL — NEVER Go Idle)

**This is the most important behavioral instruction.** After launching Codex, the sub-agent MUST actively monitor. It must NOT go idle. It must NOT wait for the team lead to check on it.

The sub-agent implements this loop using sequential Bash tool calls. Each iteration is a single Bash call that sleeps then checks status:

```
WHILE Codex is running:
  1. Issue a single Bash tool call (with timeout 200000ms):
     sleep 180 && .claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh status <worktree>

  2. Parse the JSON response:
     - If "child_alive": true -> Codex still working. Continue loop.
     - If "child_alive": false -> Codex finished (or crashed). Exit loop.

  3. Optionally check recent log output:
     tail -20 ~/.claude/sessions/codex-implement-*.jsonl 2>/dev/null | tail -5

  4. Update .agent-state.json with current status and timestamp

  5. If more than 30 minutes have elapsed with no new log output:
     WARN — Codex may be stuck. Log this but continue monitoring.
     (Codex tasks legitimately take 30+ minutes for large changes.)

  6. Continue loop
END WHILE
```

**After Codex finishes** (child_alive becomes false):

- Read the adapter's JSON output to check exit code
- If exit code 0: proceed to Step 5 (validation)
- If exit code non-zero: proceed to Step 6 (retry)
- Update `.agent-state.json` status to `"codex_completed"` or `"codex_failed"`

### 5. Independent Validation (Trust Nothing)

After Codex completes successfully, the sub-agent validates independently. Codex claims don't count — verify everything:

#### 5.1 — Check for Changes

```bash
git -C <worktree> log --oneline -5
git -C <worktree> diff --stat $BASE_SHA HEAD
```

If no commits beyond BASE_SHA or no changed files: **FAIL** — Codex didn't produce output.

#### 5.2 — Run Tests

```bash
cd <worktree> && <test command from project profile>
```

If tests fail: record failures for retry context.

#### 5.3 — Run Linter (if configured)

```bash
cd <worktree> && <lint command from project profile>
```

#### 5.4 — Run Type Checker (if configured)

```bash
cd <worktree> && <typecheck command from project profile>
```

#### 5.5 — Check Coverage (if thresholds set)

```bash
cd <worktree> && <coverage command from project profile>
```

Compare against `.coverage-thresholds.json`.

#### 5.6 — Scope Compliance

Check that only files within the work unit's defined scope were modified:

```bash
git -C <worktree> diff --name-only $BASE_SHA HEAD
```

Compare against the allowed file list from work unit decomposition. Flag any out-of-scope changes.

#### 5.7 — Verdict

- If ALL checks pass: **SUCCESS** — Update `.agent-state.json` status to `"validated"`. Report to team lead.
- If ANY check fails: proceed to Step 6 (retry).

### 6. Retry with Codex (Max 2 Retries)

If validation fails, retry with Codex up to 2 additional times:

#### 6.1 — Prepare Retry Prompt

Write a new prompt that includes:
- Original task description
- What Codex produced (diff summary)
- Specific failures (test output, lint errors, type errors)
- Clear instructions on what to fix

#### 6.2 — Reset Worktree

Reset to the original base SHA (handles any number of commits Codex may have made):

```bash
BASE_SHA="$(jq -r '.base_sha' <worktree>/.agent-state.json)"
git -C <worktree> reset --hard "$BASE_SHA"
```

#### 6.3 — Re-launch Codex

Same as Step 3.2 (Codex launch only) but with the retry prompt and `--attempt N+1`.

#### 6.4 — Monitor Again

Same as Step 4.

#### 6.5 — Validate Again

Same as Step 5.

### 7. Escalation to Claude

If Codex fails after 2 retries (3 total attempts), escalate:

- Update `.agent-state.json` status to `"escalated_to_claude"`
- The sub-agent implements the fix directly using Claude (standard implementation)
- **All Claude implementation work MUST happen inside the worktree** — same isolation rules as Codex. Use `Read`/`Edit`/`Write` tools with absolute paths under `$WORKTREE`, not the main repo.
- Include Codex's best attempt and the specific failure points as context
- After Claude implementation: run the same validation suite (Step 5)

### 8. Completion & Cleanup

After all work units are validated:

#### 8.1 — Merge Results (ONLY step that touches the main repo)

This is the **only** step where the orchestrator modifies the main repo working tree. All prior work happened exclusively in worktrees.

For each successful worktree:
- Cherry-pick or merge the work branch into the main feature branch
- Resolve any conflicts

#### 8.2 — Final Validation

Run the full test suite, linter, type checker, and coverage check on the merged result.

#### 8.3 — Cleanup Worktrees

For each worktree:

```bash
.claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh cleanup <worktree>
```

#### 8.4 — Report

Present final summary:

```
Delegated Execution Complete:

  Work Units: {N} total
  Codex Success: {M} (first attempt: {X}, retried: {Y})
  Escalated to Claude: {Z}
  Total Codex Time: {T} minutes
  Total Cost: ~${C} (estimated from token counts)

  All validations passed. Ready for PR.
```

## Behavioral Rules (Baked Into Sub-Agent Prompts)

These rules MUST be included in every sub-agent's prompt. They are non-negotiable:

### Rule 1: Active Monitoring — NEVER Go Idle

> After launching Codex, poll `codex.sh status <worktree>` every 3 minutes. Use a single Bash tool call per iteration: `sleep 180 && codex.sh status <worktree>`. Also `tail -20 <log>` to check progress. Do NOT go idle. Do NOT wait for the team lead to check on you. You are responsible for monitoring your Codex instance until completion or failure.

### Rule 2: Context-Loss Resilience

> Before starting ANY work, check for existing worktrees at `/tmp/worktree-*`. Read `.agent-state.json` in each to understand what it is. Run `codex.sh status <worktree>` for each. If a worktree already has a running Codex process or completed commits, DO NOT restart — resume monitoring or validation from where it left off. Write your state to `<worktree>/.agent-state.json` so the lead can discover your progress after context compaction.

### Rule 3: Self-Contained State

> Write your issue number, work unit ID, status, base SHA, and log path to `<worktree>/.agent-state.json` after every state transition. This file is how the team lead discovers what you're doing if context is lost. Schema:
> ```json
> {
>   "issue": "42",
>   "unit": "wu-backend-auth",
>   "status": "codex_running|monitoring|codex_completed|validating|validated|codex_failed|retrying|escalated_to_claude",
>   "base_sha": "abc123def",
>   "started_at": "2025-01-15T10:30:00Z",
>   "updated_at": "2025-01-15T10:45:00Z",
>   "log_path": "~/.claude/sessions/codex-implement-20250115T103000-12345.jsonl",
>   "agent": "codex-delegated",
>   "attempt": 1,
>   "last_check": "2025-01-15T10:45:00Z"
> }
> ```

### Rule 4: Trust Nothing from Codex

> Codex output is untrusted. Always run tests, linter, type checker, and coverage independently. Never skip validation because Codex claims success in its output.

### Rule 5: Worktree Isolation — NEVER Edit the Main Repo

> Your working directory is `$WORKTREE`. ALL file reads, edits, writes, and git commands MUST use absolute paths under `$WORKTREE`. Do NOT read or modify files at the main repo root (`$REPO_ROOT`). The worktree is a full checkout — every file you need is there. Use `git -C $WORKTREE` for git operations. The ONLY agent that touches the main repo is the orchestrator during Step 8.1 (merge). If you need to escalate and implement directly (Step 7), you still work inside the worktree. Violating this rule causes change leakage: dirty files pile up in the main repo mixing work from multiple agents, making merges impossible.

### Rule 6: Orchestrator Scratchpad (Context-Loss Resilience)

> The orchestrator (team lead) writes a scratchpad file to survive context compaction. After decomposing work units and launching sub-agents, write `.orchestrator-state.json` to the repo root (or `/tmp/orchestrator-state-<task-id>.json`). After any compaction event, read this file FIRST instead of re-polling every agent. Schema:
> ```json
> {
>   "task": "Issue #42: Add authentication",
>   "work_units": [
>     {
>       "id": "wu-auth-middleware",
>       "worktree": "/tmp/worktree-wu-auth-middleware",
>       "branch": "external/codex/wu-auth-middleware",
>       "status": "codex_running|validated|failed",
>       "agent_id": "abc123",
>       "started_at": "2025-01-15T10:30:00Z",
>       "completed_at": null
>     }
>   ],
>   "updated_at": "2025-01-15T10:45:00Z"
> }
> ```
> Update this file after every state transition (agent launched, completed, failed, retried). This is cheaper than re-reading every `.agent-state.json` and re-polling every agent after compaction.
