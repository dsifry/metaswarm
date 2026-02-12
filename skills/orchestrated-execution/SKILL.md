---
name: orchestrated-execution
description: 4-phase execution loop for work units - IMPLEMENT, VALIDATE, ADVERSARIAL REVIEW, COMMIT
auto_activate: false
triggers:
  - "orchestrated execution"
  - "4-phase loop"
  - "adversarial review"
---

# Orchestrated Execution Skill

**Core principle**: Trust nothing. Verify everything. Review adversarially.

This skill defines a generalized 4-phase execution loop that any orchestrator can invoke when implementing work units. It replaces linear "implement then review" flows with a rigorous cycle that independently validates results and adversarially reviews against a written spec contract.

---

## When to Use This Skill

- **Complex tasks** decomposed into multiple work units
- **Tasks with a written spec** containing Definition of Done (DoD) items
- **Multi-agent orchestration** where subagents produce work that needs verification
- **High-stakes changes** where self-reported "it works" is insufficient

**Do NOT use for**: Single-file bug fixes, copy changes, or tasks without a spec.

---

## 1. Work Unit Decomposition

A **work unit** is the atomic unit of orchestrated execution. Before entering the 4-phase loop, decompose the implementation plan into work units.

### Work Unit Structure

Each work unit contains:

| Field | Description | Example |
| --- | --- | --- |
| **ID** | Unique identifier (BEADS task ID) | `bd-wu-001` |
| **Title** | Human-readable name | "Implement auth middleware" |
| **Spec** | Written specification with acceptance criteria | Link to design doc section |
| **DoD Items** | Enumerated, verifiable done criteria | `[ ] Middleware rejects expired tokens` |
| **Dependencies** | Other work units that must complete first | `[bd-wu-000]` |
| **File Scope** | Files this work unit may touch | `src/middleware/auth.ts, src/middleware/auth.test.ts` |
| **Human Checkpoint** | Whether to pause for human review after completion | `true` for risky changes |

### Constructing Dependency Graphs

Work units form a directed acyclic graph (DAG):

```
wu-001 (schema changes) ───┐
                            ├──→ wu-003 (API endpoints)  ───→ wu-005 (integration tests)
wu-002 (shared utilities) ──┘                                        │
                                                                     ▼
wu-004 (UI components)  ────────────────────────────────────→ wu-006 (e2e tests)
```

**Rules for decomposition:**

1. Each work unit has a **single responsibility** — one logical change
2. File scopes should **not overlap** between parallel work units
3. Dependencies must be **explicit** — no implicit ordering assumptions
4. Work units at the same depth with no interdependencies **run in parallel**
5. Each DoD item must be **independently verifiable** (not "code looks good")

### Decomposition Template

```bash
# Create work units as BEADS tasks under the epic
bd create "WU-001: <title>" --type task --parent <epic-id> \
  --description "Spec: <spec-section>\nDoD:\n- [ ] <item-1>\n- [ ] <item-2>\nFile scope: <files>\nCheckpoint: <yes/no>"

# Set up dependencies
bd dep add <wu-003> <wu-001>
bd dep add <wu-003> <wu-002>
```

---

## 2. The 4-Phase Execution Loop

For each work unit, execute these four phases in sequence. **Do not skip phases.** Do not combine phases. Do not proceed to the next phase until the current phase produces a clear outcome.

```
┌─────────────────────────────────────────────────────────────────┐
│                    4-PHASE EXECUTION LOOP                       │
│                                                                 │
│   ┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────┐ │
│   │ IMPLEMENT│───→│ VALIDATE │───→│  ADVERSARIAL │───→│COMMIT│ │
│   │          │    │          │    │    REVIEW     │    │      │ │
│   └──────────┘    └──────────┘    └──────┬───────┘    └──────┘ │
│        ▲                                 │                      │
│        │              FAIL               │                      │
│        └─────────────────────────────────┘                      │
│                                                                 │
│   On FAIL: fix → re-validate → FRESH review → max 3 → escalate │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 1: IMPLEMENT

The coding subagent executes against the work unit spec.

**Orchestrator actions:**

1. Spawn a coding subagent with the work unit spec, DoD items, and file scope
2. The subagent implements the change following TDD (test first, then implementation)
3. The subagent reports completion — **but the orchestrator does NOT trust this report**

**Subagent spawn template:**

```
You are the CODER AGENT for work unit ${wuId}.

## Spec
${spec}

## Definition of Done
${dodItems.map((item, i) => `${i+1}. ${item}`).join('\n')}

## File Scope
You may ONLY modify these files: ${fileScope.join(', ')}

## Rules
- Follow TDD: write failing test first, then implement to make it pass
- Do NOT modify files outside your file scope
- Do NOT self-certify — the orchestrator will validate independently
- When complete, report what you changed and what tests you added
```

**Phase 1 output:** List of changed files and new tests.

### Phase 2: VALIDATE

The **orchestrator independently** runs quality gates. Never trust subagent self-reports.

**Orchestrator actions (run these yourself, NOT via the coding subagent):**

```bash
# 1. Type checking
npx tsc --noEmit

# 2. Linting
npx eslint <changed-files>

# 3. Run tests (full suite, not just new tests)
npx vitest run

# 4. Coverage check (if configured)
npx vitest run --coverage

# 5. Verify file scope was respected
git diff --name-only | while read file; do
  echo "$file" # Check each file is within the work unit's declared scope
done
```

**Phase 2 outcomes:**

- **All gates pass** → proceed to Phase 3
- **Any gate fails** → return to Phase 1 (the coding subagent fixes the issue)
- **File scope violated** → return to Phase 1 (subagent must revert out-of-scope changes)

**Critical rule:** The orchestrator runs validation commands directly. The orchestrator does NOT ask the coding subagent "did the tests pass?" and accept the answer.

### Phase 3: ADVERSARIAL REVIEW

A **separate review subagent** checks the implementation against the spec contract. This is NOT the same as a collaborative code review — it's adversarial verification.

**Key differences from collaborative review:**

| Collaborative Review | Adversarial Review |
| --- | --- |
| APPROVED / CHANGES REQUIRED | PASS / FAIL |
| Subjective quality assessment | Binary spec compliance check |
| Reviewer suggests improvements | Reviewer finds contract violations |
| Same reviewer can re-review | Fresh reviewer required on re-review |
| Uses `code-review-rubric.md` | Uses `adversarial-review-rubric.md` |

**Orchestrator actions:**

1. Spawn a **new** review subagent in adversarial mode
2. Pass: the spec, the DoD items, and the diff (NOT the coding subagent's self-assessment)
3. The reviewer checks each DoD item with evidence (file:line references)

**Reviewer spawn template:**

```
You are the ADVERSARIAL REVIEWER for work unit ${wuId}.

## Mode
Adversarial — your job is to FIND FAILURES, not to approve.

## Rubric
Read and follow: .claude/rubrics/adversarial-review-rubric.md

## Spec
${spec}

## Definition of Done
${dodItems.map((item, i) => `${i+1}. ${item}`).join('\n')}

## What to Review
Run: git diff main..HEAD -- ${fileScope.join(' ')}

## Rules
- Check EACH DoD item. Cite file:line evidence for PASS or expected-vs-found for FAIL.
- Any single BLOCKING issue means overall FAIL.
- You have NO context from previous reviews. Judge fresh.
- Do NOT suggest improvements. Only report PASS or FAIL with evidence.
```

**Phase 3 outcomes:**

- **PASS** (zero BLOCKING issues) → proceed to Phase 4
- **FAIL** (any BLOCKING issue) → return to Phase 1 with the failure report

**Fresh reviewer rule:** On re-review after FAIL, the orchestrator MUST spawn a **new** review subagent. Never pass previous findings to the new reviewer. Never reuse the same reviewer instance. This prevents anchoring bias and ensures independent verification.

### Phase 4: COMMIT

Only after PASS from adversarial review.

**Orchestrator actions:**

```bash
# Stage only files within the work unit's file scope
git add <file-scope-files>

# Commit with reference to work unit
git commit -m "feat(wu-${wuId}): <description>

DoD items verified:
$(dodItems.map((item, i) => `- [x] ${item}`).join('\n'))

Reviewed-by: adversarial-review (PASS)"
```

**After commit:**
- Update BEADS task status: `bd close <wu-task-id> --reason "4-phase loop complete. PASS."`
- If this work unit has a **human checkpoint** flag, pause and report before continuing

---

## 3. Parallel Work Unit Execution

When multiple work units have no dependencies on each other, execute them in parallel — but with structured convergence points.

```
              ┌──── WU-001: IMPLEMENT ────┐
              │                            │
Fan-out ──────┼──── WU-002: IMPLEMENT ────┼──── Converge for VALIDATE
              │                            │
              └──── WU-003: IMPLEMENT ────┘
                                           │
              ┌──── WU-001: REVIEW ────────┤
              │                            │
Fan-out ──────┼──── WU-002: REVIEW ────────┼──── Sequential COMMIT
              │                            │
              └──── WU-003: REVIEW ────────┘
```

**Rules for parallel execution:**

1. **Fan-out implementations**: Spawn coding subagents for independent work units simultaneously
2. **Converge for validation**: Wait for ALL parallel implementations to complete, then validate each
3. **Fan-out reviews**: Spawn review subagents for each work unit simultaneously
4. **Sequential commits**: Commit work units one at a time to maintain clean git history
5. **If any FAIL**: Only re-run the failed work unit's loop — don't re-run passed units

---

## 4. Human Checkpoints (Proactive)

Human checkpoints are **planned pauses**, not reactive escalations. They are defined in the spec before execution begins.

### When to Set Checkpoints

- After work units that change database schemas
- After work units that modify security-sensitive code
- After the first work unit in a new architectural pattern
- Before any destructive or irreversible operation
- At natural boundaries the human specified in the issue

### Checkpoint Report Format

When reaching a checkpoint, present this report and **wait for explicit human approval**:

```markdown
## Checkpoint: <checkpoint-name>

### Completed Work Units
| WU | Title | Status | Review |
| --- | --- | --- | --- |
| WU-001 | Schema migration | PASS | Adversarial PASS |
| WU-002 | Service layer | PASS | Adversarial PASS |

### Key Decisions Made
- <decision-1>: <rationale>
- <decision-2>: <rationale>

### What Comes Next
- WU-003: <description>
- WU-004: <description>

### Questions for Human (if any)
- <question>

---
**Action required**: Reply to continue, or provide feedback to adjust course.
```

**Do NOT continue past a checkpoint without human response.** This is not a notification — it's a gate.

---

## 5. Final Comprehensive Review

After ALL work units are complete and committed, run a final comprehensive review across the entire change set. This catches cross-unit integration issues that per-unit reviews miss.

### Final Review Checklist

```bash
# 1. Combined diff — see the full picture
git diff main..HEAD

# 2. Full test suite — not just changed files
npx vitest run

# 3. Type check — catch cross-unit type conflicts
npx tsc --noEmit

# 4. Lint — catch cross-unit style issues
npx eslint .

# 5. Coverage — verify overall coverage thresholds
npx vitest run --coverage

# 6. Commit history — verify clean, logical commits
git log main..HEAD --oneline
```

### Cross-Unit Integration Checks

- [ ] No duplicate or conflicting imports across work units
- [ ] No conflicting type definitions
- [ ] No overlapping test fixtures that could cause interference
- [ ] API contracts between work units are consistent
- [ ] No leftover TODO/FIXME markers from implementation
- [ ] File scope boundaries were respected (no unexpected file changes)

### Final Report Format

```markdown
## Final Comprehensive Review

### Overall Verdict: PASS / FAIL

### Work Units Summary
| WU | Title | Impl | Validate | Review | Commit |
| --- | --- | --- | --- | --- | --- |
| WU-001 | <title> | Done | Pass | Pass | <sha> |
| WU-002 | <title> | Done | Pass | Pass | <sha> |

### Quality Gates
- [ ] All tests pass
- [ ] Type check clean
- [ ] Lint clean
- [ ] Coverage thresholds met
- [ ] No cross-unit integration issues

### Remaining Issues
<any issues found during final review>

### Ready for PR: YES / NO
```

---

## 6. Recovery Protocol

When things go wrong during the 4-phase loop, follow this structured recovery.

### Step 1: DIAGNOSE

Identify what failed and gather evidence:

```bash
# Capture the failure
# - Which phase failed? (IMPLEMENT, VALIDATE, REVIEW)
# - What was the error message or FAIL reason?
# - Which DoD items are affected?
```

### Step 2: CLASSIFY

Categorize the failure:

| Classification | Description | Action |
| --- | --- | --- |
| **Fixable** | Clear error, known fix | Retry with specific fix instructions |
| **Ambiguous** | Unclear root cause | Investigate before retrying |
| **External** | Dependency, access, or environment issue | Escalate immediately |

### Step 3: RETRY (max 3 attempts)

For fixable and ambiguous failures:

1. **Attempt 1**: Fix the specific issue, re-run from Phase 1
2. **Attempt 2**: If same failure, try alternative approach
3. **Attempt 3**: If still failing, gather all evidence for escalation

Track retry count:

```bash
bd label add <task-id> retry:1  # or retry:2, retry:3
```

### Step 4: ESCALATE

After 3 failed attempts, escalate to human with full context:

```markdown
## Escalation: Work Unit <wu-id> Failed After 3 Attempts

### Failure History
| Attempt | Phase | Error | Fix Tried |
| --- | --- | --- | --- |
| 1 | VALIDATE | Tests fail: auth.test.ts:34 | Fixed mock setup |
| 2 | REVIEW | DoD #3 not met: missing edge case | Added edge case test |
| 3 | VALIDATE | Type error in cross-module import | Restructured imports |

### Root Cause Assessment
<best understanding of why this keeps failing>

### Options
1. <option-1>
2. <option-2>
3. Abandon this work unit and restructure

### Recommendation
<which option and why>
```

---

## 7. Anti-Patterns

These are explicit DON'Ts. Violating any of these undermines the entire orchestration pattern.

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
| --- | --- | --- | --- |
| 1 | **Self-certifying** — coding subagent says "tests pass" and you believe it | Subagents can hallucinate, skip tests, or misinterpret results | Orchestrator runs validation commands independently |
| 2 | **Skipping adversarial review** — "the code looks fine, let's commit" | Visual inspection misses spec violations; confirmation bias | Always run adversarial review against DoD items |
| 3 | **Reusing a reviewer** — same subagent re-reviews after FAIL | Anchoring bias: reviewer remembers previous findings and checks for those specifically instead of reviewing fresh | Spawn a new reviewer instance with no prior context |
| 4 | **Passing previous findings to new reviewer** — "last reviewer found X, check if fixed" | Creates anchoring bias; new reviewer should find issues independently | Pass only: spec, DoD items, diff. Nothing about previous reviews |
| 5 | **Trusting subagent file scope claims** — "I only changed the files in scope" | Subagents may accidentally modify files outside scope | Run `git diff --name-only` and verify each file independently |
| 6 | **Combining phases** — "implement and validate in one step" | Removes the independence that makes validation meaningful | Run each phase as a distinct step with its own output |
| 7 | **Continuing past a checkpoint without human response** | Defeats the purpose of proactive checkpoints | Wait. If urgent, escalate — don't skip |
| 8 | **Skipping final comprehensive review** — "all units passed individually" | Per-unit reviews can't catch cross-unit integration issues | Always run the final review after all units are committed |

---

## Quick Reference: Orchestrator Checklist

For each work unit:

- [ ] Spawn coding subagent with spec, DoD, and file scope
- [ ] Wait for implementation to complete
- [ ] **Independently** run: tsc, eslint, vitest (do NOT ask subagent)
- [ ] Verify file scope with `git diff --name-only`
- [ ] Spawn **fresh** adversarial reviewer with spec and DoD
- [ ] If PASS: commit with DoD verification in message
- [ ] If FAIL: fix → re-validate → spawn **new** reviewer (max 3 retries)
- [ ] If human checkpoint: present report and wait
- [ ] Update BEADS task status

After all work units:

- [ ] Run final comprehensive review
- [ ] Present final report
- [ ] Proceed to PR creation
