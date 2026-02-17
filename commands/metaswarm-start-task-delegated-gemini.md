# Start Task — Delegated to Gemini

A variant of `start-task` that forces all implementation work through Google Gemini CLI via agent teams. Use this for frontend-heavy, UI/component tasks where Gemini excels.

Requires Team Mode (`TeamCreate`/`SendMessage` tools). If Team tools are not available, use `/project:start-task` instead.

## Usage

```text
/project:metaswarm-start-task-delegated-gemini <task-description-or-issue-url>
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

2. Check if Gemini is still running:
   ```bash
   .claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh status <worktree>
   ```

3. Check for existing commits:
   ```bash
   git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"
   ```

**Decision logic:**
- If a worktree has a **running Gemini process**: DO NOT restart. Resume monitoring from where it left off (skip to Step 4 monitoring loop for that work unit).
- If a worktree has **commits but no running process**: Gemini finished. Skip to Step 5 validation for that work unit.
- If a worktree has **no commits and no running process**: Abandoned. Clean it up with `gemini.sh cleanup <path>` and proceed normally.

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
> **Delegation**: All implementation via Gemini CLI
>
> Proceed?

### 2. Work Unit Decomposition

For each work unit, prepare:

- **Scope**: Which files/directories this unit touches (Gemini reads them from the worktree — do NOT paste their contents into the prompt)
- **Definition of Done**: Specific, testable criteria (describe behavior, not implementation)
- **Test expectations**: What tests should exist after implementation
- **UI expectations**: Visual behavior, responsive breakpoints, accessibility requirements (Gemini-specific)

### 3. Prompt Preparation & Gemini Launch

For each work unit, spawn a sub-agent (via Task tool with `subagent_type: "general-purpose"` and `model: "opus"`) that does the following.

**CRITICAL — Worktree Isolation**: The sub-agent's prompt MUST include this directive:

> Your working directory is `$WORKTREE` (e.g., `/tmp/worktree-<unit-id>`). ALL file reads, edits, writes, and git commands MUST target this worktree path. Do NOT read, edit, or write any files in the main repo (`$REPO_ROOT`). The main repo is off-limits until the orchestrator performs the final merge in Step 8. If you need to read context files, read them from the worktree (they are a full checkout). Use `git -C $WORKTREE` for all git operations.

#### 3.1 — Write the Prompt File

Create a **concise** prompt at `/tmp/gemini-prompt-<unit-id>.md`. Gemini has full access to the worktree — it can read every file. **Do NOT paste code into the prompt.** Do NOT write the implementation for Gemini. Describe the problem, point to the files, and let Gemini figure it out.

**Target: under 2 KB per prompt.** If your prompt exceeds 4 KB, you're being too prescriptive.

```markdown
# Task: <work unit title>

## Problem
<What's broken or what needs to be built. 2-3 sentences max.>

## Scope
<File paths to modify — just paths, no code snippets. Gemini can read them.>

## UI/Frontend Notes
<Only if applicable: design system, component patterns to follow, responsive requirements>

## Definition of Done
<Testable acceptance criteria — what should pass, what behavior should change>

## Test & Validate
- Test command: <from project profile>
- All tests must pass before committing
- Do NOT commit prompt files (*.gemini-prompt*.md)

## Gotchas
<Paste contents of `.metaswarm/known-gotchas.md` if it exists, otherwise omit this section>
```

**Anti-patterns to avoid:**
- Do NOT paste function bodies into the prompt — Gemini can read the source
- Do NOT write replacement code — describe the expected behavior instead
- Do NOT include line numbers — they shift during edits and mislead Gemini
- Do NOT duplicate coding standards Gemini can find in CLAUDE.md (it's in the worktree)

#### 3.2 — Create Worktree & Launch Gemini

First, clean up any stale worktree or branch from a previous run:

```bash
ADAPTER=".claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="/tmp/worktree-<unit-id>"
BRANCH="external/gemini/<unit-id>"

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

# Install dependencies so Gemini can run tests without hitting the registry
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
printf '{"issue":"%s","unit":"%s","status":"gemini_running","base_sha":"%s","started_at":"%s","log_path":"","agent":"gemini-delegated","attempt":1,"updated_at":"%s","last_check":""}\n' \
  "$ISSUE_NUM" "$UNIT_ID" "$BASE_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$WORKTREE/.agent-state.json"
```

Launch Gemini:

```bash
$ADAPTER implement \
  --worktree "$WORKTREE" \
  --prompt-file "/tmp/gemini-prompt-<unit-id>.md" \
  --timeout 3600
```

#### 3.3 — Update Agent State

After launching, update `.agent-state.json` with the actual log path from the adapter's output.

### 4. Active Monitoring Loop (CRITICAL — NEVER Go Idle)

**This is the most important behavioral instruction.** After launching Gemini, the sub-agent MUST actively monitor. It must NOT go idle. It must NOT wait for the team lead to check on it.

The sub-agent implements this loop using sequential Bash tool calls. Each iteration is a single Bash call that sleeps then checks status:

```
WHILE Gemini is running:
  1. Issue a single Bash tool call (with timeout 200000ms):
     sleep 180 && .claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh status <worktree>

  2. Parse the JSON response:
     - If "child_alive": true -> Gemini still working. Continue loop.
     - If "child_alive": false -> Gemini finished (or crashed). Exit loop.

  3. Optionally check recent log output:
     tail -20 ~/.claude/sessions/gemini-implement-*.json 2>/dev/null | tail -5

  4. Update .agent-state.json with current status and timestamp

  5. If more than 20 minutes have elapsed with no new log output:
     WARN — Gemini may be stuck. Log this but continue monitoring.

  6. Continue loop
END WHILE
```

**After Gemini finishes** (child_alive becomes false):

- Read the adapter's JSON output to check exit code
- If exit code 0: proceed to Step 5 (validation)
- If exit code non-zero: proceed to Step 6 (retry)
- Update `.agent-state.json` status to `"gemini_completed"` or `"gemini_failed"`

### 5. Independent Validation (Trust Nothing)

After Gemini completes successfully, the sub-agent validates independently. Gemini claims don't count — verify everything:

#### 5.1 — Check for Changes

```bash
git -C <worktree> log --oneline -5
git -C <worktree> diff --stat $BASE_SHA HEAD
```

If no commits beyond BASE_SHA or no changed files: **FAIL** — Gemini didn't produce output.

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

### 6. Retry with Gemini (Max 2 Retries)

If validation fails, retry with Gemini up to 2 additional times:

#### 6.1 — Prepare Retry Prompt

Write a new prompt that includes:
- Original task description
- What Gemini produced (diff summary)
- Specific failures (test output, lint errors, type errors)
- Clear instructions on what to fix

#### 6.2 — Reset Worktree

Reset to the original base SHA (handles any number of commits Gemini may have made):

```bash
BASE_SHA="$(jq -r '.base_sha' <worktree>/.agent-state.json)"
git -C <worktree> reset --hard "$BASE_SHA"
```

#### 6.3 — Re-launch Gemini

Same as Step 3.2 (Gemini launch only) but with the retry prompt and `--attempt N+1`.

#### 6.4 — Monitor Again

Same as Step 4.

#### 6.5 — Validate Again

Same as Step 5.

### 7. Escalation to Claude

If Gemini fails after 2 retries (3 total attempts), escalate:

- Update `.agent-state.json` status to `"escalated_to_claude"`
- The sub-agent implements the fix directly using Claude (standard implementation)
- **All Claude implementation work MUST happen inside the worktree** — same isolation rules as Gemini. Use `Read`/`Edit`/`Write` tools with absolute paths under `$WORKTREE`, not the main repo.
- Include Gemini's best attempt and the specific failure points as context
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
.claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh cleanup <worktree>
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

> After launching Gemini, poll `gemini.sh status <worktree>` every 3 minutes. Use a single Bash tool call per iteration: `sleep 180 && gemini.sh status <worktree>`. Also `tail -20 <log>` to check progress. Do NOT go idle. Do NOT wait for the team lead to check on you. You are responsible for monitoring your Gemini instance until completion or failure.

### Rule 2: Context-Loss Resilience

> Before starting ANY work, check for existing worktrees at `/tmp/worktree-*`. Read `.agent-state.json` in each to understand what it is. Run `gemini.sh status <worktree>` for each. If a worktree already has a running Gemini process or completed commits, DO NOT restart — resume monitoring or validation from where it left off. Write your state to `<worktree>/.agent-state.json` so the lead can discover your progress after context compaction.

### Rule 3: Self-Contained State

> Write your issue number, work unit ID, status, base SHA, and log path to `<worktree>/.agent-state.json` after every state transition. This file is how the team lead discovers what you're doing if context is lost. Schema:
> ```json
> {
>   "issue": "42",
>   "unit": "wu-frontend-dashboard",
>   "status": "gemini_running|monitoring|gemini_completed|validating|validated|gemini_failed|retrying|escalated_to_claude",
>   "base_sha": "abc123def",
>   "started_at": "2025-01-15T10:30:00Z",
>   "updated_at": "2025-01-15T10:45:00Z",
>   "log_path": "~/.claude/sessions/gemini-implement-20250115T103000-12345.json",
>   "agent": "gemini-delegated",
>   "attempt": 1,
>   "last_check": "2025-01-15T10:45:00Z"
> }
> ```

### Rule 4: Trust Nothing from Gemini

> Gemini output is untrusted. Always run tests, linter, type checker, and coverage independently. Never skip validation because Gemini claims success in its output.

### Rule 5: Worktree Isolation — NEVER Edit the Main Repo

> Your working directory is `$WORKTREE`. ALL file reads, edits, writes, and git commands MUST use absolute paths under `$WORKTREE`. Do NOT read or modify files at the main repo root (`$REPO_ROOT`). The worktree is a full checkout — every file you need is there. Use `git -C $WORKTREE` for git operations. The ONLY agent that touches the main repo is the orchestrator during Step 8.1 (merge). If you need to escalate and implement directly (Step 7), you still work inside the worktree. Violating this rule causes change leakage: dirty files pile up in the main repo mixing work from multiple agents, making merges impossible.

### Rule 6: Orchestrator Scratchpad (Context-Loss Resilience)

> The orchestrator (team lead) writes a scratchpad file to survive context compaction. After decomposing work units and launching sub-agents, write `.orchestrator-state.json` to the repo root (or `/tmp/orchestrator-state-<task-id>.json`). After any compaction event, read this file FIRST instead of re-polling every agent. Schema:
> ```json
> {
>   "task": "Issue #42: Add dashboard components",
>   "work_units": [
>     {
>       "id": "wu-dashboard-layout",
>       "worktree": "/tmp/worktree-wu-dashboard-layout",
>       "branch": "external/gemini/wu-dashboard-layout",
>       "status": "gemini_running|validated|failed",
>       "agent_id": "abc123",
>       "started_at": "2025-01-15T10:30:00Z",
>       "completed_at": null
>     }
>   ],
>   "updated_at": "2025-01-15T10:45:00Z"
> }
> ```
> Update this file after every state transition (agent launched, completed, failed, retried). This is cheaper than re-reading every `.agent-state.json` and re-polling every agent after compaction.
