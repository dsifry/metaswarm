# Platform Adaptation Guide

This reference documents how metaswarm skills adapt across Claude Code, Gemini CLI, Codex CLI, and OpenCode. Skills use the Agent Skills standard (SKILL.md with YAML frontmatter) which is portable across all platforms.

## Tool Equivalents

| Capability | Claude Code | Gemini CLI | Codex CLI | OpenCode |
|---|---|---|---|
| Read file | `Read` tool | `read_file` | `read_file` | `Read` tool |
| Write file | `Write` tool | `write_file` | `write_file` | `Write` tool |
| Edit file | `Edit` tool | `edit_file` | `apply_diff` | `Edit` tool |
| Run shell | `Bash` tool | `run_shell` | `shell` | `Bash` tool |
| Search files | `Glob` / `Grep` | `search_files` | `glob` / `grep` | `Glob` / `Grep` |
| Spawn subagent | `Task()` tool | Experimental sub-agents | Not available | Not available |
| Invoke skill | `Skill` tool | `/extension:skill` | `$skill-name` | Not available |
| Plan mode | `EnterPlanMode` | Not available | Not available | Not available |

## Multi-Agent Dispatch

### Claude Code (Full Support)

Claude Code provides `Task()` for spawning independent subagents. metaswarm uses this for:
- Parallel design review (5 agents simultaneously)
- Adversarial review (fresh reviewer with no prior context)
- Background research while implementation continues

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

Codex uses the `name` field from SKILL.md frontmatter for `$name` invocation — not the directory name. The `metaswarm-` prefix on directory names is for organization only.

| Action | Claude Code | Gemini CLI | Codex CLI | OpenCode |
|---|---|---|---|---|---|
| Start task | `/start-task` or `/metaswarm:start-task` | `/metaswarm:start-task` | `$start` | `/start-task` |
| Setup | `/setup` or `/metaswarm:setup` | `/metaswarm:setup` | `$setup` | `npx metaswarm setup --opencode` |
| Brainstorm | `/brainstorm` or `/metaswarm:brainstorm` | `/metaswarm:brainstorm` | `$brainstorming-extension` | `Not available` |
| Review design | `/review-design` or `/metaswarm:review-design` | `/metaswarm:review-design` | `$design-review-gate` | `/review-design` |

## Instruction Files

| Platform | File | Purpose |
|---|---|---|---|
| Claude Code | `CLAUDE.md` | Project instructions loaded automatically |
| Gemini CLI | `GEMINI.md` | Extension context loaded automatically |
| Codex CLI | `AGENTS.md` | Agent instructions loaded automatically |
| OpenCode | `.opencode/OPENCODE.md` | Agent instructions loaded automatically |

All four contain the same workflow enforcement rules (TDD, coverage gates, quality gates) adapted for the platform's command syntax and capabilities.
