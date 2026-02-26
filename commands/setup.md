# Setup

Interactive project setup for metaswarm. Detects your project, configures metaswarm, and writes project-local files.

## Usage

```text
/setup
```

## Behavior

Invokes the `metaswarm:setup` skill, which:

1. Detects your project's language, framework, test runner, and tools
2. Asks 3-5 configuration questions (coverage threshold, external tools, CI, etc.)
3. Writes project-local files (CLAUDE.md, coverage config, knowledge base, scripts)
4. Creates command shims for high-frequency commands
5. Generates `.metaswarm/project-profile.json` with your configuration

This replaces the old `npx metaswarm init` workflow. No Node.js required.

## Related

- `/metaswarm:status` — check current setup state
- `/metaswarm:migrate` — migrate from npm-installed metaswarm
