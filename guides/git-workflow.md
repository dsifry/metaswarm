# Git Workflow Guide

This guide covers Git best practices, branch management, commit conventions, and PR workflows for projects using the metaswarm framework. It is framework-level guidance applicable to any codebase.

---

## Table of Contents

- [Current Branch Awareness](#current-branch-awareness)
- [Branch Naming Conventions](#branch-naming-conventions)
- [Commit Guidelines](#commit-guidelines)
- [Pre-Commit Verification](#pre-commit-verification)
- [PR Creation Workflow](#pr-creation-workflow)
- [PR Comment Monitoring](#pr-comment-monitoring)
- [Multi-File Commit Strategy](#multi-file-commit-strategy)
- [Pipeline Orchestration Pattern](#pipeline-orchestration-pattern)
- [Tag and Release Conventions](#tag-and-release-conventions)
- [Conflict Resolution](#conflict-resolution)
- [Common Git Commands](#common-git-commands)
- [Best Practices](#best-practices)

---

## Current Branch Awareness

**CRITICAL**: Always maintain awareness of your current branch to prevent wrong-branch operations.

Before ANY git operation (add, commit, push, checkout), you MUST:

```bash
# 1. Check current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

# 2. Verify it matches your intention
# If working on a PR, ensure branch name matches the PR

# 3. Check if PR exists for this branch
gh pr list --head "$CURRENT_BRANCH" --state open
```

Common branch confusion scenarios to avoid:

- Pushing to main instead of a feature branch
- Creating a PR from the wrong branch
- Committing fixes to an unrelated branch
- Losing track of context after multiple git operations

### Detecting the Main Branch

Not all repositories use `main`. Detect the default branch programmatically:

```bash
# Get the default branch name
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# Fallback if not set
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
fi

echo "Default branch: $DEFAULT_BRANCH"
```

### Checking Remote Tracking

```bash
# Check if current branch tracks a remote
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "No upstream set"

# Set upstream when pushing for the first time
git push -u origin "$(git branch --show-current)"
```

---

## Branch Naming Conventions

Use prefixed branch names that communicate intent:

| Prefix      | Purpose                          | Example                          |
| ----------- | -------------------------------- | -------------------------------- |
| `feature/`  | New functionality                | `feature/user-authentication`    |
| `feat/`     | Short form of feature            | `feat/add-search`                |
| `fix/`      | Bug fixes                        | `fix/null-reference-in-loader`   |
| `chore/`    | Maintenance, deps, config        | `chore/update-dependencies`      |
| `refactor/` | Code restructuring (no behavior change) | `refactor/extract-service` |
| `docs/`     | Documentation changes            | `docs/api-reference`             |
| `test/`     | Test additions or fixes          | `test/add-integration-tests`     |
| `ci/`       | CI/CD pipeline changes           | `ci/add-coverage-gate`           |
| `hotfix/`   | Urgent production fixes          | `hotfix/security-patch`          |

Rules:

- Use lowercase with hyphens (kebab-case)
- Keep names concise but descriptive
- Include issue numbers when applicable: `fix/issue-123-login-error`
- Never work directly on main/master

---

## Commit Guidelines

### Conventional Commit Format

Use the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```

Types:

| Type         | When to Use                                  |
| ------------ | -------------------------------------------- |
| `feat`       | New feature                                  |
| `fix`        | Bug fix                                      |
| `chore`      | Maintenance (deps, config, build)            |
| `refactor`   | Code change that neither fixes nor adds      |
| `test`       | Adding or correcting tests                   |
| `docs`       | Documentation only                           |
| `style`      | Formatting, whitespace (no logic change)     |
| `perf`       | Performance improvement                      |
| `ci`         | CI/CD configuration changes                  |
| `revert`     | Reverting a previous commit                  |

### AI Attribution

When commits are generated with AI assistance:

```
feat: add rate limiting middleware

- Implement token bucket algorithm
- Add per-endpoint configuration
- Include bypass for health checks

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Guidelines:

- **DO**: Include `Co-Authored-By` for attribution
- **DO**: Use conventional commit format
- **DO**: Group related changes into logical commits
- **DON'T**: Create commits without running validation first
- **DON'T**: Write vague messages like "fix stuff" or "updates"

### Commit Message Quality

The subject line should:

- Be under 72 characters
- Use imperative mood ("add" not "added")
- Not end with a period
- Explain the "why" when not obvious from the diff

The body (when included) should:

- Be separated from the subject by a blank line
- Wrap at 72 characters
- Explain what changed and why

---

## Pre-Commit Verification

Before ANY git operations:

1. **Verify current branch**: `git branch --show-current`
2. **Check for uncommitted changes**: `git status`
3. **Review changes**: `git diff` (unstaged) or `git diff --cached` (staged)
4. **Run validation on modified files**:

```bash
# Get list of modified TypeScript/JavaScript files
MODIFIED_FILES=$(git diff --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx)$')

# Run linter
if [ -n "$MODIFIED_FILES" ]; then
  echo "$MODIFIED_FILES" | xargs npx eslint --max-warnings 0
fi

# Run type checker
npx tsc --noEmit

# Kill stale test processes before running tests
pkill -f vitest 2>/dev/null || true
pkill -f jest 2>/dev/null || true

# Run tests if any test files were modified
if echo "$MODIFIED_FILES" | grep -q '\.test\.' || echo "$MODIFIED_FILES" | grep -q '\.spec\.'; then
  npm test -- --run  # Adjust for your test runner
fi

# Run coverage check (all thresholds must be met before push)
npm run test:coverage  # Adjust for your package manager
```

### Validation Order

Always validate in this order (fail fast):

1. **Type check** -- catches structural errors
2. **Lint** -- catches style and correctness issues
3. **Test** -- catches behavioral regressions
4. **Coverage** -- ensures no untested code paths

---

## PR Creation Workflow

1. **Verify branch**: `git branch --show-current`
2. **Push branch**: `git push -u origin <branch-name>`
3. **Create PR with comprehensive description**:

```bash
gh pr create --title "feat: clear description" --body "$(cat <<'EOF'
## Summary

Brief description of what this PR does and why.

## Changes

- Change 1
- Change 2
- Change 3

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Coverage thresholds met
- [ ] Manual testing completed (if applicable)

## Review Focus

Areas that need careful review.

## Related Issues

Closes #123
EOF
)"
```

4. Include in PR description:
   - Summary with context on the "why"
   - Detailed list of changes
   - Testing confirmation
   - Review focus areas
   - Related issue references

---

## PR Comment Monitoring

### When to Check for Comments

Check for PR comments at these key moments:

1. **After completing significant work on an existing PR, before committing** -- "Before we commit, check for any new comments."
2. **After pushing updates to an existing PR** -- "After push, check for new feedback."
3. **Before switching away from a PR branch** -- "Before switching branches, check for pending feedback."
4. **Before starting new tasks** -- If you have open PRs, check for pending feedback first.

### When This Does NOT Apply

- Working on initial feature development before creating a PR
- Making changes on a branch that has not been pushed yet
- Working on a branch without an associated PR

### Checking for Comments

```bash
# List your open PRs
gh pr list --author @me --state open

# Quick check for new comments
gh pr view <pr-number> --json comments,reviews | jq -r '.comments | length'

# View all review comments
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments

# Check inline code comments
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments \
  | jq -r '.[] | "\(.path):\(.line) - \(.body)"'
```

### Resolving Comments

- Only check and address comments on PRs that you authored
- Never modify other people's PRs unless explicitly asked
- When addressing feedback: fix the code, push, and reply to the comment
- Resolve threads only after the feedback has been addressed

---

## Multi-File Commit Strategy

### Strategy 1: Single Comprehensive Commit

Best for: Related changes across multiple files.

```bash
git add src/services/ src/utils/
git commit -m "$(cat <<'EOF'
feat: implement rate limiting

- Add token bucket service
- Add rate limit middleware
- Add configuration utilities

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### Strategy 2: Logical Commit Grouping

Best for: Large features with distinct components.

```bash
# Core logic
git add src/services/ src/lib/
git commit -m "feat(core): add rate limiting service"

# API integration
git add src/api/ src/middleware/
git commit -m "feat(api): integrate rate limiting middleware"

# Tests
git add **/*.test.ts
git commit -m "test: add rate limiting tests"
```

### Strategy 3: File-by-File Commits

Best for: Unrelated changes or debugging.

```bash
git add src/services/auth.ts
git commit -m "fix: resolve token validation edge case"

git add src/utils/logger.ts
git commit -m "refactor: improve log formatting"
```

---

## Pipeline Orchestration Pattern

When multiple agents work in parallel (e.g., across worktrees), use a **pipeline pattern** instead of batching.

### Core Rule: Pipeline, Don't Batch

As soon as an agent finishes, immediately push, create a PR, and launch a shepherd. Do not wait for other agents to complete.

```text
Timeline (correct - pipeline):
  Agent A finishes -> push + PR + shepherd (immediately)
  Agent B still running...
  Agent C finishes -> push + PR + shepherd (immediately)
  Agent A's PR merges (shepherd handled CI + reviews)
  Agent B finishes -> push + PR + shepherd (immediately)

Timeline (wrong - batched):
  Wait for A, B, C to all finish -> push all -> create all PRs -> shepherd all
```

### Per-Agent Timing

Track timing for each agent to identify bottlenecks:

| Metric              | Calculation                | What It Reveals               |
| ------------------- | -------------------------- | ----------------------------- |
| Implementation time | impl-done - impl-start     | Code complexity / agent speed |
| PR turnaround       | pr-merged - pr-created     | CI + review bottlenecks       |
| Shepherd overhead   | pr-merged - shepherd-start | Review/CI iteration cost      |
| Pipeline gap        | pr-created - impl-done     | Orchestration latency         |
| Total cycle time    | pr-merged - impl-start     | End-to-end per story          |

**Pipeline gap should be near zero.** If it is consistently high, the orchestrator is batching instead of pipelining.

---

## Tag and Release Conventions

### Semantic Versioning

Use [SemVer](https://semver.org/) for releases: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Tagging Releases

```bash
# Create annotated tag
git tag -a v1.2.0 -m "Release v1.2.0: add rate limiting and improve auth"

# Push tags to remote
git push origin v1.2.0

# Push all tags
git push origin --tags

# List tags
git tag -l "v1.*"
```

### Release Workflow

```bash
# Create release on GitHub with auto-generated notes
gh release create v1.2.0 --generate-notes --title "v1.2.0"

# Create pre-release
gh release create v1.2.0-rc.1 --prerelease --title "v1.2.0 Release Candidate 1"
```

---

## Conflict Resolution

### Prevention

- Rebase feature branches on main regularly
- Keep PRs small and focused
- Communicate when modifying shared interfaces or contracts
- Use feature flags for long-running work

### Resolution Process

```bash
# Update your branch with latest main
git fetch origin
git rebase origin/main

# If conflicts occur during rebase:
# 1. Resolve conflicts in each file
# 2. Stage resolved files
git add <resolved-files>

# 3. Continue rebase
git rebase --continue

# If the rebase becomes too complex, abort and try merge instead
git rebase --abort
git merge origin/main
```

### Conflict Resolution Rules

- Never blindly accept "ours" or "theirs" -- understand the intent of both changes
- If the conflict involves code you did not write, consult the author
- After resolving, run the full validation suite to ensure nothing broke
- For worktree conflicts across parallel agents, see the [Worktree Development Guide](./worktree-development.md)

---

## Common Git Commands

### Working with Branches

```bash
# Create and switch to new branch
git checkout -b feature/branch-name

# List all branches
git branch -a

# Delete local branch
git branch -d branch-name

# Update branch from main
git fetch origin
git rebase origin/main
```

### Stashing Changes

```bash
# Save current changes
git stash

# List stashes
git stash list

# Apply most recent stash
git stash pop

# Apply specific stash
git stash apply stash@{2}
```

### Undoing Changes

```bash
# Undo last commit (keep changes staged)
git reset --soft HEAD~1

# Undo last commit (keep changes unstaged)
git reset HEAD~1

# Amend last commit message
git commit --amend
```

---

## Best Practices

1. **Commit frequently**: Make small, logical commits that each represent one coherent change.
2. **Write clear messages**: Use conventional commit format. Future you (and your agents) will thank you.
3. **Review before push**: Always review `git diff` before pushing. Catch mistakes early.
4. **Keep branches updated**: Regularly sync with the default branch to minimize conflicts.
5. **Clean up**: Delete merged branches locally and remotely.
6. **Never force-push to shared branches**: Force-pushing to main or shared branches destroys history for others.
7. **Use PRs for all changes**: Even small fixes benefit from the review workflow.

---

## See Also

- [Worktree Development Guide](./worktree-development.md) -- Parallel development with git worktrees
- [Build Validation Guide](./build-validation.md) -- Pre-commit and CI validation workflows
- [Testing Patterns Guide](./testing-patterns.md) -- Test-driven development workflow
