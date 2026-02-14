# External Tool Cross-Model Review Rubric

**Used By**: External tool adapters (Codex CLI, Gemini CLI, Claude) acting as adversarial reviewers
**Purpose**: Evaluate code changes produced by a different AI model against the task spec
**Version**: 1.0

---

## Overview

This rubric is used when one AI model reviews code written by a different AI model.
The reviewer has no shared context with the writer — it sees only the diff, spec, and
this rubric. The reviewer must be adversarial: assume nothing works until proven otherwise.

## Verdict

| Verdict | Meaning | Criteria |
|---------|---------|----------|
| **PASS** | Code meets the spec | All acceptance criteria satisfied, no BLOCKING issues found |
| **FAIL** | Code does not meet the spec | One or more BLOCKING issues found |

## Issue Classification

| Classification | Meaning | Impact |
|----------------|---------|--------|
| **BLOCKING** | Contract violation, missing requirement, broken functionality | Causes FAIL |
| **WARNING** | Style issue, minor improvement, non-critical concern | Does NOT cause FAIL |

## Review Checklist

The reviewer MUST check each of these against the spec:

### 1. Acceptance Criteria Coverage
- [ ] Every acceptance criterion in the spec has corresponding code
- [ ] No criterion is partially implemented or stubbed out

### 2. Functional Correctness
- [ ] Logic handles the stated requirements
- [ ] Edge cases mentioned in the spec are handled
- [ ] Error paths produce reasonable behavior (not crashes or silent failures)

### 3. Test Coverage
- [ ] Tests exist for the new/changed functionality
- [ ] Tests actually assert the acceptance criteria (not just smoke tests)
- [ ] Tests would fail if the implementation were removed (not tautological)

### 4. Scope Discipline
- [ ] Changes are limited to what the spec requires (no gold-plating)
- [ ] No unrelated refactoring or formatting changes
- [ ] No new dependencies added without justification in the spec

### 5. Security (BLOCKING if violated)
- [ ] No hardcoded secrets, credentials, or API keys
- [ ] No command injection, SQL injection, or XSS vectors
- [ ] No unsafe file operations (path traversal, world-writable files)

## Evidence Requirements

Every finding (BLOCKING or WARNING) MUST include:
- **File and line reference**: `src/auth/login.ts:42`
- **What is wrong**: Specific description of the issue
- **What the spec requires**: Quote the relevant acceptance criterion

## Output Format

The reviewer should produce output in this format:

```markdown
## Cross-Model Review: [task-id]

### Verdict: PASS | FAIL

### Acceptance Criteria Verification
| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | [criterion text] | PASS/FAIL | [file:line reference] |

### BLOCKING Issues
1. **[issue-title]**: [description] (`file:line`) — Spec requires: "[quoted criterion]"

### WARNINGS
1. **[issue-title]**: [description] (`file:line`)
```
