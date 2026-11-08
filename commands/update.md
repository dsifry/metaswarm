---
description: Check for and apply metaswarm updates, then regenerate the project's phase agents
---

# Update

Check for and apply metaswarm updates.

## Usage

```text
/update
```

## Behavior

1. Read current plugin version from `.claude-plugin/plugin.json`
2. Check if the marketplace has a newer version available
3. If an update is available, guide the user through applying it:
   - For marketplace installs: the plugin auto-updates via the marketplace system
   - For npm installs: suggest migrating to the plugin (`/metaswarm:migrate`)
4. After update, regenerate the project's phase agents: `MA="$(command -v metaswarm-agents.sh || echo "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/bin/metaswarm-agents.sh")"; "$MA" generate` (uses `command -v metaswarm-agents.sh` — the plugin `bin/` is on PATH) (skip if the project has no `.metaswarm/models.yaml`). Exit 1 means a generated file was hand-edited; report it and use `--force` only if the user asks.
5. Verify all skills load correctly

## Notes

- Marketplace-installed plugins auto-update when Claude Code syncs plugins
- This command is primarily useful for checking the current version and troubleshooting
- Replaces the old `/metaswarm-update-version` command
