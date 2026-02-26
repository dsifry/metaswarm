---
name: plan-review-gate
description: Automatic adversarial review gate that spawns 3 independent reviewers in parallel after any plan is drafted - all must PASS before presenting to user
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

1. **Fresh instances only.** Each reviewer is a new `Task()` instance — never resumed, never given prior context.
2. **No cross-reviewer visibility.** No reviewer sees another reviewer's output. Ever.
3. **Read-only codebase access.** Reviewers can read files, run grep/glob, but cannot modify anything.
4. **No prior review findings on re-review.** When re-reviewing after iteration, completely fresh instances are spawned. The new reviewers have zero knowledge of what previous reviewers found.
5. **Input is limited to:** the plan text, the user's original request, and the codebase (via read-only tools).

**Why isolation matters:** Reviewers who see prior findings anchor on those findings instead of reviewing independently. Fresh instances prevent this bias and ensure each review cycle is a genuine independent check.

---

## Workflow

```text
1. Plan drafted by planner/explorer/orchestrator
2. Spawn 3 adversarial reviewers in PARALLEL (fresh Task() instances)
3. Collect all 3 verdicts
4. IF all PASS --> present plan to user with gate approval summary
5. IF any FAIL -->
   a. Planner reads ALL feedback from all reviewers
   b. Planner incorporates changes OR documents why feedback doesn't apply
   c. Spawn 3 NEW reviewer instances (never reuse -- prevents anchoring)
   d. Repeat from step 3
6. Max 3 iterations --> present plan with remaining issues noted for user decision
```

### Phase 1: Spawn Reviewers (Parallel)

```typescript
// Spawn all three reviewers in parallel for efficiency
const [feasibilityResult, completenessResult, scopeResult] = await Promise.all([
  Task({
    subagent_type: "general-purpose",
    description: "Feasibility review",
    prompt: feasibilityReviewPrompt(planText, userRequest),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Completeness review",
    prompt: completenessReviewPrompt(planText, userRequest),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Scope & Alignment review",
    prompt: scopeAlignmentReviewPrompt(planText, userRequest),
  }),
]);
```

### Phase 2: Evaluate Gate

```text
IF feasibilityResult.verdict === "PASS"
   AND completenessResult.verdict === "PASS"
   AND scopeResult.verdict === "PASS":
  --> GATE APPROVED. Present plan to user.

ELSE:
  --> Consolidate all FAIL findings.
  --> Pass to planner for revision.
  --> Increment iteration counter.
  --> IF iterations >= 3: present plan with remaining issues to user.
  --> ELSE: spawn fresh reviewers on revised plan.
```

### Phase 3: Iteration (on FAIL)

1. Planner receives consolidated feedback from ALL reviewers (both PASS and FAIL)
2. Planner revises the plan, addressing each FAIL finding explicitly
3. For each finding, planner either:
   - **Fixes it** — modifies the plan to resolve the issue
   - **Rebuts it** — documents why the finding is incorrect or not applicable (with evidence)
4. Spawn 3 entirely new `Task()` instances for re-review
5. New reviewers see ONLY the revised plan and original request — NOT previous findings

### Phase 4: Escalation (after 3 iterations)

If the gate has not achieved consensus after 3 iterations:

```markdown
## Plan Review Gate: ESCALATION REQUIRED (3/3 iterations exhausted)

### Remaining Blocking Issues

#### Feasibility
- [issue with evidence]

#### Completeness
- [issue with evidence]

#### Scope & Alignment
- [issue with evidence]

### Iteration History
| Iteration | Feasibility | Completeness | Scope & Alignment |
|-----------|-------------|--------------|-------------------|
| 1         | FAIL        | PASS         | FAIL              |
| 2         | PASS        | PASS         | FAIL              |
| 3         | PASS        | PASS         | FAIL              |

### Options
1. **Override** — Proceed with plan as-is (remaining issues become known risks)
2. **Revise** — Continue iterating on the plan manually
3. **Simplify** — Reduce scope to eliminate contentious items
4. **Cancel** — Abandon this plan and start fresh

Please choose an option or provide additional context.
```

---

## Reviewer Prompts

### Feasibility Reviewer Prompt

````markdown
You are the FEASIBILITY REVIEWER for a plan review gate.

## Mode
Adversarial — your job is to FIND FAILURES in plan feasibility, not to approve.

## Rubric
Read and follow: ./rubrics/plan-review-rubric-adversarial.md (Feasibility section)

## User's Original Request
${userRequest}

## Plan Under Review
${planText}

## Your Task
Determine whether this plan can actually be executed against the real codebase. Check:

1. **File paths exist** — Use glob/grep to verify every file path the plan references actually exists. Fabricated paths = BLOCKING FAIL.
2. **Dependency ordering** — Verify work units don't have circular dependencies or reference things created in later steps. Read the codebase to confirm.
3. **Technical approach** — Does the plan use patterns, libraries, and conventions that match the actual codebase? Read existing code to verify.
4. **Unstated assumptions** — Does the plan silently depend on services, configurations, or infrastructure that doesn't exist?

## Rules
- Check EACH criterion. Cite file:line or glob results as evidence for PASS, or specific gaps for FAIL.
- Any single BLOCKING issue means overall FAIL.
- You have NO context from previous reviews. Judge fresh.
- Do NOT suggest improvements. Only report PASS or FAIL with evidence.
- Do NOT consider other reviewers. You are independent.

## Output Format
Follow the per-reviewer output format defined in the skill.
````

### Completeness Reviewer Prompt

````markdown
You are the COMPLETENESS REVIEWER for a plan review gate.

## Mode
Adversarial — your job is to FIND GAPS in plan coverage, not to approve.

## Rubric
Read and follow: ./rubrics/plan-review-rubric-adversarial.md (Completeness section)

## User's Original Request
${userRequest}

## Plan Under Review
${planText}

## Your Task
Determine whether this plan fully addresses every aspect of the user's request. Check:

1. **Requirement mapping** — Extract each distinct requirement from the user's request. For each one, find the plan item that addresses it. Missing mapping = BLOCKING FAIL.
2. **Verification steps** — Each planned change must have a defined way to verify it works (test, assertion, manual check). Missing verification = BLOCKING FAIL.
3. **Edge cases** — Are error scenarios, empty states, and boundary conditions addressed? Obvious gaps = BLOCKING FAIL.
4. **Rollback/backward compatibility** — Does the plan consider what happens if changes need to be reverted?
5. **Cross-file integration** — Are files that import or depend on changed files accounted for?

## Rules
- Check EACH criterion. Cite specific user requirements and plan items as evidence.
- Any single BLOCKING issue means overall FAIL.
- You have NO context from previous reviews. Judge fresh.
- Do NOT suggest improvements. Only report PASS or FAIL with evidence.
- Do NOT consider other reviewers. You are independent.

## Output Format
Follow the per-reviewer output format defined in the skill.
````

### Scope & Alignment Reviewer Prompt

````markdown
You are the SCOPE & ALIGNMENT REVIEWER for a plan review gate.

## Mode
Adversarial — your job is to FIND MISALIGNMENT between the plan and user request, not to approve.

## Rubric
Read and follow: ./rubrics/plan-review-rubric-adversarial.md (Scope & Alignment section)

## User's Original Request
${userRequest}

## Plan Under Review
${planText}

## Your Task
Determine whether this plan is right-sized for what the user actually asked. Check:

1. **Matches user request** — Does the plan solve what was asked? Or does it solve something the planner found more interesting? Divergence = BLOCKING FAIL.
2. **No scope creep** — Are there features, abstractions, or refactoring beyond what was requested? Unnecessary additions = BLOCKING FAIL.
3. **No under-scoping** — Are obvious implications of the request omitted? Missing obvious work = BLOCKING FAIL.
4. **Complexity proportional** — Is the solution complexity proportional to the problem complexity?
5. **Simpler alternative** — Is there a significantly simpler approach that achieves the same outcome?

## Rules
- Check EACH criterion. Cite the user's request and plan scope as evidence.
- Any single BLOCKING issue means overall FAIL.
- You have NO context from previous reviews. Judge fresh.
- Do NOT suggest improvements. Only report PASS or FAIL with evidence.
- Do NOT consider other reviewers. You are independent.

## Output Format
Follow the per-reviewer output format defined in the skill.
````

---

## Output Formats

### Per-Reviewer Output

Each reviewer produces output in this exact format:

```markdown
## [Reviewer Name] — [PASS/FAIL]

### Evidence
- [Finding 1]: [file:line reference or specific gap with evidence]
- [Finding 2]: [file:line reference or specific gap with evidence]
- ...

### Verdict
[PASS: All criteria met — no blocking issues found]
OR
[FAIL: {numbered list of blocking issues with evidence}]
```

### Consolidated Gate Output (All PASS)

```markdown
## Plan Review Gate — APPROVED (iteration N of 3)

| Reviewer | Verdict | Key Finding |
|----------|---------|-------------|
| Feasibility | PASS | All file paths verified, deps ordered correctly |
| Completeness | PASS | All N requirements mapped to plan items |
| Scope & Alignment | PASS | Plan matches user request, no scope creep |

Plan is ready for user review.
```

### Consolidated Gate Output (Any FAIL)

```markdown
## Plan Review Gate — REVISION NEEDED (iteration N of 3)

| Reviewer | Verdict | Blocking Issues |
|----------|---------|-----------------|
| Feasibility | PASS | — |
| Completeness | FAIL | 2 blocking issues |
| Scope & Alignment | FAIL | 1 blocking issue |

### Blocking Issues (MUST ADDRESS)

#### Completeness Reviewer
1. **Missing requirement mapping**: User asked for X but no plan item addresses it
2. **No verification for WU-003**: Plan item has no test or assertion defined

#### Scope & Alignment Reviewer
1. **Scope creep**: WU-005 adds caching layer not requested by user

---

**Iteration**: N of 3
**Action Required**: Planner must address all blocking issues and resubmit.
```

---

## Anti-Patterns

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
| --- | --- | --- | --- |
| 1 | **Reusing reviewer instances** — passing findings to next review cycle | Anchoring bias: reviewer checks for previous findings instead of reviewing fresh | Spawn new `Task()` instances with no prior context |
| 2 | **Cross-reviewer contamination** — sharing one reviewer's output with another | Destroys independence; reviewers converge instead of checking independently | Each reviewer sees only: plan, user request, codebase |
| 3 | **Treating FAIL as advisory** — "reviewer failed but the issues are minor" | Undermines the gate; equivalent to not having a gate | FAIL means revise and re-review. No exceptions. |
| 4 | **Skipping the gate for "simple" plans** — "this is straightforward, skip review" | Judgment of simplicity is exactly what the gate validates | If the plan has 2+ work units or touches 3+ files, run the gate |
| 5 | **Planner self-reviewing** — same agent that wrote the plan also reviews it | Confirmation bias; planner will approve their own work | Reviewers must be separate `Task()` instances from the planner |
| 6 | **Unlimited iterations** — "keep reviewing until it passes" | Diminishing returns; likely a fundamental plan problem after 3 rounds | Max 3 iterations, then escalate to user with full context |
| 7 | **Partial re-review** — only re-running the reviewer that failed | Other reviewers might fail on the revised plan | All 3 reviewers re-run on every iteration (fresh instances) |

---

## Integration Points

### Upstream (inputs to this gate)

- `writing-plans` skill — produces plans that feed into this gate
- `orchestrated-execution` plan validation — pre-flight checklist runs before this gate
- Direct plan drafting by planner/explorer agents

### Downstream (after gate approval)

- Plan presented to user for final approval
- **After user approval**: Persist the approved plan to `.beads/plans/active-plan.md` (see Section: Plan Persistence below)
- User-approved plan flows to `orchestrated-execution` for the 4-phase execution loop
- Work unit decomposition and implementation begin

### Plan Persistence

After the gate approves AND the user approves the plan, persist it to BEADS so it survives context compaction:

```bash
mkdir -p .beads/plans

# Write with metadata header
cat > .beads/plans/active-plan.md << 'PLAN_EOF'
# Active Plan
<!-- approved: <timestamp> -->
<!-- gate-iterations: <N> -->
<!-- user-approved: true -->
<!-- status: in-progress -->

<full approved plan text>
PLAN_EOF
```

This enables context recovery — if the agent loses context mid-execution, it can re-read the approved plan from disk instead of re-running the entire gate. See `orchestrated-execution` Section 6.5 for the full recovery protocol.

### Relationship to Design Review Gate

The **design review gate** (`design-review-gate`) validates _design documents_ using 5 specialist agents (PM, Architect, Designer, Security, CTO) with APPROVED/NEEDS_REVISION verdicts.

The **plan review gate** (this skill) validates _implementation plans_ using 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) with binary PASS/FAIL verdicts.

These are complementary gates at different stages:
1. Design review gate validates _what_ to build
2. Plan review gate validates _how_ to build it
3. Orchestrated execution validates _that_ it was built correctly

---

## Success Criteria

The plan review gate succeeds when:

- [ ] All three reviewers return PASS verdict
- [ ] All blocking issues are resolved with evidence
- [ ] Plan is presented to user with gate approval summary
- [ ] Reviewer isolation was maintained (fresh instances, no cross-contamination)
- [ ] Gate completed within 3 iterations

---

## Related Skills

- `design-review-gate` — Validates design documents before planning begins
- `orchestrated-execution` — Executes approved plans using the 4-phase loop
- `writing-plans` — Produces plans that feed into this gate

---

## Rubric Reference

Reviewers follow: `./rubrics/plan-review-rubric-adversarial.md`

This adversarial rubric is distinct from `./rubrics/plan-review-rubric.md` (used by the CTO Agent for collaborative plan review). See the rubric file for detailed scoring criteria and evidence requirements.
