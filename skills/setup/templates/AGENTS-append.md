
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration. It provides 22 agents (+3 deprecated), a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Most tasks**: `$start` -- primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then say: `Use the full metaswarm orchestration workflow.`

### Available Skills

Codex discovers skills by their SKILL.md `name` field. Invoke with `$name` syntax.

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work on a task |
| `$setup` | Interactive guided setup |
| `$design-review-gate` | Trigger design review gate (5 reviewers) |
| `$pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | Handle PR review comments |
| `$brainstorming-extension` | Refine an idea with design review gate |
| `$create-issue` | Create a well-structured GitHub Issue |
| `$plan-review-gate` | Adversarial plan review (3 reviewers) |

### Quality Gates

- **Design Review Gate** -- 5-reviewer design review after design is drafted (`$design-review-gate`)
- **Plan Review Gate** -- 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS
- **Coverage Gate** -- `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Testing & Quality

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Enforced via `.coverage-thresholds.json`
- **Coverage source of truth** -- `.coverage-thresholds.json` defines thresholds. The orchestrator reads it during validation.

### Workflow Enforcement (MANDATORY)

- **After brainstorming** -> MUST run `$design-review-gate` before planning or implementation
- **After any plan is created** -> MUST run `$plan-review-gate` before presenting to user
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. All skills must check it.
- **Agent discipline** -> NEVER use `--no-verify`, NEVER `git push --force` without approval, NEVER self-certify, ALWAYS follow TDD, STAY within file scope

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Escalate to the human** -> the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit.
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.
- **Overengineering signal** -> restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.

These rules apply in order, top to bottom (escalation is checked before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md` in the metaswarm plugin.
