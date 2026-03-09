
## tribunal

This project uses [tribunal](https://github.com/jpeggdev/tribunal) for multi-agent orchestration. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Most tasks**: `/tribunal:start-task` -- primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then say: `Use the full tribunal orchestration workflow.`

### Available Commands

| Command | Purpose |
|---|---|
| `/tribunal:start-task` | Begin tracked work on a task |
| `/tribunal:prime` | Load relevant knowledge before starting |
| `/tribunal:review-design` | Trigger design review gate (5 reviewers) |
| `/tribunal:pr-shepherd` | Monitor a PR through to merge |
| `/tribunal:self-reflect` | Extract learnings before PR creation |
| `/tribunal:handle-pr-comments` | Handle PR review comments |
| `/tribunal:brainstorm` | Refine an idea before implementation |
| `/tribunal:create-issue` | Create a well-structured GitHub Issue |
| `/tribunal:plan-review-gate` | Adversarial plan review (3 reviewers) |

### Quality Gates

- **Design Review Gate** -- 5-reviewer design review after design is drafted (`/tribunal:review-design`)
- **Plan Review Gate** -- 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS
- **Coverage Gate** -- `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Testing & Quality

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Enforced via `.coverage-thresholds.json`
- **Coverage source of truth** -- `.coverage-thresholds.json` defines thresholds. The orchestrator reads it during validation.

### Workflow Enforcement (MANDATORY)

- **After brainstorming** -> MUST run Design Review Gate before planning or implementation
- **After any plan is created** -> MUST run Plan Review Gate before presenting to user
- **Before finishing a branch** -> MUST run `/tribunal:self-reflect` and commit knowledge base updates before PR creation
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. All skills must check it.
- **Subagents** -> NEVER use `--no-verify`, NEVER `git push --force` without approval, NEVER self-certify, ALWAYS follow TDD, STAY within file scope
