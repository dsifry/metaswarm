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

## Coordination Mode Note

This skill is mode-agnostic — the 4-phase execution loop works identically in both Task Mode and Team Mode. The differences:

- **Phase 1 (IMPLEMENT)**: In Team Mode, the coding subagent may be a persistent teammate (retains context across work units). In Task Mode, it's a fresh `Task()` per work unit.
- **Phase 3 (ADVERSARIAL REVIEW)**: ALWAYS a fresh `Task()` instance in BOTH modes. Never a teammate, never resumed.
- **All quality gates**: Unchanged regardless of mode.

See `guides/agent-coordination.md` for full mode detection and coordination details.

---

## Plan Review Gate

After drafting an implementation plan (Step 1: Plan Validation), submit it to the **Plan Review Gate** before presenting to the user. The gate spawns 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) — all must PASS. See `skills/plan-review-gate/SKILL.md` for details.

---

## When to Use This Skill

- **Complex tasks** decomposed into multiple work units
- **Tasks with a written spec** containing Definition of Done (DoD) items
- **Multi-agent orchestration** where subagents produce work that needs verification
- **High-stakes changes** where self-reported "it works" is insufficient

**Do NOT use for**: Single-file bug fixes, copy changes, or tasks without a spec.

---

## 1. Plan Validation (Pre-Flight Checklist)

Before submitting a plan to the Design Review Gate, the orchestrator MUST verify every item on this checklist. This prevents expensive design review cycles on fundamentally broken plans.

> **Note**: The `Plan` subagent type cannot write files (it has read-only access by design). If you spawn an Architect as a Plan subagent, it will return the plan as text in its response. The orchestrator must write the plan to `PLAN.md` itself.

### Architecture Checklist
- [ ] Every data access goes through a service layer (no direct DB calls from routes/handlers)
- [ ] Each work unit has a single responsibility (max ~5 files created/modified)
- [ ] Error handling strategy specified (typed error hierarchy, how errors cross layer boundaries)
- [ ] No hard-coded configuration — environment variables for all external service config

### Dependency Graph Checklist
- [ ] Each WU's dependencies are minimal (only depends on what it actually imports/uses)
- [ ] No unnecessary serialization — WUs that CAN be parallel ARE marked parallel
- [ ] No circular dependencies
- [ ] Integration WUs exist to wire components into the app shell (not just built in isolation)

### API Contract Checklist
If the plan includes HTTP endpoints or WebSocket protocols, verify:
- [ ] Every HTTP endpoint specifies: method, path, request schema, all response status codes, error response shapes
- [ ] WebSocket message types fully specified (client-to-server AND server-to-client message type tables)
- [ ] Protocol concerns documented: heartbeat, reconnection, acknowledgment strategy
- [ ] Response codes are explicit (not "returns the todo" but "returns 201 with the created todo")

### Security Checklist
- [ ] Trust boundaries identified (which inputs are untrusted?)
- [ ] Input validation specified for every endpoint/handler (schema, max size)
- [ ] Rate limiting specified for expensive operations (AI API calls, file uploads)
- [ ] Authentication/authorization requirements documented
- [ ] Secrets management documented (.env pattern, .gitignore verification)

### UI/UX Checklist
If the plan includes a user interface:
- [ ] User flows documented with trigger, steps, and visible outcome (see UI-FLOWS.md template)
- [ ] Text-based wireframes for each screen showing layout and interactive elements
- [ ] Empty states, loading states, and error states defined for each view
- [ ] Integration work units explicitly created to wire components into the app shell
- [ ] Component hierarchy documented (what renders what, where)

### External Dependencies Checklist
- [ ] All external services identified (APIs, SDKs, third-party services)
- [ ] Required credentials/config documented (env var names, how to obtain)
- [ ] Human checkpoint planned BEFORE work units that depend on external services
- [ ] Graceful degradation specified for when credentials are missing
- [ ] `.env.example` includes all required env vars

### Completeness Checklist
- [ ] All human checkpoints from the spec are included
- [ ] All features from the spec have at least one work unit
- [ ] Tooling is consistent (one package manager, matching config files across WUs)
- [ ] No WU exceeds ~5 files or ~3 distinct concerns
- [ ] WUs that are too large are split with explicit dependencies between parts

**If any checklist item fails, fix the plan BEFORE submitting to Design Review Gate.**

### Required Plan Sections

Every plan submitted for Design Review MUST include these sections:

1. **Work Unit Decomposition** — WU list with DoD items, file scopes, dependencies
2. **API Contract** (if applicable) — structured endpoint/protocol specs:
   ```markdown
   ### POST /api/todos
   - **Request Body**: `{ title: string }` (required, 1-500 chars, trimmed)
   - **Success**: `201 Created` -> `{ id, title, completed, createdAt, updatedAt }`
   - **Errors**: `400` (validation) / `500` (internal)
   ```
3. **Security Considerations** — trust boundaries, input validation table, rate limiting table, secrets management
4. **User Flows** (if UI exists) — text wireframes and interaction flows (use UI-FLOWS.md template)
5. **External Dependencies** — services, credentials, setup instructions
6. **Human Checkpoints** — named pause points with review criteria

---

## 2. Work Unit Decomposition

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

## 3. The 4-Phase Execution Loop

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

1. Spawn a coding subagent with the work unit spec, DoD items, file scope, and the **Project Context Document**
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

## Project Context
${projectContext}

## Rules
- Follow TDD: write failing test first, then implement to make it pass
- Do NOT modify files outside your file scope
- Do NOT self-certify — the orchestrator will validate independently
- When complete, report what you changed and what tests you added
- NEVER use --no-verify on git commits — pre-commit hooks are mandatory
- NEVER use git push --force
- NEVER suppress linter/type errors with eslint-disable, @ts-ignore, or as any
- NEVER skip tests or claim "tests pass" without actually running them
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

# 4. Coverage enforcement (BLOCKING — read .coverage-thresholds.json)
# If .coverage-thresholds.json exists, read the enforcement command and run it
# This is NOT optional. Coverage below threshold = VALIDATION FAIL.
if [ -f .coverage-thresholds.json ]; then
  CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
  eval "$CMD"
fi

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
- Update the **Project Context Document** with completed work unit details

**After commit, update SERVICE-INVENTORY.md:**
If this work unit created or modified services, factories, database tables, or shared modules, update `SERVICE-INVENTORY.md` with the new entries. This document is read by subsequent coder agents to avoid duplicating existing services.

---

## 4. Quality Gate Enforcement

Quality gates are BLOCKING STATE TRANSITIONS, not advisory recommendations. The orchestrator CANNOT advance to the next phase without gate passage.

### State Machine

```
IMPLEMENT ──→ VALIDATE ──→ REVIEW ──→ COMMIT
                 │            │
                 ↓            ↓
              FAIL:         FAIL:
           fix + re-run   fix + re-validate
                          + FRESH re-review
                 │            │
              (max 3)      (max 3)
                 │            │
                 ↓            ↓
              ESCALATE     ESCALATE
             (to human)   (to human)
```

### Transition Rules (MUST, not SHOULD)

1. **IMPLEMENT → VALIDATE**: Always. No exceptions.
2. **VALIDATE → REVIEW**: ONLY if ALL validation checks pass:
   - Tests pass (exit code 0)
   - Coverage meets `.coverage-thresholds.json` thresholds
   - Type checking passes
   - Lint passes
   - File scope respected
3. **REVIEW → COMMIT**: ONLY if adversarial review returns PASS
4. **FAIL → retry**: Fix the issue, then re-run the FAILED gate (not skip it)
5. **Re-review after fix**: MUST spawn a FRESH reviewer (new instance, no memory)
6. **Max retries**: 3 attempts per gate, then ESCALATE to human with full failure history

### On FAIL: Mandatory Re-Review Protocol

1. Fix the issue identified by the reviewer
2. Re-run Phase 2 (VALIDATE) — ALL quality gates, not just the one that failed
3. **MANDATORY**: Spawn a NEW adversarial reviewer (fresh instance, no memory of previous review)
4. Only COMMIT after the fresh reviewer returns PASS
5. Max 3 retry cycles before ESCALATE to human

Track each attempt visibly: "Re-review attempt 1/3", "Re-review attempt 2/3", etc.

### What the Orchestrator MUST NOT Do

- "Coverage is close enough at 92%, proceeding to commit"
- "Adversarial review found issues but they're minor, committing anyway"
- "Fix applied, skipping re-review since the fix is straightforward"
- "5 FAILs encountered, moving to next work unit without resolution"
- "Tests pass but coverage command failed — proceeding anyway"

### What the Orchestrator MUST Do

- "VALIDATION FAIL: coverage at 87%, threshold is 100%. Returning to IMPLEMENT."
- "ADVERSARIAL REVIEW FAIL. Spawning fresh reviewer for re-review. Attempt 2 of 3."
- "Max retries (3) exceeded for WU-004. Escalating to human with failure history."
- "Fix applied. Re-running validation. Re-running adversarial review with FRESH reviewer."

---

## 5. Parallel Work Unit Execution

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

**Stale notification handling:** When parallel subagent results arrive after the orchestrator has moved past their work unit (e.g., at a checkpoint), acknowledge them briefly in one line. Do NOT print a full "still waiting at checkpoint" block for each stale notification — this clutters the conversation and wastes context window.

---

## 6. Project Context Document

The orchestrator MUST maintain a project context document that grows with each work unit. This is passed to every coder subagent to prevent context loss.

### Context Document Structure

```markdown
# Project Context (Maintained by Orchestrator)

## Tooling
- Package manager: <npm/pnpm/yarn>
- Test runner: <vitest/jest> (<config-file>)
- Linter: <eslint> (<config-file>)
- Build: <vite/webpack/tsc> (<config-file>)

## Completed Work Units
| WU | Title | Key Files | Services Created |
|----|-------|-----------|-----------------|

## Established Patterns
- <pattern-1>: <description>
- <pattern-2>: <description>

## Active Services
See SERVICE-INVENTORY.md
```

**Update rules:**
- After each Phase 4 (COMMIT), add the completed work unit to the table
- After each Phase 1 (IMPLEMENT), update patterns if new ones emerge
- Pass this document to every coder subagent alongside the work unit spec

---

## 7. Human Checkpoints (Proactive)

Human checkpoints are **planned pauses**, not reactive escalations. They are defined in the spec before execution begins.

### When to Set Checkpoints

- After work units that change database schemas
- After work units that modify security-sensitive code
- After the first work unit in a new architectural pattern
- Before any destructive or irreversible operation
- At natural boundaries the human specified in the issue
- Before work units that depend on external services (APIs, SDKs requiring credentials)
  - Present: service name, required env vars, how to obtain credentials
  - Ask: "Do you have these configured? [Y/n]"

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

## 8. Final Comprehensive Review

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
if [ -f .coverage-thresholds.json ]; then
  CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
  eval "$CMD"
fi

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
- [ ] SERVICE-INVENTORY.md is up to date with all created services

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

## 8.5. Pre-PR Knowledge Capture (MANDATORY)

After the final comprehensive review passes but BEFORE creating the PR, run `/self-reflect` to extract learnings into the knowledge base. This captures implementation insights, debugging discoveries, and architectural decisions while context is freshest — not deferred to post-merge when details have faded.

```text
## Pre-PR Knowledge Capture

Final review PASSED. Before creating the PR, extracting learnings...

/self-reflect

Learnings captured: [N] items added to knowledge base.
Committing knowledge base updates...
Proceeding to PR creation.
```

**Why before PR, not after merge?** By the time a PR is merged, the implementing agent's context may be gone (session ended, context compacted). The richest insights — why a certain approach was chosen, what debugging dead-ends were hit, which patterns emerged — exist NOW, immediately after implementation. Capture them now.

**Knowledge base changes are part of the PR.** After self-reflect updates the knowledge base files, commit them alongside the implementation. This ensures learnings are reviewed as part of the PR and land atomically with the code that generated them. Do NOT defer knowledge base commits to a separate PR or post-merge step.

---

## 9. Recovery Protocol

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

## 10. Anti-Patterns

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
| 9 | **Skipping coverage enforcement** — "tests pass, coverage doesn't matter" | Coverage thresholds exist for a reason; low coverage means untested paths | Read .coverage-thresholds.json and run the enforcement command. Block on failure. |
| 10 | **Building UI components in isolation** — all components tested but never wired into the app | Users can't interact with components that aren't rendered | Plan must include integration WUs that wire components into the app shell |
| 11 | **Proceeding without external credentials** — building features that require API keys without verifying the user has them | Features will fail at runtime; user discovers this after 10+ commits | Checkpoint before external-service WUs to verify credentials are configured |
| 12 | **Advisory quality gates** — treating FAIL as a suggestion rather than a blocking transition | Undermines the entire trust model; equivalent to skipping the gate | Quality gates are state transitions. FAIL means retry or escalate, never skip. |
| 13 | **Using `--no-verify`** — bypassing pre-commit hooks on git commits | Pre-commit hooks catch lint errors, type errors, and formatting issues before they enter history | Never use `--no-verify`. Fix the underlying issue instead. |
| 14 | **Skipping design review gate after brainstorming** — going directly from brainstorming to writing-plans | Expensive implementation work begins on unreviewed designs | Always run the 5-agent design review gate between brainstorming and planning |
| 15 | **Skipping plan review gate** — presenting a plan to the user without adversarial review | Plans with feasibility gaps, missing requirements, or scope creep reach implementation | Always run the 3-reviewer plan review gate before presenting any plan |

---

## Quick Reference: Orchestrator Checklist

Before execution (Plan Validation):

- [ ] Run pre-flight checklist (architecture, dependencies, API contracts, security, UI/UX, external deps)
- [ ] Verify all required plan sections are present
- [ ] Fix any checklist failures BEFORE submitting to Design Review Gate

For each work unit:

- [ ] Spawn coding subagent with spec, DoD, file scope, and **Project Context Document**
- [ ] Wait for implementation to complete
- [ ] **Independently** run: tsc, eslint, vitest, coverage enforcement (do NOT ask subagent)
- [ ] Verify file scope with `git diff --name-only`
- [ ] Spawn **fresh** adversarial reviewer with spec and DoD
- [ ] If PASS: commit with DoD verification in message
- [ ] If FAIL: fix → re-validate → spawn **new** reviewer (max 3 retries, then ESCALATE)
- [ ] If human checkpoint: present report and wait
- [ ] Update BEADS task status
- [ ] Update **SERVICE-INVENTORY.md** if services/factories/modules were created
- [ ] Update **Project Context Document** with completed work unit

Quality Gate Rules:

- [ ] VALIDATE → REVIEW: ONLY if ALL checks pass (tests, coverage, types, lint, file scope)
- [ ] REVIEW → COMMIT: ONLY if adversarial review returns PASS
- [ ] FAIL at any gate: retry (max 3), then ESCALATE — never skip
- [ ] Re-review after fix: MUST use FRESH reviewer (new instance, no memory)

After all work units:

- [ ] Run final comprehensive review (with coverage enforcement)
- [ ] Verify SERVICE-INVENTORY.md is complete
- [ ] Present final report
- [ ] Run `/self-reflect` to capture learnings (BEFORE PR creation)
- [ ] Commit knowledge base updates (included in the PR)
- [ ] Proceed to PR creation
