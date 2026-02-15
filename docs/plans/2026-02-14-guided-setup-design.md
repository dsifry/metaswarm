# Claude-Guided Installation Experience — Design Document

> **Status**: Approved
> **Date**: 2026-02-14

## Problem

`npx metaswarm init` copies 60+ files, then leaves users with a 30-60 minute gap of manual customization — editing CLAUDE.md TODOs, fixing coverage commands for their language, adapting TypeScript-centric agent configs, setting up external tools, and reading 700+ lines of docs.

## Solution

Split installation into a **thin CLI bootstrap** and a **Claude-driven interactive setup skill**.

### Architecture

```
Path A (CLI-first):                    Path B (Claude-first):
npx metaswarm init                     User tells Claude: "Set up metaswarm"
  └── copies 3 files                     └── Claude invokes /project:metaswarm-setup
  └── prints: "Run /project:metaswarm-setup"   └── checks if init was run
                                                └── runs npx metaswarm install if needed
Both paths converge:
/project:metaswarm-setup
  └── detects project context (language, framework, test runner, etc.)
  └── presents findings to user
  └── asks 3-5 targeted questions
  └── installs components via npx metaswarm install
  └── customizes all templates for detected stack
  └── writes .metaswarm/project-profile.json
  └── runs health checks, suggests first task
```

### CLI Commands

#### `npx metaswarm init` (the thin bootstrapper)

Copies ONLY:
- `.claude/commands/metaswarm-setup.md`
- `.claude/commands/metaswarm-update-version.md`
- Minimal CLAUDE.md entry (create or append) pointing to `/project:metaswarm-setup`

Prints:
```
metaswarm bootstrapped.
Open Claude Code and run: /project:metaswarm-setup
```

#### `npx metaswarm install` (the file copier)

Called by the setup skill (or directly by users). Copies all component groups:
- agents, skills, rubrics, guides, commands, knowledge, scripts, bin, templates
- ORCHESTRATION.md → SKILL.md
- plugin.json generation
- chmod +x bin/*.sh

This is essentially the current `init` logic, minus the bootstrapper and CLAUDE.md handling.

Supports `--full` flag for legacy behavior (init + install in one step).

### Skill: `/project:metaswarm-setup`

**Phase 1: Bootstrap Check**
- Check for `.claude/plugins/metaswarm/` — if missing, run `npx metaswarm install`
- Check for `.metaswarm/project-profile.json` — if exists, offer re-setup or skip

**Phase 2: Project Detection** (automatic, no questions asked)
- Language: `package.json` → Node.js, `pyproject.toml` → Python, `go.mod` → Go, `Cargo.toml` → Rust, etc.
- Framework: parse dependencies (next → Next.js, fastapi → FastAPI, etc.)
- Test runner: vitest.config.*, jest.config.*, pytest in deps, go test, cargo test
- Linter: .eslintrc*, ruff.toml, .golangci.yml, clippy
- Formatter: .prettierrc*, biome.json, black, rustfmt
- Package manager: pnpm-lock.yaml → pnpm, yarn.lock → yarn, package-lock.json → npm
- Type checker: tsconfig.json → tsc, mypy in deps, go vet, cargo check
- CI: .github/workflows/ → GitHub Actions, .gitlab-ci.yml → GitLab CI
- Git hooks: .husky/ → Husky, .pre-commit-config.yaml → pre-commit
- Present: "I detected a TypeScript/Next.js project using Vitest, pnpm, ESLint + Prettier"

**Phase 3: Targeted Questions** (3-5 questions max, based on what's detected)
- Coverage thresholds: "Default is 100% — want to start lower?"
- External tools: "Want to set up Codex/Gemini for cost savings?" → guide install
- Visual review: "Your project has a web UI — enable screenshot review?"
- CI: "No CI pipeline detected — create one for GitHub Actions?"
- Hooks: "No git hooks detected — want pre-push quality checks?"
- BEADS: "Want BEADS task tracking? (requires bd CLI)"

**Phase 4: Customize** (automatic, based on detection + answers)
- CLAUDE.md: fill in TODO sections with detected test/lint/coverage/language commands
- .coverage-thresholds.json: set enforcement.command for detected test runner
- .gitignore: add language-appropriate ignores if missing entries
- Agent configs: note detected language in project context for agents
- External tools: run install + auth flow if requested
- Write `.metaswarm/project-profile.json`

**Phase 5: Verify & First Task**
- Run health checks (external tools if enabled)
- Show summary of what was installed and customized
- Suggest: "Try /project:start-task on a small bug or feature"

### Command: `/project:metaswarm-update-version`

1. Read `.metaswarm/project-profile.json` for current version
2. Run `npx metaswarm@latest install` to refresh all files
3. Show what changed (new skills, updated agents, etc.)
4. Re-run detection if project has evolved
5. Update project profile with new version
6. Preserve user customizations (never overwrite CLAUDE.md customizations, etc.)

### Project Profile (`.metaswarm/project-profile.json`)

```json
{
  "metaswarm_version": "0.7.0",
  "installed_at": "2026-02-14T23:45:00Z",
  "updated_at": "2026-02-14T23:45:00Z",
  "detection": {
    "language": "typescript",
    "framework": "nextjs",
    "test_runner": "vitest",
    "linter": "eslint",
    "formatter": "prettier",
    "package_manager": "pnpm",
    "type_checker": "tsc",
    "ci": "github-actions",
    "git_hooks": "husky"
  },
  "choices": {
    "coverage_threshold": 100,
    "external_tools": true,
    "visual_review": true,
    "beads": true
  },
  "commands": {
    "test": "pnpm vitest run",
    "coverage": "pnpm vitest run --coverage",
    "lint": "pnpm eslint .",
    "typecheck": "pnpm tsc --noEmit",
    "format_check": "pnpm prettier --check ."
  }
}
```

### Documentation Changes

- **README.md**: Change install section to recommend "tell Claude: set up metaswarm"
- **INSTALL.md**: Restructure around guided flow, keep npx as "Manual/CI Installation"
- **GETTING_STARTED.md**: Rewrite quickstart around `/project:metaswarm-setup`
- **templates/CLAUDE.md**: Add `/project:metaswarm-setup` and `/project:metaswarm-update-version`

### What Does NOT Change

- All existing skills, agents, rubrics, guides remain as-is
- `npx metaswarm init --full` preserves current behavior for CI/scripting
- File-level idempotency (skip if exists) preserved in install command

## Design Decisions

1. **Skill, not CLI** — Intelligence lives in Claude, not bash/node. Claude understands project context better than any script.
2. **Thin bootstrap** — Init copies only what's needed to invoke Claude. Everything else is pulled by the skill.
3. **Separate install command** — The heavy file-copying is a distinct CLI command the skill invokes programmatically.
4. **Project profile** — Single source of truth for detection results, user choices, and version tracking.
5. **Namespaced commands** — `/project:metaswarm-setup` and `/project:metaswarm-update-version` avoid collision with other projects' commands.
6. **No language-conditional templates** — We keep one set of templates and customize post-copy. Simpler than maintaining N template variants.
