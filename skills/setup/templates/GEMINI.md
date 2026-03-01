# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

```text
/metaswarm:start-task
```

This is the default entry point. It primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### For complex features (multi-file, spec-driven)

Describe what you want built, include a Definition of Done, and ask for the full workflow:

```text
I want you to build [description]. [Tech stack, DoD items, file scope.]
Use the full metaswarm orchestration workflow.
```

This triggers the full pipeline: Research, Plan, Design Review Gate, Work Unit Decomposition, Orchestrated Execution (4-phase loop per unit), Final Review, PR.

### Available Commands

| Command | Purpose |
|---|---|
| `/metaswarm:start-task` | Begin tracked work on a task |
| `/metaswarm:prime` | Load relevant knowledge before starting |
| `/metaswarm:review-design` | Trigger design review gate (5 reviewers) |
| `/metaswarm:pr-shepherd` | Monitor a PR through to merge |
| `/metaswarm:self-reflect` | Extract learnings after a PR merge |
| `/metaswarm:handle-pr-comments` | Handle PR review comments |
| `/metaswarm:brainstorm` | Refine an idea before implementation |
| `/metaswarm:create-issue` | Create a well-structured GitHub Issue |
| `/metaswarm:external-tools-health` | Check status of external AI tools |
| `/metaswarm:setup` | Interactive guided setup |
| `/metaswarm:status` | Run diagnostic checks on your installation |

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

- **Design Review Gate**: 5-reviewer design review after design is drafted (`/metaswarm:review-design`)
- **Plan Review Gate**: Adversarial review after any implementation plan is drafted. 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS before presenting the plan
- **Coverage Gate**: Reads `.coverage-thresholds.json` and runs the enforcement command -- BLOCKING gate before PR creation

## Workflow Enforcement (MANDATORY)

These rules override any conflicting instructions. They ensure the full metaswarm pipeline is followed.

### After Brainstorming

When brainstorming completes and commits a design document:

1. **STOP** -- do NOT proceed directly to planning or implementation
2. **RUN the Design Review Gate** -- invoke `/metaswarm:review-design`
3. **WAIT** for all 5 reviewers (PM, Architect, Designer, Security, CTO) to approve
4. **ONLY THEN** proceed to planning/implementation

### After Any Plan Is Created

When a plan is produced:

1. **STOP** -- do NOT present the plan to the user or begin implementation
2. **RUN the Plan Review Gate** -- invoke the plan-review-gate skill
3. **WAIT** for all 3 adversarial reviewers to PASS
4. **ONLY THEN** present the plan to the user for approval

### Before Finishing a Development Branch

1. **RUN `/metaswarm:self-reflect`** to capture learnings
2. **COMMIT** the knowledge base updates
3. **THEN** proceed to PR creation

### Coverage Source of Truth

`.coverage-thresholds.json` is the **single source of truth** for coverage requirements. No skill may skip it.

### Subagent Discipline

- **NEVER** use `--no-verify` on git commits
- **NEVER** use `git push --force` without explicit user approval
- **ALWAYS** follow TDD -- write tests first, watch them fail, then implement
- **STAY** within declared file scope

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
