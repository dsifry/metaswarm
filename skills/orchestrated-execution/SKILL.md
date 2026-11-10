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

- **Phase 1 (IMPLEMENT)**: In Team Mode, the coding subagent may be a persistent teammate (retains context across work units). In Task Mode, it's a fresh `Task()` per work unit. Role type: `roleType("coder")`.
- **Phase 3 (ADVERSARIAL REVIEW)**: ALWAYS a fresh `Task()` instance (`roleType("adversarial-reviewer")`) in BOTH modes. Never a teammate, never resumed.
- **All quality gates**: Unchanged regardless of mode.

See `./guides/agent-coordination.md` for full mode detection and coordination details.

---

## Plan Review Gate

After drafting an implementation plan (Step 1: Plan Validation), submit it to the **Plan Review Gate** before writing-plans presents the plan (or before you present it to the user); see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md). In full orchestration there is no separate design doc, so after the Plan Review Gate passes the plan goes to the Design Review Gate ([two pipelines](./guides/workflow-enforcement.md#two-pipelines)). The Plan Review Gate spawns 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) — all must PASS. See `skills/plan-review-gate/SKILL.md` for details.

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

> **Note**: the Architect is spawned as `roleType("planner")`, which can write `PLAN.md` itself (it is not read-only, unlike the reviewer types). Role types are resolved per [Role type resolution](./guides/agent-coordination.md#role-type-resolution).

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

```text
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

```text
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
│ FAIL: fix → re-validate → FRESH review → severity rule (cap 10) │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 1: IMPLEMENT

The coding subagent executes against the work unit spec.

**Orchestrator actions:**

1. Spawn a coding subagent (role type `roleType("coder")`) with the work unit spec, DoD items, file scope, and the **Project Context Document**
2. The subagent implements the change following TDD (test first, then implementation)
3. The subagent reports completion — **but the orchestrator does NOT trust this report**

**Subagent spawn template** (role type `roleType("coder")`):

```text
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

1. Spawn a **new** review subagent in adversarial mode (role type `roleType("adversarial-reviewer")`)
2. Pass: the spec, the DoD items, and the diff (NOT the coding subagent's self-assessment)
3. The reviewer checks each DoD item with evidence (file:line references)

**Reviewer spawn template** (role type `roleType("adversarial-reviewer")`):

```text
You are the ADVERSARIAL REVIEWER for work unit ${wuId}.

## Mode
Adversarial — your job is to FIND FAILURES, not to approve.

## Rubric
Read and follow: ./rubrics/adversarial-review-rubric.md

## Spec
${spec}

## Definition of Done
${dodItems.map((item, i) => `${i+1}. ${item}`).join('\n')}

## What to Review
Run: git diff main..HEAD -- ${fileScope.join(' ')}

## Findings
Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
- theme: <short label>       # on every finding; reuse an earlier theme label when one fits
- needs_user: yes | no       # blockers only: yes only if just the user can answer it
- origin: implementation | requirement | assumption   # blockers only
- assumption: <ledger id such as A3, or a quoted decision>   # required when origin is assumption

## Earlier Theme Labels
${themeLabels}
(Round 1: none. From round 2 on these are the canonical theme labels from earlier rounds, labels only. Reuse one in `theme` when it fits; otherwise use a new short label.)

## Rules
- Check EACH DoD item. Cite file:line evidence for PASS or expected-vs-found for FAIL.
- Any `blocker: yes` finding means overall FAIL. A critical or major finding without `protects` is advisory (`blocker: no`).
- You have NO context from previous reviews. Judge fresh.
- Report every finding with the 6 fields; minor/nit findings are recorded as follow-ups, not suggestions.
- Do not mark `needs_user` when the design's Confirmed section already answers the question. Add `theme` to every finding and the other signal fields to each blocker.
```

**Phase 3 outcomes:**

- **PASS** (no `blocker: yes` finding) → proceed to Phase 4; file any minor/nit findings as follow-ups
- **FAIL** (at least one `blocker: yes` finding) → apply the severity rule in [On FAIL](#on-fail-mandatory-re-review-protocol): iterate (return to Phase 1 with the failure report), clarify (stop and ask the user) or escalate

**Fresh reviewer rule:** On re-review after FAIL, the orchestrator MUST spawn a **new** review subagent (role type `roleType("adversarial-reviewer")`). Never pass previous findings to the new reviewer. Never reuse the same reviewer instance. This prevents anchoring bias and ensures independent verification.

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

```text
IMPLEMENT ──→ VALIDATE ──→ REVIEW ──→ COMMIT
                 │            │
                 ↓            ↓
              FAIL:         FAIL: severity rule (cap 10):
           fix + re-run   fix + re-validate
                          + FRESH re-review
                 │            │
        (max 3 VALIDATE)      │
                 │            │
                 ↓            ↓
              ESCALATE     ESCALATE when the rule says so
             (to human)   (to human, with a recommendation)
```

### Transition Rules (MUST, not SHOULD)

1. **IMPLEMENT → VALIDATE**: Always. No exceptions.
2. **VALIDATE → REVIEW**: ONLY if ALL validation checks pass:
   - Tests pass (exit code 0)
   - Coverage meets `.coverage-thresholds.json` thresholds
   - Type checking passes
   - Lint passes
   - File scope respected
3. **REVIEW → COMMIT**: ONLY if adversarial review returns PASS, or rule line 5 downgraded every remaining blocker to a follow-up
4. **FAIL → retry**: Fix the issue, then re-run the FAILED gate (not skip it)
5. **Re-review after fix**: MUST spawn a FRESH reviewer (new `roleType("adversarial-reviewer")` instance, no memory)
6. **Max retries**: VALIDATE gets 3 attempts, then ESCALATE to human with full failure history (see [Recovery Protocol](#9-recovery-protocol)). VALIDATE attempts count consecutive failed VALIDATE runs for the work unit; a VALIDATE PASS resets the count to 0, so each review round's re-validation starts fresh. The number of review rounds is governed separately by the severity rule and its 10-round cap. Three consecutive failures escalate. REVIEW follows the severity rule (see On FAIL below; cap 10 rounds).

### On FAIL: Mandatory Re-Review Protocol

A review FAIL (at least one `blocker: yes` finding) is not retried on a fixed count. After each review round the orchestrator applies the severity rule from [`./guides/delivery-scope.md`](./guides/delivery-scope.md): `SAFETY_CAP` = 10 rounds per work unit, and the first line that matches wins. "Re-validate" means running Phase 2 (VALIDATE) again.

```text
after each review round (round = 1, 2, ...):
  file every minor/nit finding as a follow-up (see Follow-ups)
  1. no blocker: yes findings            → PASS, advance
  2. a Clarify signal (C1–C4) fires      → stop: misunderstanding analysis, Clarification report, wait for the user
  3. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal
  4. the same critical/major finding recurs after a fix attempt for it,
     or two reviewers rate the same finding blocker vs. non-blocker   → escalate
  5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;
                                           any still names a credible scenario → escalate with a recommendation;
                                           otherwise downgrade them to follow-ups and advance
  6. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers
                                         → fix blockers, re-validate, FRESH review
  7. otherwise                           → fix blockers, re-validate, FRESH review
```

- **Single reviewer.** Phase 3 has one reviewer per work unit, so "≥2 independent reviewers" is false. Reviewers of other work units running in parallel don't count.
- **Overengineering check (line 5).** Signals include repeated review/fix cycles without a new user-visible risk, tests for states the real storage or API cannot produce, and validation growing faster than the feature. Restate the work unit's DoD, re-classify each open blocker, and escalate only if one still names a credible scenario; otherwise downgrade them to follow-ups and commit.
- **Malformed output.** A FAIL whose findings lack the 6 fields is re-requested once in the contract format, then escalated with the raw output. It is never treated as PASS. A blocker that lacks `needs_user` or `origin` gets one re-request too; if they are still missing they are treated as unknown, which triggers nothing.
- **Follow-ups.** Minor/nit findings never block. When `bd` is available, file each as a BEADS task (`bd create --type task`) linked to the work unit. Otherwise, or if `bd create` fails, list them under a `### Follow-ups` heading in the work unit's report; the PR body carries them (see 8.5).
- **Clarify (line 2).** A Clarify signal (C1–C4, see [Clarify signals](./guides/delivery-scope.md#clarify-signals)) is a stop, not an escalation. Run the misunderstanding analysis and send the Clarification report from the [Clarify section](./guides/delivery-scope.md#clarify) of the guide, then wait for the user. Mark the BEADS task for this work waiting on the user (`bd update <task-id> --status blocked` and `bd label add <task-id> waiting:human`), and set `status: clarify-pending` with `pendingClarify` in the history file. Line 2 never uses the escalation report; the Clarification report's options are in the guide and none of them approves.
- **Round history.** Keep the round history and write it after every round to `.beads/context/review-history/orchestrated-execution-<slug>-<occurrence>.json` (the format, the `status` lifecycle and `pendingClarify` are in the guide's Round history section). `<occurrence>` is the next free integer for that gate and slug, starting at 1. For this gate the slug is `<plan-slug>-<wu-id>`, so the file is `orchestrated-execution-<plan-slug>-<wu-id>-<occurrence>.json`. `<plan-slug>` is the issue number or a short slug of the title in the `# Plan:` heading of `.beads/plans/active-plan.md` (for example `103`), so different issues do not collide. Store the artifact path (here `.beads/plans/active-plan.md#<wu-id>`) in the file, set `reviewers` to 1, and use stable role names as reviewer labels.
- **After each round, before the rule.** First set `fix_induced` on each new blocker that matches the `lastFix` stored before this round's review (the changes made since the previous review). Then map each blocker's `theme` to a `canonicalTheme`, and merge duplicate blockers (the same canonical theme and the same defect) by setting `mergedInto` on each duplicate. Run the rule. When you then fix the blockers, overwrite `lastFix` with that fix before the next review.
- **Themes.** From round 2 on, give each fresh reviewer the earlier canonical theme labels (labels only, never the findings) and ask it to reuse one when it fits.
- **Helper.** Set `HISTORY` to the review-history file path, then run the rule with `RR=lib/review-rule.js; { [ -f ./lib/review-rule.js ] && grep -q '"name": *"metaswarm"' package.json 2>/dev/null; } || { RR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v metaswarm-agents.sh 2>/dev/null)")")}/lib/review-rule.js"; [ -f "$RR" ] || RR=lib/review-rule.js; }; node "$RR" "$HISTORY"` (HISTORY is the path of the review-history file, for example `HISTORY=.beads/context/review-history/<file>.json`). It prints `{line, action, signals, capHit}`. Recurring or disputed (line 4) and overengineering (line 5) need your judgement, so set the round's `recurring`, `disputed` and `overengineering` flags first. If the path does not resolve or Node is unavailable, apply the rule by hand. On exit 2, fix the history file and run it again.

When the rule says iterate:

1. Fix every `blocker: yes` finding identified by the reviewer
2. Re-run Phase 2 (VALIDATE) — ALL quality gates, not just the one that failed
3. **MANDATORY**: Spawn a NEW adversarial reviewer (role type `roleType("adversarial-reviewer")`, fresh instance, no memory of previous review)
4. Only COMMIT after the fresh reviewer returns PASS, or rule line 5 downgraded every remaining blocker to a follow-up
5. Apply the severity rule after every round; stop and Clarify when it says clarify, and ESCALATE to human when it says escalate (at most 10 rounds)
6. **Coder model escalation**: after `escalation.coder.after_failures` failed VALIDATE attempts (default 2, read from `.metaswarm/models.yaml`), re-spawn the coder with `roleType("coder")` plus a per-call `model` set to `escalation.coder.claude` (default `opus`). The per-call `model` overrides the agent-file default (the `coder` role's `sonnet`).

Track each round visibly: "Review round 1/10", "Review round 2/10", etc.

When the rule says clarify (line 2), use the Clarification report from the [Clarify section](./guides/delivery-scope.md#clarify) of the guide, not this one. When it says escalate (lines 3, 4 or 5), report:

```markdown
## Review Escalation: Phase 3 ADVERSARIAL REVIEW — WU-<id>

**Rule line**: <3 cap hit | 4 recurring/disputed | 5 overengineering signal>

### Remaining findings
- **Critical**: <title>: <description> — protects: <...> — evidence: <...>
- **Major**: <title>: <description> — protects: <...> — evidence: <...>
- **Minor**: <title> (follow-up filed)
- **Nit**: <title> (follow-up filed)

### Round history
| Round | Verdict | Blockers (critical/major) | Fixed this round | Signals (C1–C4) | Themes | Rule decision |
|-------|---------|---------------------------|------------------|-----------------|--------|---------------|
| 1     | FAIL    | 0 / 2                     | —                | —               | <theme-a> | 7: iterate    |
| 2     | FAIL    | 0 / 1                     | 0 / 2            | —               | <theme-b> | 6: iterate    |
| 3     | FAIL    | 0 / 1                     | 0 / 0            | —               | <theme-a>, <theme-c> | 4: escalate (recurring) |

### Options
1. **Revise** — fix the remaining blockers (or the requirement they protect), then run a fresh review round
2. **Narrow scope** — move the contentious items to a new issue, then run a fresh review round on what remains
3. **Defer** — shelve this work for later; nothing advances
4. **Cancel** — abandon this work
5. **Clarify the requirement / re-brainstorm** — answer the open questions about the requirement; a new gate occurrence starts

**Recommendation**: <revise|clarify|narrow scope|defer|cancel> — <reason from the rule>
```

### What the Orchestrator MUST NOT Do

- "Coverage is close enough at 92%, proceeding to commit"
- "Adversarial review FAILed, committing with an unresolved `blocker: yes` finding anyway"
- "Fix applied, skipping re-review since the fix is straightforward"
- "5 FAILs encountered, moving to next work unit without resolution"
- "Tests pass but coverage command failed — proceeding anyway"

### What the Orchestrator MUST Do

- "VALIDATION FAIL: coverage at 87%, threshold is 100%. Returning to IMPLEMENT."
- "ADVERSARIAL REVIEW FAIL: 2 `blocker: yes` findings. Severity rule line 7: fixing, re-validating, spawning fresh reviewer. Review round 2/10."
- "Severity rule line 4: the same major finding recurred after a fix attempt for WU-004. Escalating to human with round history and a recommendation."
- "Severity rule line 2: a blocker needs the user's answer (C1). Stopping: running the misunderstanding analysis, sending the Clarification report, marking WU-004 waiting on the user."
- "Review PASS: no `blocker: yes` findings. 1 minor finding filed as a follow-up. Committing."
- "Fix applied. Re-running validation. Re-running adversarial review with FRESH reviewer."

---

## 5. Parallel Work Unit Execution

When multiple work units have no dependencies on each other, execute them in parallel — but with structured convergence points.

```text
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

1. **Fan-out implementations**: Spawn coding subagents (role type `roleType("coder")`) for independent work units simultaneously
2. **Converge for validation**: Wait for ALL parallel implementations to complete, then validate each
3. **Fan-out reviews**: Spawn review subagents (role type `roleType("adversarial-reviewer")`) for each work unit simultaneously
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

### Persisting to Disk (MANDATORY)

The Project Context Document MUST be written to `.beads/context/project-context.md` and kept in sync with the in-memory version. This ensures the context survives context compaction and session boundaries.

```bash
# Create directory if needed
mkdir -p .beads/context

# Write/update after each Phase 4 (COMMIT) and at orchestration start
# The file should always reflect the current state of execution
```

**When to write:**
- At orchestration start (initial creation)
- After each Phase 4 (COMMIT) — add the completed work unit
- After each Phase 1 (IMPLEMENT) — update patterns if new ones emerge
- At human checkpoints — snapshot current state

**The file is NOT committed to git** during execution — it's a working document. It gets cleaned up after the PR is created (or left for the next session if interrupted).

---

## 6.5. Plan Persistence (Context Recovery)

Approved plans and execution state are persisted to `.beads/` so agents can recover after context compaction or session interruption.

### What Gets Persisted

| File | Contents | Written When |
|------|----------|-------------|
| `.beads/plans/active-plan.md` | The adversarially-reviewed, user-approved implementation plan | After plan review gate PASS + user approval |
| `.beads/context/project-context.md` | Project Context Document (tooling, completed WUs, patterns) | After each Phase 4 COMMIT |
| `.beads/context/execution-state.md` | Current work unit, phase, VALIDATE attempts, review round | After each phase transition |
| `.beads/context/review-history/orchestrated-execution-<plan-slug>-<wu-id>-<occurrence>.json` | Review round history for the work unit's Phase 3 (format in `./guides/delivery-scope.md`) | After every review round |

### Writing the Approved Plan

After the Plan Review Gate approves a plan AND the user approves it, persist immediately:

```bash
mkdir -p .beads/plans

# Write the approved plan with metadata header
cat > .beads/plans/active-plan.md << 'PLAN_EOF'
# Active Plan
<!-- approved: <timestamp> -->
<!-- gate-iterations: <N> -->
<!-- user-approved: true -->
<!-- status: in-progress -->

<full plan text including work unit decomposition, DoD items, file scopes, dependencies>
PLAN_EOF
```

### Writing Execution State

After each phase transition, update the execution state:

```bash
cat > .beads/context/execution-state.md << 'STATE_EOF'
# Execution State
<!-- updated: <timestamp> -->

## Current Position
- Active work unit: <wu-id>
- Current phase: <IMPLEMENT|VALIDATE|REVIEW|COMMIT>
- VALIDATE attempts: <0-3> (consecutive failed VALIDATE runs; resets to 0 on PASS)
- Review round: <1-10>
- Review history: <.beads/context/review-history/orchestrated-execution-<plan-slug>-<wu-id>-<occurrence>.json, or none>

## Work Unit Status
| WU | Status | Phase | VALIDATE attempts (0-3) | Review rounds (0-10) |
|----|--------|-------|-------------------------|----------------------|
| WU-001 | COMPLETE | COMMITTED | 0 | 1 |
| WU-002 | IN-PROGRESS | VALIDATE | 1 | 0 |
| WU-003 | PENDING | — | 0 | 0 |

## Open Findings (orchestrator only, never passed to reviewers)
| Finding | Title | Description | Evidence | Severity | Protects | First round | Fix attempts | Status |
|---------|-------|-------------|----------|----------|----------|-------------|--------------|--------|
| WU-002-F1 | Expired token not rejected | <finding description> | <expected vs. found> | major | <scenario/requirement> | 1 | 1 | open |

## Blocked / Escalated
<any blocked or escalated work units with context>
STATE_EOF
```

### Context Recovery Protocol

When the orchestrator detects it has lost context (after compaction or in a new session), it recovers by reading persisted state:

```text
1. Check: Does `.beads/plans/active-plan.md` exist with `status: in-progress`?
   - YES → Context was lost mid-execution. Recover.
   - NO → No active execution. Start fresh.

2. Recovery steps:
   a. Read `.beads/plans/active-plan.md` — reload the approved plan
   b. Read `.beads/context/project-context.md` — reload completed work and patterns
   c. Read `.beads/context/execution-state.md` — find where execution stopped, and reload its Open Findings table (title, description, evidence, severity, protects, fix attempts) so rule line 4 can still detect a recurring blocker — match each fresh finding by its title/description and protects, and use evidence only as a secondary signal, because a fix can move file:line references. A saved finding without a title (written before this change) falls back to description plus protects; this history is for the orchestrator only — never pass them to a fresh reviewer. A state file written before the column split has a single legacy `Retries` column: read that value as VALIDATE attempts, and take the review round from the Current Position `Review round` line
   d. Read the review history file named by the `Review history` line (the non-closed `.beads/context/review-history/orchestrated-execution-<plan-slug>-<wu-id>-*.json`; if several are non-closed, use the newest and set the rest to `closed`). If its `status` is `clarify-pending`, re-ask the `pendingClarify` questions with the Clarification report and do not iterate. Otherwise continue at the next round. See the Round history section of `./guides/delivery-scope.md`.
   e. Run `/prime` (metaswarm knowledge priming) for the current work unit — reload relevant knowledge base facts.
      The full recovery order is: if bd is installed, `bd prime` (bd context); then read `.beads/plans/active-plan.md` and `.beads/context/*.md`; then `/prime` for knowledge.
   f. Resume from the current work unit and phase

3. Announce recovery to user:
   "Recovered execution context from BEADS. Resuming from WU-<id>, Phase <phase>."
```

**When to trigger recovery:** The orchestrator should check for `.beads/plans/active-plan.md` at the start of any orchestrated execution. If the file exists with `status: in-progress` and the orchestrator has no plan in its current context, it's a recovery scenario.

### Cleanup

After the PR is created (or the plan is abandoned):

```bash
# Mark plan as completed (cross-platform sed)
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/status: in-progress/status: completed/' .beads/plans/active-plan.md
else
  sed -i 's/status: in-progress/status: completed/' .beads/plans/active-plan.md
fi

# Archive execution state (don't delete — useful for post-mortem)
mv .beads/context/execution-state.md .beads/context/execution-state-<timestamp>.md

# Project context can be kept for reference
```

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

Record significant decisions persistently with `bd create "<decision>" --type decision -d "<rationale>"` so they survive compaction and are available across sessions.

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

### Follow-ups
<minor/nit findings from every gate and work unit: BEADS task IDs, or the items themselves>

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

**Follow-ups go in the PR body.** Collect every follow-up recorded by the gates and work units (BEADS task IDs, or the `### Follow-ups` lists kept when `bd` was unavailable) and include them in the PR body under a `### Follow-ups` heading, so non-blocking findings are not lost.

**Knowledge base changes are part of the PR.** After self-reflect updates the knowledge base files, commit them alongside the implementation. This ensures learnings are reviewed as part of the PR and land atomically with the code that generated them. Do NOT defer knowledge base commits to a separate PR or post-merge step.

---

## 9. Recovery Protocol

When IMPLEMENT or VALIDATE goes wrong during the 4-phase loop, follow this structured recovery. Its 3-attempt cap applies to VALIDATE failures (tests, coverage, lint, typecheck, file scope). REVIEW failures don't use it: they follow the severity rule in [On FAIL](#on-fail-mandatory-re-review-protocol) (cap 10 rounds).

### Step 1: DIAGNOSE

Identify what failed and gather evidence:

```bash
# Capture the failure
# - Which phase failed? (IMPLEMENT or VALIDATE; a REVIEW failure follows the severity rule in On FAIL instead)
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

### Step 3: RETRY (VALIDATE: up to 3 attempts)

VALIDATE attempts count consecutive failed VALIDATE runs for the work unit; a VALIDATE PASS resets the count to 0, so each review round's re-validation starts fresh. The number of review rounds is governed separately by the severity rule and its 10-round cap.

For fixable and ambiguous VALIDATE failures:

1. **Attempt 1**: Fix the specific issue, re-run from Phase 1
2. **Attempt 2**: If same failure, try alternative approach
3. **Attempt 3**: If still failing, gather all evidence for escalation

**Model escalation (coder).** Retrying alone never changes the model. After `escalation.coder.after_failures` failed VALIDATE attempts (default 2, from `.metaswarm/models.yaml`), re-spawn the coder with `roleType("coder")` plus a per-call `model` set to `escalation.coder.claude` (default `opus`). The per-call `model` overrides the agent-file default, so the escalated attempt runs on `opus` while earlier attempts ran on the coder's configured model.

Track VALIDATE attempts with labels, and remove the `retry:N` label when VALIDATE passes (review rounds are tracked in `.beads/context/execution-state.md`, not labels):

```bash
bd label add <task-id> retry:1  # or retry:2, retry:3
```

### Step 4: ESCALATE

After 3 failed VALIDATE attempts, escalate to human with full context:

```markdown
## Escalation: Work Unit <wu-id> Failed VALIDATE After 3 Attempts

### Failure History
| Attempt | Phase | Error | Fix Tried |
| --- | --- | --- | --- |
| 1 | VALIDATE | Tests fail: auth.test.ts:34 | Fixed mock setup |
| 2 | VALIDATE | Coverage 94%, threshold 100% | Added edge case test |
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
| 12 | **Advisory quality gates** — treating a `blocker: yes` FAIL as advisory, or a failed VALIDATE check as a suggestion | Undermines the entire trust model; equivalent to skipping the gate | Quality gates are state transitions. FAIL means retry, iterate under the severity rule, or escalate, never skip. |
| 13 | **Using `--no-verify`** — bypassing pre-commit hooks on git commits | Pre-commit hooks catch lint errors, type errors, and formatting issues before they enter history | Never use `--no-verify`. Fix the underlying issue instead. |
| 14 | **Skipping design review gate for a project-sized design doc** — going directly from a committed design doc to writing-plans | Expensive implementation work begins on unreviewed designs | Run the 6-agent design review gate between a committed project-sized design doc and planning (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)) |
| 15 | **Skipping plan review gate** — presenting a plan to the user without adversarial review | Plans with feasibility gaps, missing requirements, or scope creep reach implementation | Always run the 3-reviewer plan review gate before presenting any plan |

---

## Quick Reference: Orchestrator Checklist

Before execution (Plan Validation):

- [ ] Run pre-flight checklist (architecture, dependencies, API contracts, security, UI/UX, external deps)
- [ ] Verify all required plan sections are present
- [ ] Fix any checklist failures BEFORE submitting to Design Review Gate

For each work unit:

- [ ] Spawn coding subagent (role type `roleType("coder")`) with spec, DoD, file scope, and **Project Context Document**
- [ ] Wait for implementation to complete
- [ ] **Independently** run: tsc, eslint, vitest, coverage enforcement (do NOT ask subagent)
- [ ] Verify file scope with `git diff --name-only`
- [ ] Spawn **fresh** adversarial reviewer (role type `roleType("adversarial-reviewer")`) with spec and DoD
- [ ] If PASS: commit with DoD verification in message
- [ ] If FAIL: apply the severity rule → fix → re-validate → spawn **new** reviewer (`roleType("adversarial-reviewer")`; escalate when the rule says so, at most 10 rounds)
- [ ] File minor/nit findings as follow-ups (BEADS, else `### Follow-ups`)
- [ ] If human checkpoint: present report and wait
- [ ] Update BEADS task status
- [ ] Update **SERVICE-INVENTORY.md** if services/factories/modules were created
- [ ] Update **Project Context Document** with completed work unit

Quality Gate Rules:

- [ ] VALIDATE → REVIEW: ONLY if ALL checks pass (tests, coverage, types, lint, file scope)
- [ ] REVIEW → COMMIT: ONLY if adversarial review returns PASS, or rule line 5 downgraded every remaining blocker to a follow-up
- [ ] FAIL at VALIDATE: retry (max 3 VALIDATE attempts), then ESCALATE; FAIL at REVIEW: severity rule (cap 10) — never skip
- [ ] Re-review after fix: MUST use FRESH reviewer (new instance, no memory)

After all work units:

- [ ] Run final comprehensive review (with coverage enforcement)
- [ ] Verify SERVICE-INVENTORY.md is complete
- [ ] Present final report
- [ ] Run `/self-reflect` to capture learnings (BEFORE PR creation)
- [ ] Commit knowledge base updates (included in the PR)
- [ ] Proceed to PR creation
