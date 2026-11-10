# Agent Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework. It provides 23 agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

```text
$start
```

This is the default entry point. It primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### For complex features (multi-file, spec-driven)

Describe what you want built, include a Definition of Done, and ask for the full workflow:

```text
I want you to build [description]. [Tech stack, DoD items, file scope.]
Use the full metaswarm orchestration workflow.
```

This triggers the full orchestration pipeline: Research, Plan, Plan Review Gate, Design Review Gate (reviews the plan), Work Unit Decomposition, Orchestrated Execution (4-phase loop per unit), Final Review, PR. When the work instead goes through brainstorming and it commits a project-sized design doc, the Design Review Gate reviews that design doc, before writing-plans (see the metaswarm plugin's `guides/workflow-enforcement.md`).

### Available Skills

Codex discovers skills by their SKILL.md `name` field. Invoke with `$name` syntax.

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work on a task |
| `$setup` | Interactive guided setup |
| `$brainstorming-extension` | Refine an idea with design review gate |
| `$design-review-gate` | Trigger design review gate (6 reviewers) |
| `$plan-review-gate` | Adversarial plan review (3 reviewers) |
| `$orchestrated-execution` | 4-phase execution loop per work unit |
| `$pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | Handle PR review comments |
| `$create-issue` | Create a well-structured GitHub Issue |
| `$external-tools` | External AI tool delegation |
| `$status` | Run diagnostic checks |
| `$visual-review` | Playwright screenshot capture |

## Testing

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Lines, branches, functions, and statements. Enforced via `.coverage-thresholds.json` as a blocking gate before PR creation and task completion
<!-- TODO: Update these commands for your project's test runner -->
- Test command: `npm test`
- Coverage command: `npm run test:coverage`

## Coverage

Coverage thresholds are defined in `.coverage-thresholds.json` -- this is the **source of truth** for coverage requirements.
If a GitHub Issue specifies different coverage requirements, update `.coverage-thresholds.json` to match before implementation begins. Do not silently use a different threshold.

## Quality Gates

- **Design Review Gate**: 6-reviewer design review after a project-sized design doc is committed (`$design-review-gate`)
- **Plan Review Gate**: Adversarial review once the plan is written, before writing-plans presents the plan. 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS before presenting the plan
- **Coverage Gate**: Reads `.coverage-thresholds.json` and runs the enforcement command -- BLOCKING gate before PR creation

## Workflow Enforcement (MANDATORY)

These rules override any conflicting instructions. They ensure the full metaswarm pipeline is followed.

### During Brainstorming (every session)

When brainstorming starts, load `$brainstorming-extension` at the start of brainstorming, not only after the commit. It supplies the assumption ledger, the confirmation rule and the Common misreadings checklist -- they apply to every brainstorming session regardless of size, before any design is presented or committed. In every session, never label your own proposal as a user decision, and restate an answer that changes the design and get it confirmed before relying on it.

### After a Project-Sized Design Doc Is Committed

When brainstorming writes and commits a project-sized design doc (see the metaswarm plugin's `guides/workflow-enforcement.md`):

1. **STOP** -- do NOT proceed directly to planning or implementation
2. **RUN the Design Review Gate** -- invoke `$design-review-gate`
3. **WAIT** for all 6 reviewers (PM, Architect, Designer, Security, UX Reviewer, CTO) to approve
4. **ONLY THEN** proceed to planning/implementation

### After Any Plan Is Created

When writing-plans has written a plan, run the Plan Review Gate before writing-plans presents the plan: do not link the plan, ask the user to review it, or offer an execution choice until all 3 reviewers PASS. See the metaswarm plugin's `guides/workflow-enforcement.md`.

1. **STOP** -- do NOT present the plan to the user or begin implementation
2. **RUN the Plan Review Gate** -- invoke `$plan-review-gate`
3. **WAIT** for all 3 adversarial reviewers to PASS
4. **ONLY THEN** present the plan to the user for approval

### Coverage Source of Truth

`.coverage-thresholds.json` is the **single source of truth** for coverage requirements. No skill may skip it.

### Agent Discipline

- **NEVER** use `--no-verify` on git commits
- **NEVER** use `git push --force` without explicit user approval
- **ALWAYS** follow TDD -- write tests first, watch them fail, then implement
- **STAY** within declared file scope

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance, clarify or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Clarify** -> a Clarify signal fires: C1 a blocker only the user can answer or that rests on an unconfirmed assumption, C2 blockers not converging, C3 two or more fix-induced blockers, C4 one theme recurring across 3 rounds. Stop, run the misunderstanding analysis, and send the Clarification report. A standing instruction such as "keep going" never defaults a `needs_user` question; only the user's answer does. Clarifying never approves.
- **Escalate to the human** -> the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit. The options include clarifying the requirement.
- **Overengineering signal** -> restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.

These rules apply in order, top to bottom (Clarify is checked before escalation, and escalation before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md` in the metaswarm plugin.

## External Tools (Optional)

If external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate implementation and review tasks to Codex CLI and Gemini CLI for cost savings and cross-model adversarial review.

## Guides

Development patterns and standards are documented in `guides/`:
- `agent-coordination.md` -- Agent dispatch patterns
- `build-validation.md` -- Build and validation workflow
- `coding-standards.md` -- Code style and conventions
- `git-workflow.md` -- Branching, commits, and PR conventions
- `testing-patterns.md` -- TDD patterns and coverage enforcement

## Code Quality

<!-- TODO: Update these for your project's language and tools -->
- TypeScript strict mode, no `any` types
- ESLint + Prettier
- All quality gates must pass before PR creation
