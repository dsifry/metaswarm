# metaswarm for OpenCode

Install metaswarm's 13 orchestration skills, 19 agent personas, and slash commands for [OpenCode](https://opencode.ai).

## How OpenCode finds metaswarm

OpenCode auto-discovers `SKILL.md` files from any of these locations:

- `.opencode/skills/<name>/SKILL.md`
- `~/.config/opencode/skills/<name>/SKILL.md`
- `.claude/skills/<name>/SKILL.md` ← populated by metaswarm Claude Code install
- `~/.claude/skills/<name>/SKILL.md`
- `.agents/skills/<name>/SKILL.md`
- **`~/.agents/skills/<name>/SKILL.md`** ← populated by metaswarm Codex install

So **a single `npx metaswarm init --opencode` call symlinks all 13 metaswarm skills into `~/.agents/skills/metaswarm-*` and OpenCode picks them up automatically** — no plugin, no `opencode.json` edit, no marketplace install required.

## Install

### Quick install

```bash
npx metaswarm init --opencode
```

This reuses the Codex install path: clones the metaswarm repo to `~/.codex/metaswarm` and symlinks each skill into `~/.agents/skills/metaswarm-<name>/`.

### Manual install

```bash
git clone https://github.com/dsifry/metaswarm.git ~/.codex/metaswarm
mkdir -p ~/.agents/skills
for d in ~/.codex/metaswarm/skills/*/; do
  ln -sf "$d" ~/.agents/skills/metaswarm-$(basename "$d")
done
```

## Project setup

In your project directory:

```bash
npx metaswarm setup --opencode
```

This writes `AGENTS.md` (read by both OpenCode and Codex) and `.coverage-thresholds.json`.

If you also want metaswarm slash commands available in this project's OpenCode TUI, the metaswarm repo's own `.opencode/commands/` directory ships them, generated from `lib/sync-resources.js`. Point your project at them by either:

- Symlinking: `ln -s ~/.codex/metaswarm/.opencode/commands .opencode/commands`
- Or copying the files into your own `.opencode/commands/`
- Or referencing the metaswarm repo as a path in your project structure

## How OpenCode invokes metaswarm

| OpenCode UI gesture | What happens |
|---|---|
| Ask in chat | The orchestrator agent loads relevant skills via the built-in `skill` tool |
| `/start-task <desc>` | Runs the metaswarm `start-task` slash command (`.opencode/commands/start-task.md`) |
| `@general help me with X` | Spawns OpenCode's built-in `general` subagent — analog to Claude's `Task()` |
| Tab key | Cycles between primary agents (`build`, `plan`, etc.) |

Skills are loaded on-demand by the model when relevant. The `<available_skills>` block in the system prompt shows OpenCode the list of metaswarm skills with their descriptions.

## Available slash commands

Generated from `lib/sync-resources.js` — same source as the Claude `.md` and Gemini `.toml` commands:

| Command | Purpose |
|---|---|
| `/start-task` | Begin tracked work with complexity assessment |
| `/prime` | Load relevant knowledge from BEADS before starting work |
| `/setup` | Interactive guided project setup |
| `/brainstorm` | Refine an idea before implementation |
| `/review-design` | 5-reviewer design review gate |
| `/pr-shepherd` | Monitor a PR through to merge |
| `/handle-pr-comments` | Address PR review comments |
| `/create-issue` | Create a well-structured GitHub Issue |
| `/self-reflect` | Extract learnings from PR comments and session |
| `/status` | Diagnostic checks on your installation |
| `/update` | Update metaswarm to the latest version |
| `/external-tools-health` | Check external AI tool availability |

## Subagents

Metaswarm's 19 agent personas (under `agents/`) are markdown files with frontmatter compatible with OpenCode's `.opencode/agents/<name>.md` convention. They become available as `@<name>` mentions when copied into a project's `.opencode/agents/` directory.

## Limitations and known differences

- **No SessionStart hook.** OpenCode plugins can listen for `event` with `session.created`, but this requires writing a JS plugin — not shipped in v1. The Claude Code SessionStart context-priming behavior is not auto-replicated; users get it by running `/prime` manually or by including key context in `AGENTS.md`.
- **No PreCompact equivalent in v1.** OpenCode has `experimental.session.compacting`, which is the analog. Not used by metaswarm v1; sessions compact with OpenCode's defaults.
- **Subagent dispatch model.** OpenCode's `@mention` invokes real subagents (similar to Claude's `Task()`), so parallel review gates work. This is in contrast to Codex CLI which is sequential.

## Updating

```bash
cd ~/.codex/metaswarm && git pull
node ~/.codex/metaswarm/lib/sync-resources.js --sync
```

The `--sync` step regenerates `.opencode/commands/*.md` if any commands changed upstream.

## Uninstall

```bash
# Remove skill symlinks (also affects Codex)
for link in ~/.agents/skills/metaswarm-*; do rm -f "$link"; done
# Remove installation
rm -rf ~/.codex/metaswarm
# (Optional) remove project commands if you copied them
rm -rf .opencode/commands
```
