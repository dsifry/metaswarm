# Plan Review Rubric

**Used By**: CTO Agent
**Purpose**: Evaluate implementation plans before coding begins
**Version**: 1.0

---

## Overview

This rubric ensures implementation plans are complete, correct, and aligned with codebase standards before any code is written. Plans that don't meet all REQUIRED criteria must be sent back for revision.

---

## Evaluation Categories

### 1. Requirements Alignment (REQUIRED)

| Criterion                                         | Pass                  | Fail                      |
| ------------------------------------------------- | --------------------- | ------------------------- |
| Plan addresses ALL requirements from GitHub Issue | All items covered     | Missing requirements      |
| Success criteria are measurable and testable      | Clear metrics defined | Vague or unmeasurable     |
| Scope is appropriate (no under/over-engineering)  | Right-sized solution  | Too simple or too complex |
| Edge cases are identified                         | Listed with handling  | Not considered            |

**Questions to Ask**:

- Does this solve the actual problem stated in the Issue?
- Are there requirements that seem implied but aren't explicitly addressed?
- Is anything being built that wasn't asked for?

---

### 2. Architecture Fit (REQUIRED)

| Criterion                          | Pass                         | Fail                   |
| ---------------------------------- | ---------------------------- | ---------------------- |
| Follows existing codebase patterns | Uses established conventions | Invents new patterns   |
| Service placement is correct       | Correct directory/layer      | Wrong location         |
| Dependencies flow correctly        | Proper DI, no circular deps  | Incorrect dependencies |
| Naming follows conventions         | Matches existing style       | Inconsistent naming    |

**Reference Docs**:

- `CLAUDE.md` (Architecture Overview section)
- `docs/SERVICE_INVENTORY.md`
- `.claude/guides/testing-patterns.md`

**Questions to Ask**:

- Does this fit with how similar features are implemented?
- Are new abstractions justified or premature?
- Does the service belong in the proposed location?

---

### 3. Technical Correctness (REQUIRED)

| Criterion                       | Pass                    | Fail                         |
| ------------------------------- | ----------------------- | ---------------------------- |
| TypeScript types are sound      | Proper typing, no `any` | Loose types, `any` usage     |
| Error handling is complete      | All error paths covered | Missing error handling       |
| Database operations are correct | Proper queries, indexes | N+1 queries, missing indexes |
| API contracts are well-defined  | Clear request/response  | Ambiguous contracts          |

**Questions to Ask**:

- Will this work correctly in all scenarios?
- Are failure modes handled appropriately?
- Is the data model correct and normalized?

---

### 4. Testing Strategy (REQUIRED)

| Criterion                    | Pass                        | Fail                          |
| ---------------------------- | --------------------------- | ----------------------------- |
| Test approach is defined     | Clear testing plan          | No testing mentioned          |
| TDD workflow specified       | Tests before implementation | Implementation first          |
| Mock strategy is appropriate | Uses mock factories         | Manual mocks or real services |
| Coverage targets identified  | Specific areas to test      | Vague "will add tests"        |

**Reference Docs**:

- `.claude/guides/testing-patterns.md`
- `src/test-utils/factories/`

**Questions to Ask**:

- Are the right things being tested?
- Is the mocking strategy sustainable?
- Will tests catch regressions?

---

### 5. Security Considerations (REQUIRED)

| Criterion                  | Pass                            | Fail                          |
| -------------------------- | ------------------------------- | ----------------------------- |
| Auth/authz is addressed    | Proper access controls          | Missing or wrong permissions  |
| Input validation present   | Zod schemas, sanitization       | Direct user input usage       |
| No sensitive data exposure | Proper data handling            | Logging secrets, exposing PII |
| OWASP top 10 considered    | Known vulnerabilities addressed | Security not mentioned        |

**Questions to Ask**:

- Can this be exploited?
- Is user input properly validated?
- Are secrets handled correctly?

---

### 6. Operational Readiness (RECOMMENDED)

| Criterion                  | Pass                  | Needs Work          |
| -------------------------- | --------------------- | ------------------- |
| Logging is appropriate     | Key operations logged | Over/under logging  |
| Metrics defined            | Observable operations | No observability    |
| Error messages are helpful | Actionable messages   | Generic errors      |
| Migration path clear       | Safe rollout plan     | Big bang deployment |

**Questions to Ask**:

- Can we debug this in production?
- How do we know if it's working?
- What's the rollback strategy?

---

### 7. Documentation (RECOMMENDED)

| Criterion                 | Pass                  | Needs Work          |
| ------------------------- | --------------------- | ------------------- |
| API documented            | Clear endpoint docs   | Undocumented APIs   |
| Complex logic explained   | Comments where needed | Magic code          |
| README updates identified | Doc changes listed    | Docs not considered |

---

## Scoring

### REQUIRED Categories (1-4, 5)

All REQUIRED criteria must PASS. Any FAIL = plan needs revision.

### RECOMMENDED Categories (6-7)

Should be addressed but won't block approval. Note for improvement.

---

## Review Output Format

```markdown
## Plan Review: <task-id>

### Verdict: APPROVED | NEEDS REVISION

### Requirements Alignment

- [x] All requirements addressed
- [x] Success criteria measurable
- [ ] Scope appropriate - **ISSUE**: Over-engineered caching layer not needed
- [x] Edge cases identified

### Architecture Fit

- [x] Follows existing patterns
- [x] Service placement correct
- [x] Dependencies correct
- [x] Naming conventions followed

### Technical Correctness

- [x] TypeScript types sound
- [ ] Error handling complete - **ISSUE**: Missing handling for rate limits
- [x] Database operations correct
- [x] API contracts defined

### Testing Strategy

- [x] Test approach defined
- [x] TDD workflow specified
- [x] Mock strategy appropriate
- [x] Coverage targets identified

### Security Considerations

- [x] Auth/authz addressed
- [x] Input validation present
- [x] No sensitive data exposure
- [x] OWASP considered

### Operational Readiness

- [x] Logging appropriate
- [ ] Metrics defined - **NOTE**: Consider adding timing metrics
- [x] Error messages helpful
- [x] Migration path clear

### Documentation

- [x] API documented
- [x] Complex logic explained
- [x] README updates identified

---

### Required Changes (Must Fix)

1. Remove unnecessary caching layer - simplify to direct DB calls
2. Add error handling for API rate limits (429 responses)

### Recommendations (Nice to Have)

1. Add timing metrics for API calls
2. Consider adding retry logic with exponential backoff

### Questions for Author

1. Is the 1-hour cache TTL based on data requirements?
```

---

## Iteration Protocol

### First Review

- Provide detailed feedback using format above
- Mark task as needs revision if any REQUIRED criteria fail

### Subsequent Reviews

- Focus only on previously identified issues
- Verify fixes are correct
- Check for regression in other areas

### Approval

- All REQUIRED criteria pass
- Update task status accordingly

---

## Common Rejection Reasons

1. **Over-engineering**: Building abstractions for single use cases
2. **Missing error handling**: Happy path only
3. **Wrong service location**: Not following established service patterns
4. **No testing strategy**: "Will add tests later"
5. **Security gaps**: Missing auth checks or input validation
6. **Breaking existing patterns**: Inventing new conventions
7. **Scope creep**: Addressing issues not in the GitHub Issue
