# OpenCode Integration — Phase 0 Spike Findings

**Date:** 2026-04-28
**bd issue:** `metaswarm-y4o.1`
**GitHub:** dsifry/metaswarm#41
**Status:** Spike complete — recommend proceeding to Phase 1 with a **lean** scope.

## TL;DR

OpenCode natively reads the same Agent Skills standard metaswarm already publishes (`SKILL.md` with `name` + `description` frontmatter), and it auto-discovers skills from `.claude/skills/` and `.agents/skills/` — **the two locations metaswarm already installs to**. Commands are markdown files with frontmatter under `.opencode/commands/`. The plugin SDK is mature and well-typed.

**Net effect:** the OpenCode spoke is dramatically smaller than originally estimated. Best-case: a small `.opencode/` directory + a generator for `.opencode/commands/*.md` from the existing `TOML_COMMAND_MAP`, and OpenCode users get the full metaswarm hub for free. Plugin is **optional** (only needed for hooks like SessionStart-equivalent).

## Sources consulted

- `.opencode/node_modules/@opencode-ai/plugin/dist/index.d.ts`
- `.opencode/node_modules/@opencode-ai/plugin/dist/tool.d.ts`
- `.opencode/node_modules/@opencode-ai/plugin/dist/example.js`, `example-workspace.js`
- https://opencode.ai/docs/skills/
- https://opencode.ai/docs/commands/
- https://opencode.ai/docs/agents/
- https://opencode.ai/docs/plugins/
- https://opencode.ai/docs/

## Findings against the original spike questions

### 1. Skill discovery — **best possible outcome**

OpenCode searches all of these locations for `SKILL.md`:

- `.opencode/skills/<name>/SKILL.md`
- `~/.config/opencode/skills/<name>/SKILL.md`
- **`.claude/skills/<name>/SKILL.md`** ← metaswarm Claude Code install target
- **`~/.claude/skills/<name>/SKILL.md`**
- **`.agents/skills/<name>/SKILL.md`**
- **`~/.agents/skills/<name>/SKILL.md`** ← metaswarm Codex install target (`.codex/install.sh:34-78` symlinks here)

> Discovery walks up from cwd to git worktree, so a metaswarm-managed `.claude/skills/` or `.agents/skills/` at the repo root is automatically picked up.

Frontmatter requirements (`name`, `description`, optional `license`, `compatibility`, `metadata`) are a **strict subset** of what metaswarm's existing `SKILL.md` files declare. Name regex `^[a-z0-9]+(-[a-z0-9]+)*$` matches all 13 current skills.

**Implication:** If a user has Codex installed via metaswarm (which symlinks all 13 skills into `~/.agents/skills/metaswarm-<name>/`), OpenCode picks them up with zero additional work. Same if Claude is installed.

### 2. Commands — file-based, simple

`.opencode/commands/<name>.md` with frontmatter:

```markdown
---
description: Run tests with coverage
agent: build           # optional
model: provider/model  # optional
subtask: true          # optional
---
Prompt template body. Supports $ARGUMENTS, $1 $2..., !`shell command`, @file/path.
```

Filename = command name. Triggered by `/<name>` in TUI. Almost identical semantics to Claude `.md` commands and Gemini `.toml` commands. **The existing `TOML_COMMAND_MAP` in `lib/sync-resources.js:89-160` can drive a 3rd output format trivially.**

### 3. Subagent dispatch — `@mention` is real subagents

OpenCode has a typed `subagent` mode with permissions, prompt files, and the same Task-tool delegation pattern as Claude Code. `@general`, `@explore` are built-in subagents. Custom subagents go in `.opencode/agents/<name>.md` with markdown frontmatter (`mode`, `model`, `permission`, `prompt`, etc.).

> The 19 metaswarm agent personas in `agents/*.md` could be installed as `.opencode/agents/<name>.md` directly — they're already markdown with frontmatter, just need a frontmatter shape adjustment if any fields differ.

### 4. Plugin SDK — mature, optional for our use case

Hooks available include `chat.params`, `chat.headers`, `permission.ask`, `command.execute.before`, `tool.execute.before`, `tool.execute.after`, `shell.env`, `event` (with session.idle, session.created, session.compacted, etc.), `experimental.session.compacting`, `experimental.compaction.autocontinue`. There is **no SessionStart hook**, but there is `event` (with `session.created`) and `experimental.session.compacting` (Claude's PreCompact analog).

A plugin would be needed only if metaswarm wants to:
- Inject context on session start (use `event` listening for `session.created`)
- Customize compaction (use `experimental.session.compacting` — directly equivalent to Claude PreCompact)
- Add metaswarm-specific custom tools

Plugins go in `.opencode/plugins/*.{js,ts}` (auto-loaded) or are referenced as npm packages in `opencode.json`. `~/.cache/opencode/node_modules/` is the install cache.

### 5. Path-resolution env var — N/A

Plugins receive `directory`, `worktree`, `project` in their context object. Skills are loaded from absolute paths discovered by OpenCode itself. **There is no `${CLAUDE_PLUGIN_ROOT}`-style template variable to thread through `hooks/session-start.sh`.** OpenCode hooks are JS plugin functions, not shell scripts.

### 6. Marketplace — npm, not a custom registry

OpenCode plugins ship as npm packages (`opencode-helicone-session`, `opencode-wakatime`, etc.). Users add them via `opencode.json`'s `plugin` array. **If metaswarm wanted a one-line install story, publishing `opencode-metaswarm` to npm is the path.**

### 7. AGENTS.md — confirmed shared with Codex

`/init` creates `AGENTS.md`. OpenCode reads it as project context. Same file as Codex consumes. Current language about Codex `$name` invocation needs editing for OpenCode accuracy.

### 8. Hooks — JS-based, plugin-driven

Already covered in (4). No shell-hook surface. `hooks/session-start.sh` doesn't apply to OpenCode.

## Updated effort estimate (revised down)

The original M-L estimate assumed we'd need a full plugin + custom command shape + Codex-style symlink installer. Reality is much leaner.

### Phase 1 (revised): "Lean spoke"

- **`.opencode/commands/*.md`** — Generated from `TOML_COMMAND_MAP`. Just extend `lib/sync-resources.js` with one more output writer. **(S, ~2h)**
- **`.opencode/agents/*.md`** — Generated/copied from `agents/*.md` with frontmatter normalization. **(S, ~2h)**
- **No `.opencode/install.sh` needed** — Skills auto-discover from `.claude/skills/` or `.agents/skills/`. The existing `cli/metaswarm.js` `installClaude()` or `installCodex()` paths already populate one of these. We just document this and add a `--opencode` flag that runs whichever it currently runs (or both). **(S, ~1h)**
- **No plugin in v1** — Defer until we want session-start context injection or custom compaction. **(0)**
- **`opencode.json` template** — Optional starter config users can drop in. **(S, ~1h)**
- **`docs/README.opencode.md`** — Real content explaining auto-discovery via `.claude/skills/`/`.agents/skills/`, command list, agent list. **(S, ~1h)**
- **`lib/platform-detect.js`** — `detectOpenCode()` checks `command -v opencode`. **(S, ~30min)**
- **`cli/metaswarm.js`** — `--opencode` flag; mostly a no-op that runs the codex install path + writes `.opencode/commands/`. **(S, ~1h)**
- **`skills/start/references/opencode-tools.md`** — Flesh out Read/Edit/Glob/Grep/Bash/Task/Skill mappings (most map 1:1 to the same names). **(S, ~30min)**
- **`skills/start/references/platform-adaptation.md`** — Add OpenCode column. **(S, ~30min)**
- **`AGENTS.md` + templates** — Add OpenCode-aware section. Resolve Codex-specific `$name` language. **(S, ~30min)**
- **README/INSTALL/USAGE/CHANGELOG/GETTING_STARTED** — Doc propagation. **(S, ~1h)**
- **Tests** — `tests/opencode/test-opencode-discovery.sh` validates `.opencode/commands/` generation and skill auto-discovery paths. **(S, ~1h)**

**New total for Phase 1: ~12h (1.5 focused days), down from ~16h.**

### Phase 2 (external-tools adapter) — unchanged

OpenCode CLI as delegation target. ~8h. Headless invocation via `opencode run "prompt"` (need to confirm CLI flag — see open question below).

### Phase 3 (DRY refactor) — unchanged

Centralize platform metadata. Now even more justified since we're going from 3-way to 4-way duplication for command files.

## Recommended approach: **JS plugin = NO, file-based = YES**

Per the question I asked earlier ("How should metaswarm be installed into OpenCode?"), the spike resolves it cleanly:

- **NO custom plugin in v1.** OpenCode discovers skills/agents/commands from disk. We don't need to register anything via the SDK.
- **Reuse existing install targets.** `.claude/skills/` (Claude install) and `.agents/skills/` (Codex install) are both auto-discovered by OpenCode. Zero new install code.
- **Generate `.opencode/commands/*.md`** alongside Gemini TOML using the existing map.
- **Optionally publish `opencode-metaswarm` to npm later** if we want one-line install via `opencode.json`. Defer.

## Remaining open questions

1. **Headless invocation flag.** What's the `opencode` command equivalent of `claude --print` / `gemini --prompt` / `codex exec`? Needed for Phase 2 external-tools adapter. (Quick check via `opencode --help` once installed.)
2. **Agent frontmatter shape.** Need to compare metaswarm's `agents/*.md` frontmatter against OpenCode's expected shape (`description`, `mode`, `model`, `permission`, etc.) to know if a normalizer is needed or a simple copy works.
3. **Skill compatibility field.** OpenCode supports `compatibility: opencode` in frontmatter. Should metaswarm SKILL.md files declare `compatibility: [claude, codex, gemini, opencode]` or omit it (omit = universal)?
4. **Permissions surface.** Should we ship a recommended `opencode.json` permission policy for the metaswarm subagents, or leave to user?

## Recommendation

Close this spike. Update `metaswarm-y4o.2` (Phase 1) with the revised lean scope. Begin implementation. Open question 1 (headless flag) gets answered as part of Phase 2 prep.
