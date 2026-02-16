# Start Task — Delegated to Codex

A variant of `start-task` that forces all implementation work through OpenAI Codex CLI via agent teams. Use this for backend-heavy, multi-issue parallel execution where cost savings matter.

## Usage

```text
/project:start-task-delegated-codex <task-description-or-issue-url>
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

**Before starting ANY new work**, check if there are already running Codex instances from a previous session or before context compaction:

Run via Bash:

```bash
ls -d /tmp/worktree-* 2>/dev/null || echo "NONE"
```

For each worktree found:

1. Check if Codex is still running:
   ```bash
   .claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh status <worktree>
   ```

2. Check for existing commits:
   ```bash
   git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"
   ```

3. Check for agent state:
   ```bash
   cat <worktree>/.agent-state.json 2>/dev/null || echo "no state file"
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

Ask the user to confirm:

> **Task**: {summary}
> **Work units**: {N} units identified
> **Delegation**: All implementation via Codex CLI
> **Estimated time**: {N} units × ~10-20 min each (Codex running in parallel)
>
> Proceed?

### 2. Work Unit Decomposition

For each work unit, prepare:

- **Scope**: Which files/directories this unit touches
- **Definition of Done**: Specific, testable criteria
- **Context files**: List of files the implementer needs to read
- **Test expectations**: What tests should exist after implementation

### 3. Prompt Preparation & Codex Launch

For each work unit, spawn a sub-agent (via Task tool with `subagent_type: "general-purpose"`) that does the following:

#### 3.1 — Write the Prompt File

Create a self-contained markdown prompt at `/tmp/codex-prompt-{unit-id}.md` with:

```markdown
# Task: {work unit title}

## Context
{Issue body or task description}
{Relevant CLAUDE.md sections — coding standards, test patterns}

## Files to Modify
{List of files with brief description of needed changes}

## Current Code
{Paste relevant code snippets from context files — Codex can't read your repo without this}

## Definition of Done
{Specific criteria from work unit decomposition}

## Testing Requirements
- Write tests FIRST (TDD)
- Test command: {from project profile}
- Coverage command: {from project profile}
- All tests must pass before committing

## Coding Standards
{From CLAUDE.md — language-specific rules, lint, format requirements}

## IMPORTANT
- Only modify files listed above. Do not touch other files.
- Commit your changes with a descriptive message when done.
- Run tests and fix any failures before committing.
```

#### 3.2 — Create Worktree & Launch Codex

```bash
ADAPTER=".claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh"

# Create worktree (the adapter handles branch creation)
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="/tmp/worktree-{unit-id}"
git worktree add -b "external/codex/{unit-id}" "$WORKTREE" HEAD

# Write agent state file for discoverability
cat > "$WORKTREE/.agent-state.json" << 'EOF'
{
  "issue": "{issue-number-or-id}",
  "unit": "{unit-id}",
  "status": "codex_running",
  "started_at": "{ISO timestamp}",
  "log_path": "{will be set by adapter}",
  "agent": "codex-delegated"
}
EOF

# Launch Codex
$ADAPTER implement \
  --worktree "$WORKTREE" \
  --prompt-file "/tmp/codex-prompt-{unit-id}.md" \
  --timeout 3600
```

#### 3.3 — Write Agent State

After launching, update `.agent-state.json` with the actual log path from the adapter's output.

### 4. Active Monitoring Loop (CRITICAL — NEVER Go Idle)

**This is the most important behavioral instruction.** After launching Codex, the sub-agent MUST actively monitor. It must NOT go idle. It must NOT wait for the team lead to check on it.

The sub-agent runs this loop:

```
WHILE Codex is running:
  1. Wait 3 minutes (sleep 180)

  2. Check Codex status:
     .claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh status <worktree>

  3. Parse the JSON response:
     - If "child_alive": true → Codex still working. Continue loop.
     - If "child_alive": false → Codex finished (or crashed). Exit loop.

  4. Check recent log output for progress:
     tail -20 ~/.claude/sessions/codex-implement-*.jsonl 2>/dev/null | tail -5

  5. Update .agent-state.json with current status and timestamp

  6. If more than 30 minutes have elapsed with no new log output:
     WARN — Codex may be stuck. Log this but continue monitoring
     (Codex tasks legitimately take 30+ minutes for large changes)

  7. Continue loop
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
git -C <worktree> diff --stat HEAD~1 HEAD
```

If no commits or no changed files: **FAIL** — Codex didn't produce output.

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

### 6. Retry with Codex (Max 2 Retries)

If validation fails, retry with Codex up to 2 additional times:

#### 6.1 — Prepare Retry Prompt

Write a new prompt that includes:
- Original task description
- What Codex produced (diff summary)
- Specific failures (test output, lint errors, type errors)
- Clear instructions on what to fix

#### 6.2 — Reset Worktree

```bash
git -C <worktree> reset --hard HEAD~1  # Undo Codex's commit
```

#### 6.3 — Re-launch Codex

Same as Step 3.2 but with the retry prompt and `--attempt N+1`.

#### 6.4 — Monitor Again

Same as Step 4.

#### 6.5 — Validate Again

Same as Step 5.

### 7. Escalation to Claude

If Codex fails after 2 retries (3 total attempts), escalate:

- Update `.agent-state.json` status to `"escalated_to_claude"`
- The sub-agent implements the fix directly using Claude (standard implementation)
- Include Codex's best attempt and the specific failure points as context
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

> After launching Codex, poll `codex.sh status <worktree>` every 3 minutes and `tail -20 <log>` to check progress. Do NOT go idle. Do NOT wait for the team lead to check on you. You are responsible for monitoring your Codex instance until completion or failure.

### Rule 2: Context-Loss Resilience

> Before starting ANY work, check for existing worktrees at `/tmp/worktree-*`. Run `codex.sh status <worktree>` for each. If a worktree already has a running Codex process or completed commits, DO NOT restart — resume monitoring or validation from where it left off. Write your state to `<worktree>/.agent-state.json` so the lead can discover your progress after context compaction.

### Rule 3: Self-Contained State

> Write your issue number, work unit ID, status, and log path to `<worktree>/.agent-state.json` after every state transition. This file is how the team lead discovers what you're doing if context is lost. Format:
> ```json
> {
>   "issue": "42",
>   "unit": "wu-backend-auth",
>   "status": "monitoring|codex_completed|validating|validated|codex_failed|retrying|escalated_to_claude",
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
