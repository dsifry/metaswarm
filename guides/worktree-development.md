# Worktree Development Guide

This guide covers git worktree usage patterns for parallel development in projects using the metaswarm framework. Worktrees enable multiple agents (or developers) to work on different features simultaneously without interfering with each other.

---

## Table of Contents

- [When to Use Worktrees](#when-to-use-worktrees)
- [Worktree Setup](#worktree-setup)
- [Environment Isolation](#environment-isolation)
- [Workflow Patterns](#workflow-patterns)
- [Hub-and-Spoke Pattern](#hub-and-spoke-pattern)
- [Agent Full-Lifecycle Ownership](#agent-full-lifecycle-ownership)
- [Layered Merge Pipeline](#layered-merge-pipeline)
- [Handoff Documents](#handoff-documents)
- [Conflict Detection and Resolution](#conflict-detection-and-resolution)
- [Worktree Cleanup and Maintenance](#worktree-cleanup-and-maintenance)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## When to Use Worktrees

### Good Use Cases

| Scenario                               | Why Worktrees Help                                            |
| -------------------------------------- | ------------------------------------------------------------- |
| **Multiple PRs in review**             | Work on new features while PRs await review                   |
| **Parallel feature development**       | Multiple agents work on different features simultaneously     |
| **Testing against different branches** | Compare behavior across branches without stashing             |
| **Long-running tasks**                 | Do not block other work while waiting for builds/tests        |
| **Code review reference**              | Keep PR code open while working on something else             |

### When NOT to Use Worktrees

- **Simple, quick tasks** -- Overhead is not worth it for 5-minute fixes
- **Tight integration work** -- When changes need to see each other immediately
- **Schema migrations** -- Shared databases require careful coordination
- **Single-branch workflow** -- If you are only working on one thing

---

## Worktree Setup

### Creating a Worktree

From the **main repository** (not from another worktree):

```bash
# Create a worktree with a new branch
git worktree add ~/Developer/<project>-worktrees/<agent-name> -b feature/<feature-name>

# Create a worktree from an existing branch
git worktree add ~/Developer/<project>-worktrees/<agent-name> feature/<existing-branch>

# Create a worktree from a specific commit (detached HEAD)
git worktree add ~/Developer/<project>-worktrees/<agent-name> <commit-sha>
```

### Directory Structure

Establish a consistent directory layout:

```text
~/Developer/
+-- my-project/                        # Main repository (hub)
|   +-- .claude/
|   |   +-- handoffs/                  # Handoff documents between agents
|   +-- guides/                        # Project guides
|   +-- src/                           # Source code
+-- my-project-worktrees/             # All worktrees live here
    +-- agent-1/                       # Worktree for agent 1
    |   +-- .claude/
    |   |   +-- handoffs/
    |   +-- src/
    +-- agent-2/                       # Worktree for agent 2
    +-- hotfix/                        # Worktree for hotfix
```

Rules:

- All worktrees live in a sibling directory named `<project>-worktrees/`
- Each worktree gets a descriptive name (agent name, feature name, or purpose)
- The main repository is always the orchestration hub

### Post-Setup

After creating a worktree, install dependencies:

```bash
cd ~/Developer/<project>-worktrees/<agent-name>
npm install  # or pnpm install, yarn install
```

---

## Environment Isolation

Each worktree must be isolated to prevent resource conflicts. Use environment variables or configuration to ensure separation:

### Port Isolation

Each worktree should use a unique port to avoid `EADDRINUSE` errors:

| Resource       | Main Repo | Worktree 1 | Worktree 2 |
| -------------- | --------- | ----------- | ----------- |
| App Server     | Base port | Base + 1    | Base + 2    |
| Debug Port     | Base + 10 | Base + 11   | Base + 12   |
| Dev Server     | Base + 20 | Base + 21   | Base + 22   |

### Environment Variables

Set these per-worktree to prevent collisions:

```bash
# In each worktree's .env or shell environment
PORT=<unique-port>
CACHE_KEY_PREFIX="<worktree-name>:"
WORKTREE_ID="<worktree-name>"
DATABASE_URL="<shared-or-isolated-db-url>"
```

### Automated Setup Script

Create a setup script that configures isolation automatically:

```bash
#!/usr/bin/env bash
# worktree-setup.sh <worktree-name> <branch-name>
set -euo pipefail

WORKTREE_NAME="$1"
BRANCH_NAME="$2"
PROJECT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WORKTREE_BASE="$(dirname "$PROJECT_DIR")/${PROJECT_NAME}-worktrees"
WORKTREE_PATH="${WORKTREE_BASE}/${WORKTREE_NAME}"

# Create worktree directory
mkdir -p "$WORKTREE_BASE"
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"

# Install dependencies
cd "$WORKTREE_PATH"
npm install

# Configure environment isolation
if [ -f .env ]; then
  # Calculate unique port offset from worktree name hash
  OFFSET=$(echo "$WORKTREE_NAME" | cksum | awk '{print ($1 % 100) + 1}')
  echo "" >> .env
  echo "# Worktree isolation" >> .env
  echo "WORKTREE_ID=${WORKTREE_NAME}" >> .env
  echo "CACHE_KEY_PREFIX=${WORKTREE_NAME}:" >> .env
fi

echo "Worktree ready at: $WORKTREE_PATH"
```

---

## Workflow Patterns

### Starting Work in a Worktree

1. **Create the worktree** from the main repository:

   ```bash
   git worktree add ~/Developer/<project>-worktrees/<name> -b feature/<feature>
   ```

2. **Navigate and set up**:

   ```bash
   cd ~/Developer/<project>-worktrees/<name>
   npm install
   ```

3. **Start development**:

   ```bash
   npm run dev
   ```

### Referencing Code from Other Branches

View files from other branches without switching context:

```bash
# View file content from another branch
git show main:src/services/order.service.ts

# Diff against main
git diff main -- src/services/

# Diff between two branches
git diff feature/auth...feature/orders -- src/shared/
```

### Coordinating Shared Resources

**CRITICAL**: All worktrees share the same git repository and potentially the same database.

Before any schema or migration change:

1. Check active worktrees: `git worktree list`
2. Coordinate with other developers/agents
3. Run migrations from the main repository only
4. Other worktrees regenerate clients after migration

---

## Hub-and-Spoke Pattern

The hub-and-spoke pattern is the recommended approach for complex features with parallel work streams.

### Architecture

```text
Main Repository (Hub / Orchestrator)
+-- Creates worktrees
+-- Spawns agents with Task tool (run_in_background: true)
+-- Continues other work while agents run
+-- Checks agent status periodically
+-- Merges completed features
+-- Coordinates shared resources (database, config)

Worktree: feat-auth (Spoke / Worker Agent)
+-- Agent works in isolated directory
+-- Creates PR when implementation is done
+-- Monitors CI and handles failures
+-- Responds to review comments autonomously
+-- Reports back when PR is ready to merge OR blocked

Worktree: feat-orders (Spoke / Worker Agent)
+-- Parallel agent works independently
+-- Owns its own PR lifecycle
+-- Handles CI failures and reviews
+-- Reports back when ready or blocked
```

### Spawning Agents

Instead of manually navigating to worktrees, orchestrate agents directly:

```typescript
// From main repository, spawn a background agent
Task({
  description: "Implement feature X in worktree",
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: `
You are working in a git worktree at /path/to/<project>-worktrees/feat-x
on branch feature/x.

IMPORTANT: Change to the worktree directory first:
cd /path/to/<project>-worktrees/feat-x

Your task: [Detailed task description]

After implementation:
1. Run validation (lint, typecheck, test, coverage)
2. Create PR
3. Monitor CI and handle failures autonomously
4. Respond to review comments
5. Report back when PR is ready to merge or if blocked

Run autonomously - the orchestrator will check in periodically.
`,
});
```

### Key Principles

- **Agents own their PR lifecycle**: The orchestrator spawns and moves on, checking back periodically
- **Orchestrator remains free**: Not blocked polling CI for any single agent
- **Agents handle their own failures**: CI failures, review comments, merge conflicts
- **Parallel execution**: Multiple agents work simultaneously in separate worktrees

---

## Agent Full-Lifecycle Ownership

Each agent owns the complete lifecycle of its story:

```text
1. Implement (TDD, in worktree)
2. Run validation (lint, typecheck, test, coverage)
3. Commit changes
4. Push branch
5. Create PR (gh pr create)
6. Shepherd PR through CI
7. Address EVERY code review comment (fix or explain)
8. Resolve ALL review threads
9. Squash merge when all checks pass
```

**The orchestrator does NOT batch these steps.** Each agent pipelines its own output through to merge independently.

### Agent Self-Shepherding

After creating a PR, the agent monitors and maintains it:

```bash
# Create PR
git push -u origin feature/my-feature
PR_URL=$(gh pr create --title "feat: ..." --body "...")
PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')

# Monitor CI status
gh pr checks "$PR_NUMBER" --watch

# If CI fails, fix and push
# If reviews come in, address them
# When all checks pass and threads are resolved, report ready
```

---

## Layered Merge Pipeline

When implementing multiple stories that have dependency chains, use a layered merge pipeline to ensure each layer builds on merged, validated code.

### Core Principle

**Never build dependent code on unmerged branches.** Stories in layer N+1 must only be implemented after layer N is squash-merged to the default branch. This prevents stub duplication and ensures agents import real services instead of recreating them.

### Layer Classification

```text
Layer 1: Stories with NO dependencies on other unmerged stories
Layer 2: Stories that depend on Layer 1 code
Layer 3: Stories that depend on Layer 2 code
...
```

### Pipeline Pattern

Pipeline each agent's output immediately -- do not wait for all agents to finish:

```text
Timeline (correct):
  Agent A finishes -> push + PR + shepherd (immediately)
  Agent B finishes -> push + PR + shepherd (immediately)
  Agent C still running...
  Agent A's PR merges
  Agent C finishes -> push + PR + shepherd (immediately)
  Agent B's PR merges
  Agent C's PR merges
  -> Pull main, create layer N+1 worktrees, launch next wave

Anti-pattern (wasteful):
  Wait for ALL agents -> batch push -> batch PR -> batch shepherd
```

### Orchestration Steps

1. **Identify layers**: Group stories by dependency. Independent stories = Layer 1.
2. **Create worktrees from current main**: `git worktree add <path> -b feat/<story> main`
3. **Launch agents in parallel** with explicit context about what services exist on main.
4. **As each agent completes**: Push, create PR, begin shepherding immediately.
5. **Shepherd agents handle CI and reviews** autonomously.
6. **Layer N+1 worktree creation can overlap**: While layer N shepherds are running, create N+1 worktrees for stories that have no dependency on unmerged layer N code. Implementation agents for N+1 still wait for the phase gate.
7. **PHASE GATE**: Do NOT start layer N+1 implementation until ALL layer N PRs are squash-merged to main. No exceptions.
8. **After all layer N PRs merge**: Pull main, clean up worktrees/branches, launch layer N+1 agents.
9. **Inform layer N+1 agents**: Enumerate every new service/utility now on main. Agents must `import` and use them, NOT recreate stubs.

### Phase Gate Checklist

Before starting any new layer, the orchestrator MUST verify:

- [ ] ALL PRs from previous layer show state=MERGED
- [ ] `git pull origin main` reflects all merged commits
- [ ] No open PRs remain from the previous layer
- [ ] Task tracking for previous layer is closed

```bash
# Verify all previous layer PRs are merged
for pr in <pr_numbers>; do
  state=$(gh pr view $pr --json state -q .state)
  if [ "$state" != "MERGED" ]; then
    echo "BLOCKED: PR #$pr is $state, not MERGED"
    exit 1
  fi
done

# Pull latest main
git checkout main && git pull origin main
```

### Informing Agents About Existing Code

Each implementation agent prompt MUST include:

```text
## CRITICAL: Services already on main -- DO NOT recreate these
- `src/services/auth.service.ts` -- AuthService (use for authentication)
- `src/lib/cache.ts` -- CacheManager (use for caching patterns)
- [... enumerate all relevant services ...]

**You MUST import and use existing code. Do NOT create stubs or duplicates.**
```

---

## Handoff Documents

When passing work between agents or sessions, use structured handoff documents.

### Handoff Contract

Every handoff must include:

1. **What was accomplished** -- Completed tasks with specific outcomes
2. **What remains** -- Specific next steps (not vague goals)
3. **Key decisions** -- Why certain approaches were chosen
4. **Gotchas** -- Things the next agent should know
5. **Test status** -- Did tests pass? What coverage? What needs testing?

### Handoff Document Template

```markdown
# Handoff: <Feature/Task Name>

## Date: <YYYY-MM-DD>

## From: <source agent/session>

## To: <target agent/session>

## Completed

- [x] Implemented OrderService with create/update/delete
- [x] Added unit tests (100% coverage)
- [x] Integrated with existing AuthService

## Remaining

- [ ] Add integration tests for API routes
- [ ] Update API documentation
- [ ] Add rate limiting to create endpoint

## Key Decisions

- Used repository pattern for data access (consistent with existing services)
- Chose optimistic locking for concurrent updates (discussed in Issue #45)

## Gotchas

- The OrderStatus enum is defined in shared types -- do NOT redefine it
- Database migrations have NOT been run yet -- run from main repo only
- The mock factory for Orders is in `src/test-utils/factories/order.ts`

## Test Status

- Unit tests: 47 passing, 100% coverage
- Integration tests: Not yet written
- Linting: Clean (0 warnings)
- Type check: Clean (0 errors)
```

### Storage Location

Store handoff documents in `.claude/handoffs/`:

```text
.claude/handoffs/
+-- 20250115-1430-order-service-handoff.md
+-- 20250116-0900-auth-refactor-handoff.md
```

---

## Conflict Detection and Resolution

### Prevention Strategies

| Shared Resource          | How to Coordinate                                        |
| ------------------------ | -------------------------------------------------------- |
| **Database schema**      | Never migrate without checking other worktrees           |
| **Package dependencies** | Commit lock files; let package manager resolve           |
| **Shared interfaces**    | Use interfaces; do not modify contracts without coordination |
| **Test data**            | Use unique identifiers per worktree                      |
| **Configuration**        | Keep environment-specific config in `.env` (not tracked) |

### Detecting Conflicts Early

```bash
# Check if your branch has diverged from main
git fetch origin
git log --oneline origin/main..HEAD  # Your commits not on main
git log --oneline HEAD..origin/main  # Main commits not on your branch

# Check for potential conflicts before merging
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main
```

### Resolving Conflicts Across Worktrees

When two worktrees modify the same files:

1. **Merge the simpler/smaller change first**
2. **Rebase the remaining worktree on updated main**:
   ```bash
   cd ~/Developer/<project>-worktrees/<remaining-agent>
   git fetch origin
   git rebase origin/main
   # Resolve conflicts
   git add <resolved-files>
   git rebase --continue
   ```
3. **Re-run full validation** after resolving conflicts
4. **Update the PR** with force-push if rebased: `git push --force-with-lease`

### Shared Interface Changes

If one agent needs to change a shared interface:

1. Create the interface change as a **separate, small PR**
2. Merge it first (Layer 0)
3. All other agents rebase onto the updated main
4. Continue with their feature work

---

## Worktree Cleanup and Maintenance

### Routine Cleanup

After a PR is merged:

```bash
# Remove the worktree
git worktree remove ~/Developer/<project>-worktrees/<agent-name>

# Delete the feature branch
git branch -d feature/<feature-name>

# Prune stale worktree references
git worktree prune
```

### Lifecycle Per Layer

```bash
# 1. Pull latest main after previous layer merges
git checkout main && git pull origin main

# 2. Clean up old worktrees
git worktree remove ~/Developer/<project>-worktrees/<old-agent>
git branch -d <old-branch>

# 3. Create fresh worktrees for new layer
git worktree add ~/Developer/<project>-worktrees/<new-agent> -b feat/<new-story> main

# 4. Launch agents, pipeline PRs as they complete

# 5. After all merge, repeat for next layer
```

### Listing and Auditing Worktrees

```bash
# List all active worktrees
git worktree list

# Show detailed info (including prunable entries)
git worktree list --verbose

# Remove all stale references
git worktree prune --verbose
```

---

## Troubleshooting

### Port Conflicts

**Symptom**: `Error: listen EADDRINUSE: address already in use`

**Solution**:

```bash
# Find what is using the port
lsof -i :<port>

# Kill the process or use a different port
PORT=<new-port> npm run dev
```

### Cache Key Collisions

**Symptom**: Unexpected cache data or overwrites between worktrees

**Solution**: Ensure `CACHE_KEY_PREFIX` is set per worktree:

```bash
export CACHE_KEY_PREFIX="$(basename $PWD):"
```

### Build Cache Problems

**Symptom**: Stale builds, incorrect types after switching branches

**Solution**:

```bash
# Clear build caches
rm -rf dist node_modules/.cache node_modules/.vite

# Reinstall dependencies
npm install

# Rebuild
npm run build
```

### Worktree Creation Fails

**Symptom**: `fatal: 'branch-name' is already checked out at...`

**Cause**: The branch is checked out in another worktree.

**Solution**:

```bash
# Create a new branch for this worktree
git worktree add ~/Developer/<project>-worktrees/<name> -b <new-branch-name>

# Or check out a different branch in the existing worktree first
```

### Stale Worktrees

**Symptom**: Old worktrees taking up space or causing confusion.

**Solution**:

```bash
# List all worktrees
git worktree list

# Remove a stale worktree
git worktree remove ~/Developer/<project>-worktrees/<old-name>

# Prune worktree references for manually deleted directories
git worktree prune
```

---

## Quick Reference

| Operation                 | Command                                                         |
| ------------------------- | --------------------------------------------------------------- |
| Create worktree           | `git worktree add <path> -b <branch> [start-point]`            |
| List worktrees            | `git worktree list`                                             |
| Remove worktree           | `git worktree remove <path>`                                    |
| Prune stale references    | `git worktree prune`                                            |
| View file from branch     | `git show <branch>:<filepath>`                                  |
| Diff against main         | `git diff main -- <path>`                                       |
| Check divergence          | `git log --oneline origin/main..HEAD`                           |
| Fetch + rebase on main    | `git fetch origin && git rebase origin/main`                    |
| Force push after rebase   | `git push --force-with-lease`                                   |

---

## See Also

- [Git Workflow Guide](./git-workflow.md) -- Branch management, commit conventions, and pipeline orchestration
- [Build Validation Guide](./build-validation.md) -- Validation workflows and CI integration
- [Testing Patterns Guide](./testing-patterns.md) -- TDD workflow for implementation agents
