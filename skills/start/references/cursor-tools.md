# Cursor Tool Mapping (Future)

This file maps Claude Code tool names to Cursor equivalents.
Implementation deferred — see `docs/plans/2026-02-26-plugin-migration-design.md` for details.

Cursor tools are mostly identical to Claude Code. Key differences TBD.

## Role types on this host

metaswarm spawn sites name a phase role through `roleType`. Roster: `design-reviewer`, `plan-reviewer`, `adversarial-reviewer`, `planner`, `researcher`, `coder`, `pr-shepherd-agent`, `knowledge-curator-agent`, `issue-orchestrator`, `swarm-coordinator-agent`.

| Role | Host mechanism | Model source |
|---|---|---|
| any roster role | Cursor subagent file in `.cursor/agents/` (Cursor also reads `.claude/agents/`, so the Claude files generated from `.metaswarm/models.yaml` may be picked up) | `model` frontmatter field; default `inherit` (the parent's model). The parent can also name a model at launch. |

Source: https://cursor.com/docs/context/subagents (verified from the docs page). Whether Cursor accepts Claude-style aliases such as `opus` and `sonnet` in `model` is **unverified**. Cursor may also substitute a model per plan or admin policy.

**Fallback:** where no subagent file resolves, pass the role name through to the host's generic subagent launch with the role's `agents/<role>.md` as the instructions. The parent agent's model applies.
