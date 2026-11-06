# OpenCode Tool Mapping (Future)

This file maps Claude Code tool names to OpenCode equivalents.
Implementation deferred — see `docs/plans/2026-02-26-plugin-migration-design.md` for details.

| Claude Code Tool | OpenCode Equivalent |
|------------------|---------------------|
| `Task()` | `@mention` |
| `Skill` | Skill tool |

## Role types on this host

metaswarm spawn sites name a phase role through `roleType`. Roster: `design-reviewer`, `plan-reviewer`, `adversarial-reviewer`, `planner`, `researcher`, `coder`, `pr-shepherd-agent`, `knowledge-curator-agent`, `issue-orchestrator`, `swarm-coordinator-agent`.

| Role | Host mechanism | Model source |
|---|---|---|
| any roster role | `@mention` of an OpenCode subagent (`mode: subagent`) defined in `.opencode/agents/<role>.md` | The agent file's `model` key (`provider/model-id`); if unset, subagents use the model of the invoking primary agent |

Source: https://opencode.ai/docs/agents/ (verified). OpenCode has a per-agent model mechanism, but metaswarm does not generate `.opencode/agents/` files (candidate follow-up issue). OpenCode support in metaswarm is otherwise unimplemented and unverified.

**Fallback:** where no such agent file exists, pass the role name through to the host's generic spawn (an `@mention` or the task tool) with the role's `agents/<role>.md` as the instructions. The primary agent's model applies.
