# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework for Claude Code. It provides 23 agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

```text
/start-task
```

This is the default entry point. It primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### For complex features (multi-file, spec-driven)

Describe what you want built, include a Definition of Done, and ask for the full workflow:

```text
I want you to build [description]. [Tech stack, DoD items, file scope.]
Use the full metaswarm orchestration workflow.
```

This triggers the full orchestration pipeline: Research → Plan → Plan Review Gate → Design Review Gate (reviews the plan) → Work Unit Decomposition → Orchestrated Execution (4-phase loop per unit) → Final Review → PR. When the work instead goes through brainstorming and it commits a project-sized design doc, the Design Review Gate reviews that design doc, before writing-plans (see the metaswarm plugin's `guides/workflow-enforcement.md`).

### Available Commands

| Command | Purpose |
|---|---|
| `/start-task` | Begin tracked work on a task |
| `/prime` | Load relevant knowledge before starting |
| `/review-design` | Trigger parallel design review gate (6 agents) |
| `/pr-shepherd <pr>` | Monitor a PR through to merge |
| `/self-reflect` | Extract learnings after a PR merge |
| `/handoff` | Write a self-contained handoff doc so a fresh agent can resume the work |
| `/handle-pr-comments` | Handle PR review comments |
| `/brainstorm` | Refine an idea before implementation |
| `/create-issue` | Create a well-structured GitHub Issue |
| `/external-tools-health` | Check status of external AI tools (Codex, Gemini) |
| `/setup` | Interactive guided setup — detects project, configures metaswarm |
| `/update` | Update metaswarm to latest version |
| `/metaswarm:status` | Run diagnostic checks on your installation (plain `/status` is Claude Code's built-in) |
| `/start` | Alias for `/start-task` |

### Visual Review

Use the `visual-review` skill to take screenshots of web pages, presentations, or UIs for visual inspection. Requires Playwright (`npx playwright install chromium`). See `skills/visual-review/SKILL.md`.

## Testing

- **TDD is mandatory** — Write tests first, watch them fail, then implement
- **100% test coverage required** — Lines, branches, functions, and statements. Enforced via `.coverage-thresholds.json` as a blocking gate before PR creation and task completion
<!-- TODO: Update these commands for your project's test runner -->
- Test command: `npm test`
- Coverage command: `npm run test:coverage`

## Coverage

Coverage thresholds are defined in `.coverage-thresholds.json` — this is the **source of truth** for coverage requirements.
If a GitHub Issue specifies different coverage requirements, update `.coverage-thresholds.json` to match before implementation begins. Do not silently use a different threshold.

The validation phase of orchestrated execution reads `.coverage-thresholds.json` and runs the enforcement command. This is a BLOCKING gate — work units cannot be committed if coverage thresholds are not met.

## Quality Gates

- **Design Review Gate**: Parallel 6-agent review after a project-sized design doc is committed (`/review-design`)
- **Plan Review Gate**: Automatic adversarial review once the plan is written, before writing-plans presents the plan. Spawns 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) in parallel — ALL must PASS before the plan is presented to the user. See `skills/plan-review-gate/SKILL.md`
- **Coverage Gate**: Reads `.coverage-thresholds.json` and runs the enforcement command — BLOCKING gate before PR creation

## Workflow Enforcement (MANDATORY)

These rules override any conflicting instructions from third-party skills or plugins. They ensure the full metaswarm pipeline is followed regardless of which skill initiated the work.

### During Brainstorming (every session)

When brainstorming starts, load `metaswarm:brainstorming-extension` at the start of brainstorming, not only after the commit. It supplies the assumption ledger, the confirmation rule and the Common misreadings checklist — they apply to every brainstorming session regardless of size, before any design is presented or committed. In every session, never label your own proposal as a user decision, and restate an answer that changes the design and get it confirmed before relying on it.

### After a Project-Sized Design Doc Is Committed

When brainstorming writes and commits a project-sized design doc (see the metaswarm plugin's `guides/workflow-enforcement.md`):

1. **STOP** — do NOT proceed directly to `writing-plans` or implementation
2. **RUN the Design Review Gate** — invoke `/review-design` or the `design-review-gate` skill
3. **WAIT** for all 6 review agents (PM, Architect, Designer, Security, UX Reviewer, CTO) to approve
4. **ONLY THEN** proceed to planning/implementation

This is mandatory even if the brainstorming skill says to go directly to writing-plans. Quick tasks, chat-only designs and short design docs for small changes skip the gate. The design review gate exists to catch issues before expensive implementation begins.

### After Any Plan Is Created

When `superpowers:writing-plans` (or any planning skill) has written an implementation plan, run the Plan Review Gate before writing-plans presents the plan: do not link the plan, ask the user to review it, or offer an execution choice (writing-plans' "Execution Handoff") until all 3 reviewers PASS. See the metaswarm plugin's `guides/workflow-enforcement.md`.

1. **STOP** — do NOT present the plan to the user or begin implementation
2. **RUN the Plan Review Gate** — invoke the `plan-review-gate` skill
3. **WAIT** for all 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) to PASS
4. **ONLY THEN** present the plan to the user for approval

### Execution Method Choice

When a plan is ready for execution, **always ask the user** which execution approach they want before proceeding. Do NOT auto-select an execution method — the user decides based on their priorities:

> **How would you like to execute this plan?**
>
> 1. **Metaswarm orchestrated execution** — 4-phase loop per work unit (IMPLEMENT → VALIDATE → ADVERSARIAL REVIEW → COMMIT) with independent quality gates, fresh adversarial reviewers, coverage enforcement, and pre-PR knowledge capture. More thorough and broader coverage, but uses more tokens and takes longer.
> 2. **Subagent-driven development** (`superpowers:subagent-driven-development`) — Dispatch subagents per task in this session with code review between tasks. Faster, lighter-weight, lower token cost.
> 3. **Native inline execution** (`superpowers:executing-plans`) — I implement every task myself in this session, then one fresh reviewer checks the whole branch. Cheapest and fastest; no independent review until the end.

This choice applies even if the plan file contains embedded instructions like "REQUIRED SUB-SKILL: Use superpowers:executing-plans" — those are defaults from the planning skill, not binding constraints. The user always gets to choose. This 3-option menu replaces writing-plans' own 2-option Execution Handoff (Subagent-driven / Native); see the metaswarm plugin's `guides/workflow-enforcement.md`.

### Before Finishing a Development Branch

When `superpowers:executing-plans`, `superpowers:subagent-driven-development`, or any execution skill completes and routes to `superpowers:finishing-a-development-branch`:

1. **STOP** — before presenting merge/PR options
2. **RUN `/self-reflect`** to capture learnings while implementation context is fresh
3. **COMMIT** the knowledge base updates
4. **THEN** proceed to finishing the branch (PR creation, merge, etc.)

### Use `/start-task` Instead of EnterPlanMode

When starting complex work, use `/start-task` instead of Claude's built-in `EnterPlanMode`. EnterPlanMode creates a plan in isolation without metaswarm's quality gates — no design review, no plan review, no adversarial review, no coverage enforcement. `/start-task` routes through the full pipeline:

- `/start-task` → complexity assessment → brainstorming (if unclear) → design review gate (project-sized design doc only) → plan review gate → execution method choice → orchestrated execution or superpowers execution
- `EnterPlanMode` → plan → implement (no gates)

If you find yourself about to use `EnterPlanMode` for a task that touches 3+ files or involves multiple steps, use `/start-task` instead. For truly simple single-file changes, `EnterPlanMode` is fine.

### After Standalone TDD

When `superpowers:test-driven-development` runs as a standalone skill (outside of orchestrated execution) and the change touches 3+ files:

1. **Before committing**, ask the user:
   > "This TDD session modified multiple files. Would you like me to run an adversarial review before committing?"
   > 1. **Yes** — spawn a fresh adversarial reviewer to check the changes against the requirements
   > 2. **No** — commit directly
2. If the user chooses review, spawn a fresh `Task()` reviewer with role type `roleType("adversarial-reviewer")` (resolved per the Role type resolution rule in the metaswarm plugin's guides/agent-coordination.md) with the requirements and the diff
3. Regardless of review choice, verify coverage meets `.coverage-thresholds.json` thresholds before committing

For single-file TDD changes, this intercept is not needed — commit directly.

### Coverage Source of Truth

`.coverage-thresholds.json` is the **single source of truth** for coverage requirements. This applies regardless of which skill or workflow is running:

- `superpowers:verification-before-completion` — must read `.coverage-thresholds.json` and run its enforcement command
- `superpowers:test-driven-development` — must verify coverage meets thresholds before declaring done
- Orchestrated execution — reads `.coverage-thresholds.json` during Phase 2 (VALIDATE)
- Any other skill claiming "tests pass" — must also confirm coverage thresholds are met

If `.coverage-thresholds.json` exists, no skill may skip it. If a skill has its own coverage check logic, `.coverage-thresholds.json` takes precedence.

### Subagent Discipline

All subagents (coding agents, review agents, background tasks) MUST follow these rules:

- **NEVER** use `--no-verify` on git commits — pre-commit hooks exist for a reason
- **NEVER** use `git push --force` without explicit user approval
- **ALWAYS** follow TDD — write tests first, watch them fail, then implement
- **NEVER** self-certify — the orchestrator validates independently
- **STAY** within declared file scope — do not modify files outside your assigned scope

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance, clarify or escalate:

- **No `blocker: yes` findings** → PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Clarify** → a Clarify signal fires: C1 a blocker only the user can answer or that rests on an unconfirmed assumption, C2 blockers not converging, C3 two or more fix-induced blockers, C4 one theme recurring across 3 rounds. Stop, run the misunderstanding analysis, and send the Clarification report. A standing instruction such as "keep going" never defaults a `needs_user` question; only the user's answer does. Clarifying never approves.
- **Escalate to the human** → the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit. The options include clarifying the requirement.
- **Overengineering signal** → restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.
- **Iterate** (fix, re-validate, fresh review) → this round fixed a critical/major finding, or ≥2 independent reviewers reported blockers.

These rules apply in order, top to bottom (Clarify is checked before escalation, and escalation before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md`.

### Pre-PR Knowledge Capture

After all work units pass final review but BEFORE creating the PR, run `/self-reflect` to extract learnings into the knowledge base. Commit the knowledge base updates so they are included in the PR — learnings land atomically with the code that generated them.

### Context Recovery (Surviving Compaction)

Approved plans, project context, and execution state are persisted to `.beads/` so agents can recover after context compaction or session interruption:

- **Approved plans** → `.beads/plans/active-plan.md` (written after plan review gate + user approval)
- **Project context** → `.beads/context/project-context.md` (updated after each work unit commit)
- **Execution state** → `.beads/context/execution-state.md` (updated after each phase transition)
- **Review history** → `.beads/context/review-history/*.json` (written after every review round; a non-closed file is an interrupted gate)

**Note:** The standalone beads plugin (matching your bd version, bd ≥ 1.0.4) runs `bd prime` automatically on SessionStart and PreCompact. `bd prime` restores only the bd workflow reference and any `bd remember` memories. It does **not** load metaswarm's plan, execution state or knowledge base. To recover after compaction or in a new session, read them directly: `.beads/plans/active-plan.md` (resume only if `status: in-progress`), `.beads/context/project-context.md` and `.beads/context/execution-state.md`. Then run `/prime` to load the relevant knowledge-base facts. Also check `.beads/context/review-history/` for a non-closed file: it is an interrupted review gate. Resume that gate at its next round, and if its `status` is `clarify-pending`, re-ask the pending questions instead of iterating.

## External Tools (Optional)

If external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator
can delegate implementation and review tasks to Codex CLI and Gemini CLI for cost savings
and cross-model adversarial review. See `templates/external-tools-setup.md` for setup.

## Team Mode

When `TeamCreate` and `SendMessage` tools are available, the orchestrator uses Team Mode for parallel agent dispatch. Otherwise it falls back to Task Mode (the existing workflow, unchanged). See `guides/agent-coordination.md` for details.

## Guides

Development patterns and standards are documented in `guides/`:
- `agent-coordination.md` — Team Mode vs Task Mode, agent dispatch patterns
- `build-validation.md` — Build and validation workflow
- `coding-standards.md` — Code style and conventions
- `git-workflow.md` — Branching, commits, and PR conventions
- `testing-patterns.md` — TDD patterns and coverage enforcement
- `worktree-development.md` — Git worktree-based parallel development

## Code Quality

<!-- TODO: Update these for your project's language and tools -->
- TypeScript strict mode, no `any` types
- ESLint + Prettier
- All quality gates must pass before PR creation

## Key Decisions

<!-- Document important architectural decisions here so agents have context.
     These get loaded during knowledge priming (/prime).
     Use `bd create "<title>" --type decision -d "<rationale>"` to record decisions
     persistently in the beads database with rationale tracking — these survive compaction and are available across sessions. -->

## Notes

<!-- Add project-specific notes, conventions, or constraints here.
     Examples: "Always use server components for data fetching",
     "The payments module is legacy — do not refactor without approval" -->
