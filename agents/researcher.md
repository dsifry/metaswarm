---
name: researcher
description: "Deprecated alias for codebase-researcher (removed in the next release). Read-only codebase exploration with file:line citations; spawn codebase-researcher instead."
model: sonnet
disallowedTools: Write, Edit, NotebookEdit
---

# Researcher (deprecated alias)

**Type**: `researcher`, a deprecated alias of `codebase-researcher`. It stays for one release so existing spawns and `.metaswarm/models.yaml` files that name `researcher` keep working.

Spawn `codebase-researcher` instead (role type resolution maps `researcher` to it; see "Role type resolution" in `guides/agent-coordination.md`). For design research, use `deep-researcher` (see `guides/research-selection.md`).

If you were spawned as `researcher`: read `agents/codebase-researcher.md` in the metaswarm plugin (the plugin root is found with `dirname "$(dirname "$(command -v metaswarm-agents.sh)")"`, or `$CLAUDE_PLUGIN_ROOT` if set) and follow it exactly. You are read-only: never edit the repository.
