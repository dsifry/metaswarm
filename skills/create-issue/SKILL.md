# Create GitHub Issue Skill

Create comprehensive, well-structured GitHub issues with embedded agent instructions for autonomous PR lifecycle management.

## Overview

This skill generates GitHub issues that are self-contained work packets. Each issue includes:

1. **Problem/Feature specification** with clear scope
2. **Technical specification** with types, schemas, and API design
3. **TDD Implementation Plan** with test-first cycles
4. **Acceptance Criteria** checklist
5. **Agent Instructions** for complete PR lifecycle (implementation → review → merge)

## Usage

```
/create-issue
```

## Interactive Flow

### Step 1: Issue Type

Ask the user:

```
What type of issue is this?
1. Feature - New functionality
2. Bug - Something broken
3. Refactor - Improving existing code
```

### Step 2: Brief Description

```
Brief description of the problem or feature? (1-2 sentences)
```

### Step 3: Complexity Assessment

```
What's the estimated complexity?
1. Simple (< 1 day)
2. Medium (2-5 days)
3. Complex (> 1 week)
```

### Step 4: Context Gathering

```
Any related files, services, or issues I should reference?
(Or say "explore codebase" and I'll investigate)
```

### Step 5: Generate Issue

Based on inputs, generate the full issue using the appropriate template below.

---

## Issue Templates

### Feature Template

````markdown
## Summary

[1-2 sentence description]

**Complexity**: [simple|medium|complex]
**Estimated Effort**: [X days]

---

## Problem

[What problem does this solve? Why is it needed?]

### Evidence

[Logs, metrics, user reports, or reasoning]

### Scope

- IN SCOPE: [what's included]
- OUT OF SCOPE: [what's explicitly NOT included]

---

## Architecture Decision

**Decision**: [What approach will be taken]
**Rationale**: [Why this approach, why NOT alternatives]

---

## Technical Specification

### Types/Interfaces

```typescript
// Key type definitions
```
````

### Zod Schemas (if applicable)

```typescript
// Validation schemas
```

### API Endpoints (if applicable)

| Method | Path | Description |
| ------ | ---- | ----------- |

### Database Changes (if applicable)

[Schema changes, migrations needed]

---

## TDD Implementation Plan

### Cycle 1: [Happy Path]

```typescript
it("should [expected behavior]", async () => {
  // Test code
});
```

### Cycle 2: [Error Handling]

```typescript
it("should handle [error case]", async () => {
  // Test code
});
```

### Cycle 3: [Edge Cases]

### Cycle 4: [Integration]

---

## Error Handling

| Scenario | Behavior | Logging |
| -------- | -------- | ------- |

---

## Implementation Phases

### Phase 1: [Core] (High Priority)

- [ ] Task 1
- [ ] Task 2

### Phase 2: [Enhancement] (Medium Priority)

- [ ] Task 3

---

## Files to Create/Modify

- **NEW**: `path/to/new/file.ts`
- `path/to/existing/file.ts` - [what changes]

---

## Acceptance Criteria

- [ ] All TDD cycles implemented with passing tests
- [ ] Zero TypeScript errors (`pnpm typecheck`)
- [ ] Zero lint warnings (`pnpm lint`)
- [ ] All tests pass (`pnpm test --run`)
- [ ] **JSDoc documentation** added to all new/modified services
- [ ] **`docs/SERVICE_INVENTORY.md`** updated (if new/modified service)
- [ ] **Mock factories** added/updated (if new service)
- [ ] PR created and all CI checks pass
- [ ] **ALL code review comments addressed** (see Agent Instructions)
- [ ] All review threads resolved
- [ ] PR approved and merged

---

## Agent Instructions

**CRITICAL**: Follow this protocol when implementing this issue. A PR is NOT complete until ALL steps are done.

### Phase 0: Research (BEFORE writing any code)

**Read these files first to avoid reinventing the wheel:**

1. **Service Inventory** - Check for existing services that might already do what you need:

   ```bash
   # Read the service inventory
   cat docs/SERVICE_INVENTORY.md
   # Or search for specific functionality
   grep -i "embedding\|search\|cache" docs/SERVICE_INVENTORY.md
   ```

2. **Mock Factories** - Review existing mocks to reuse patterns:

   ```bash
   ls src/test-utils/factories/
   ```

3. **Similar Services** - Find services with similar patterns:
   ```bash
   # Find orchestrator patterns
   ls src/lib/services/*-orchestrator*.ts
   # Find persistence patterns
   ls src/lib/services/*-persistence*.ts
   ```

**Why this matters**: Reusing existing services and patterns saves time, maintains consistency, and prevents duplicate code.

### Phase A: Implementation

1. Create feature branch from main: `git checkout -b feat/[short-name]`
2. Follow TDD cycles exactly as specified above
3. **Add JSDoc documentation** to all new/modified services
4. Run local validation: `pnpm lint && pnpm typecheck && pnpm test --run`
5. **Update service inventory** (if new service)
6. Create PR with comprehensive description using `/create-pr`

### Phase B: Code Review Iteration

**Wait for code reviews before proceeding. Do NOT mark complete after pushing code.**

For EACH code review iteration:

1. **Fetch ALL comments** (including trivial, nitpicks, and out-of-scope):

   ```bash
   PR_NUMBER=XXX
   OWNER=$(gh repo view --json owner -q .owner.login)
   REPO=$(gh repo view --json name -q .name)
   gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" --paginate
   ```

2. **Address ALL comments by category**:

   | Type                   | Action                                               |
   | ---------------------- | ---------------------------------------------------- |
   | Critical/Major         | Fix immediately                                      |
   | Medium/Minor           | Fix before merge                                     |
   | **Trivial/Nitpick**    | **Fix these too!** Do NOT skip                       |
   | **Out-of-scope**       | **Investigate thoroughly** - often the BEST insights |

3. **For each comment**:
   - **< 1 day of work** → Implement the fix in this PR
   - **> 1 day OR architectural** → Create a new GitHub issue, link in response
   - **Disagree** → Reply explaining why with technical reasoning

4. **After making changes**:

   ```bash
   pnpm lint && pnpm typecheck && pnpm test --run
   git add . && git commit -m "fix: address review feedback" && git push
   ```

5. **Respond to EVERY comment thread individually**:

   ```bash
   COMMENT_ID=XXX
   CURRENT_USER=$(gh api user -q '.login')
   gh api "/repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
     -X POST \
     -f body="Fixed in commit $(git rev-parse --short HEAD). [explanation]

   *(Response by Claude on behalf of @$CURRENT_USER)*"
   ```

6. **Wait for next review cycle** - Do NOT resolve threads yourself

7. **Repeat steps 1-6** until reviewer confirms satisfaction

### Phase C: Thread Resolution

Only AFTER reviewer approval:

1. Re-fetch all threads to get current IDs
2. Resolve each thread:

   ```bash
   THREAD_ID="PRRT_xxx"
   gh api graphql -f threadId="$THREAD_ID" -f query='
     mutation($threadId: ID!) {
       resolveReviewThread(input: {threadId: $threadId}) {
         thread { id isResolved }
       }
     }'
   ```

3. Verify all threads resolved before proceeding

### Phase D: Merge Readiness

PR is ready for merge ONLY when ALL are true:

- [ ] All CI checks pass (green)
- [ ] **EVERY** code review comment addressed (including trivial/out-of-scope)
- [ ] **EVERY** thread has individual response
- [ ] All threads are resolved (after reviewer approval)
- [ ] GitHub issues created for any deferred work (> 1 day)
- [ ] No pending reviewer comments awaiting response

### Phase E: Squash Merge and Cleanup

**IMPORTANT**: Always use squash merge, never regular merge.

1. **Squash and merge** the PR (combines all commits into one clean commit):

   ```bash
   # Via GitHub CLI
   gh pr merge $PR_NUMBER --squash --delete-branch

   # Or via GitHub web UI:
   # Click "Squash and merge" (NOT "Merge" or "Rebase and merge")
   ```

2. **Delete the feature branch** (automatically done with --delete-branch flag):

   ```bash
   # If branch wasn't auto-deleted:
   git push origin --delete feat/[branch-name]
   git branch -d feat/[branch-name]
   ```

3. **Update local main**:

   ```bash
   git checkout main
   git pull origin main
   ```

### Reference

See the `/metaswarm:handle-pr-comments` command for detailed protocol.

---

## Related Issues

- [Link to related issues]

## References

- [Link to relevant docs, specs, or PRs]

````

---

### Bug Template

Use the Feature template with these modifications:

**Title format**: `fix: [brief description]`

**Replace "Problem" section with**:

```markdown
## Bug Report

**Priority**: [P0-Critical|P1-High|P2-Medium|P3-Low]
**Affected Users**: [scope of impact]
**First Reported**: [date/source]

### Expected Behavior

[What should happen]

### Actual Behavior

[What actually happens]

### Steps to Reproduce

1. Step 1
2. Step 2
3. Step 3

### Root Cause Analysis

[If known, explain why this is happening]

### Evidence

[Logs, stack traces, screenshots]
````

**Replace "TDD Implementation Plan" with**:

````markdown
## Test Cases

### Test 1: Verify fix for reported issue

```typescript
it("should [correct behavior] when [condition]", async () => {
  // Reproduce the bug scenario
  // Verify it's now fixed
});
```
````

### Test 2: Regression test

```typescript
it("should not regress [related functionality]", async () => {
  // Ensure fix doesn't break other things
});
```

````

---

### Refactor Template

Use the Feature template with these modifications:

**Title format**: `refactor: [brief description]`

**Add after "Summary"**:

```markdown
## Background

[Why is this refactor needed? What triggered it?]

### Review Feedback Being Addressed

> [Quote the review comment that prompted this work]

- Original PR: #XXX
- Comment by: @reviewer
````

**Add to "Acceptance Criteria"**:

```markdown
- [ ] No breaking changes to public APIs
- [ ] All existing tests still pass without modification
- [ ] Performance not degraded (if applicable)
```

---

## After Generation

After generating the issue content:

1. **Show preview** to user
2. **Ask for modifications** if needed
3. **Create issue** with appropriate labels:

   ```bash
   # Feature
   gh issue create --title "feat: [title]" --body "[content]" \
     --label "enhancement" --label "complexity:[level]"

   # Bug
   gh issue create --title "fix: [title]" --body "[content]" \
     --label "bug" --label "priority:[level]"

   # Refactor
   gh issue create --title "refactor: [title]" --body "[content]" \
     --label "refactor" --label "complexity:[level]"
   ```

4. **Report issue number** to user

---

## Key Principles

1. **Self-contained**: Issues should have everything an agent needs to work autonomously
2. **TDD-first**: Always include test specifications before implementation
3. **Complete lifecycle**: Agent Instructions cover implementation through merge
4. **No shortcuts**: ALL review comments must be addressed, including trivial/nitpicks
5. **Out-of-scope = gold**: Comments marked out-of-scope often contain the best insights
6. **Iterate until done**: PR is not complete until ALL threads are resolved
