# OpenCode Tool Mapping

OpenCode tool names mostly mirror Claude Code's, with some renames and an additional native concept (the `skill` tool).

## Built-in tools

| Claude Code Tool | OpenCode Equivalent | Notes |
|---|---|---|
| `Read` | `read` | Same semantics; respects worktree-relative paths |
| `Write` | `write` | Same |
| `Edit` | `edit` | Same |
| `Bash` | `bash` | Permissions are gated per-pattern in `opencode.json` |
| `Glob` | `glob` | Same |
| `Grep` | `grep` | Same |
| `Task()` | `task` (subagent dispatch) | Use `@<agent-name>` in chat to invoke; backed by the `task` tool |
| `WebFetch` | `webfetch` | Same |
| `WebSearch` | `websearch` | Same |
| `TodoWrite` / `TodoRead` | `todowrite` / `todoread` | Same |
| `Skill` | `skill` | Native — agent loads SKILL.md by name from discovery paths |

## Skill discovery

OpenCode auto-discovers `SKILL.md` from these paths (walks from cwd up to git worktree, plus globals):

- `.opencode/skills/<name>/SKILL.md`
- `~/.config/opencode/skills/<name>/SKILL.md`
- **`.claude/skills/<name>/SKILL.md`** — populated by metaswarm Claude install
- `~/.claude/skills/<name>/SKILL.md`
- **`.agents/skills/<name>/SKILL.md`**
- **`~/.agents/skills/<name>/SKILL.md`** — populated by metaswarm Codex install (`metaswarm-<name>` symlinks)

So a metaswarm install for either Claude Code or Codex CLI **automatically** makes all skills available to OpenCode users on the same machine. No additional registration required.

## Agent dispatch

Like Claude's `Task()`, OpenCode subagents run in isolated child sessions and report back to the parent. Built-in: `@general` (parallel general-purpose), `@explore` (read-only). Custom subagents go in `.opencode/agents/<name>.md` with frontmatter (`mode: subagent`, `permission`, `model`, `prompt`).

This means **metaswarm parallel review gates work natively on OpenCode**, unlike Codex CLI which runs them sequentially.

## Slash commands

`.opencode/commands/<name>.md` with YAML frontmatter:

```markdown
---
description: Run tests with coverage
agent: build           # optional - which agent runs the command
model: provider/model  # optional - override model for this command
subtask: true          # optional - force subagent invocation
---
Prompt body. Supports $ARGUMENTS, $1 $2..., !`shell`, @file/path.
```

Filename = command name. Triggered by `/<name>`. Metaswarm generates these from the same source map as Gemini's TOML (see `lib/sync-resources.js`).

## Plugin hooks (not used in v1)

If we ever need session-start context priming or compaction customization, OpenCode plugins are JS/TS modules under `.opencode/plugins/*.{js,ts}` using `@opencode-ai/plugin`. Notable hooks: `event` (session.created, session.idle, etc.), `experimental.session.compacting` (Claude PreCompact analog), `tool.execute.before/after`, `chat.params`.

## Project context

OpenCode reads **`AGENTS.md`** (same file as Codex). The `/init` command creates one. Metaswarm's `setup --opencode` flag writes `AGENTS.md` from the existing template.
