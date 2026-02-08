# Task Completion Checklist

**CRITICAL**: This checklist MUST be followed before marking ANY development task as complete.

## Quick Tasks (Simple bug fixes, small changes)

For straightforward changes that don't add new services, API endpoints, or schema changes, the minimum required steps are:

1. Run tests, lint, and typecheck
2. Verify no tests were removed or commented out
3. Review your diff with `git diff`

Escalate to the full checklist below when adding new services, API endpoints, database schema changes, complex UI components, or multi-file refactoring.

---

## Pre-Work Checklist (Before Writing Code)

Before creating any new service, hook, component, factory, or API route:

- [ ] Check if a service already exists for this functionality
- [ ] Check if mock factories already exist for related models
- [ ] Check if shared mocks already exist
- [ ] If extending existing functionality, use or extend the existing service rather than creating a duplicate

This prevents duplicate services, duplicate factories, and inconsistent mock patterns.

---

## Full Checklist

### 1. Test Verification

- [ ] Run all tests on modified test files
- [ ] Ensure ALL tests pass (no skipped, no failures)
- [ ] Verify NO tests were removed or commented out
- [ ] If tests were modified, ensure the test logic was preserved

### 2. Type Safety Verification

- [ ] Run typecheck
- [ ] Fix ALL type errors properly (no `@ts-ignore`, no `any` unless absolutely necessary)
- [ ] If fixing test type errors, preserve all existing tests

### 3. Build Verification

- [ ] Run production build to ensure it succeeds
- [ ] Address any build warnings or errors
- [ ] Verify no runtime errors introduced

### 4. Code Quality Validation (MANDATORY)

Before marking ANY task complete, you MUST run ALL validation tools:

1. TypeScript Check - catches type errors
2. ESLint Check - ONLY on modified files
3. Prettier Check - catches formatting issues

**CRITICAL**:

- Run ESLint ONLY on files you modified to avoid scope creep
- If you see errors in one tool but not another, keep checking!

### 5. Functionality Preservation

- [ ] Existing functionality remains intact
- [ ] No regression in related features
- [ ] API contracts maintained (if applicable)

### 5a. Service Inventory Update

If you added new services, hooks, middleware, components, or routes:

- [ ] Update service inventory documentation with new entries

## Special Considerations

### When Fixing Type Errors in Tests

1. **NEVER** remove tests to fix type errors
2. Add proper type imports first
3. Use `as unknown as Type` pattern for complex mocks
4. If a test seems wrong, use extended thinking before modifying
5. Preserve the original test intent

### When Modifying Existing Code

1. Understand why the code exists before changing it
2. Check for related tests that might break
3. Verify no side effects in other parts of the system
4. Use `git diff` to review all changes before committing

### Red Flags - Stop and Think

- About to delete a test? **STOP** - Fix the type error instead
- Adding `@ts-ignore`? **STOP** - Find the proper type solution
- Commenting out code? **STOP** - Fix it or remove it properly
- Build failing? **STOP** - Don't proceed until it's fixed

### 6. PR Review Comments (For PR-Related Tasks)

When working on a PR or declaring a PR ready for merge:

**BLOCKING: Run the PR comments check script and show output as proof:**

```bash
bin/pr-comments-check.sh <PR_NUMBER>
```

- [ ] Script returns exit code 0 (all inline comments addressed)
- [ ] Script output shown in your response as proof
- [ ] No comment silently ignored -- each must have: a fix, a deferral explanation, or a reasoned disagreement

**Additional PR comment scripts (use when needed):**

```bash
# Filter actionable vs non-actionable comments by priority
bin/pr-comments-filter.sh <PR_NUMBER>
```

- [ ] After pushing fixes, wait 2 min and re-check for new automated reviewer comments

### 7. Pre-Push Validation (MANDATORY BEFORE `git push`)

**CRITICAL**: Run lint, typecheck, and format checks BEFORE every `git push` to avoid CI/CD failures.

**Kill stale test runners** (prevents orphaned processes from accumulating):

```bash
pkill -f vitest 2>/dev/null || true
pkill -f jest 2>/dev/null || true
```

**Coverage enforcement** (required for all implementation tasks):

If a `.coverage-thresholds.json` file exists in the project root, read `enforcement.command` from it and run that command. Do NOT hardcode a specific coverage command — always read from the file:

```bash
# Read the enforcement command dynamically
CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
eval "$CMD"
```

Coverage thresholds are enforced as a blocking gate. Do NOT push or create a PR if coverage is below any threshold. Fix coverage first.

### 8. Agent Full-Lifecycle PR Ownership (MANDATORY for worktree agents)

When working as a task agent in a worktree (spawned by an orchestrator), you own the **complete lifecycle** -- not just implementation. Do NOT return to the orchestrator after committing. You must:

- [ ] **Coverage gate (BLOCKS PR creation)**: If `.coverage-thresholds.json` exists, read `enforcement.command` from it and run that command. Verify ALL thresholds are met. **Do NOT push or create a PR if coverage is below any threshold. Fix coverage first.**
- [ ] Push branch to remote: `git push -u origin HEAD`
- [ ] Create PR: `gh pr create --title "..." --body "..."`
- [ ] Shepherd PR through CI (monitor checks, fix failures)
- [ ] Address **every single** code review comment (fix code or reply with explanation)
- [ ] Resolve **all** review threads via GraphQL
- [ ] Squash merge when ready: `gh pr merge <number> --squash --auto`
- [ ] Report final merge status back to orchestrator

**The orchestrator will NOT start the next phase until your PR is merged to main.**

### 9. BEADS Issue Tracking (MANDATORY for tracked tasks)

If working on a BEADS-tracked issue, update its status before declaring complete:

```bash
# View current issue status
bd show <ISSUE_ID>

# Mark issue as closed
bd close <ISSUE_ID> --reason "Completed in commit <SHA>. All tests pass."

# Close multiple issues at once
bd close <ID1> <ID2> --reason "Completed in commit <SHA>"
```

- [ ] BEADS issue closed (if applicable)
- [ ] Completion reason included with commit reference
- [ ] Any follow-up work captured as new BEADS issues: `bd create --title "..." --priority 2`
- [ ] Run `bd sync` to push BEADS changes to git

## Final Verification

Before responding to the user that a task is complete:

1. Have you run ALL verification steps above?
2. Can you confidently say the code is production-ready?
3. Would you be comfortable deploying this change?
4. **Have you run pre-push validation?** (lint, typecheck, prettier)

If any answer is "no", continue working on the task.

## Remember

> "It's better to take extra time to do it right than to rush and introduce bugs."

The user relies on you to deliver high-quality, working code. Never compromise on these standards.
