# Guided Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the monolithic `npx metaswarm init` with a thin bootstrap + Claude-guided interactive setup.

**Architecture:** Thin CLI bootstrap (3 files) → `/project:metaswarm-setup` skill (detects, installs, customizes) + `/project:metaswarm-update-version` for updates.

**Tech Stack:** Node.js CLI, Claude Code skills (markdown), shell commands

---

### Task 1: Create the metaswarm-setup command

**Files:**
- Create: `commands/metaswarm-setup.md`

**Description:**
The slash command that users invoke via `/project:metaswarm-setup`. This is a command file that triggers the guided-setup skill. It should:
- Check if metaswarm components are installed (`.claude/plugins/metaswarm/` exists)
- If not, run `npx metaswarm install` to copy all components
- Run project detection (scan for language/framework/test/lint/CI marker files)
- Present detection results to user
- Ask targeted questions using AskUserQuestion (coverage thresholds, external tools, visual review, CI, hooks)
- Customize CLAUDE.md (fill TODO sections), .coverage-thresholds.json (enforcement command), .gitignore (language ignores)
- Write `.metaswarm/project-profile.json` with detection results and user choices
- Run health checks and suggest first task

The command should be comprehensive enough to stand alone (no separate SKILL.md needed — the command IS the skill).

**Key detection logic to include:**

```
Language detection:
  package.json → node
  tsconfig.json → typescript (refines node)
  pyproject.toml OR setup.py OR requirements.txt → python
  go.mod → go
  Cargo.toml → rust
  pom.xml OR build.gradle → java
  Gemfile → ruby

Package manager (Node.js):
  pnpm-lock.yaml → pnpm
  yarn.lock → yarn
  bun.lockb → bun
  package-lock.json → npm (default)

Test runner:
  vitest in devDeps OR vitest.config.* → vitest
  jest in devDeps OR jest.config.* → jest
  pytest in deps OR [tool.pytest] → pytest
  go.mod + *_test.go → go test
  Cargo.toml → cargo test

Linter:
  .eslintrc* OR eslint.config.* → eslint
  biome.json → biome
  [tool.ruff] OR ruff.toml → ruff
  .golangci.yml → golangci-lint

Formatter:
  .prettierrc* → prettier
  biome.json → biome
  black in deps → black

CI:
  .github/workflows/ → github-actions
  .gitlab-ci.yml → gitlab-ci

Hooks:
  .husky/ → husky
  .pre-commit-config.yaml → pre-commit
```

**Customization mapping:**

For CLAUDE.md TODO sections:
- Test command: map test runner + package manager → command
- Coverage command: map test runner + package manager → coverage command
- Code quality line: map language → appropriate description
- Lint/format tools line: map detected tools → description

For .coverage-thresholds.json:
- enforcement.command: map test runner + package manager → coverage command

For .gitignore (append missing entries):
- node: node_modules/, dist/, .next/, .nuxt/
- python: __pycache__/, *.pyc, .venv/, *.egg-info/
- go: vendor/ (if vendoring)
- rust: target/
- java: build/, .gradle/, target/

---

### Task 2: Create the metaswarm-update-version command

**Files:**
- Create: `commands/metaswarm-update-version.md`

**Description:**
The slash command for updating metaswarm to the latest version. It should:
1. Read `.metaswarm/project-profile.json` for current version
2. Run `npx metaswarm@latest install` to refresh all component files
3. Read the CHANGELOG from the package to show what's new
4. Preserve user customizations (never overwrite CLAUDE.md body, .coverage-thresholds.json if user modified enforcement.command, etc.)
5. Re-run project detection if profile is stale
6. Update project-profile.json with new version and timestamp
7. Report summary of what changed

---

### Task 3: Refactor cli/metaswarm.js — split init and install

**Files:**
- Modify: `cli/metaswarm.js`

**Description:**
Refactor the CLI to have two subcommands:

**`metaswarm init`** (thin bootstrap):
- Copy `commands/metaswarm-setup.md` → `.claude/commands/metaswarm-setup.md`
- Copy `commands/metaswarm-update-version.md` → `.claude/commands/metaswarm-update-version.md`
- Handle CLAUDE.md: if none exists, create minimal one that mentions metaswarm-setup; if exists without marker, ask to append a reference to `/project:metaswarm-setup`
- Print: "metaswarm bootstrapped. Open Claude Code and run: /project:metaswarm-setup"
- Support `--full` flag that runs init + install (legacy behavior for CI/scripting)

**`metaswarm install`** (the file copier):
- Move all current init file-copying logic here
- Copy all component groups: agents, skills, rubrics, guides, commands, knowledge, scripts, bin, templates
- Copy ORCHESTRATION.md → SKILL.md
- Generate plugin.json
- chmod +x bin/*.sh
- Handle .coverage-thresholds.json, .gitignore, .env.example, SERVICE-INVENTORY.md, external-tools.yaml, CI workflow
- Run bd init if available
- Support `--with-husky` flag

**`metaswarm --help`** — updated to show both commands.

The `install` command should be idempotent (skip existing files, same as current behavior).

---

### Task 4: Update templates/CLAUDE.md for new commands

**Files:**
- Modify: `templates/CLAUDE.md`
- Modify: `templates/CLAUDE-append.md` (if it exists)

**Description:**
- Add `/project:metaswarm-setup` and `/project:metaswarm-update-version` to the commands table
- Add a note at the top: "This project uses metaswarm. Run /project:metaswarm-setup to configure for your project."
- The TODO sections should remain (the setup skill fills them in)

---

### Task 5: Update documentation (README, INSTALL, GETTING_STARTED)

**Files:**
- Modify: `README.md`
- Modify: `INSTALL.md`
- Modify: `GETTING_STARTED.md`

**Description:**

**README.md** — Update the Install section:
- Primary path: "Open Claude Code in your project and run `/project:metaswarm-setup`" (if already bootstrapped) or "Run `npx metaswarm init` then `/project:metaswarm-setup`"
- The "That's it" paragraph should emphasize Claude walks you through everything
- Keep `npx metaswarm init --full` as alternative for CI/scripting

**INSTALL.md** — Restructure:
- "Recommended: Claude-Guided Setup" as primary section
- "Manual Installation" (npx metaswarm init --full) as secondary
- "Updating" section referencing /project:metaswarm-update-version
- Remove or simplify the long manual customization matrix (the skill handles this now)

**GETTING_STARTED.md** — Rewrite quickstart:
- Step 1: `npx metaswarm init`
- Step 2: Open Claude Code, run `/project:metaswarm-setup`
- Step 3: Claude detects your project and configures everything
- Step 4: Run `/project:start-task` on your first task

---

### Task 6: Update CHANGELOG and commit

**Files:**
- Modify: `CHANGELOG.md`

**Description:**
Add v0.7.0 entry:
- Claude-guided installation (`/project:metaswarm-setup`)
- Self-update command (`/project:metaswarm-update-version`)
- Thin bootstrap (npx metaswarm init copies 3 files, not 60+)
- Project detection (language, framework, test runner, linter, CI, package manager)
- Auto-customization of CLAUDE.md, coverage thresholds, .gitignore
- Project profile (.metaswarm/project-profile.json)
- `npx metaswarm install` as separate command
- `--full` flag preserves legacy behavior

---
