# OpenCode Integration for MetaSwarm

[OpenCode](https://opencode.ai) is an open-source AI coding assistant. MetaSwarm adds multi-agent orchestration on top of OpenCode via its configuration and agent system.

## Installation

### Prerequisites

- [OpenCode CLI](https://opencode.ai) v2 (OpenCode V1 plugin API is not supported)
- Node.js >= 22.18 (the BEADS MCP server runs with plain `node`; older Node.js can use `npx tsx`)

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
| `opencode.json` | OpenCode configuration registering commands, agents, and the BEADS MCP server |
| `.opencode/commands/` | Command templates referenced by `{file:...}` in the config |
| `.opencode/agents/` | Agent prompts referenced by `{file:...}` in the config |
| `.opencode/OPENCODE.md` | Project instructions (loaded via `instructions` field) |
| `.opencode/plugins/metaswarm-session.js` | Session plugin: setup verification, BEADS state on compaction |
| `scripts/beads-mcp-server.ts` | BEADS MCP server (zero dependencies, started by `mcp.servers.beads`) |

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
| Plugin hooks | `.opencode/plugins/metaswarm-session.js` — setup verification, BEADS state injected on compaction (OpenCode V2 plugin API) | session events beyond setup and compaction |
| BEADS MCP | `scripts/beads-mcp-server.ts` (zero-dependency stdio server) wired via `mcp.servers.beads` | — |
| Skills discovery | none | `skill` tool wiring via `.opencode/plugins` |
| `.opencode/` structure | commands/, agents/, plugins/ | hooks/ |

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

- Extend the session plugin with session events beyond setup verification and compaction
- Register remaining commands and agents
- Add OpenCode to the hub-and-spoke sync-resources validation pipeline
