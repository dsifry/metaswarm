
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Most tasks**: `/metaswarm:start-task` -- primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then say: `Use the full metaswarm orchestration workflow.`

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

### Quality Gates

- **Design Review Gate** -- 5-reviewer design review after design is drafted (`/metaswarm:review-design`)
- **Plan Review Gate** -- 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS
- **Coverage Gate** -- `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Testing & Quality

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Enforced via `.coverage-thresholds.json`
- **Coverage source of truth** -- `.coverage-thresholds.json` defines thresholds. The orchestrator reads it during validation.

### Workflow Enforcement (MANDATORY)

- **After brainstorming** -> MUST run Design Review Gate before planning or implementation
- **After any plan is created** -> MUST run Plan Review Gate before presenting to user
- **Before finishing a branch** -> MUST run `/metaswarm:self-reflect` and commit knowledge base updates before PR creation
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. All skills must check it.
- **Subagents** -> NEVER use `--no-verify`, ALWAYS follow TDD, STAY within file scope
