# Platform Adaptation Guide

This reference documents how metaswarm skills adapt across Claude Code, Gemini CLI, Codex CLI, and OpenCode. Skills use the Agent Skills standard (SKILL.md with YAML frontmatter) which is portable across all four platforms.

## Tool Equivalents

| Capability | Claude Code | Gemini CLI | Codex CLI | OpenCode |
|---|---|---|---|---|
| Read file | `Read` tool | `read_file` | `read_file` | `read` |
| Write file | `Write` tool | `write_file` | `write_file` | `write` |
| Edit file | `Edit` tool | `edit_file` | `apply_diff` | `edit` |
| Run shell | `Bash` tool | `run_shell` | `shell` | `bash` |
| Search files | `Glob` / `Grep` | `search_files` | `glob` / `grep` | `glob` / `grep` |
| Spawn subagent | `Task()` tool | Experimental sub-agents | Not available | `task` tool / `@mention` |
| Invoke skill | `Skill` tool | `/extension:skill` | `$skill-name` | `skill` tool (auto) |
| Plan mode | `EnterPlanMode` | Not available | Not available | Not available |

## Multi-Agent Dispatch

### Claude Code (Full Support)

Claude Code provides `Task()` for spawning independent subagents. metaswarm uses this for:
- Parallel design review (5 agents simultaneously)
- Adversarial review (fresh reviewer with no prior context)
- Background research while implementation continues

### OpenCode (Full Support)

OpenCode provides a `task` tool and `@mention` syntax for dispatching subagents into isolated child sessions. metaswarm parallel review gates run natively — the same parallel pattern as Claude Code:
- Parallel design review via multiple `task` invocations in a single response
- Adversarial review via the built-in `@general` subagent (fresh context per invocation)
- Custom reviewer agents go in `.opencode/agents/<name>.md` with `mode: subagent` frontmatter

### Gemini CLI (Limited)

Gemini CLI has experimental sub-agent support. When unavailable:
- Design review runs **sequentially** — each reviewer runs in-session one at a time
- Adversarial review uses rubrics as structured checklists (the agent reviews its own work against the rubric criteria with explicit evidence requirements)
- The quality of review is maintained through the rubric structure, not agent isolation

### Codex CLI (Sequential Only)

Codex CLI has no subagent dispatch. All workflows run sequentially in-session:
- Review gates become self-review against rubric checklists
- The agent explicitly works through each rubric criterion, citing file:line evidence
- Human review at checkpoints becomes more important as a compensating control

## Graceful Degradation Rules

1. **Never skip a quality gate** — if parallel dispatch is unavailable, run it sequentially
2. **Rubrics are the invariant** — the same review criteria apply regardless of whether a fresh agent or the current agent evaluates them
3. **Evidence requirements don't change** — file:line citations are required on all platforms
4. **TDD is mandatory everywhere** — write tests first, watch them fail, then implement
5. **Coverage gates are blocking everywhere** — `.coverage-thresholds.json` is enforced regardless of platform

## Command Invocation

Codex uses the `name` field from SKILL.md frontmatter for `$name` invocation — not the directory name. The `metaswarm-` prefix on directory names is for organization only. OpenCode uses standard `/<name>` slash commands generated under `.opencode/commands/<name>.md`.

| Action | Claude Code | Gemini CLI | Codex CLI | OpenCode |
|---|---|---|---|---|
| Start task | `/start-task` | `/metaswarm:start-task` | `$start` | `/start-task` |
| Setup | `/setup` | `/metaswarm:setup` | `$setup` | `/setup` |
| Brainstorm | `/brainstorm` | `/metaswarm:brainstorm` | `$brainstorming-extension` | `/brainstorm` |
| Review design | `/review-design` | `/metaswarm:review-design` | `$design-review-gate` | `/review-design` |

## Instruction Files

| Platform | File | Purpose |
|---|---|---|
| Claude Code | `CLAUDE.md` | Project instructions loaded automatically |
| Gemini CLI | `GEMINI.md` | Extension context loaded automatically |
| Codex CLI | `AGENTS.md` | Agent instructions loaded automatically |
| OpenCode | `AGENTS.md` | Same file as Codex; loaded automatically |

All four contain the same workflow enforcement rules (TDD, coverage gates, quality gates) adapted for the platform's command syntax and capabilities.

## Skill Discovery Paths

| Platform | Discovery paths |
|---|---|
| Claude Code | `.claude/skills/<name>/`, `~/.claude/skills/<name>/` |
| Gemini CLI | Built-in extension manifest |
| Codex CLI | `~/.agents/skills/<name>/` (symlinks created during install) |
| OpenCode | All of: `.opencode/skills/`, `~/.config/opencode/skills/`, `.claude/skills/`, `~/.claude/skills/`, `.agents/skills/`, `~/.agents/skills/` |

Because OpenCode walks the union of Claude and Codex skill paths, **a metaswarm install for either Claude Code or Codex CLI is automatically picked up by OpenCode** on the same machine. No separate registration required.
