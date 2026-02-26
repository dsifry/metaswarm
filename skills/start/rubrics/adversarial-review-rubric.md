# Adversarial Review Rubric

**Used By**: Code Review Agent (adversarial mode)
**Purpose**: Binary spec compliance verification against Definition of Done contract
**Version**: 1.0

---

## Overview

This rubric is for **adversarial review** — a fundamentally different mode from collaborative code review. Your job is to **find failures**, not to help improve the code. You are checking whether the implementation meets its written contract (the spec and DoD items), not whether the code is "good."

**Key distinction:**
- **Collaborative review** (`code-review-rubric.md`): "How can this code be better?"
- **Adversarial review** (this rubric): "Does this code meet its contract? Prove it."

---

## Verdict

Every adversarial review produces exactly one verdict:

| Verdict | Meaning | Criteria |
| --- | --- | --- |
| **PASS** | Implementation meets its contract | Zero BLOCKING issues |
| **FAIL** | Implementation violates its contract | One or more BLOCKING issues |

There is no "APPROVED WITH COMMENTS." There is no "CHANGES SUGGESTED." PASS or FAIL.

---

## Issue Classification

Every issue found is classified as BLOCKING or WARNING:

| Classification | Meaning | Impact on Verdict |
| --- | --- | --- |
| **BLOCKING** | Contract violation — spec says X, code does not do X | Causes FAIL |
| **WARNING** | Quality concern — not a spec violation but worth noting | Does NOT cause FAIL |

**When in doubt, it's BLOCKING.** The threshold for PASS should be high. Err on the side of FAIL.

---

## Evidence Requirements

Every finding — whether PASS or FAIL — requires **cited evidence**. Assertions without evidence are invalid.

### For PASS (per DoD item)

```markdown
**DoD #1**: "Middleware rejects expired tokens"
**Verdict**: PASS
**Evidence**:
- Implementation: `src/middleware/auth.ts:34` — checks `token.exp < Date.now()`
- Test: `src/middleware/auth.test.ts:67` — test case "rejects expired token" asserts 401 response
```

### For FAIL (per DoD item)

```markdown
**DoD #3**: "Rate limiting returns 429 after 10 requests per minute"
**Verdict**: FAIL (BLOCKING)
**Expected**: Rate limiter triggers at 10 requests/minute and returns HTTP 429
**Found**: Rate limiter exists at `src/middleware/rate-limit.ts:12` but threshold is hardcoded to 100, not 10. No test verifies the 10-request threshold.
**Evidence**: `src/middleware/rate-limit.ts:12` — `const MAX_REQUESTS = 100`
```

### Invalid Evidence (will be rejected)

- "The code looks correct" (no file:line reference)
- "Tests appear to cover this" (no specific test cited)
- "I believe this works" (assertion without proof)
- "Similar to the pattern in other files" (comparison is not evidence)

---

## Review Categories

### 1. Spec Compliance (BLOCKING threshold)

The primary check. For each DoD item:

| Check | Classification | Criteria |
| --- | --- | --- |
| DoD item fully implemented | BLOCKING if missing | Implementation exists AND handles all specified cases |
| DoD item tested | BLOCKING if untested | At least one test directly verifies the DoD item's behavior |
| DoD item matches spec language | BLOCKING if divergent | Implementation does what the spec SAYS, not what the reviewer thinks it should do |

**Process:**

1. Read each DoD item verbatim
2. Search the diff for the implementation
3. Search the diff for tests that verify the behavior
4. Cite file:line for both implementation and test
5. If either is missing → BLOCKING FAIL

### 2. Test Quality (BLOCKING / WARNING threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| Tests verify behavior, not presence | BLOCKING | No `toBeDefined()` as sole assertion for DoD-critical behavior |
| Tests cover error paths | WARNING | Happy path alone is insufficient for DoD items mentioning errors |
| Tests don't test mock behavior | BLOCKING | Tests must exercise real logic, not just verify mocks were called |
| Tests are deterministic | WARNING | No timing-dependent, order-dependent, or flaky patterns |

### 3. Type Safety (BLOCKING / WARNING threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| No `any` types | BLOCKING | `any` in new code is always a contract violation |
| No unsafe type assertions | WARNING | `as` casts without type guards noted but not blocking |
| Types match runtime behavior | BLOCKING | Type says X but runtime can produce Y |

### 4. File Scope (BLOCKING threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| Changes within declared file scope | BLOCKING if violated | Work unit may only modify its declared files |
| No unrelated changes | BLOCKING | No "while I was here" modifications |

**How to check:**

```bash
# Get actual changed files
git diff main..HEAD --name-only

# Compare against declared file scope
# Every changed file must be in the work unit's declared file scope
```

### 5. Security (BLOCKING threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| No injection vulnerabilities | BLOCKING | SQL, NoSQL, command injection |
| No XSS vulnerabilities | BLOCKING | Unescaped user input in output |
| Auth/authz enforced | BLOCKING | If spec mentions access control, it must be implemented |
| No secrets in code | BLOCKING | No hardcoded credentials, API keys, tokens |
| Input validation present | WARNING | If spec mentions validation, must exist |

---

## Output Format

The adversarial review MUST produce output in this exact format:

```markdown
## Adversarial Review: Work Unit <wu-id>

### Verdict: PASS | FAIL

### DoD Verification

| # | DoD Item | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | <item text> | PASS | impl: `file:line`, test: `file:line` |
| 2 | <item text> | FAIL (BLOCKING) | Expected: <X>, Found: <Y> at `file:line` |
| 3 | <item text> | PASS | impl: `file:line`, test: `file:line` |

### BLOCKING Issues

1. **DoD #2 not met**: <description with evidence>
2. **`any` type introduced**: `src/services/foo.ts:45` — `const data: any = ...`

### WARNINGS

1. <warning with evidence>

### Files Reviewed

- `src/middleware/auth.ts` (modified, in scope)
- `src/middleware/auth.test.ts` (added, in scope)
```

---

## Reviewer Conduct Rules

1. **Judge against the spec, not your preferences.** If the spec says "use callbacks" and the code uses callbacks, that's PASS — even if you'd prefer promises.
2. **No suggestions.** This is not a collaborative review. Report PASS or FAIL. Nothing else.
3. **No leniency.** "Close enough" is FAIL. The spec is the contract.
4. **No anchoring.** If you're re-reviewing after a FAIL, you should have NO knowledge of the previous review. If you do, you are not a fresh reviewer — escalate this to the orchestrator.
5. **Evidence or silence.** If you can't cite a file:line reference, you can't make the claim.

---

## Comparison: Collaborative vs Adversarial

| Dimension | Collaborative (`code-review-rubric.md`) | Adversarial (this rubric) |
| --- | --- | --- |
| **Goal** | Improve code quality | Verify contract compliance |
| **Verdict** | APPROVED / CHANGES REQUIRED | PASS / FAIL |
| **Issue severity** | CRITICAL / HIGH / MEDIUM / LOW | BLOCKING / WARNING |
| **Contract** | General coding standards | Specific DoD items from spec |
| **Evidence** | Helpful but optional | Mandatory (file:line) |
| **Suggestions** | Encouraged | Prohibited |
| **Re-review** | Same reviewer OK | Fresh reviewer required |
| **Tone** | Collaborative partner | Independent auditor |
| **When used** | Before PR creation | During orchestrated execution loop |
