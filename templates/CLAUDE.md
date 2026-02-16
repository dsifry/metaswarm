# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework for Claude Code. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

```text
/project:start-task
```

This is the default entry point. It primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### For complex features (multi-file, spec-driven)

Describe what you want built, include a Definition of Done, and ask for the full workflow:

```text
I want you to build [description]. [Tech stack, DoD items, file scope.]
Use the full metaswarm orchestration workflow.
```

This triggers the full pipeline: Research → Plan → Design Review Gate → Work Unit Decomposition → Orchestrated Execution (4-phase loop per unit) → Final Review → PR.

### Available Commands

| Command | Purpose |
|---|---|
| `/project:start-task` | Begin tracked work on a task |
| `/project:prime` | Load relevant knowledge before starting |
| `/project:review-design` | Trigger parallel design review gate (5 agents) |
| `/project:pr-shepherd <pr>` | Monitor a PR through to merge |
| `/project:self-reflect` | Extract learnings after a PR merge |
| `/project:handle-pr-comments` | Handle PR review comments |
| `/project:brainstorm` | Refine an idea before implementation |
| `/project:create-issue` | Create a well-structured GitHub Issue |
| `/project:external-tools-health` | Check status of external AI tools (Codex, Gemini) |
| `/project:metaswarm-doctor` | Post-install/upgrade health check for the full stack |
| `/project:metaswarm-start-task-delegated-codex` | Start task with all implementation delegated to Codex CLI |
| `/project:metaswarm-start-task-delegated-gemini` | Start task with all implementation delegated to Gemini CLI |
| `/project:metaswarm-setup` | Interactive guided setup — detects project, configures metaswarm |
| `/project:metaswarm-update-version` | Update metaswarm to latest version |

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

- **Design Review Gate**: Parallel 5-agent review after design is drafted (`/project:review-design`)
- **Plan Review Gate**: Automatic adversarial review after any implementation plan is drafted. Spawns 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) in parallel — ALL must PASS before the plan is presented to the user. See `.claude/plugins/metaswarm/skills/plan-review-gate/SKILL.md`
- **Coverage Gate**: Reads `.coverage-thresholds.json` and runs the enforcement command — BLOCKING gate before PR creation

## External Tools (Optional)

If external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator
can delegate implementation and review tasks to Codex CLI and Gemini CLI for cost savings
and cross-model adversarial review. See `templates/external-tools-setup.md` for setup.

## Team Mode

When `TeamCreate` and `SendMessage` tools are available, the orchestrator uses Team Mode for parallel agent dispatch. Otherwise it falls back to Task Mode (the existing workflow, unchanged). See `.claude/guides/agent-coordination.md` for details.

## Guides

Development patterns and standards are documented in `.claude/guides/`:
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
     These get loaded during knowledge priming (/project:prime). -->

## Notes

<!-- Add project-specific notes, conventions, or constraints here.
     Examples: "Always use server components for data fetching",
     "The payments module is legacy — do not refactor without approval" -->
