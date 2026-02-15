# Plan Review Rubric (Adversarial)

**Used By**: Feasibility, Completeness, and Scope & Alignment reviewers (plan-review-gate)
**Purpose**: Binary spec compliance verification for implementation plans against user request and codebase reality
**Version**: 1.0

---

## Overview

This rubric is for **adversarial plan review** — a fundamentally different mode from collaborative plan review. Your job is to **find failures** in the plan, not to improve it. You are checking whether the plan meets its contract (the user's request, executed against the real codebase), not whether the plan is "good."

**Key distinction:**
- **Collaborative review** (`plan-review-rubric.md`): "How can this plan be better?" APPROVED / NEEDS REVISION.
- **Adversarial review** (this rubric): "Does this plan meet its contract? Prove it." PASS / FAIL.

---

## Verdict

Every adversarial plan review produces exactly one verdict:

| Verdict | Meaning | Criteria |
| --- | --- | --- |
| **PASS** | Plan meets its contract | Zero BLOCKING issues found |
| **FAIL** | Plan violates its contract | One or more BLOCKING issues found |

There is no "APPROVED WITH COMMENTS." There is no "CHANGES SUGGESTED." PASS or FAIL.

---

## Issue Classification

Every issue found is classified as BLOCKING or WARNING:

| Classification | Meaning | Impact on Verdict |
| --- | --- | --- |
| **BLOCKING** | Contract violation — plan claims X, codebase says otherwise, or user asked for X and plan omits it | Causes FAIL |
| **WARNING** | Quality concern — not a contract violation but worth noting | Does NOT cause FAIL |

**When in doubt, it's BLOCKING.** The threshold for PASS should be high. Err on the side of FAIL.

---

## Evidence Requirements

Every finding — whether PASS or FAIL — requires **cited evidence**. Assertions without evidence are invalid.

### For PASS (per criterion)

```markdown
**Criterion**: "All file paths exist"
**Verdict**: PASS
**Evidence**:
- Plan references `src/services/auth.ts` — verified via glob, file exists
- Plan references `src/middleware/rate-limit.ts` — verified via glob, file exists
- Plan references `src/utils/token.ts` — verified via glob, file exists
```

### For FAIL (per criterion)

```markdown
**Criterion**: "All requirements mapped to plan items"
**Verdict**: FAIL (BLOCKING)
**Expected**: User requirement "add rate limiting to API endpoints" mapped to a plan item
**Found**: No plan item addresses rate limiting. User request paragraph 2 explicitly states this requirement. Plan items WU-001 through WU-004 cover auth, routing, tests, and docs only.
**Evidence**: User request line "...and add rate limiting to all public API endpoints" has no corresponding work unit.
```

### Invalid Evidence (will be rejected)

- "The plan looks reasonable" (no specific reference)
- "Requirements seem covered" (no requirement-to-plan-item mapping)
- "File paths are probably correct" (not verified against codebase)
- "Similar to other plans that worked" (comparison is not evidence)

---

## Review Categories

### 1. Feasibility (Feasibility Reviewer)

Can this plan actually be executed against the real codebase?

| Check | Classification | Criteria |
| --- | --- | --- |
| File paths exist | BLOCKING if fabricated | Every file path in the plan must be verified with glob/grep against the real codebase |
| Dependency ordering correct | BLOCKING if circular or forward-ref | Work units must not depend on outputs of later work units; no circular dependencies |
| Technical approach matches codebase | BLOCKING if incompatible | Proposed patterns, libraries, frameworks, and conventions must match what the codebase actually uses (verify by reading existing code) |
| No unstated assumptions | BLOCKING if critical assumption missing | Plan must not silently depend on services, env vars, configs, or infrastructure that doesn't exist |
| Build/test commands valid | WARNING | Referenced commands (npm scripts, test runners, build tools) should exist in package.json or equivalent |

**How to verify:**

1. For every file path in the plan, run glob to confirm it exists (or that the parent directory exists for new files)
2. For dependency ordering, trace the dependency graph and verify no cycles or forward references
3. For technical approach, read 2-3 existing files in the same area and confirm the plan's approach matches
4. For assumptions, check that referenced services, env vars, and configs exist

### 2. Completeness (Completeness Reviewer)

Does the plan fully address every aspect of the user's request?

| Check | Classification | Criteria |
| --- | --- | --- |
| All requirements mapped | BLOCKING if gap exists | Extract each distinct requirement from user request; map each to a plan item; report unmapped requirements |
| Verification steps defined | BLOCKING if missing | Each planned change must specify how to verify it works (test name, manual check, or assertion) |
| Edge cases considered | BLOCKING if obvious gaps | Error scenarios, empty/null states, boundary conditions, concurrent access (where relevant) |
| Rollback/backward compatibility | WARNING | Plan should note if changes are reversible and if they break existing behavior |
| Cross-file integration points | BLOCKING if missing | Files that import or depend on changed files must be accounted for in the plan |

**How to verify:**

1. Read the user's original request and extract a numbered list of distinct requirements
2. For each requirement, find the specific plan item(s) that address it
3. Present the mapping as a table: requirement -> plan item(s)
4. Any requirement without a plan item = BLOCKING FAIL
5. For integration points, grep for imports of files being changed

### 3. Scope & Alignment (Scope & Alignment Reviewer)

Is the plan right-sized for what the user actually asked?

| Check | Classification | Criteria |
| --- | --- | --- |
| Matches user request | BLOCKING if divergent | Plan scope must align with what was asked — not with what the planner finds interesting or wants to refactor |
| No scope creep | BLOCKING if present | Plan items not traceable to user requirements are scope creep (unless they are necessary technical prerequisites) |
| No under-scoping | BLOCKING if present | Obvious implications of the request that are omitted (e.g., user asks for API endpoint but plan omits tests) |
| Complexity proportional | WARNING | A 10-line config change shouldn't produce a 15-work-unit plan |
| Simpler alternative not considered | WARNING | If a significantly simpler approach exists, note it |

**How to verify:**

1. Compare user request scope against plan scope — they should be proportional
2. For each plan item, trace it back to a user requirement or a necessary technical prerequisite
3. Items that cannot be traced = scope creep
4. Read the user request for implied work that the plan omits

---

## Output Format

Each reviewer MUST produce output in this exact format:

```markdown
## [Reviewer Name] — [PASS/FAIL]

### Evidence
- [Finding 1]: [file:line, glob result, or specific gap with evidence]
- [Finding 2]: [file:line, glob result, or specific gap with evidence]
- ...

### Verdict
[PASS: All criteria met — no blocking issues found]
OR
[FAIL: {numbered list of blocking issues with evidence}]
```

---

## Reviewer Conduct Rules

1. **Judge against the user request and codebase reality, not your preferences.** If the user asked for a REST API and the plan describes a REST API, that's PASS — even if you'd prefer GraphQL.
2. **No suggestions.** This is not a collaborative review. Report PASS or FAIL with evidence. Nothing else.
3. **No leniency.** "Close enough" is FAIL. The user's request is the contract.
4. **No anchoring.** If you are re-reviewing after a FAIL, you should have NO knowledge of the previous review. If you do, you are not a fresh reviewer — escalate this to the orchestrator.
5. **Evidence or silence.** If you can't cite a specific file path, glob result, user requirement, or plan item, you can't make the claim.
6. **Independence.** You do not know what other reviewers found. Do not speculate about other reviewers' verdicts. Your review stands alone.

---

## Comparison: Collaborative vs Adversarial Plan Review

| Dimension | Collaborative (`plan-review-rubric.md`) | Adversarial (this rubric) |
| --- | --- | --- |
| **Goal** | Improve plan quality | Verify plan contract compliance |
| **Verdict** | APPROVED / NEEDS REVISION | PASS / FAIL |
| **Evidence** | Helpful but optional | Mandatory (file paths, requirements, plan items) |
| **Suggestions** | Encouraged | Prohibited |
| **Re-review** | Same reviewer focuses on previously identified issues | Fresh reviewer required — no prior context |
| **Tone** | Collaborative partner | Independent auditor |
| **Reviewer count** | 1 (CTO Agent) | 3 (Feasibility, Completeness, Scope & Alignment) |
| **When used** | Single-reviewer plan quality check | Gate before presenting plan to user |
