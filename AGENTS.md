# Agent Instructions

This project is **metaswarm** — a multi-agent orchestration framework for Claude Code, Gemini CLI, Codex CLI, and OpenCode. It provides 19 specialized agents, 13 orchestration skills, quality gates, and TDD enforcement.

## Quick Reference

This file is read by both **Codex CLI** and **OpenCode**. Codex invokes skills via `$name`; OpenCode exposes equivalent slash commands as `/<name>`.

| Codex | OpenCode | Purpose |
|---|---|---|
| `$start` | `/start-task` | Begin tracked work on a task |
| `$setup` | `/setup` | Interactive guided setup for a project |
| `$brainstorming-extension` | `/brainstorm` | Refine an idea before implementation |
| `$design-review-gate` | `/review-design` | Trigger design review gate (5 reviewers) |
| `$plan-review-gate` | (auto via `/start-task`) | Adversarial plan review (3 reviewers) |
| `$orchestrated-execution` | (auto via `/start-task`) | 4-phase execution loop per work unit |
| `$pr-shepherd` | `/pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | `/handle-pr-comments` | Handle PR review comments |
| `$create-issue` | `/create-issue` | Create a well-structured GitHub Issue |
| `$status` | `/status` | Run diagnostic checks |

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

## External Tools Routing

When external AI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate implementation and review tasks to OpenAI Codex CLI, Google Gemini CLI, and OpenCode for cost savings and cross-model adversarial review.

### Visual Review

When tasks produce visual output, agents can use `$visual-review` to capture screenshots via Playwright for visual inspection.
