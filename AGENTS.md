# Agent Instructions

This project is **metaswarm** — a multi-agent orchestration framework for Claude Code, Gemini CLI, and Codex CLI. It provides 23 agents, 14 orchestration skills, quality gates, and TDD enforcement.

## Quick Reference

Codex discovers skills by their SKILL.md `name` field. Invoke with `$name` syntax.

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work on a task |
| `$setup` | Interactive guided setup for a project |
| `$brainstorming-extension` | Refine an idea before implementation |
| `$design-review-gate` | Trigger design review gate (6 reviewers) |
| `$plan-review-gate` | Adversarial plan review (3 reviewers) |
| `$orchestrated-execution` | 4-phase execution loop per work unit |
| `$pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | Handle PR review comments |
| `$create-issue` | Create a well-structured GitHub Issue |
| `$status` | Run diagnostic checks |

## BEADS Issue Tracking

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
# If a Dolt remote is configured: bd dolt push (local-only workspaces need no sync)
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   # If a Dolt remote is configured: bd dolt push (local-only workspaces need no sync)
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## Quality Gates (MANDATORY)

- **During brainstorming** -> load `$brainstorming-extension` at the start of brainstorming, not only after the commit, for its assumption ledger, confirmation rule and Common misreadings checklist; it applies to every brainstorming session regardless of size
- **Assumptions** -> never label your own proposal as a user decision, and restate an answer that changes the design and get it confirmed before relying on it.
- **After a project-sized design doc is committed** -> MUST run `$design-review-gate` before planning (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **After the plan is written** -> MUST run `$plan-review-gate` before writing-plans presents the plan (see the metaswarm plugin's `guides/workflow-enforcement.md`)
- **TDD is mandatory** -> Write tests first, watch them fail, then implement
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. BLOCKING gate.
- **NEVER** use `--no-verify` on git commits
- **NEVER** use `git push --force` without explicit user approval
- **NEVER** self-certify -- the orchestrator validates independently
- **ALWAYS** follow TDD, STAY within file scope

## Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance, clarify or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Clarify** -> a Clarify signal fires: C1 a blocker only the user can answer or that rests on an unconfirmed assumption, C2 blockers not converging, C3 two or more fix-induced blockers, C4 one theme recurring across 3 rounds. Stop, run the misunderstanding analysis, and send the Clarification report. A standing instruction such as "keep going" never defaults a `needs_user` question; only the user's answer does. Clarifying never approves.
- **Escalate to the human** -> the same critical/major finding recurs after a fix attempt for it, two reviewers rate the same finding blocker vs. non-blocker, or the safety cap of 10 rounds is hit. The options include clarifying the requirement.
- **Overengineering signal** -> restate the DoD and re-classify each blocker against the policy; escalate if any still names a credible scenario, otherwise downgrade them to follow-ups and advance.
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.

These rules apply in order, top to bottom (Clarify is checked before escalation, and escalation before iteration). A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md`.

## External Tools Routing

When external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI for cost savings and cross-model adversarial review.

### Visual Review

When tasks produce visual output, agents can use `$visual-review` to capture screenshots via Playwright for visual inspection.
