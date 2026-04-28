# OpenCode Integration

[OpenCode](https://opencode.ai) is supported as a host CLI for metaswarm. OpenCode users get all 13 metaswarm skills, the orchestration workflow, and slash commands without any plugin install — discovery is automatic from `~/.agents/skills/`.

## Quick start

```bash
# Install OpenCode (if you haven't)
curl -fsSL https://opencode.ai/install | bash

# Install metaswarm for OpenCode
npx metaswarm init --opencode

# In your project
npx metaswarm setup --opencode
```

The first command symlinks all metaswarm skills into `~/.agents/skills/metaswarm-*`, which OpenCode discovers automatically. The second writes `AGENTS.md` and `.coverage-thresholds.json` into your project.

## How it works

OpenCode's [Agent Skills](https://opencode.ai/docs/skills/) loader walks several discovery paths, including `~/.agents/skills/` — the same directory metaswarm's Codex installer populates. So one install covers both Codex and OpenCode users.

For project-specific slash commands, metaswarm generates `.opencode/commands/*.md` from the same source map that drives the Gemini TOML commands (see `lib/sync-resources.js`). The two formats stay in sync via `lib/sync-resources.js --check`.

For full details — install, project setup, slash command list, agent personas, limitations, and updating — see [`.opencode/README.md`](../.opencode/README.md) at the repo root.

## Comparison with other CLIs

| Aspect | Claude Code | Codex CLI | Gemini CLI | OpenCode |
|---|---|---|---|---|
| Install | Plugin marketplace | Clone + symlink | Extension | Auto-discovery via `~/.agents/skills/` |
| Project file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `AGENTS.md` (shared with Codex) |
| Slash commands | `commands/*.md` | None (skills are `$name`) | `commands/metaswarm/*.toml` | `.opencode/commands/*.md` |
| Subagent dispatch | `Task()` (parallel) | Sequential | Sequential | `@mention` (parallel, similar to `Task()`) |
| Skill discovery | `.claude/skills/` | `~/.agents/skills/` | Built-in extension | Walks `.opencode/`, `.claude/`, `.agents/` paths |
