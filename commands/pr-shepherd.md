---
description: Monitor a PR through to merge - handles CI failures, reviews, and thread resolution
---

# PR Shepherd

Monitor a PR from creation through merge, handling CI failures, review comments, and thread resolution automatically.

## Usage

```text
/project:pr-shepherd [pr-number]
```

If no PR number is provided, uses the PR associated with the current branch.

## What This Does

1. **Monitors CI/CD** - Polls every 60 seconds for status changes
2. **Monitors Reviews** - Watches for new comments and unresolved threads
3. **Auto-fixes simple issues** - Lint, prettier, type errors
4. **Asks before complex fixes** - Presents options with pros/cons for approval
5. **Handles review comments** - Delegates to `handling-pr-comments` skill
6. **Checkpoints at 4 hours** - Asks if you want to continue or handoff

## Steps

1. **Get PR information**:

   ```bash
   PR_NUMBER=${1:-$(gh pr view --json number -q .number 2>/dev/null)}
   if [ -z "$PR_NUMBER" ]; then
     echo "No PR found. Provide PR number: /project:pr-shepherd 123"
     exit 1
   fi
   ```

2. **Activate the pr-shepherd skill**:
   Load and follow the pr-shepherd skill definition.

3. **Begin monitoring loop** (background, every 60s):
   - Check CI status
   - Check for new review comments
   - Check unresolved thread count
   - Take action based on state machine

4. **Handle issues as they arise**:
   - Simple CI failures -> auto-fix with TDD
   - Complex failures -> present options, wait for approval
   - New comments -> invoke `handling-pr-comments` skill

5. **Exit when done**:
   - All CI green AND all threads resolved -> report success
   - 4-hour timeout -> checkpoint with user

## Example

```text
/project:pr-shepherd 695

> I'm using the pr-shepherd skill to monitor PR #695 through to merge.
> I'll watch CI/CD, handle review comments, and fix issues as they arise.
>
> Current status:
> - CI: Running (2/5 checks complete)
> - Threads: 0 unresolved
>
> Monitoring... (will check every 60 seconds)
```

## Notes

- The agent stays active until the PR is ready to merge or you stop it
- All code changes use TDD process
- Complex issues always get user approval before fixing
- Uses `handling-pr-comments` skill for review comment handling
