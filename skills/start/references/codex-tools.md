# Codex CLI Tool Mapping

This file maps Claude Code tool names to Codex CLI equivalents.
Use these mappings when adapting metaswarm skills to run under Codex.

| Claude Code Tool | Codex Equivalent |
|------------------|------------------|
| `Task()` | `spawn_agent` |
| `Skill` | Native skills |
| `Read` | `exec_command` with `sed`, `nl`, `rg`, or direct file tools when available |
| `Write` | `apply_patch` for manual edits |
| `Bash` | `exec_command` |
| `/setup` | `$setup` |
| `/start-task` | `$start` |
| `/status` | `$status` |
| `/pr-shepherd` | `$pr-shepherd` |

## Codex Plugin Notes

- Codex discovers metaswarm skills from `.codex-plugin/plugin.json` via `"skills": "./skills/"`.
- Codex invokes skills by `SKILL.md` frontmatter name, not by directory name.
- Codex plugin hooks are optional and require the `plugin_hooks` feature; core metaswarm workflows must work without hook context.
- Prefer explicit setup/status checks over assuming SessionStart hooks ran.
