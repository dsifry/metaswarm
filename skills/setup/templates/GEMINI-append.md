
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration. It provides 23 agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Most tasks**: `/metaswarm:start-task` -- primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then say: `Use the full metaswarm orchestration workflow.`

### Available Commands

| Command | Purpose |
|---|---|
| `/metaswarm:start-task` | Begin tracked work on a task |
| `/metaswarm:prime` | Load relevant knowledge before starting |
| `/metaswarm:review-design` | Trigger design review gate (6 reviewers) |
| `/metaswarm:pr-shepherd` | Monitor a PR through to merge |
| `/metaswarm:self-reflect` | Extract learnings after a PR merge |
| `/metaswarm:handle-pr-comments` | Handle PR review comments |
| `/metaswarm:brainstorm` | Refine an idea before implementation |
| `/metaswarm:create-issue` | Create a well-structured GitHub Issue |
| `/metaswarm:plan-review-gate` | Adversarial plan review (3 reviewers) |

### Quality Gates

- **Design Review Gate** -- 6-reviewer design review after a project-sized design doc is committed (`/metaswarm:review-design`)
- **Plan Review Gate** -- 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) -- ALL must PASS
- **Coverage Gate** -- `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Testing & Quality

- **TDD is mandatory** -- Write tests first, watch them fail, then implement
- **100% test coverage required** -- Enforced via `.coverage-thresholds.json`
- **Coverage source of truth** -- `.coverage-thresholds.json` defines thresholds. The orchestrator reads it during validation.

### Workflow Enforcement (MANDATORY)

- **During brainstorming** -> load the `brainstorming-extension` skill at the start of brainstorming, not only after the commit, for its assumption ledger, confirmation rule and Common misreadings checklist; it applies to every brainstorming session regardless of size
- **Assumptions** -> never label your own proposal as a user decision, and restate an answer that changes the design and get it confirmed before relying on it.
- **After a project-sized design doc is committed** -> MUST run Design Review Gate before planning or implementation (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **After the plan is written** -> MUST run Plan Review Gate before writing-plans presents the plan (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **Before finishing a branch** -> MUST run `/metaswarm:self-reflect` and commit knowledge base updates before PR creation
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. All skills must check it.
- **Subagents** -> NEVER use `--no-verify`, NEVER `git push --force` without approval, NEVER self-certify, ALWAYS follow TDD, STAY within file scope

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance, clarify or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Clarify** -> a Clarify signal fires: C1 a blocker only the user can answer or that rests on an unconfirmed assumption, C2 blockers not converging, C3 two or more fix-induced blockers, C4 one theme recurring across 3 rounds. Stop, run the misunderstanding analysis, and send the Clarification report. A standing instruction such as "keep going" never defaults a `needs_user` question; only the user's answer does. Clarifying never approves.
- **Escalate to the human** -> the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit. The options include clarifying the requirement.
- **Overengineering signal** -> restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.

These rules apply in order, top to bottom (Clarify is checked before escalation, and escalation before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md` in the metaswarm plugin.
