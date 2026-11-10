
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration with Claude Code. It provides 23 agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Most tasks**: `/start-task` — primes context, guides scoping, picks the right level of process
- **Complex features** (multi-file, spec-driven): Describe what you want built with a Definition of Done, then tell Claude: `Use the full metaswarm orchestration workflow.`

### Available Commands

| Command | Purpose |
|---|---|
| `/start-task` | Begin tracked work on a task |
| `/prime` | Load relevant knowledge before starting |
| `/review-design` | Trigger parallel design review gate (6 agents) |
| `/pr-shepherd <pr>` | Monitor a PR through to merge |
| `/self-reflect` | Extract learnings after a PR merge |
| `/handoff` | Write a self-contained handoff doc so a fresh agent can resume the work |
| `/handle-pr-comments` | Handle PR review comments |
| `/brainstorm` | Refine an idea before implementation |
| `/create-issue` | Create a well-structured GitHub Issue |

### Quality Gates

- **Design Review Gate** — Parallel 6-agent review after a project-sized design doc is committed (`/review-design`)
- **Plan Review Gate** — Automatic adversarial review once the plan is written, before writing-plans presents the plan. Spawns 3 independent reviewers (Feasibility, Completeness, Scope & Alignment) in parallel — ALL must PASS before presenting the plan. See `skills/plan-review-gate/SKILL.md`
- **Coverage Gate** — `.coverage-thresholds.json` defines thresholds. BLOCKING gate before PR creation

### Team Mode

When `TeamCreate` and `SendMessage` tools are available, the orchestrator uses Team Mode for parallel agent dispatch. Otherwise it falls back to Task Mode (existing workflow, unchanged). See `guides/agent-coordination.md` for details.

### Guides

Development patterns and standards are documented in `guides/` — covering agent coordination, build validation, coding standards, git workflow, testing patterns, and worktree development.

### Testing & Quality

- **TDD is mandatory** — Write tests first, watch them fail, then implement
- **100% test coverage required** — Enforced via `.coverage-thresholds.json` as a blocking gate before PR creation and task completion
- **Coverage source of truth** — `.coverage-thresholds.json` defines thresholds. Update it if your spec requires different values. The orchestrator reads it during validation — this is a BLOCKING gate.

### Workflow Enforcement (MANDATORY)

These rules override any conflicting instructions from third-party skills:

- **During brainstorming** → load `metaswarm:brainstorming-extension` at the start of brainstorming, not only after the commit, for its assumption ledger, confirmation rule and Common misreadings checklist; it applies to every brainstorming session regardless of size
- **Assumptions** → never label your own proposal as a user decision, and restate an answer that changes the design and get it confirmed before relying on it.
- **After a project-sized design doc is committed** → MUST run Design Review Gate (6 agents) before writing-plans or implementation (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **After the plan is written** → MUST run Plan Review Gate (3 adversarial reviewers) before writing-plans presents the plan (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **Execution method choice** → ALWAYS ask the user whether to use metaswarm orchestrated execution (more thorough, uses more tokens) or superpowers execution skills (faster, lighter-weight). Never auto-select.
- **Before finishing a branch** → MUST run `/self-reflect` and commit knowledge base updates before PR creation
- **Complex tasks** → Use `/start-task` instead of `EnterPlanMode` for tasks touching 3+ files. EnterPlanMode bypasses all quality gates.
- **Standalone TDD on 3+ files** → Ask user if they want adversarial review before committing
- **Coverage** → `.coverage-thresholds.json` is the single source of truth. All skills must check it, including `verification-before-completion`.
- **Subagents** → NEVER use `--no-verify`, ALWAYS follow TDD, NEVER self-certify, STAY within file scope
- **Context recovery** → Approved plans and execution state persist to `.beads/`. The beads plugin's automatic `bd prime` restores only bd workflow context. It does **not** load metaswarm's plan, execution state or knowledge base. After compaction, read `.beads/plans/active-plan.md` and `.beads/context/*.md` directly, then run `/prime` for knowledge. Also check `.beads/context/review-history/` for a non-closed file: it is an interrupted review gate. Resume that gate at its next round, and if its `status` is `clarify-pending`, re-ask the pending questions instead of iterating.

### Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance, clarify or escalate:

- **No `blocker: yes` findings** → PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Clarify** → a Clarify signal fires: C1 a blocker only the user can answer or that rests on an unconfirmed assumption, C2 blockers not converging, C3 two or more fix-induced blockers, C4 one theme recurring across 3 rounds. Stop, run the misunderstanding analysis, and send the Clarification report. A standing instruction such as "keep going" never defaults a `needs_user` question; only the user's answer does. Clarifying never approves.
- **Escalate to the human** → the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit. The options include clarifying the requirement.
- **Overengineering signal** → restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.
- **Iterate** (fix, re-validate, fresh review) → this round fixed a critical/major finding, or ≥2 independent reviewers reported blockers.

These rules apply in order, top to bottom (Clarify is checked before escalation, and escalation before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md` in the metaswarm plugin.
