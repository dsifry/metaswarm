# Update Metaswarm (deprecated alias)

`/metaswarm-update-version` is a deprecated alias left over from the npm-era install. Use `/update` instead. It checks for a newer plugin version, regenerates the project's phase agents and verifies that skills load.

## Usage

```text
/metaswarm-update-version   # deprecated: use /update
```

## Behavior

1. Tell the user once that `/metaswarm-update-version` is deprecated and that `/update` replaces it.
2. Ask the user to run `/update` (in plugin installs: `/metaswarm:update`), then stop. Don't try to reproduce the update steps here.
