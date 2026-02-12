# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework for Claude Code. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### For non-trivial tasks (features, multi-file changes)

Create a GitHub Issue with a spec, then:

```text
Work on issue #N. Use the full metaswarm orchestration workflow.
```

This triggers the full pipeline: Research → Plan → Design Review Gate → Work Unit Decomposition → Orchestrated Execution (4-phase loop per unit) → Final Review → PR.

### For simple tasks (single-file fixes, quick changes)

```text
/project:start-task
```

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
