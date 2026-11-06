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

## Role types on this host

metaswarm spawn sites name a phase role through `roleType` (see `guides/agent-coordination.md`, "Role type resolution"). Claude Code resolves it to a `metaswarm-<role>` agent type with a default model in its frontmatter. Codex resolves it differently.

| Role | Host mechanism | Model source |
|---|---|---|
| `design-reviewer` | `spawn_agent` with `agents/design-reviewer.md` as the instructions | Codex default, or `agents.default_subagent_model` |
| `plan-reviewer` | `spawn_agent` with `agents/plan-reviewer.md` | same |
| `adversarial-reviewer` | `spawn_agent` with `agents/adversarial-reviewer.md` | same |
| `planner` | `spawn_agent` with `agents/planner.md` | same |
| `researcher` | `spawn_agent` with `agents/researcher.md` | same |
| `coder` | `spawn_agent` with `agents/coder.md` | same |
| `pr-shepherd-agent` | `spawn_agent` with `agents/pr-shepherd-agent.md` | same |
| `knowledge-curator-agent` | `spawn_agent` with `agents/knowledge-curator-agent.md` | same |
| `issue-orchestrator` | `spawn_agent` with `agents/issue-orchestrator.md` | same |
| `swarm-coordinator-agent` | `spawn_agent` with `agents/swarm-coordinator-agent.md` | same |

**Fallback (what metaswarm does today):** Codex has no per-role model that metaswarm configures, so pass the role name through to `spawn_agent` with the role's agent file as the instructions. The Codex default model applies. The Claude defaults (opus for reviewers and planner, sonnet for researcher, coder and the two housekeeping agents) are not enforced on Codex.

**Mechanisms that exist but are NOT wired up by metaswarm (candidate follow-up issue, host-side generator):**
- Codex config reference documents `agents.<name>.config_file` (a TOML layer per role, which can set a model) and `agents.<name>.description`, plus `agents.default_subagent_model` and `agents.default_subagent_reasoning_effort`, where "an explicit spawn model takes precedence". Source: https://developers.openai.com/codex/config-reference (verified via the page text).
- The installed Codex CLI (0.160.0) binary embeds a `spawn_agent` tool description saying sub-agents inherit the current model and that the `model` field should only be set when the user asks, and has a `expose_spawn_agent_model_overrides` setting. So a per-call `model` exists. Its exact schema is **unverified** (not documented on the config reference page, and not exercised here).
- `.metaswarm/models.yaml` `roles.<role>.codex` is used only by the external-tools adapters when Claude is the host; it does not configure Codex as a host.
