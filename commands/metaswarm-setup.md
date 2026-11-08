---
description: Deprecated alias for /setup
---

# Metaswarm Setup (deprecated alias)

`/metaswarm-setup` is a deprecated alias left over from the npm-era install. Use `/setup` instead. It runs the same guided setup through the `metaswarm:setup` skill.

## Usage

```text
/metaswarm-setup   # deprecated: use /setup
```

## Behavior

1. Tell the user once that `/metaswarm-setup` is deprecated and that `/setup` replaces it.
2. Run the `/setup` flow: invoke the `metaswarm:setup` skill (`/metaswarm:setup` in plugin installs), passing along any arguments.
