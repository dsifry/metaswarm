---
name: plan-review-gate
description: Automatic adversarial review gate that spawns 3 independent reviewers in parallel once a plan is written - all must PASS before writing-plans presents the plan
auto_activate: true
triggers:
  - "plan drafted"
  - "implementation plan created"
  - before:writing-plans:execution-handoff
  - "plan written, before writing-plans presents it"
  - after:orchestrated-execution:plan-validation
---

# Plan Review Gate

**Core principle**: No plan reaches the user without surviving independent adversarial scrutiny.

## Purpose

This skill automatically activates once an implementation plan is written, before writing-plans presents the plan (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). It spawns three independent adversarial reviewers in parallel — Feasibility, Completeness, and Scope & Alignment — each as a fresh `Task()` instance. ALL three must PASS. On failure, the planner incorporates feedback and resubmits to entirely fresh reviewer instances. After each round the gate applies the severity rule from [`./guides/delivery-scope.md`](./guides/delivery-scope.md) (at most 10 rounds) to advance, iterate or escalate.

---

## Activation Triggers

This skill auto-activates when:

1. An implementation plan is drafted (by planner, explorer, or orchestrator)
2. writing-plans has written the plan, before its Execution Handoff (link the plan, user review request, execution choice)
3. The orchestrator's plan validation phase produces a plan for review
4. User explicitly requests: `/plan-review <path-to-plan>`

**Do NOT use for**: Trivial changes (single-file bug fixes, copy edits, config tweaks). The plan must have at least 2 work units or touch 3+ files to warrant gate review.

---

## The 3 Adversarial Reviewers

Each reviewer is a fresh `Task()` instance with read-only access to the codebase. Reviewers report every finding in the 6-field contract (`title`, `description`, `severity`, `protects`, `evidence`, `blocker`) from `./guides/delivery-scope.md`, and return PASS/FAIL: FAIL only if at least one finding has `blocker: yes`.

**Reading the check tables.** The tables below keep their wording and map onto the contract:

- "BLOCKING if …" checks produce critical or major findings. They block only with `protects` (the user requirement, DoD item or credible scenario the check protects).
- "WARNING" checks produce minor findings, recorded as follow-ups.

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
2. Spawn 3 adversarial reviewers in PARALLEL (fresh Task() instances, role type `roleType("plan-reviewer")`)
3. Collect all 3 verdicts
4. IF all PASS (or rule line 5 downgraded every remaining blocker) --> present plan to user with gate approval summary
5. IF any FAIL --> apply the severity rule (Phase 2). When it says iterate:
   a. Planner reads ALL feedback from all reviewers
   b. Planner fixes each blocker OR documents why it doesn't apply; minor/nit findings become follow-ups
   c. Spawn 3 NEW reviewer instances (role type `roleType("plan-reviewer")`; never reuse -- prevents anchoring)
   d. Repeat from step 3
6. The severity rule escalates (recurring/disputed blocker, overengineering signal, or the 10-round cap)
   --> present the plan with the Phase 4 escalation report for user decision
```

### Phase 1: Spawn Reviewers (Parallel)

```typescript
// Spawn all three reviewers in parallel for efficiency.
// Every reviewer uses the plan-reviewer role type; the role lives in the prompt.
// Role types are resolved per ../start/guides/agent-coordination.md#role-type-resolution
const [feasibilityResult, completenessResult, scopeResult] = await Promise.all([
  Task({
    subagent_type: roleType("plan-reviewer"),
    description: "Feasibility review",
    prompt: feasibilityReviewPrompt(planText, userRequest),
  }),
  Task({
    subagent_type: roleType("plan-reviewer"),
    description: "Completeness review",
    prompt: completenessReviewPrompt(planText, userRequest),
  }),
  Task({
    subagent_type: roleType("plan-reviewer"),
    description: "Scope & Alignment review",
    prompt: scopeAlignmentReviewPrompt(planText, userRequest),
  }),
]);
```

### Phase 2: Evaluate Gate

The orchestrator, not the reviewers, decides what happens after each round. It applies the severity rule from [`./guides/delivery-scope.md`](./guides/delivery-scope.md): `SAFETY_CAP` = 10 rounds per gate occurrence, and the first line that matches wins. "Re-validate" here means revising the plan; "FRESH review" means spawning fresh `roleType("plan-reviewer")` reviewers on the revised plan.

```text
after each review round (round = 1, 2, ...):
  file every minor/nit finding as a follow-up (see Follow-ups)
  1. no blocker: yes findings            → PASS, advance
  2. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal
  3. the same critical/major finding recurs after a fix attempt for it,
     or two reviewers rate the same finding blocker vs. non-blocker   → escalate
  4. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers
                                         → fix blockers, re-validate, FRESH review
  5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;
                                           any still names a credible scenario → escalate with a recommendation;
                                           otherwise downgrade them to follow-ups and advance
  6. otherwise                           → fix blockers, re-validate, FRESH review
```

- **PASS, advance** means GATE APPROVED: present the plan to the user. Line 5's downgrade-and-advance counts the same, with the downgraded items listed as follow-ups.
- **Overengineering check (line 5).** Signals include repeated review/fix cycles without a new user-visible risk, and blockers that protect only theoretical states. Restate the user's request and DoD, re-classify each open blocker, and escalate only if one still names a credible scenario.
- **Malformed output.** A FAIL whose findings lack the 6 fields is re-requested once in the contract format, then escalated with the raw output. It is never treated as PASS.

**Follow-ups.** Minor/nit findings never block. When `bd` is available, file each as a BEADS task (`bd create --type task`), linked to the epic if one exists. Otherwise, or if `bd create` fails, list them under a `### Follow-ups` heading in the gate output, so the plan and later the PR body carry them.

### Phase 3: Iteration (on FAIL)

1. Planner receives consolidated feedback from ALL reviewers (both PASS and FAIL)
2. Planner revises the plan, addressing each `blocker: yes` finding explicitly
3. For each blocker, planner either:
   - **Fixes it** — modifies the plan to resolve the issue
   - **Rebuts it** — documents why the finding is incorrect or not applicable (with evidence)
4. Spawn 3 entirely new `Task()` instances (role type `roleType("plan-reviewer")`) for re-review
5. New reviewers see ONLY the revised plan and original request — NOT previous findings

### Phase 4: Escalation

When the severity rule says escalate (line 2, 3 or 5):

```markdown
## Review Escalation: Plan Review Gate — <plan name>

**Rule line**: <2 cap hit | 3 recurring/disputed | 5 overengineering signal>

### Remaining findings
- **Critical**: [Feasibility] <title>: <description> — protects: <...> — evidence: <...>
- **Major**: [Completeness] <title>: <description> — protects: <...> — evidence: <...>
- **Minor**: [Scope & Alignment] <title> (follow-up filed)
- **Nit**: [Feasibility] <title> (follow-up filed)

### Round history
| Round | Feasibility | Completeness | Scope & Alignment | Blockers (critical/major) | Fixed this round | Rule decision |
|-------|-------------|--------------|-------------------|---------------------------|------------------|---------------|
| 1     | FAIL        | PASS         | FAIL              | 0 / 2                     | —                | 4: iterate    |
| 2     | PASS        | PASS         | FAIL              | 0 / 1                     | 0 / 2            | 4: iterate    |
| 3     | PASS        | PASS         | FAIL              | 0 / 1                     | 0 / 0            | 3: escalate   |

### Follow-ups
- <minor/nit findings, or the BEADS task IDs filed for them>

### Options
1. **Revise** — fix the remaining blockers (or the requirement they protect), then run a fresh review round
2. **Narrow scope** — move the contentious items to a new issue, then run a fresh review round on what remains
3. **Defer** — shelve this work for later; nothing advances
4. **Cancel** — abandon this work

**Recommendation**: <revise|narrow scope|defer|cancel> — <reason from the rule>
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

1. **File paths exist** — Use glob/grep to verify every file path the plan references actually exists. Fabricated path = blocker (major; protects: the plan must be executable against the real codebase).
2. **Dependency ordering** — Verify work units don't have circular dependencies or reference things created in later steps. Read the codebase to confirm. Circular or forward reference = blocker (major; protects: the plan's execution order).
3. **Technical approach** — Does the plan use patterns, libraries, and conventions that match the actual codebase? Read existing code to verify. Incompatible approach = blocker (major; protects: the plan must be executable against the real codebase).
4. **Unstated assumptions** — Does the plan silently depend on services, configurations, or infrastructure that doesn't exist? Missing critical dependency = blocker (major; protects: the plan must be executable against the real codebase).

## Findings
Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty

## Rules
- Check EACH criterion. Cite file:line or glob results as evidence for PASS, or specific gaps for FAIL.
- Any `blocker: yes` finding means overall FAIL. A critical or major finding without `protects` is advisory (`blocker: no`).
- You have NO context from previous reviews. Judge fresh.
- Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.
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

1. **Requirement mapping** — Extract each distinct requirement from the user's request. For each one, find the plan item that addresses it. Missing mapping = blocker (major; protects: <the unmapped requirement>).
2. **Verification steps** — Each planned change must have a defined way to verify it works (test, assertion, manual check). Missing verification = blocker (major; protects: <the change's DoD item>).
3. **Edge cases** — Are error scenarios, empty states, and boundary conditions addressed? Obvious gap = blocker (major; protects: <the credible user scenario that fails>).
4. **Rollback/backward compatibility** — Does the plan consider what happens if changes need to be reverted?
5. **Cross-file integration** — Are files that import or depend on changed files accounted for? Missing integration point = blocker (major; protects: <the dependent behaviour that would break>).

## Findings
Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty

## Rules
- Check EACH criterion. Cite specific user requirements and plan items as evidence.
- Any `blocker: yes` finding means overall FAIL. A critical or major finding without `protects` is advisory (`blocker: no`).
- You have NO context from previous reviews. Judge fresh.
- Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.
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

1. **Matches user request** — Does the plan solve what was asked? Or does it solve something the planner found more interesting? Divergence = blocker (major; protects: <the user's request>).
2. **No scope creep** — Are there features, abstractions, or refactoring beyond what was requested? Unnecessary addition = blocker (major; protects: <the user's request and its scope>).
3. **No under-scoping** — Are obvious implications of the request omitted? Missing obvious work = blocker (major; protects: <the implied requirement>).
4. **Complexity proportional** — Is the solution complexity proportional to the problem complexity?
5. **Simpler alternative** — Is there a significantly simpler approach that achieves the same outcome?

## Findings
Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty

## Rules
- Check EACH criterion. Cite the user's request and plan scope as evidence.
- Any `blocker: yes` finding means overall FAIL. A critical or major finding without `protects` is advisory (`blocker: no`).
- You have NO context from previous reviews. Judge fresh.
- Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.
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

### Findings
1. - title: <short label, ≤ ~80 chars>
   - description: <1-3 sentences: what is wrong and why it matters>
   - severity: critical | major | minor | nit
   - protects: <credible user scenario | explicit requirement | DoD item>   (required for critical/major)
   - evidence: <file:line reference, glob result, or expected-vs-found>
   - blocker: yes | no

### Verdict
[FAIL: at least one `blocker: yes` finding — list their numbers]
OR
[PASS: no `blocker: yes` finding]
```

### Consolidated Gate Output (All PASS)

```markdown
## Plan Review Gate — APPROVED (round N)

| Reviewer | Verdict | Key Finding |
|----------|---------|-------------|
| Feasibility | PASS | All file paths verified, deps ordered correctly |
| Completeness | PASS | All N requirements mapped to plan items |
| Scope & Alignment | PASS | Plan matches user request, no scope creep |

### Follow-ups
- [Scope & Alignment] minor: <title> (bd-123)

Plan is ready for user review.
```

### Consolidated Gate Output (Any FAIL)

```markdown
## Plan Review Gate — REVISION NEEDED (round N)

| Reviewer | Verdict | Blockers (critical/major) | Minor/Nit |
|----------|---------|---------------------------|-----------|
| Feasibility | PASS | 0 / 0 | 1 |
| Completeness | FAIL | 0 / 2 | 0 |
| Scope & Alignment | FAIL | 0 / 1 | 1 |

### Blockers (MUST ADDRESS)

#### Critical
- none

#### Major
1. [Completeness] **Missing requirement mapping**: User asked for X but no plan item addresses it — protects: requirement "X" — evidence: no WU mentions X
2. [Completeness] **No verification for WU-003**: Plan item has no test or assertion defined — protects: WU-003 DoD — evidence: WU-003 has no Verification line
3. [Scope & Alignment] **Scope creep**: WU-005 adds caching layer not requested by user — protects: the user's request — evidence: WU-005

### Follow-ups
- [Feasibility] minor: <title> (bd-124)
- [Scope & Alignment] nit: <title> (bd-125)

---

**Round**: N (cap 10)
**Rule decision**: 4: iterate — ≥2 independent reviewers reported blockers
**Action Required**: Planner must address every blocker above and resubmit to fresh reviewers.
```

---

## Anti-Patterns

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
| --- | --- | --- | --- |
| 1 | **Reusing reviewer instances** — passing findings to next review cycle | Anchoring bias: reviewer checks for previous findings instead of reviewing fresh | Spawn new `Task()` instances with no prior context |
| 2 | **Cross-reviewer contamination** — sharing one reviewer's output with another | Destroys independence; reviewers converge instead of checking independently | Each reviewer sees only: plan, user request, codebase |
| 3 | **Treating a blocker as advisory** — downgrading a justified blocker without the rule ("it's only one blocker, present the plan anyway") | Undermines the gate; equivalent to not having a gate | A `blocker: yes` FAIL means revise and re-review. Only rule line 5 (overengineering check) may downgrade a blocker to a follow-up. |
| 4 | **Skipping the gate for "simple" plans** — "this is straightforward, skip review" | Judgment of simplicity is exactly what the gate validates | If the plan has 2+ work units or touches 3+ files, run the gate |
| 5 | **Planner self-reviewing** — same agent that wrote the plan also reviews it | Confirmation bias; planner will approve their own work | Reviewers must be separate `Task()` instances from the planner |
| 6 | **Iterating on a fixed count** — stopping after N rounds regardless of what remains, or reviewing until every nit is gone | Stops while real blockers remain, or keeps going on findings that don't block delivery | Severity-gated iteration, cap 10: apply the rule after every round, file minor/nit as follow-ups, escalate with a recommendation |
| 7 | **Partial re-review** — only re-running the reviewer that failed | Other reviewers might fail on the revised plan | All 3 reviewers re-run on every iteration (fresh instances) |

---

## Integration Points

### Upstream (inputs to this gate)

- `writing-plans` skill — produces plans that feed into this gate; the gate runs before writing-plans' Execution Handoff
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
- [ ] Every `blocker: yes` finding is resolved with evidence; minor/nit findings are filed as follow-ups
- [ ] Plan is presented to user with gate approval summary
- [ ] Reviewer isolation was maintained (fresh instances, no cross-contamination)
- [ ] Each round's decision followed the severity rule (at most 10 rounds), or the gate escalated with a recommendation

---

## Related Skills

- `design-review-gate` — Validates design documents before planning begins
- `orchestrated-execution` — Executes approved plans using the 4-phase loop
- `writing-plans` — Produces plans that feed into this gate; the gate runs before its Execution Handoff

---

## Rubric Reference

Reviewers follow: `./rubrics/plan-review-rubric-adversarial.md`

This adversarial rubric is distinct from `./rubrics/plan-review-rubric.md` (used by the CTO Agent for collaborative plan review). See the rubric file for detailed scoring criteria and evidence requirements.
