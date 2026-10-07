---
description: Interactive project setup — detects your project, configures metaswarm, writes project-local files
---

# Setup

Interactive setup for metaswarm in OpenCode. Detects your project stack, asks targeted questions, and writes project-local files including instructions, coverage configuration, and command definitions.

## When to Use

Run `/setup` when:

- Setting up metaswarm for the first time in your OpenCode project
- Re-configuring metaswarm (coverage thresholds, optional features)
- Switching to a different test runner or coverage tool

## How It Works

The setup process has three phases:

1. **Project Detection** — scans your project to detect language, framework, test runner, linter, formatter, CI, and git hooks
2. **Interactive Questions** — asks about coverage threshold and optional features based on your stack
3. **File Generation** — creates `.opencode/OPENCODE.md` with instructions, `.coverage-thresholds.json` with your chosen thresholds, and project-local configuration

## What Gets Created

After setup completes, your project will have:

- **`.opencode/OPENCODE.md`** — project instructions explaining how to use metaswarm with your stack
- **`.coverage-thresholds.json`** — test coverage requirements (100% recommended, configurable)
- **`.metaswarm/project-profile.json`** — your detected stack and configuration choices

## Running Setup

### Basic Setup

```bash
/setup
```

The skill will:
1. Detect your project automatically
2. Present findings and ask for confirmation
3. Ask about coverage threshold
4. Ask about optional features (external AI tools, visual review, CI, git hooks)
5. Write all necessary files

### Re-running Setup

If you've already run setup and want to reconfigure:

```bash
/setup
```

It will detect your existing `.metaswarm/project-profile.json` and ask if you want to re-run (overwriting previous choices) or skip.

## Coverage Threshold

You'll be asked to choose a coverage threshold:

- **100% (Recommended)** — All lines, branches, functions, and statements must be covered by tests. Enforced before PR creation.
- **80%** — 80% coverage required. Useful for less mature projects.
- **60%** — 60% coverage required. For legacy codebases.
- **Custom** — Specify your own percentage.

The setup will determine the appropriate test command for your runner:

- **pytest** (Python): `pytest --cov --cov-fail-under=<threshold>`
- **vitest/pnpm** (Node.js): `pnpm vitest run --coverage`
- **jest/npm** (Node.js): `npx jest --coverage`
- **go** (Go): `go test -coverprofile=coverage.out ./...`
- **cargo** (Rust): `cargo tarpaulin --fail-under <threshold>`

## Optional Features

### External AI Tools

If you want to delegate implementation and review tasks to external AI models (Codex or Gemini) for cost savings:

- Choose "Yes" during setup
- Configure credentials via `opencode auth`
- Setup will create `.metaswarm/external-tools.yaml` with routing rules

### Visual Review

If your project is a web app (detected frameworks: Next.js, Nuxt, React, Vue, Angular, SvelteKit, Django, Flask):

- Choose "Yes" to enable screenshot-based UI review
- Requires Playwright (will be documented in OPENCODE.md)

### GitHub Actions CI

If you don't have CI configured yet:

- Choose "Yes" to create a basic GitHub Actions workflow
- Pipeline will run tests, coverage checks, linting, and type checking
- Located in `.github/workflows/ci.yml`

### Git Hooks

If you don't have pre-push hooks:

- Choose "Yes" to enable Husky or Lefthook
- Prevents pushing code that fails tests or coverage gates
- Keeps CI green and catches issues locally

## Troubleshooting

### Setup script not found

If you see an error about the setup script:

- Verify you're running this from your OpenCode project root (where `.opencode/OPENCODE.md` exists)
- Ensure the metaswarm plugin is installed via `opencode plugin list`

### Detection missed my framework

If setup didn't detect your framework correctly:

- Check that you have the appropriate marker files (e.g., `package.json` for Node.js, `pyproject.toml` for Python)
- You can manually edit `.metaswarm/project-profile.json` after setup
- Re-run `/setup` to reconfigure

### Can't determine test runner

If you have multiple test runners:

- Setup will ask you to choose
- You can always edit `.coverage-thresholds.json` afterward to change the command

## Next Steps

After setup completes:

1. Read **`.opencode/OPENCODE.md`** for platform-specific instructions
2. Run **`/prime`** to load relevant knowledge before starting work
3. Run **`/start-task <description>`** to begin tracked development work
4. Run **`/review-design`** for architecture reviews of design documents

Your project is now configured for metaswarm-based development!
