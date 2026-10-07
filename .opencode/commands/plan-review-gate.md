---
name: plan-review-gate
description: Adversarial plan review with 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) — ALL must PASS before presenting plan to user
auto_activate: true
triggers:
  - "plan drafted"
  - "implementation plan created"
  - after:writing-plans
  - after:orchestrated-execution:plan-validation
---

# Plan Review Gate

**Core principle**: No plan reaches the user without surviving independent adversarial scrutiny.

## Purpose

This skill automatically activates after any implementation plan is drafted, before presenting it to the user. It spawns three independent adversarial reviewers in parallel — Feasibility, Completeness, and Scope & Alignment — each as a fresh `Task()` instance. ALL three must PASS. On failure, the planner incorporates feedback and resubmits to entirely fresh reviewer instances. The gate iterates until consensus or max iterations.

---

## Activation Triggers

This skill auto-activates when:

1. An implementation plan is drafted (by planner, explorer, or orchestrator)
2. The `writing-plans` skill completes a plan
3. The orchestrator's plan validation phase produces a plan for review
4. User explicitly requests: `/plan-review <path-to-plan>`

**Do NOT use for**: Trivial changes (single-file bug fixes, copy edits, config tweaks). The plan must have at least 2 work units or touch 3+ files to warrant gate review.

---

## The 3 Adversarial Reviewers

Each reviewer is a fresh `Task()` instance with read-only access to the codebase. Reviewers produce binary PASS/FAIL verdicts backed by cited evidence. No suggestions — only findings.

### Reviewer 1: Feasibility

Can this plan actually be executed against the real codebase?

| Check | Classification | Criteria |
| --- | --- | --- |
| File paths exist | BLOCKING if fabricated | Every file path referenced in the plan must exist (verify with glob/grep) |
| Dependency ordering correct | BLOCKING if circular or forward-ref | Work units depend only on things that exist or are created before them |
| Technical approach matches codebase | BLOCKING if incompatible | Proposed patterns, libraries, and conventions match what the codebase actually uses |
| No unstated assumptions | BLOCKING if critical | Plan does not silently depend on services, env vars, or infrastructure that doesn't exist |
| File scope realistic | WARNING | Each work unit's file scope is achievable without cascading changes |

### Reviewer 2: Completeness

Does the plan fully address every aspect of the user's request?

| Check | Classification | Criteria |
| --- | --- | --- |
| All requirements mapped | BLOCKING if gap exists | Every user requirement maps to at least one plan item |
| Verification steps defined | BLOCKING if missing | Each change has a way to verify it worked (test, manual check, or assertion) |
| Edge cases considered | BLOCKING if obvious gaps | Error scenarios, empty states, boundary conditions addressed |
| Rollback/backward compatibility | WARNING | Plan considers what happens if changes need to be reverted |
| Cross-file integration points | BLOCKING if missing | Files that import/depend on changed files are accounted for |

### Reviewer 3: Scope & Alignment

Is the plan right-sized for what the user actually asked?

| Check | Classification | Criteria |
| --- | --- | --- |
| Matches user request | BLOCKING if divergent | Plan solves what was asked, not what the planner finds interesting |
| No scope creep | BLOCKING if present | No unnecessary features, abstractions, or refactoring beyond the request |
| No under-scoping | BLOCKING if present | Obvious implications of the request are not omitted |
| Complexity proportional | WARNING | Solution complexity matches problem complexity |
| No simpler alternative missed | WARNING | Plan is not over-engineered when a simpler approach would suffice |

---

## Reviewer Isolation Rules

These rules are **mandatory**. Violating any of them invalidates the review.

1. **No shared context** — Each reviewer gets a fresh `Task()` instance. They do NOT see other reviewers' outputs.
2. **Read-only** — Reviewers can read files, grep, glob. They CANNOT edit, write, or run tests.
3. **Binary verdict** — PASS or FAIL. No "conditional pass" or "pass with concerns".
4. **Evidence required** — Every BLOCKING finding must cite specific file paths, line numbers, or doc sections.
5. **No suggestions** — Reviewers only report findings. The planner decides how to fix.

---

## Workflow

### Phase 1: Spawn Reviewers (Parallel)

```typescript
const [feasibilityResult, completenessResult, scopeResult] = await Promise.all([
  Task({
    subagent_type: "general-purpose",
    description: "Feasibility review",
    prompt: feasibilityReviewPrompt(planPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Completeness review",
    prompt: completenessReviewPrompt(planPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Scope & Alignment review",
    prompt: scopeAlignmentReviewPrompt(planPath),
  }),
]);
```

### Phase 2: Aggregate Results

Each reviewer returns:

```typescript
interface ReviewResult {
  reviewer: "feasibility" | "completeness" | "scope-alignment";
  verdict: "PASS" | "FAIL";
  blockers: string[];        // MUST fix - cited with evidence
  warnings: string[];        // Non-blocking concerns
  evidence: Array<{          // For each blocker
    file: string;
    line?: number;
    excerpt: string;
    issue: string;
  }>;
}
```

### Phase 3: Gate Decision

```
IF all three reviewers return PASS:
  → Plan is APPROVED
  → Present to user for implementation approval
  → Proceed to Orchestrated Execution

ELSE:
  → Consolidate all blockers with evidence
  → Present to planner (human or agent)
  → Planner revises plan
  → Re-run gate with FRESH reviewer instances (max 3 iterations)
```

### Phase 4: Human Escalation

After 3 failed iterations:

1. Create summary of remaining blockers with evidence
2. Ask human to decide: override, defer, or cancel

---

## Reviewer Prompts

### Feasibility Reviewer Prompt

```markdown
You are the FEASIBILITY REVIEWER for the Plan Review Gate.

## Your Task

Review this implementation plan for technical feasibility against the ACTUAL codebase. You have read-only access to the codebase — use glob, grep, and read tools to verify every claim.

## Plan Document
<path>: {planPath}

## Review Criteria (ALL must be satisfied for PASS)

### 1. File Path Verification
- [ ] Every file path mentioned in the plan EXISTS (verify with glob/grep)
- [ ] No fabricated paths, no "will be created" without explicit creation step
- [ ] Directory structures match actual codebase

### 2. Dependency Ordering
- [ ] Work units only depend on things that exist OR are created in earlier units
- [ ] No circular dependencies between work units
- [ ] No forward references to work units that don't create the dependency

### 3. Technical Approach Match
- [ ] Proposed patterns exist in codebase (grep for similar implementations)
- [ ] Libraries/frameworks are already used in project (check package.json, imports)
- [ ] Conventions match (naming, structure, error handling)

### 4. No Unstated Critical Assumptions
- [ ] No dependency on services not in codebase (databases, queues, external APIs)
- [ ] No dependency on env vars not documented
- [ ] No dependency on infrastructure not provisioned

### 5. File Scope Realistic (WARNING only)
- [ ] Each work unit's file scope is achievable
- [ ] No cascading changes beyond declared scope

## Output Format — RETURN JSON ONLY

```json
{
  "reviewer": "feasibility",
  "verdict": "PASS" | "FAIL",
  "blockers": ["Specific blocking issues with file:line evidence"],
  "warnings": ["Non-blocking concerns"],
  "evidence": [
    {"file": "path/to/file.ts", "line": 42, "excerpt": "relevant code", "issue": "what's wrong"}
  ]
}
```
```

### Completeness Reviewer Prompt

```markdown
You are the COMPLETENESS REVIEWER for the Plan Review Gate.

## Your Task

Review this implementation plan for completeness — does it address EVERY aspect of the user's request with verifiable outcomes?

## Plan Document
<path>: {planPath}

## Review Criteria (ALL must be satisfied for PASS)

### 1. Requirements Coverage
- [ ] Every user requirement maps to at least one plan item
- [ ] No requirements omitted
- [ ] Acceptance criteria defined per requirement

### 2. Verification Steps
- [ ] Each change has a way to verify it worked (test command, manual check, assertion)
- [ ] Test files specified where new tests are needed
- [ ] Integration test paths defined

### 3. Edge Cases
- [ ] Error scenarios addressed (network failures, invalid input, timeouts)
- [ ] Empty states handled
- [ ] Boundary conditions (limits, pagination, permissions)

### 4. Rollback/Backward Compatibility (WARNING)
- [ ] Plan considers what happens if changes need reverting
- [ ] Database migrations have rollback (if applicable)
- [ ] API versioning maintained

### 5. Cross-File Integration
- [ ] Files that import/depend on changed files are identified
- [ ] Caller updates included in scope
- [ ] No silent breaking changes

## Output Format — RETURN JSON ONLY

```json
{
  "reviewer": "completeness",
  "verdict": "PASS" | "FAIL",
  "blockers": ["Specific gaps with evidence"],
  "warnings": ["Non-blocking concerns"],
  "evidence": [
    {"file": "path/to/file.ts", "line": 42, "excerpt": "relevant code", "issue": "what's missing"}
  ]
}
```
```

### Scope & Alignment Reviewer Prompt

```markdown
You are the SCOPE & ALIGNMENT REVIEWER for the Plan Review Gate.

## Your Task

Review this implementation plan for scope — does it solve what the user asked, nothing more, nothing less?

## Plan Document
<path>: {planPath}

## Review Criteria (ALL must be satisfied for PASS)

### 1. Matches User Request
- [ ] Plan solves the EXACT problem stated, not a related one
- [ ] No pivot to "better" problem without user confirmation

### 2. No Scope Creep
- [ ] No features not requested
- [ ] No premature abstractions
- [ ] No refactoring beyond what's needed for the feature
- [ ] No "while we're at it" additions

### 3. No Under-Scoping
- [ ] Obvious implications are NOT omitted
- [ ] If user asks for X which requires Y, Y is in scope
- [ ] Dependencies on other teams/systems acknowledged

### 4. Complexity Proportional (WARNING)
- [ ] Solution complexity matches problem complexity
- [ ] Not using sledgehammer for nut

### 5. Simpler Alternative (WARNING)
- [ ] No simpler approach missed
- [ ] Configuration over code considered
- [ ] Existing library vs custom build evaluated

## Output Format — RETURN JSON ONLY

```json
{
  "reviewer": "scope-alignment",
  "verdict": "PASS" | "FAIL",
  "blockers": ["Specific scope violations with evidence"],
  "warnings": ["Non-blocking concerns"],
  "evidence": [
    {"file": "path/to/file.ts", "line": 42, "excerpt": "relevant code", "issue": "scope issue"}
  ]
}
```
```

---

## Iteration Protocol

### Round 1: Initial Review
1. Spawn all three reviewers in parallel
2. Wait for all results
3. If all PASS → Plan APPROVED
4. If any FAIL → Consolidate and present

### Rounds 2-3: Revision Cycles
1. Present consolidated blockers with evidence to planner
2. Planner revises plan
3. Re-run gate with FRESH reviewer instances
4. Repeat until all PASS or max 3 iterations

### Round 4: Escalation
If still not approved after 3 iterations:

```markdown
## Plan Review Gate: Escalation Required

After 3 review cycles, the following blockers remain:

### Feasibility Reviewer
- [blocker 1 with evidence]
- [blocker 2 with evidence]

### Completeness Reviewer
- [blocker 1 with evidence]

### Scope & Alignment Reviewer
- [blocker 1 with evidence]

### Options
1. **Override** - Proceed anyway (document technical debt)
2. **Defer** - Shelve for later
3. **Revise** - Continue iterating
4. **Cancel** - Abandon

Choose option or provide additional context.
```

---

## Integration with Other Skills

- **`writing-plans`**: Triggers this gate after plan completion
- **`orchestrated-execution`**: Runs plan validation phase which triggers this gate
- **`design-review-gate`**: Runs BEFORE this gate (design → plan → plan-review-gate → execution)

---

## Success Criteria

The plan review gate succeeds when:
- [ ] All three reviewers return PASS
- [ ] All blocking issues are resolved with evidence
- [ ] Plan document is updated with revisions
- [ ] Plan is presented to user for final approval