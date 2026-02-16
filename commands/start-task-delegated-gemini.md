# Start Task — Delegated to Gemini

A variant of `start-task` that forces all implementation work through Google Gemini CLI via agent teams. Use this for frontend-heavy, UI/component tasks where Gemini excels.

## Usage

```text
/project:start-task-delegated-gemini <task-description-or-issue-url>
```

## When to Use

- Frontend / UI / component tasks (Gemini's strength per routing config)
- React, Next.js, Vue, Svelte, CSS/Tailwind work
- Dashboard and layout implementations
- When Codex is unavailable or over-budget
- Cost optimization with Google's free tier (1K req/day)

## Steps

### 0. Pre-Flight Checks (BLOCKING)

Before anything else, verify the tool stack is ready. ALL checks must pass.

#### 0.1 — External Tools Health

Run via Bash:

```bash
.claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh health
```

Parse the JSON output. If `status` is NOT `"ready"`:
- **STOP** — Tell the user: "Gemini CLI is not available. Status: {status}. Fix this before using delegated mode."
- Suggest: "Run `/project:external-tools-health` for diagnostics, or install with `npm i -g @google/gemini-cli`."

#### 0.2 — Check for Existing Worktrees (CRITICAL — Context-Loss Resilience)

**Before starting ANY new work**, check if there are already running Gemini instances from a previous session or before context compaction:

Run via Bash:

```bash
ls -d /tmp/worktree-* 2>/dev/null || echo "NONE"
```

For each worktree found:

1. Check for agent state:
   ```bash
   cat <worktree>/.agent-state.json 2>/dev/null || echo "no state file"
   ```

2. Check for existing commits:
   ```bash
   git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"
   ```

3. Check if any Gemini processes are still active (look for adapter PID files):
   ```bash
   cat <worktree>/.gemini-adapter.pid 2>/dev/null && kill -0 "$(cat <worktree>/.gemini-adapter.pid)" 2>/dev/null && echo "RUNNING" || echo "NOT_RUNNING"
   ```

**Decision logic:**
- If a worktree has a **running Gemini process**: DO NOT restart. Resume monitoring from where it left off (skip to Step 4 monitoring loop for that work unit).
- If a worktree has **commits but no running process**: Gemini finished. Skip to Step 5 validation for that work unit.
- If a worktree has **no commits and no running process**: Abandoned. Clean it up and proceed normally.

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

Ask the user to confirm:

> **Task**: {summary}
> **Work units**: {N} units identified
> **Delegation**: All implementation via Gemini CLI
> **Estimated time**: {N} units × ~5-15 min each (Gemini is typically faster than Codex)
>
> Proceed?

### 2. Work Unit Decomposition

For each work unit, prepare:

- **Scope**: Which files/directories this unit touches
- **Definition of Done**: Specific, testable criteria
- **Context files**: List of files the implementer needs to read
- **Test expectations**: What tests should exist after implementation
- **UI expectations**: Visual behavior, responsive breakpoints, accessibility requirements (Gemini-specific)

### 3. Prompt Preparation & Gemini Launch

For each work unit, spawn a sub-agent (via Task tool with `subagent_type: "general-purpose"`) that does the following:

#### 3.1 — Write the Prompt File

Create a self-contained markdown prompt at `/tmp/gemini-prompt-{unit-id}.md` with:

```markdown
# Task: {work unit title}

## Context
{Issue body or task description}
{Relevant CLAUDE.md sections — coding standards, test patterns}

## Files to Modify
{List of files with brief description of needed changes}

## Current Code
{Paste relevant code snippets from context files}

## Definition of Done
{Specific criteria from work unit decomposition}

## UI/Frontend Specifics
{Component hierarchy, design tokens, responsive requirements, accessibility}
{Reference existing component patterns in the codebase}

## Testing Requirements
- Write tests FIRST (TDD)
- Test command: {from project profile}
- Coverage command: {from project profile}
- All tests must pass before committing
- Include component/snapshot tests where appropriate

## Coding Standards
{From CLAUDE.md — language-specific rules, lint, format requirements}

## IMPORTANT
- Only modify files listed above. Do not touch other files.
- Commit your changes with a descriptive message when done.
- Run tests and fix any failures before committing.
- Follow existing component patterns and design system conventions.
```

#### 3.2 — Create Worktree & Launch Gemini

```bash
ADAPTER=".claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh"

# Create worktree
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="/tmp/worktree-{unit-id}"
git worktree add -b "external/gemini/{unit-id}" "$WORKTREE" HEAD

# Write agent state file for discoverability
cat > "$WORKTREE/.agent-state.json" << 'EOF'
{
  "issue": "{issue-number-or-id}",
  "unit": "{unit-id}",
  "status": "gemini_running",
  "started_at": "{ISO timestamp}",
  "log_path": "{will be set by adapter}",
  "agent": "gemini-delegated"
}
EOF

# Launch Gemini
$ADAPTER implement \
  --worktree "$WORKTREE" \
  --prompt-file "/tmp/gemini-prompt-{unit-id}.md" \
  --timeout 3600
```

#### 3.3 — Write Agent State

After launching, update `.agent-state.json` with the actual log path from the adapter's output.

### 4. Active Monitoring Loop (CRITICAL — NEVER Go Idle)

**This is the most important behavioral instruction.** After launching Gemini, the sub-agent MUST actively monitor. It must NOT go idle. It must NOT wait for the team lead to check on it.

The sub-agent runs this loop:

```
WHILE Gemini is running:
  1. Wait 3 minutes (sleep 180)

  2. Check Gemini adapter status:
     - Check if adapter PID is still alive: kill -0 "$(cat <worktree>/.gemini-adapter.pid)" 2>/dev/null
     - Check log file for recent output

  3. Parse status:
     - If adapter alive → Gemini still working. Continue loop.
     - If adapter dead → Gemini finished (or crashed). Exit loop.

  4. Check recent log output for progress:
     tail -20 ~/.claude/sessions/gemini-implement-*.jsonl 2>/dev/null | tail -5

  5. Update .agent-state.json with current status and timestamp

  6. If more than 20 minutes have elapsed with no new log output:
     WARN — Gemini may be stuck. Log this but continue monitoring.

  7. Continue loop
END WHILE
```

**After Gemini finishes** (adapter process exits):

- Read the adapter's JSON output to check exit code
- If exit code 0: proceed to Step 5 (validation)
- If exit code non-zero: proceed to Step 6 (retry)
- Update `.agent-state.json` status to `"gemini_completed"` or `"gemini_failed"`

### 5. Independent Validation (Trust Nothing)

After Gemini completes successfully, the sub-agent validates independently. Gemini claims don't count — verify everything:

#### 5.1 — Check for Changes

```bash
git -C <worktree> log --oneline -5
git -C <worktree> diff --stat HEAD~1 HEAD
```

If no commits or no changed files: **FAIL** — Gemini didn't produce output.

#### 5.2 — Run Tests

```bash
cd <worktree> && {test command from project profile}
```

If tests fail: record failures for retry context.

#### 5.3 — Run Linter (if configured)

```bash
cd <worktree> && {lint command from project profile}
```

#### 5.4 — Run Type Checker (if configured)

```bash
cd <worktree> && {typecheck command from project profile}
```

#### 5.5 — Check Coverage (if thresholds set)

```bash
cd <worktree> && {coverage command from project profile}
```

Compare against `.coverage-thresholds.json`.

#### 5.6 — Scope Compliance

Check that only files within the work unit's defined scope were modified:

```bash
git -C <worktree> diff --name-only HEAD~1 HEAD
```

Compare against the allowed file list from work unit decomposition. Flag any out-of-scope changes.

#### 5.7 — Verdict

- If ALL checks pass: **SUCCESS** — Update `.agent-state.json` status to `"validated"`. Report to team lead.
- If ANY check fails: proceed to Step 6 (retry).

### 6. Retry with Gemini (Max 2 Retries)

If validation fails, retry with Gemini up to 2 additional times:

#### 6.1 — Prepare Retry Prompt

Write a new prompt that includes:
- Original task description
- What Gemini produced (diff summary)
- Specific failures (test output, lint errors, type errors)
- Clear instructions on what to fix

#### 6.2 — Reset Worktree

```bash
git -C <worktree> reset --hard HEAD~1  # Undo Gemini's commit
```

#### 6.3 — Re-launch Gemini

Same as Step 3.2 but with the retry prompt and `--attempt N+1`.

#### 6.4 — Monitor Again

Same as Step 4.

#### 6.5 — Validate Again

Same as Step 5.

### 7. Escalation to Claude

If Gemini fails after 2 retries (3 total attempts), escalate:

- Update `.agent-state.json` status to `"escalated_to_claude"`
- The sub-agent implements the fix directly using Claude (standard implementation)
- Include Gemini's best attempt and the specific failure points as context
- After Claude implementation: run the same validation suite (Step 5)

### 8. Completion & Cleanup

After all work units are validated:

#### 8.1 — Merge Results

For each successful worktree:
- Cherry-pick or merge the work branch into the main feature branch
- Resolve any conflicts

#### 8.2 — Final Validation

Run the full test suite, linter, type checker, and coverage check on the merged result.

#### 8.3 — Cleanup Worktrees

For each worktree, remove it safely:

```bash
# Scrub build artifacts, then remove worktree
REPO_ROOT="$(git rev-parse --show-toplevel)"
git -C "$REPO_ROOT" worktree remove <worktree> 2>/dev/null || rm -rf <worktree>
git -C "$REPO_ROOT" worktree prune
```

#### 8.4 — Report

Present final summary:

```
Delegated Execution Complete:

  Work Units: {N} total
  Gemini Success: {M} (first attempt: {X}, retried: {Y})
  Escalated to Claude: {Z}
  Total Gemini Time: {T} minutes
  Total Cost: ~${C} (estimated from token counts)

  All validations passed. Ready for PR.
```

## Behavioral Rules (Baked Into Sub-Agent Prompts)

These rules MUST be included in every sub-agent's prompt. They are non-negotiable:

### Rule 1: Active Monitoring — NEVER Go Idle

> After launching Gemini, check adapter PID status every 3 minutes and `tail -20 <log>` to check progress. Do NOT go idle. Do NOT wait for the team lead to check on you. You are responsible for monitoring your Gemini instance until completion or failure.

### Rule 2: Context-Loss Resilience

> Before starting ANY work, check for existing worktrees at `/tmp/worktree-*`. Check each for `.agent-state.json` and running processes. If a worktree already has a running Gemini process or completed commits, DO NOT restart — resume monitoring or validation from where it left off. Write your state to `<worktree>/.agent-state.json` so the lead can discover your progress after context compaction.

### Rule 3: Self-Contained State

> Write your issue number, work unit ID, status, and log path to `<worktree>/.agent-state.json` after every state transition. This file is how the team lead discovers what you're doing if context is lost. Format:
> ```json
> {
>   "issue": "42",
>   "unit": "wu-frontend-dashboard",
>   "status": "monitoring|gemini_completed|validating|validated|gemini_failed|retrying|escalated_to_claude",
>   "started_at": "2025-01-15T10:30:00Z",
>   "updated_at": "2025-01-15T10:45:00Z",
>   "log_path": "~/.claude/sessions/gemini-implement-20250115T103000-12345.jsonl",
>   "agent": "gemini-delegated",
>   "attempt": 1,
>   "last_check": "2025-01-15T10:45:00Z"
> }
> ```

### Rule 4: Trust Nothing from Gemini

> Gemini output is untrusted. Always run tests, linter, type checker, and coverage independently. Never skip validation because Gemini claims success in its output.
