# metaswarm

Multi-agent orchestration framework for software development. 22 agents (+3 deprecated), 14 skills, quality gates, TDD enforcement.

## Getting Started

Run `/metaswarm:start-task` to begin tracked work, or `/metaswarm:setup` to configure metaswarm for this project.

## Available Commands

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
| `/metaswarm:status` | Run diagnostic checks |

## Workflow

For complex features, describe what you want with a Definition of Done and say:
`Use the full metaswarm orchestration workflow.`

This runs: Research -> Plan -> Design Review Gate -> Work Unit Decomposition -> Orchestrated Execution (4-phase loop per unit) -> Final Review -> PR.

## Quality Gates (MANDATORY)

- **After brainstorming** -> MUST run `/metaswarm:review-design` before planning
- **After any plan** -> MUST run Plan Review Gate before presenting to user
- **Before finishing branch** -> MUST run `/metaswarm:self-reflect` before PR
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. BLOCKING gate.
- **TDD is mandatory** -> Write tests first, watch them fail, then implement

## Rules

- NEVER use `--no-verify` on git commits
- NEVER use `git push --force` without explicit user approval
- ALWAYS follow TDD
- STAY within declared file scope

## Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.
- **Stop and advance** -> an overengineering signal is present and no remaining blocker names a credible scenario; downgrade them to follow-ups.
- **Escalate to the human** -> a critical/major finding recurs after a fix, reviewers disagree on severity, or the safety cap of 10 rounds is hit.

These rules apply in order, and the cap is checked first. A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md`.

## Platform Notes

Gemini CLI has limited sub-agent support. When sub-agents are unavailable:
- Design review runs sequentially (each reviewer in-session one at a time)
- Adversarial review uses rubrics as structured checklists
- Quality of review is maintained through rubric structure

See `skills/start/references/platform-adaptation.md` for the full cross-platform guide.

## Role types on this host

Spawn sites name a phase role through `roleType` (see `guides/agent-coordination.md`). Roster: `design-reviewer`, `plan-reviewer`, `adversarial-reviewer`, `planner`, `researcher`, `coder`, `pr-shepherd-agent`, `knowledge-curator-agent`, `issue-orchestrator`, `swarm-coordinator-agent`.

| Role | Host mechanism | Model source |
|---|---|---|
| any roster role | Gemini CLI subagent: a Markdown file in `.gemini/agents/<role>.md` (project) or `~/.gemini/agents/` (user) | `model` frontmatter field (for example `gemini-3-preview`); default `inherit` (the main session model). `agents.overrides` in `settings.json` can also override run configuration. |

Source: https://geminicli.com/docs/core/subagents/ (verified from the docs page; the page notes Antigravity CLI replaced Gemini CLI for some tiers). metaswarm does not generate `.gemini/agents/` files (candidate follow-up issue). Gemini CLI is not installed here, so none of this was exercised.

**Fallback:** if no subagent file exists for a role, pass the role name through to the host's generic sub-agent with the role's `agents/<role>.md` as the instructions; the session model applies. `.metaswarm/models.yaml` `roles.<role>.gemini` is used by the external-tools adapters when Claude is the host.
