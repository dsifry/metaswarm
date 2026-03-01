---
name: pr-shepherd
description: Monitor a PR through to merge — handle CI failures, review comments, and thread resolution automatically until all checks pass
---

# pr-shepherd

Use when a PR has been created and needs to be monitored through to merge - handles CI failures, review comments, and thread resolution automatically until all checks pass and all threads are resolved.

**IMPORTANT**: This skill is designed for the **agent working in a worktree**, NOT the orchestrator. The agent handles its own PR monitoring so the orchestrator remains free for other work.

## Coordination Mode Note

This skill supports both coordination modes:

- **Task Mode** (default): Runs as a single long-running `Task()` with `run_in_background: true`. Orchestrator checks via `TaskOutput(block: false)`.
- **Team Mode**: Runs as a persistent `shepherd` teammate in the `issue-{number}` team. Sends async status updates via `SendMessage` (CI failure, review comments, all-green, PR merged). Orchestrator can respond with instructions (e.g., "defer that comment, create an issue instead"). Responds to `shutdown_request` for graceful exit.

All monitoring, fixing, and review handling logic is identical in both modes. See `./guides/agent-coordination.md` for mode detection.

---

## When to Activate

Activate this skill when ANY of these conditions are true:

- Agent just created a PR with `gh pr create`
- User asks to "shepherd", "monitor", or "see through" a PR
- User invokes `/pr-shepherd <pr-number>`
- User asks to "watch this PR" or "handle this PR until it's merged"
- Orchestrator spawned you with instructions to shepherd a PR
- **Automatic**: `bin/create-pr-with-shepherd.sh` was used (outputs shepherd instructions)

### Automatic Activation via Wrapper Script

When `bin/create-pr-with-shepherd.sh` creates a PR, it outputs shepherd instructions:

```text
==========================================
  PR Shepherd Active for PR #123
==========================================

The pr-shepherd skill will:
  - Monitor CI/CD status
  - Auto-fix lint, type, and test issues
  - Handle review comments
  - Resolve threads after addressing feedback
  - Report when PR is ready to merge

To manually invoke shepherd later:
  /pr-shepherd 123
```

When you see this output, **immediately invoke the pr-shepherd skill** with the PR number shown.

## Announce at Start

"I'm using the pr-shepherd skill to monitor this PR through to merge. I'll watch CI/CD, handle review comments, and fix issues as they arise."

## For Orchestrators: Spawning Agents with PR Shepherding

When spawning an agent to work in a worktree, include PR shepherding in the task prompt:

```text
Work in worktree at /path/to/worktree on branch feature/xyz.

Task: [describe the implementation task]

After creating the PR:
1. Use the pr-shepherd skill to monitor it through to merge
2. Handle CI failures and review comments autonomously
3. Only escalate to orchestrator for complex issues requiring user input
4. Report back when PR is ready to merge or if blocked

Run in background so I can continue other work.
```

**Key principle**: The agent owns its PR lifecycle. The orchestrator spawns and forgets, checking back via `AgentOutputTool` when needed.

## State Machine

The agent operates in one of these states:

```text
MONITORING → FIXING → MONITORING → WAITING_FOR_USER → FIXING → MONITORING → DONE
```

| State              | What Happens                                | Exit When                                      |
| ------------------ | ------------------------------------------- | ---------------------------------------------- |
| `MONITORING`       | Poll CI and reviews every 60s in background | CI fails, new comments, all done, or need help |
| `FIXING`           | Fix issues using TDD, run local validation  | Local validation passes OR need user guidance  |
| `HANDLING_REVIEWS` | Invoke `handling-pr-comments` skill         | Comments handled OR need user input            |
| `WAITING_FOR_USER` | Present options, wait for user decision     | User responds                                  |
| `DONE`             | All CI green + all threads resolved         | Exit successfully                              |

## Phase 1: Initialize

```bash
# Get PR info
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null)
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)

# If no PR on current branch, check if number was provided
if [ -z "$PR_NUMBER" ]; then
  echo "No PR found for current branch. Provide PR number."
  exit 1
fi

echo "Shepherding PR #$PR_NUMBER"
```

## Phase 2: Monitoring Loop (Background)

Run GTG every 60 seconds as the **single source of truth** for PR readiness:

### Primary Check: GTG (Good-To-Go)

GTG consolidates CI status, comment classification, and thread resolution into one call. Use it instead of separate API queries.

```bash
# Primary readiness check — structured JSON output
GTG_RESULT=$(gtg $PR_NUMBER --repo "$OWNER/$REPO" --format json \
  --exclude-checks "Merge Ready (gtg)" \
  --exclude-checks "CodeRabbit" \
  --exclude-checks "Cursor Bugbot" \
  --exclude-checks "claude" 2>&1)

STATUS=$(echo "$GTG_RESULT" | jq -r '.status')
ACTION_ITEMS=$(echo "$GTG_RESULT" | jq -r '.action_items[]?' 2>/dev/null)
CI_STATE=$(echo "$GTG_RESULT" | jq -r '.ci_status.state')
```

**GTG statuses:**

| Status               | Meaning                            | Agent Action                              |
| -------------------- | ---------------------------------- | ----------------------------------------- |
| `READY`              | All CI green, all threads resolved | → DONE                                    |
| `ACTION_REQUIRED`    | Actionable comments need fixes     | → HANDLING_REVIEWS (use `action_items`)   |
| `UNRESOLVED_THREADS` | Review threads still open          | → HANDLING_REVIEWS                        |
| `CI_FAILING`         | One or more CI checks failing      | → FIXING                                  |
| `ERROR`              | Couldn't fetch PR data             | Retry after 60s, escalate after 3 retries |

**GTG reports, agents act**: GTG does not resolve threads or fix code — it only tells you what's blocking. After addressing feedback, you must resolve threads yourself using the GraphQL mutation in `handle-pr-comments.md` (Section 3). GTG will report `READY` on the next poll once threads are resolved.

### Evaluate State Transitions

```text
if STATUS == "READY":
  → DONE

if STATUS == "CI_FAILING":
  → Parse action_items for specific failures
  → if is_simple_failure(failure): FIXING
  → else: WAITING_FOR_USER

if STATUS == "ACTION_REQUIRED" or STATUS == "UNRESOLVED_THREADS":
  → HANDLING_REVIEWS (action_items tells you exactly what to fix)

if STATUS == "ERROR":
  → Retry, then escalate
```

### Fallback: Manual Checks

If GTG is unavailable (e.g., not installed in environment), fall back to manual queries:

```bash
# CI status
FAILED_CHECKS=$(gh pr checks $PR_NUMBER --json name,conclusion --jq '[.[] | select(.conclusion == "FAILURE")] | length')

# Unresolved threads
UNRESOLVED=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')
```

### Re-triggering GTG CI Check

When threads are resolved but the `Merge Ready (gtg)` GitHub Actions check is stale:

```bash
gh workflow run gtg.yml -f pr_number=$PR_NUMBER
```

## Phase 3: Fixing Issues

### Simple Issues (Auto-fix)

These can be fixed without user approval:

- Lint failures → run linter
- Prettier failures → run formatter
- Type errors → fix the types
- Test failures in code YOU wrote → fix using TDD

### Complex Issues (Need Approval)

These require user input BEFORE fixing:

- Test failures in code you didn't write
- Infrastructure/config failures
- Ambiguous errors
- Anything you're uncertain about

### FIXING State Rules

1. **Use TDD** - Invoke `superpowers:test-driven-development` for code changes
2. **Kill stale test runners** - Run `pkill -f vitest 2>/dev/null || true` before test runs
3. **Stay until green** - Don't leave FIXING until `pnpm lint && pnpm typecheck && pnpm test --run && pnpm test:coverage` all pass
4. **Only push when verified** - Never push code that fails local validation or coverage thresholds
5. **Return to MONITORING after push** - Let CI run, continue monitoring

```bash
# Kill stale vitest processes before running tests
pkill -f vitest 2>/dev/null || true

# After fixing, always validate locally (including coverage)
pnpm lint && pnpm typecheck && pnpm test --run && pnpm test:coverage

# Only push if all pass (including coverage thresholds)
git add -A && git commit -m "fix: <description>" && git push
```

## Phase 4: Handling Reviews

When new review comments are detected:

1. Invoke the `handling-pr-comments` skill
2. That skill handles categorization, fixes, responses, and thread resolution
3. **CRITICAL: The handling-pr-comments skill includes an iteration loop**
4. **ALL threads must be resolved** before returning to MONITORING
5. If a thread cannot be resolved (needs clarification from reviewer), query the comment author asking for follow-up
6. Return to MONITORING only when:
   - All threads are resolved, AND
   - Post-push verification confirms NO new comments appeared

### Iteration Enforcement

**THE #1 FAILURE MODE**: Returning to MONITORING after one pass without checking for new comments.

The `handling-pr-comments` skill's Phase 7 (Post-Push Iteration Check) MUST complete successfully before exiting HANDLING_REVIEWS state. The skill will iterate automatically:

```text
HANDLING_REVIEWS:
  → handling-pr-comments skill (Phases 1-7)
  → IF Phase 7 finds new comments: skill re-runs Phases 1-7
  → IF Phase 7 confirms no new comments: exit to MONITORING
```

**DO NOT** manually override or skip Phase 7. If you find yourself tempted to skip iteration, you're about to make the #1 mistake.

### Out-of-Scope Comments

Reviewers may leave comments on code outside the PR diff. The `handling-pr-comments` skill handles these, but key points:

- **Treat out-of-scope as IN SCOPE by default** - respect reviewer feedback
- Use **ultrathink** to evaluate if fixes are quick (< 30 min, < 3 files)
- If simple: fix immediately and note it was outside original scope
- If complex: create a GitHub issue and link it in the thread response
- **Always respond and resolve** - never leave out-of-scope threads hanging

## Phase 5: Waiting for User

When user input is needed, ALWAYS:

1. **Present the situation clearly**
2. **Offer 2-4 options with pros/cons**
3. **State your recommendation**
4. **Allow user to choose OR provide their own approach**

### Template

```text
[Describe what happened]

**Options:**

1. **[Option name]** (Recommended)
   - [What it involves]
   - Pros: [benefits]
   - Cons: [drawbacks]

2. **[Option name]**
   - [What it involves]
   - Pros: [benefits]
   - Cons: [drawbacks]

3. **[Option name]**
   - [What it involves]
   - Pros: [benefits]
   - Cons: [drawbacks]

Which approach would you like? (Or describe a different approach)
```

### After User Responds

- If user picks a numbered option → proceed with that approach → FIXING
- If user describes alternative → proceed with their approach → FIXING

## Phase 6: Soft Timeout (4 Hours)

At 4 hours elapsed, pause and checkpoint:

```text
**PR Shepherd Checkpoint** (4 hours elapsed)

Current status:
- CI: [status]
- Threads: [X] resolved, [Y] unresolved
- Commits: [N] fix commits pushed

**Options:**

1. **Keep monitoring** (Recommended)
   - Continue for another 4 hours
   - Pros: PR may get reviewed soon
   - Cons: Ties up agent resources

2. **Exit with handoff**
   - Save status report, exit cleanly
   - Pros: Frees resources
   - Cons: Must manually re-invoke later

3. **Set shorter check-in**
   - Check back in 1 hour instead of 4
   - Pros: More frequent checkpoints
   - Cons: More interruptions

What would you like to do? (Or describe a different approach)
```

## Exit Conditions

### Success (DONE)

Exit successfully when ALL are true:

- All CI checks passing
- **Every single** code review comment has been addressed (fix or explanation -- NONE ignored)
- All review threads resolved (zero unresolved)
- No pending questions
- PR squash-merged to main (not just "ready to merge" -- actually merged)

Report:

```text
**PR #[number] Ready to Merge**

- CI: All checks passing
- Reviews: All threads resolved
- Commits: [N] total ([M] fix commits)

The PR is ready for final approval and merge.
```

### Post-Completion RAM Cleanup

After the PR is merged and knowledge extraction tasks are created, invoke automatic RAM cleanup to free resources:

```text
/auto-ram-cleanup
```

**Why**: Development processes (test runners, build watchers, language servers) accumulate during PR work. Cleaning up after merge frees memory for the next task.

**What stays running**:

- Docker containers (needed for database/services)
- Essential IDE processes

**What gets cleaned**:

- Orphaned test runners (vitest, jest)
- Build watchers no longer needed
- Duplicate language server instances
- Other development tool cruft

## Phase 7: Post-Merge Verification & Fallback Knowledge Extraction

**Primary path**: Self-reflect should have already run pre-PR (see orchestrated-execution section 8.5), with knowledge base changes committed as part of the PR. This phase verifies that happened and handles the fallback case.

**Fallback**: If self-reflect was NOT run pre-PR (e.g., PR was created outside the orchestrated workflow), create a blocking task for knowledge extraction after merge.

### When PR is Merged

After detecting that the PR has been merged (or after user merges it):

```bash
# Check if PR was merged
MERGED=$(gh pr view $PR_NUMBER --json merged -q .merged)

if [ "$MERGED" = "true" ]; then
  # Create a task for knowledge curation
  # Use your project's task tracking system
  echo "Create task: Curate learnings from PR #$PR_NUMBER"

  # If there's an associated epic, add this task as a blocker
  # (The epic can't close until learnings are extracted)
fi
```

**Note**: Self-reflect (`/self-reflect`) should have already run BEFORE the PR was created (see orchestrated-execution skill, section 8.5). If it was skipped, run it now as a fallback — but the preferred time is pre-PR while implementation context is freshest.

### Report to User

When creating the curation task:

````text
**PR #[number] Merged Successfully**

Created blocking task: [CURATION_TASK_ID]
- Title: "Curate learnings from PR #[number]"
- Status: pending
- Blocker for: [epic if applicable]

To extract learnings, invoke:
```
/curate-pr-learnings [number]
```

The command will:
1. Fetch PR comments (deterministic script)
2. AI analyzes and extracts learnings (your job)
3. Store validated learnings (deterministic script)

Then close the task.
````

### Why This Matters

1. **Security**: Webhook-triggered code execution is an attack surface. CLI/agent invocation is safer.
2. **Blocking Task**: The epic can't close until learnings are extracted, ensuring knowledge capture.
3. **Agent Autonomy**: An agent can pick up the curation task and process it.
4. **Human Oversight**: Human can also run curation manually via the CLI script.

### For Epic Completions: Extract Conversation Learnings

When this PR completes an **epic** (closes the last blocking task), you MUST also extract learnings from conversation history. Feature work often contains the richest architectural discussions.

**Detect epic completion:**

> **Note**: This pattern assumes single-epic workflows. If multiple epics are in-progress,
> `.[0]` selects the first one, which may not be the epic related to this PR.
> For multi-epic projects, correlate the PR's task to its blocking epic manually.

```bash
# Check if this PR closes an epic (assumes single in-progress epic)
# Use your project's task tracking system to check epic status
```

**If epic is completing:**

1. Create a task for conversation extraction
2. Report the task to user:

   ```text
   **Epic Completion Detected**

   This PR completes the epic. Created conversation extraction task.

   Before closing the epic, extract learnings from conversations.
   ```

**Why extract from conversations?**

- **Strategic insights**: Architectural decisions, trade-offs discussed
- **Debugging discoveries**: Root causes found after hours of investigation
- **Non-obvious behaviors**: "It turns out that..." moments
- **Integration quirks**: API behaviors that caused issues

These learnings are often NOT in code review comments - they're in the back-and-forth conversation.

### Timeout with Handoff

If user chooses to exit at checkpoint:

```text
**PR #[number] Shepherd Handoff**

Status at exit:
- CI: [status]
- Threads: [X] resolved, [Y] unresolved
- Last activity: [timestamp]

To resume: `/pr-shepherd [number]`
```

## Skills Invoked

| Situation           | Skill                                 |
| ------------------- | ------------------------------------- |
| New review comments | `handling-pr-comments`                |
| Code changes needed | `superpowers:test-driven-development` |
| Complex debugging   | `superpowers:systematic-debugging`    |

## Mandatory Pre-Completion Check

**BLOCKING: You MUST run this script and show its output before declaring ANY PR ready:**

```bash
bin/pr-comments-check.sh <PR_NUMBER>
```

This script:

- Returns exit code 0 if all comments addressed
- Returns exit code 1 if ANY unaddressed comments exist
- Shows status for each comment

**If the script shows ANY unaddressed comments, you are NOT done.** Address each unaddressed comment:

For EACH top-level comment (where `in_reply_to_id` is null) without a reply:

1. If actionable → Fix it and reply confirming the fix
2. If out-of-scope → Reply explaining deferral (create issue if needed)
3. If disagree → Reply with reasoning
4. **NEVER ignore silently**

A PR is NOT ready until every top-level comment has been addressed with a reply.

## Verification Checklist

Before exiting DONE state:

- [ ] All CI checks are green
- [ ] All review threads are resolved
- [ ] No pending user questions
- [ ] Final status reported to user

After PR is merged (Phase 7):

- [ ] Created task for knowledge curation
- [ ] Added task as blocker to epic (if applicable)
- [ ] Reported curation task ID to user
- [ ] Verified `/self-reflect` ran pre-PR (if not, run it now as fallback)

After all post-merge tasks complete:

- [ ] Ran `/auto-ram-cleanup` to free development resources
- [ ] Confirmed Docker containers still running (if needed)

## Common Mistakes

### #1 MISTAKE: Returning to MONITORING without checking for NEW comments

- After pushing a fix and responding to threads, you MUST run Phase 7
- Automated reviewers (CodeRabbit, Cursor) analyze every commit
- NEW comments often appear within 1-2 minutes of your push
- If you skip Phase 7, you'll miss the new comments and declare complete prematurely

**Pushing without local validation**

- NEVER push code that hasn't passed `pnpm lint && pnpm typecheck && pnpm test --run && pnpm test:coverage`

**Auto-fixing complex issues**

- If uncertain, ASK. Always go through WAITING_FOR_USER for complex issues.

**Forgetting to invoke handling-pr-comments**

- When new comments arrive, delegate to that skill. Don't handle comments inline.

**Not presenting options to user**

- Always give 2-4 options with pros/cons. Never just ask "what should I do?"

**Leaving FIXING state early**

- Stay in FIXING until local validation passes. Don't assume a fix worked.

**Skipping the handling-pr-comments iteration loop**

- The skill has Phases 1-7 with an explicit iteration loop
- Phase 7 checks for new comments after your fix push
- If Phase 7 finds new comments, the skill loops back to Phase 1
- DO NOT exit early - let the skill complete its full iteration
