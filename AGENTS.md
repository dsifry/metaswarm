# Agent Instructions

This project is **metaswarm** — a multi-agent orchestration framework for Claude Code, Gemini CLI, and Codex CLI. It provides 22 agents (+3 deprecated), 13 orchestration skills, quality gates, and TDD enforcement.

## Quick Reference

Codex discovers skills by their SKILL.md `name` field. Invoke with `$name` syntax.

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work on a task |
| `$setup` | Interactive guided setup for a project |
| `$brainstorming-extension` | Refine an idea before implementation |
| `$design-review-gate` | Trigger design review gate (5 reviewers) |
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
bd sync               # Sync with git
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
   bd sync
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

- **After brainstorming** -> MUST run `$design-review-gate` before planning
- **After any plan** -> MUST run `$plan-review-gate` before presenting to user
- **TDD is mandatory** -> Write tests first, watch them fail, then implement
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. BLOCKING gate.
- **NEVER** use `--no-verify` on git commits
- **NEVER** use `git push --force` without explicit user approval
- **NEVER** self-certify -- the orchestrator validates independently
- **ALWAYS** follow TDD, STAY within file scope

## Delivery Scope & Review Iteration

Block delivery only for a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, or an important error or recovery-path failure. Every review finding carries a `severity` (critical/major/minor/nit); to block, a critical/major finding must also name what it `protects` (a user scenario, requirement or DoD item). Findings without `protects` are advisory, not blockers. After each review round the orchestrator decides whether to iterate, advance or escalate:

- **No `blocker: yes` findings** -> PASS, advance. Minor/nit findings become follow-ups (a BEADS task, or a GitHub issue if over a day).
- **Iterate** (fix, re-validate, fresh review) -> this round fixed a critical/major finding, or 2+ independent reviewers reported blockers.
- **Stop and advance** -> an overengineering signal is present and no remaining blocker names a credible scenario; downgrade them to follow-ups.
- **Escalate to the human** -> a critical/major finding recurs after a fix, reviewers disagree on severity, or the safety cap of 10 rounds is hit.

These rules apply in order, and the cap is checked first. A round that still has a blocker and matches none of them also iterates. If `bd` is unavailable, list follow-ups in a `### Follow-ups` section.

Full policy, finding contract and ordered rule: `guides/delivery-scope.md`.

## External Tools Routing

When external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI for cost savings and cross-model adversarial review.

### Visual Review

When tasks produce visual output, agents can use `$visual-review` to capture screenshots via Playwright for visual inspection.
