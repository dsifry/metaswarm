# OpenCode Integration for MetaSwarm

[OpenCode](https://opencode.ai) is an open-source AI coding assistant. MetaSwarm adds multi-agent orchestration on top of OpenCode via its configuration and agent system.

## Installation

### Prerequisites

- [OpenCode CLI](https://opencode.ai) v1.17.11 or later (`opencode --version`)
- Node.js >= 18

### Install MetaSwarm

```bash
npx metaswarm init --opencode
```

Or install for all supported CLIs:

```bash
npx metaswarm init --all
```

### Project Setup

In your project directory:

```bash
npx metaswarm setup --opencode
```

This generates:

| File | Purpose |
|------|---------|
| `opencode.json` | OpenCode configuration registering commands and agents |
| `.opencode/commands/` | Command templates referenced by `{file:...}` in the config |
| `.opencode/agents/` | Agent prompts referenced by `{file:...}` in the config |
| `.opencode/OPENCODE.md` | Project instructions (loaded via `instructions` field) |

## Workflow

```text
/prime
/start-task <description>
/review-design
```

1. **`/prime`** — Load relevant knowledge from BEADS knowledge base
2. **`/start-task`** — Begin tracked work with complexity assessment
3. **`/review-design`** — Trigger the design review gate with 5 parallel reviewers

## Architecture

MetaSwarm uses a hub-and-spoke architecture. OpenCode is one spoke alongside Claude Code, Codex CLI, and Gemini CLI.

```
metaswarm/
  skills/          # Shared orchestration skills (hub)
  commands/        # Canonical command definitions (hub)
  agents/          # Canonical agent definitions (hub)
  templates/       # Platform-specific templates
    opencode.json  # OpenCode config template
    OPENCODE.md    # Instruction file template
  .opencode/       # OpenCode spoke (future: plugin hooks)
    README.md      # This file
```

## POC Scope

This integration is a Proof-of-Concept. The following table shows what's included and what's deferred.

| Area | Included | Deferred |
|------|----------|----------|
| Commands | start-task, prime, review-design (3 of 13) | self-reflect, handoff, pr-shepherd, brainstorm, setup, update, status, handle-pr-comments, create-issue, external-tools-health |
| Agents | issue-orchestrator, architect-agent (2 of 19) | 17 remaining agents |
| Plugin hooks | none | BEADS integration, session events, compacting hook |
| Skills discovery | none | `skill` tool wiring via `.opencode/plugins` |
| `.opencode/` structure | commands/, agents/ | plugins/, hooks/ |

## Comparison with Other Platforms

| Feature | Claude Code | Codex CLI | Gemini CLI | OpenCode |
|---------|-------------|-----------|------------|----------|
| Plugin system | `.claude-plugin/` | `.codex-plugin/` | `gemini-extension.json` | `.opencode/` |
| Instructions | `CLAUDE.md` (auto) | `AGENTS.md` (auto) | `GEMINI.md` (auto) | `instructions` array in config |
| Commands | `.claude/commands/*.md` | `.agents/commands/*.md` | TOML files | `opencode.json` + `.opencode/commands/` |
| Agents | Skills-based | `.agents/agents/*.md` | N/A | `opencode.json` + `.opencode/agents/` |
| Marketplace | Claude marketplace | Codex marketplace | Gemini Extensions | Not yet available |
| Install | `claude plugin install` | `codex plugin install` | `gemini extensions install` | `npx metaswarm init --opencode` |

## Testing

```bash
# Validate the config template
node -e "JSON.parse(require('fs').readFileSync('templates/opencode.json','utf-8'))"

# Run the smoke test
bash tests/test-opencode-smoke.sh
```

## Future Work

- Add `.opencode/plugins/*.ts` for BEADS integration
- Wire `experimental.session.compacting` hook for session management
- Register remaining commands and agents
- Add OpenCode to the hub-and-spoke sync-resources validation pipeline
