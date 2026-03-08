# Setup

Interactive project setup for tribunal. Detects your project, configures tribunal, and writes project-local files.

## Usage

```text
/setup
```

## Behavior

Invokes the `tribunal:setup` skill, which:

1. Detects your project's language, framework, test runner, and tools
2. Asks 3-5 configuration questions (coverage threshold, external tools, CI, etc.)
3. Writes project-local files (CLAUDE.md, coverage config, knowledge base, scripts)
4. Creates command shims for high-frequency commands
5. Generates `.tribunal/project-profile.json` with your configuration

This replaces the old `npx tribunal init` workflow. No Node.js required.

## Related

- `/tribunal:status` — check current setup state
- `/tribunal:migrate` — migrate from npm-installed tribunal
