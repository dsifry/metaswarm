
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration. It provides 22 agents (+3 deprecated), a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

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
| `/metaswarm:plan-review-gate` | Adversarial plan review (3 reviewers) |

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
- **Subagents** -> NEVER use `--no-verify`, NEVER `git push --force` without approval, NEVER self-certify, ALWAYS follow TDD, STAY within file scope

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Escalate to the human** -> a critical/major finding recurs after a fix, reviewers disagree on severity, or the safety cap of 10 rounds is hit.
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.
- **Stop and advance** -> an overengineering signal is present and no remaining blocker names a credible scenario; downgrade them to follow-ups.

These rules apply in order, top to bottom (escalation is checked before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md` in the metaswarm plugin.
