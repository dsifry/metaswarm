
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration. It provides 19 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

This file is read by both **Codex CLI** and **OpenCode**. Codex invokes skills via `$name`; OpenCode invokes the equivalent slash commands via `/<name>`.

### Workflow

- **Most tasks**: `$start` (Codex) or `/start-task` (OpenCode) -- primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then say: `Use the full metaswarm orchestration workflow.`

### Available Skills

| Codex | OpenCode | Purpose |
|---|---|---|
| `$start` | `/start-task` | Begin tracked work on a task |
| `$setup` | `/setup` | Interactive guided setup |
| `$design-review-gate` | `/review-design` | Trigger design review gate (5 reviewers) |
| `$pr-shepherd` | `/pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | `/handle-pr-comments` | Handle PR review comments |
| `$brainstorming-extension` | `/brainstorm` | Refine an idea with design review gate |
| `$create-issue` | `/create-issue` | Create a well-structured GitHub Issue |
| `$plan-review-gate` | (auto via `/start-task`) | Adversarial plan review (3 reviewers) |

### Quality Gates

- **Design Review Gate** -- 5-reviewer design review after design is drafted (`$design-review-gate` / `/review-design`)
- **Plan Review Gate** -- 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS
- **Coverage Gate** -- `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Testing & Quality

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Enforced via `.coverage-thresholds.json`
- **Coverage source of truth** -- `.coverage-thresholds.json` defines thresholds. The orchestrator reads it during validation.

### Workflow Enforcement (MANDATORY)

- **After brainstorming** -> MUST run `$design-review-gate` / `/review-design` before planning or implementation
- **After any plan is created** -> MUST run `$plan-review-gate` (or let `/start-task` trigger it) before presenting to user
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. All skills must check it.
- **Agent discipline** -> NEVER use `--no-verify`, NEVER `git push --force` without approval, NEVER self-certify, ALWAYS follow TDD, STAY within file scope
