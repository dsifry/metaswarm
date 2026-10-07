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
4. After update, verify all skills load correctly

## Notes

- Marketplace-installed plugins auto-update when Claude Code syncs plugins
- This command is primarily useful for checking the current version and troubleshooting
- Replaces the old `/metaswarm-update-version` command
