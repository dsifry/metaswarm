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
| **PASS** | Implementation meets its contract | Zero `blocker: yes` findings |
| **FAIL** | Implementation violates its contract | At least one `blocker: yes` finding |

FAIL if and only if there is at least one `blocker: yes` finding. Findings with `blocker: no` (minor, nit, or advisory critical/major) are reported but never cause FAIL.

There is no "APPROVED WITH COMMENTS." There is no "CHANGES SUGGESTED." PASS or FAIL.

---

## Finding Contract

The policy, the finding contract and the iteration rule live in `guides/delivery-scope.md` (plugin root; `../guides/delivery-scope.md` from a skill's `rubrics/` dir). Every finding carries six fields:

```text
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
```

- **`protects:` is required for critical and major findings.** It names the credible user scenario, explicit requirement or DoD item the finding protects.
- **Blocker definition.** A finding is a blocker (`blocker: yes`) only if its severity is critical or major AND `protects` is non-empty. Minor and nit findings are never blockers.
- **Unjustified findings are advisory.** A critical or major finding that cannot name what it protects is advisory, not a blocker. It becomes a follow-up and does not cause FAIL.
- **Mapping from the check tables below.** The tables keep their wording and are read as:
  - "BLOCKING if …" checks produce critical or major findings. They block only with `protects`. A bare "BLOCKING" entry reads the same way.
  - "WARNING" checks produce minor findings.
- **The reviewer reports; the orchestrator decides.** Whether a FAIL leads to another round, an advance or an escalation is decided by the orchestrator using the iteration rule in the guide, not by the reviewer.

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
**Verdict**: FAIL
- title: Rate limit threshold is 100, not 10
- description: The middleware allows 100 requests per minute instead of the required 10, so clients are not throttled at the specified limit. No test pins the threshold, so the regression went unnoticed.
- severity: major
- protects: DoD #3 "Rate limiting returns 429 after 10 requests per minute"
- evidence: `src/middleware/rate-limit.ts:12` — expected a 10 requests/minute threshold, found `const MAX_REQUESTS = 100`; no test verifies the 10-request threshold
- blocker: yes
```

### Invalid Evidence (will be rejected)

- "The code looks correct" (no file:line reference)
- "Tests appear to cover this" (no specific test cited)
- "I believe this works" (assertion without proof)
- "Similar to the pattern in other files" (comparison is not evidence)

---

## Review Categories

### 1. Spec Compliance (blocker threshold)

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
5. If either is missing → a major finding that protects the DoD item (`blocker: yes`)

### 2. Test Quality (blocker threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| Tests verify behavior, not presence | BLOCKING | No `toBeDefined()` as sole assertion for DoD-critical behavior |
| Tests cover error paths | WARNING | Happy path alone is insufficient for DoD items mentioning errors |
| Tests don't test mock behavior | BLOCKING | Tests must exercise real logic, not just verify mocks were called |
| Tests are deterministic | WARNING | No timing-dependent, order-dependent, or flaky patterns |

### 3. Type Safety (blocker threshold)

| Check | Classification | Criteria |
| --- | --- | --- |
| No `any` types | BLOCKING | `any` in new code is always a contract violation |
| No unsafe type assertions | WARNING | `as` casts without type guards noted but not blocking |
| Types match runtime behavior | BLOCKING | Type says X but runtime can produce Y |

### 4. File Scope (blocker threshold)

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

### 5. Security (blocker threshold)

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

FAIL only if at least one finding below has `blocker: yes`.

### DoD Verification

| # | DoD Item | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | <item text> | PASS | impl: `file:line`, test: `file:line` |
| 2 | <item text> | FAIL | Expected: <X>, Found: <Y> at `file:line` |
| 3 | <item text> | PASS | impl: `file:line`, test: `file:line` |

### Findings

1. **DoD #2 not met**: <description>
   - severity: major
   - protects: DoD #2 "<item text>"
   - evidence: `file:line` — expected <X>, found <Y>
   - blocker: yes
2. **`any` type introduced**: <description>
   - severity: major
   - protects: <explicit requirement, e.g. "TypeScript strict mode, no `any` types">
   - evidence: `src/services/foo.ts:45` — `const data: any = ...`
   - blocker: yes
3. **<minor concern>**: <description>
   - severity: minor
   - protects: —
   - evidence: `file:line`
   - blocker: no

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
| **Issue severity** | CRITICAL / HIGH / MEDIUM / LOW | critical / major / minor / nit, plus `protects` and `blocker` |
| **Contract** | General coding standards | Specific DoD items from spec |
| **Evidence** | Helpful but optional | Mandatory (file:line) |
| **Suggestions** | Encouraged | Prohibited |
| **Re-review** | Same reviewer OK | Fresh reviewer required |
| **Tone** | Collaborative partner | Independent auditor |
| **When used** | Before PR creation | During orchestrated execution loop |
