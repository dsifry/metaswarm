# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

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

## External Tools Routing

When external AI tools are configured (`.metaswarm/external-tools.yaml`), the Issue Orchestrator can delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI instead of using Claude subagents for every work unit.

### How It Works

- The orchestrator runs health checks before each dispatch to determine which tools are available
- Implementation tasks are routed to the cheapest available tool by default
- Cross-model adversarial review ensures the writer is always reviewed by a different AI model
- If an external tool fails after 2 attempts, the task escalates to the next model in the chain

### Availability Detection

External tools are detected automatically by `/project:start-task`. If tools are installed but not configured, the orchestrator suggests enabling them. Run `/project:external-tools-health` to check status at any time.

### Visual Review

When tasks produce visual output (web UIs, presentations, rendered pages), agents can use the `visual-review` skill to capture screenshots via Playwright for visual inspection. This requires `npx playwright install chromium` (one-time setup).

