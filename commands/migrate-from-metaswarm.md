# Migrate from Metaswarm

Upgrade a metaswarm project to Tribunal. Converts config files and renames directories.

## Usage

/migrate-from-metaswarm

## Behavior

1. Read `.coverage-thresholds.json` → extract coverage thresholds and enforcement settings
2. Read `.metaswarm/external-tools.yaml` → flag for manual review
3. Generate `tribunal.yaml` with migrated values + new defaults (debate, agent_selection, escalation)
4. Rename `.metaswarm/` → `.tribunal/`
5. Report what changed

## What Gets Migrated

| Source | Destination |
|--------|-------------|
| `.coverage-thresholds.json` → `thresholds` | `tribunal.yaml` → `common.coverage` |
| `.coverage-thresholds.json` → `enforcement` | `tribunal.yaml` → `common.enforcement` |
| `.metaswarm/project-profile.json` | `.tribunal/project-profile.json` (renamed) |
| `.metaswarm/external-tools.yaml` | Flagged as TODO in tribunal.yaml |

## What Needs Manual Review

- External tools adapter config should be reviewed and moved into tool-specific sections
- CLAUDE.md, AGENTS.md, GEMINI.md references (verify after migration)

## Related

- `/setup` — set up a new Tribunal project from scratch
- `config` skill — how tribunal.yaml resolution works
