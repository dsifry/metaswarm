# Design: Migrate Metaswarm from npm Package to Claude Code Plugin

**Date**: 2026-02-26
**Status**: APPROVED — passed design review gate (5/5 agents, 3 iterations)
**Author**: Human + Claude

## Problem Statement

Metaswarm is currently distributed as an npm package (`npx metaswarm init`) that copies files into the user's project. This creates three problems:

1. **Installation friction**: Users need Node.js installed even for non-Node projects (Python, Go, Rust, etc.)
2. **Stale versions**: Users run whatever version they installed. No automatic updates. Many run outdated copies.
3. **Ecosystem misalignment**: Claude Code has a mature plugin system with marketplace distribution, auto-updates, and skill discovery. Metaswarm uses it partially (files land in `.claude/plugins/metaswarm/`) but bypasses the distribution mechanism entirely.

## Goals

- **Zero Node.js dependency for install and core usage** — install and run metaswarm from within Claude Code without Node.js. Some optional features (self-reflect scripts, PR comment fetching) require Node.js and are documented as such.
- **One-command install** — `/plugin marketplace add dsifry/metaswarm-marketplace`
- **Automatic updates** — marketplace auto-updater keeps users current
- **Multi-CLI architecture** — structure supports future expansion to Codex, OpenCode, Cursor. Implementation of non-Claude spokes is future work, listed under Architecture Principles, not v1.0 deliverables.
- **Backward compatible** — existing npm-installed users can migrate or keep working

## Non-Goals

- Implementing Codex/OpenCode/Cursor spokes in this release (architecture supports it, implementation is future work)
- Changing metaswarm's orchestration logic, skills, or agent definitions
- Removing the BEADS integration
- Renaming the project-local `.beads/` directory (this stays as-is; only the skill directory `skills/beads/` is renamed to `skills/start/`)

## Critical Technical Constraint: `${CLAUDE_PLUGIN_ROOT}` Limitations

**`${CLAUDE_PLUGIN_ROOT}` only works in JSON configuration fields** (hooks.json, .mcp.json, plugin.json inline configs). It does **NOT** expand in SKILL.md markdown content or command .md files — it resolves to an empty string. This is a confirmed limitation ([GitHub Issue #9354](https://github.com/anthropics/claude-code/issues/9354)).

**How skills reference companion files**: When a skill is loaded via the Skill tool, Claude Code injects a "Base directory for this skill" header. Claude (the LLM) uses this to construct Read tool paths. Skills reference sibling files using relative paths (`./filename.md`, `code-reviewer.md`). This is the pattern used by superpowers and beads plugins.

**Implication**: Rubrics, guides, and agent definitions that skills reference MUST be co-located within the skill directories that use them, not in separate top-level directories. Top-level `rubrics/` and `guides/` directories exist in the plugin for auto-discovery by Claude Code's plugin loader, but skills cannot programmatically reference files outside their own directory.

## Architecture: Hub-and-Spoke Model

Adopting the same pattern as the superpowers plugin: **shared skills written in Claude Code dialect, per-CLI integration shims**.

### Hub (shared across all CLIs)

| Component | Purpose | Count |
|-----------|---------|-------|
| `skills/` | Orchestration skills with co-located resources | 13 (10 existing + setup + migrate + status) |
| `rubrics/` | Quality review rubrics (plugin auto-discovery) | 8 |
| `guides/` | Development pattern guides (plugin auto-discovery) | 6 |
| `templates/` | Project scaffolding templates | ~20 |
| `knowledge/` | Knowledge base JSONL templates | 7 |
| `bin/` | Shell utilities (copied to projects during setup) | 4 |
| `scripts/` | TS automation scripts (copied to projects during setup, requires Node.js) | 3 |
| `lib/` | Shared utilities (skill discovery, parsing) | TBD |

### Spokes (per-CLI integration)

| Directory | CLI | Contents | Status |
|-----------|-----|----------|--------|
| `.claude-plugin/` | Claude Code | `plugin.json`, `marketplace.json` | v1.0 (this release) |
| `.cursor-plugin/` | Cursor | `plugin.json` with explicit paths | Future |
| `.codex/` | Codex CLI | `INSTALL.md` (symlink instructions) | Future |
| `.opencode/` | OpenCode | `INSTALL.md`, `plugins/metaswarm.js` | Future |
| `commands/` | Claude Code + Cursor | 11 slash commands | v1.0 |
| `hooks/` | Claude Code + Cursor | SessionStart + PreCompact hooks | v1.0 |

### Tool Mapping (for future non-Claude CLIs)

```
skills/start/references/
├── codex-tools.md        # Task → spawn_agent, Skill → native skills
├── opencode-tools.md     # Task → @mention, Skill → skill tool
└── cursor-tools.md       # Mostly identical to Claude Code
```

Skills include a note: "This skill uses Claude Code tool names. Non-Claude Code platforms: see `references/<platform>-tools.md` for equivalents."

## Path Resolution Strategy

### The Problem

Skills currently hardcode paths like `.claude/rubrics/adversarial-review-rubric.md` and `guides/agent-coordination.md`. After migration, these files live in the plugin cache, not the project directory.

### Inventory of Broken Paths (13+ references)

| Category | File | Reference | Count |
|----------|------|-----------|-------|
| Rubrics | `plan-review-gate/SKILL.md` | `.claude/rubrics/plan-review-rubric-adversarial.md` | 4 |
| Rubrics | `orchestrated-execution/SKILL.md` | `.claude/rubrics/adversarial-review-rubric.md` | 1 |
| Rubrics | `external-tools/SKILL.md` | `.claude/rubrics/external-tool-review-rubric.md` | 1 |
| Guides | `orchestrated-execution/SKILL.md` | `guides/agent-coordination.md` | 1 |
| Guides | `design-review-gate/SKILL.md` | `guides/agent-coordination.md` | 1 |
| Guides | `pr-shepherd/SKILL.md` | `guides/agent-coordination.md` | 1 |
| Guides | `ORCHESTRATION.md` | `guides/agent-coordination.md` | 1 |
| Agents | `ORCHESTRATION.md` | `.claude/plugins/your-project/skills/beads/agents/` | 1 |
| Plugins | `metaswarm-setup.md` | `.claude/plugins/metaswarm/` | 2 |
| Commands | `handling-pr-comments/SKILL.md` | `.claude/commands/handle-pr-comments.md` | 1 |
| Commands | `create-issue/SKILL.md` | `.claude/commands/handle-pr-comments.md` | 1 |

### The Solution: Co-locate Resources with Skills

Following the pattern established by superpowers (`requesting-code-review/code-reviewer.md`) and beads (`skills/beads/resources/`):

1. **Rubrics** → copy into the skill directories that reference them:
   - `skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md`
   - `skills/orchestrated-execution/rubrics/adversarial-review-rubric.md`
   - `skills/external-tools/rubrics/external-tool-review-rubric.md`

2. **Guides** → copy `agent-coordination.md` into skills that reference it:
   - `skills/orchestrated-execution/guides/agent-coordination.md`
   - `skills/design-review-gate/guides/agent-coordination.md`
   - `skills/pr-shepherd/guides/agent-coordination.md`
   - `skills/start/guides/agent-coordination.md`

3. **Agent definitions** → stay under `skills/start/agents/` (the main orchestration skill). References updated from `.claude/plugins/your-project/skills/beads/agents/` to `./agents/`.

4. **Top-level directories kept** for plugin auto-discovery: `rubrics/`, `guides/` remain at plugin root so Claude Code's plugin loader can discover them. The co-located copies in skill dirs are for explicit skill references.

5. **Update all skill path references** to use relative `./` paths (e.g., `Read and follow: ./rubrics/adversarial-review-rubric.md`). Claude resolves these using the skill's base directory.

**Trade-off**: This duplicates some files (agent-coordination.md appears in 4 skill dirs, templates appear in both top-level and `skills/setup/`). The total duplication is modest (~100KB) and eliminates the path resolution fragility entirely. The `lib/sync-resources.js` build script syncs co-located copies from authoritative top-level sources, and CI validates no drift on every push.

## Repository Structure

### Plugin Repo (`dsifry/metaswarm`)

```
metaswarm/
├── .claude-plugin/
│   └── plugin.json
├── .cursor-plugin/              # Future
│   └── plugin.json
├── .codex/                      # Future
│   └── INSTALL.md
├── .opencode/                   # Future
│   ├── INSTALL.md
│   └── plugins/metaswarm.js
├── skills/
│   ├── start/                   # Main entry point (renamed from beads/)
│   │   ├── SKILL.md             # Orchestration brain (was ORCHESTRATION.md)
│   │   ├── agents/              # 18 agent definitions
│   │   ├── guides/              # Co-located: agent-coordination.md
│   │   └── references/          # Per-CLI tool mappings (future)
│   ├── orchestrated-execution/
│   │   ├── SKILL.md
│   │   ├── rubrics/             # Co-located: adversarial-review-rubric.md
│   │   └── guides/              # Co-located: agent-coordination.md
│   ├── design-review-gate/
│   │   ├── SKILL.md
│   │   └── guides/              # Co-located: agent-coordination.md
│   ├── plan-review-gate/
│   │   ├── SKILL.md
│   │   └── rubrics/             # Co-located: plan-review-rubric-adversarial.md
│   ├── setup/                   # NEW — replaces npx metaswarm init
│   │   ├── SKILL.md
│   │   ├── templates/           # Co-located: all project scaffolding templates
│   │   ├── knowledge/           # Co-located: JSONL templates
│   │   ├── bin/                 # Co-located: shell utilities
│   │   └── scripts/             # Co-located: TS automation scripts
│   ├── migrate/                 # NEW — npm-to-plugin migration
│   │   └── SKILL.md
│   ├── status/                  # NEW — diagnostic command
│   │   └── SKILL.md
│   ├── pr-shepherd/
│   │   ├── SKILL.md
│   │   └── guides/              # Co-located: agent-coordination.md
│   ├── handling-pr-comments/
│   │   └── SKILL.md
│   ├── brainstorming-extension/
│   │   └── SKILL.md
│   ├── create-issue/
│   │   └── SKILL.md
│   ├── external-tools/
│   │   ├── SKILL.md
│   │   ├── rubrics/             # Co-located: external-tool-review-rubric.md
│   │   └── adapters/
│   └── visual-review/
│       └── SKILL.md
├── commands/
│   ├── start-task.md            # Canonical entry point
│   ├── prime.md
│   ├── review-design.md
│   ├── self-reflect.md
│   ├── pr-shepherd.md
│   ├── handle-pr-comments.md
│   ├── create-issue.md
│   ├── brainstorm.md            # Wraps brainstorming-extension skill
│   ├── external-tools-health.md # External tools health check
│   ├── setup.md
│   └── update.md
├── hooks/
│   ├── hooks.json
│   └── session-start.sh
├── rubrics/                     # Authoritative copies (plugin auto-discovery)
│   ├── code-review-rubric.md
│   ├── adversarial-review-rubric.md
│   ├── plan-review-rubric.md
│   ├── plan-review-rubric-adversarial.md
│   ├── architecture-rubric.md
│   ├── security-review-rubric.md
│   ├── test-coverage-rubric.md
│   └── external-tool-review-rubric.md
├── guides/                      # Authoritative copies (plugin auto-discovery)
│   ├── agent-coordination.md
│   ├── git-workflow.md
│   ├── testing-patterns.md
│   ├── coding-standards.md
│   ├── worktree-development.md
│   └── build-validation.md
├── templates/
│   ├── CLAUDE.md
│   ├── CLAUDE-append.md
│   ├── coverage-thresholds.json
│   ├── ci.yml                   # REVISED: no eval, safe command execution
│   ├── gitignore
│   ├── pre-push
│   ├── external-tools.yaml
│   ├── .env.example
│   ├── SERVICE-INVENTORY.md
│   └── ...
├── knowledge/
│   ├── patterns.jsonl
│   ├── gotchas.jsonl
│   ├── decisions.jsonl
│   ├── api-behaviors.jsonl
│   ├── codebase-facts.jsonl
│   ├── anti-patterns.jsonl
│   └── facts.jsonl
├── bin/
│   ├── estimate-cost.sh         # REVISED: safe awk variable passing
│   ├── external-tools-verify.sh
│   ├── pr-comments-check.sh
│   └── pr-comments-filter.sh
├── scripts/
│   ├── beads-self-reflect.ts    # NOTE: Requires Node.js (tsx)
│   ├── beads-fetch-pr-comments.ts
│   └── beads-fetch-conversation-history.ts
├── lib/
│   ├── skills-core.js
│   └── sync-resources.js        # Build script to sync co-located copies from authoritative sources
└── docs/
    ├── README.codex.md          # Future
    └── README.opencode.md       # Future
```

### Marketplace Repo (`dsifry/metaswarm-marketplace`)

```
metaswarm-marketplace/
└── .claude-plugin/
    └── marketplace.json
```

The marketplace repo is lightweight — just the manifest pointing to the plugin repo via git URL. No submodules needed.

```json
{
  "name": "metaswarm-marketplace",
  "owner": {
    "name": "David Sifry",
    "email": "david@sifry.com"
  },
  "metadata": {
    "description": "Multi-agent orchestration framework for Claude Code",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "metaswarm",
      "source": {
        "source": "url",
        "url": "https://github.com/dsifry/metaswarm.git",
        "ref": "v1.0.0"
      },
      "description": "18-agent orchestration with quality gates, TDD enforcement, and knowledge capture",
      "version": "1.0.0",
      "strict": true,
      "category": "productivity",
      "keywords": ["orchestration", "agents", "tdd", "quality-gates"]
    }
  ]
}
```

**Release process**: When metaswarm tags a new release (e.g., `v1.1.0`), update the marketplace.json `ref` and `version` fields and push. A CI workflow in the marketplace repo can automate this on tag events in the plugin repo.

**Install command**: `/plugin marketplace add dsifry/metaswarm-marketplace`

## plugin.json Specification

```json
{
  "name": "metaswarm",
  "version": "1.0.0",
  "description": "Multi-agent orchestration framework for Claude Code — 18 agents, 9-phase workflow, quality gates, TDD enforcement",
  "author": {
    "name": "David Sifry",
    "email": "david@sifry.com"
  },
  "homepage": "https://github.com/dsifry/metaswarm",
  "repository": "https://github.com/dsifry/metaswarm",
  "license": "MIT",
  "keywords": ["orchestration", "agents", "tdd", "quality-gates", "beads"]
}
```

**Component discovery**: Claude Code auto-discovers components in default directories:
- `skills/*/SKILL.md` — all 13 skills auto-discovered
- `commands/*.md` — all 11 commands auto-discovered
- `hooks/hooks.json` — hooks auto-loaded
- `rubrics/*.md` — all 8 rubrics auto-discovered
- `guides/*.md` — all 6 guides auto-discovered

No explicit `skills`, `commands`, or `hooks` arrays needed in `plugin.json` when using default directory conventions. This was validated against the superpowers plugin, which also omits explicit skill listings.

## Command Namespace Strategy

### Dual-path entry point (simplified from original 5-path)

| User types | Resolves to | Mechanism |
|---|---|---|
| "use metaswarm to..." | `/metaswarm:start-task` | Auto-invoked via `start` skill description match |
| `/start-task` | `/metaswarm:start-task` | Project-local shim (backward compat, canonical short form) |
| `/metaswarm:start-task` | start-task flow | Direct plugin command (canonical namespaced form) |

**Canonical form**: `/start-task` (short, matches existing muscle memory)
**Namespaced form**: `/metaswarm:start-task` (explicit, used in documentation)
**Natural language**: "use metaswarm to..." (auto-invoked, unavoidable)

The `skills/start/SKILL.md` has description: "Use when starting work on any task, when the user mentions metaswarm, or when the user wants to begin tracked development work." This triggers auto-invocation on natural language mentions.

**Eliminated**: `/metaswarm:metaswarm` (stuttering anti-pattern) and `/metaswarm` shim (redundant with `/start-task`).

### Plugin commands (always available after install)

| Command | Purpose |
|---|---|
| `/metaswarm:start-task` | Begin tracked work with complexity assessment |
| `/metaswarm:prime` | Load knowledge base into context |
| `/metaswarm:review-design` | Trigger 5-agent design review gate |
| `/metaswarm:self-reflect` | Extract learnings after PR merge |
| `/metaswarm:pr-shepherd` | Monitor PR through to merge |
| `/metaswarm:handle-pr-comments` | Handle PR review comments |
| `/metaswarm:create-issue` | Create well-structured GitHub Issue |
| `/metaswarm:brainstorm` | Brainstorming extension (wraps superpowers:brainstorming) |
| `/metaswarm:external-tools-health` | Check external AI tools status |
| `/metaswarm:setup` | Interactive project setup (replaces npx metaswarm init) |
| `/metaswarm:update` | Check for and apply updates |

### Project-local shims (created by `/metaswarm:setup`)

6 thin `.claude/commands/` files for high-frequency commands. Each shim includes a comment explaining its purpose:

```markdown
<!-- Created by metaswarm setup. Routes to the metaswarm plugin. Safe to delete if you uninstall metaswarm. -->
```

| Shim | Routes to | Why shimmed |
|---|---|---|
| `/start-task` | `/metaswarm:start-task` | Primary entry point, referenced in CLAUDE.md |
| `/prime` | `/metaswarm:prime` | Used in every session, referenced in workflow rules |
| `/review-design` | `/metaswarm:review-design` | Referenced in CLAUDE.md workflow enforcement |
| `/self-reflect` | `/metaswarm:self-reflect` | Referenced in CLAUDE.md workflow enforcement |
| `/pr-shepherd` | `/metaswarm:pr-shepherd` | High frequency for PR workflows |
| `/brainstorm` | `/metaswarm:brainstorm` | High frequency, referenced in CLAUDE.md |

**Selection criteria**: Shimmed commands are those referenced in CLAUDE.md workflow enforcement rules or invoked 10+ times per week in typical usage.

**Not shimmed** (lower frequency, explicit namespace): `/metaswarm:setup`, `/metaswarm:update`, `/metaswarm:handle-pr-comments`, `/metaswarm:create-issue`, `/metaswarm:external-tools-health`, `/metaswarm:status`.

**Brainstorming interaction**: `/metaswarm:brainstorm` wraps `superpowers:brainstorming` with metaswarm's extension (design review gate handoff). If superpowers is not installed, the command provides standalone brainstorming. The shim `/brainstorm` routes to `/metaswarm:brainstorm`, not directly to superpowers.

## SessionStart Hook

### hooks/hooks.json

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": false
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": false
          }
        ]
      }
    ]
  }
}
```

**PreCompact hook added** (matching BEADS plugin pattern) to re-inject context before compaction clears it.

### hooks/session-start.sh

Four-phase detection:

1. **BEADS dedup check** — if standalone BEADS plugin is also installed, skip `bd prime` (let BEADS handle it). Detection is robust: check if `~/.claude/plugins/cache/` contains a directory matching `*/beads/*/` AND that directory contains a `.claude-plugin/plugin.json` with `"name": "beads"`. Simple directory existence is not sufficient (prevents spoofing).

2. **New project detection** — check if `.metaswarm/project-profile.json` exists in CWD. If not, inject nudge: "Metaswarm is installed but this project hasn't been set up yet. Run `/metaswarm:setup` to configure it, or `/metaswarm:start-task` to begin working."

3. **Legacy install detection** — check if `.claude/plugins/metaswarm/.claude-plugin/plugin.json` exists as a project-embedded plugin (old npm install). If found, inject migration message: "This project has metaswarm installed via the old npm method. Run `/metaswarm:migrate` to switch to the marketplace plugin for automatic updates."

4. **Knowledge priming** — if project IS set up and BEADS plugin is NOT separately priming, run `bd prime` (if `bd` is available) to load knowledge base.

## Setup Skill (`/metaswarm:setup`)

Replaces both `npx metaswarm init` and the old `/metaswarm-setup` command. Runs entirely inside Claude Code using standard tools.

### What it does

1. **Project detection** — scans for package.json, pyproject.toml, Cargo.toml, go.mod, etc. Determines language, framework, test runner, linter, formatter, CI, git hooks. Handles the "no language detected" case by asking the user to specify manually.

2. **Interactive questions** — 3-5 targeted questions via AskUserQuestion:
   - Coverage threshold (default 100%)
   - Enable external tools (Codex/Gemini)?
   - Enable visual review (Playwright)?
   - Set up CI pipeline?
   - Configure git hooks?

3. **Writes project-local files**:

The setup skill has all templates, knowledge bases, bin scripts, and TS scripts co-located within its own directory (following the same co-location principle used throughout the design). It reads them using `./` relative paths from its base directory.

| File | Source (relative to skill base dir) | Notes |
|---|---|---|
| `CLAUDE.md` | `./templates/CLAUDE.md` | Customized with detected project info |
| `.coverage-thresholds.json` | `./templates/coverage-thresholds.json` | Threshold from user's answer |
| `.metaswarm/project-profile.json` | Generated | Detection results + choices |
| `.metaswarm/external-tools.yaml` | `./templates/external-tools.yaml` | If external tools enabled |
| `.beads/knowledge/*.jsonl` | `./knowledge/` | Empty knowledge base templates |
| `bin/*.sh` | `./bin/` | Shell utilities |
| `scripts/*.ts` | `./scripts/` | Automation scripts (requires Node.js) |
| `.github/workflows/ci.yml` | `./templates/ci.yml` | If CI enabled |
| `.husky/pre-push` | `./templates/pre-push` | If Husky detected |
| `.claude/commands/*.md` | Generated shims | 6 command shims (see namespace section) |

4. **Does NOT copy** skills, agents, rubrics, or guides — those load directly from the plugin cache.

### Template access mechanism

The setup skill co-locates all templates within its own directory (`skills/setup/templates/`, `skills/setup/knowledge/`, `skills/setup/bin/`, `skills/setup/scripts/`). This follows the same co-location principle used by all other skills in this design — no `../` traversal, only `./` relative paths. The `lib/sync-resources.js` build script keeps these co-located copies in sync with the authoritative top-level sources. All template paths are hardcoded in the skill — no user-provided filenames are used for path construction (preventing path traversal).

### Node.js dependency note

The `scripts/*.ts` files require `npx tsx` to execute. During setup, if the project does not have Node.js installed, the setup skill:
- Still copies the scripts (they're needed if Node.js is added later)
- Warns: "Some advanced features (self-reflect, PR comment fetching) require Node.js. These scripts will work once Node.js is available."
- Core metaswarm functionality (orchestration, quality gates, TDD) works without Node.js

## Migration Skill (`/metaswarm:migrate`)

For users who installed via the old `npx metaswarm init` path.

### Safety protocol

1. **Pre-flight check**: Verify the marketplace plugin is loaded and functional before removing anything
2. **Dry run preview**: Generate and display a complete list of files that will be removed
3. **Content verification**: For each file to be removed, verify it matches a known metaswarm file (check for metaswarm header/attribution comment, or compare content hash against known templates). Files that have been modified by the user are flagged as "customized — review before deleting" and are NOT auto-deleted
4. **User confirmation**: Present the deletion list via AskUserQuestion and require explicit approval
5. **Git safety**: Recommend `git stash` or commit before proceeding. The migration skill checks for uncommitted changes and warns if present.

### What it does (after user confirms)

1. **Removes plugin-managed files** (only unmodified ones):
   - `.claude/plugins/metaswarm/` (entire embedded plugin directory)
   - `.claude/rubrics/*` files matching metaswarm content hashes
   - `.claude/guides/*` files matching metaswarm content hashes
   - `.claude/commands/metaswarm-setup.md` (old setup command)
   - `.claude/commands/metaswarm-update-version.md` (old update command)
2. **Keeps project-local files** (untouched):
   - `CLAUDE.md`
   - `.coverage-thresholds.json`
   - `.metaswarm/project-profile.json`
   - `.beads/knowledge/`
   - `bin/`, `scripts/`
   - `.github/workflows/`
3. **Writes command shims** — same 6 shims as setup
4. **Updates profile** — sets `"distribution": "plugin"` in `.metaswarm/project-profile.json`
5. **Prompts commit** — suggests committing the cleanup

### Rollback

If migration fails or the user wants to revert:
- The migration skill does NOT delete files that were already staged or committed — it uses `git rm` so changes are reversible via `git checkout`
- If the marketplace plugin fails to load after migration, running `npx metaswarm install` (v0.9.0) restores the embedded files
- Migration documention includes manual recovery steps

## Status Skill (`/metaswarm:status`)

New diagnostic command for troubleshooting.

Reports:
- Installed plugin version
- Whether project setup has been run (`.metaswarm/project-profile.json` exists)
- Whether command shims are in place
- Whether legacy embedded plugin is detected (conflict)
- Whether BEADS plugin is separately installed
- Whether `bd` CLI is available
- Whether external tools are configured and healthy
- Coverage threshold configuration

## CI Template Security Fix

The `templates/ci.yml` is revised to eliminate the `eval "$CMD"` command injection vector.

**Before** (vulnerable):
```yaml
CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
eval "$CMD"
```

**After** (safe — array-based execution + metacharacter rejection):
```yaml
# Read command from coverage config
CMD=$(node -e "console.log(JSON.parse(require('fs').readFileSync('.coverage-thresholds.json','utf-8')).enforcement.command)")
# Split into array for safe execution
read -ra CMD_ARRAY <<< "$CMD"
# Validate first word is a known package manager/runner
case "${CMD_ARRAY[0]}" in
  npm|pnpm|yarn|npx|bun|cargo|pytest|go|make) ;;
  *) echo "Error: enforcement command must start with a known package manager/runner"; exit 1 ;;
esac
# Reject shell metacharacters in the full command string
if echo "$CMD" | grep -qE '[;|&`$(){}<>\\]'; then
  echo "Error: enforcement command contains disallowed shell metacharacters"
  exit 1
fi
# Execute as array — prevents all shell metacharacter interpretation
"${CMD_ARRAY[@]}"
```

## Shell Script Security Fix

The `bin/estimate-cost.sh` is revised to use safe awk variable passing.

**Before** (fragile):
```bash
input_cost_per_token=$(awk "BEGIN {print $input_cost_rate / 1000000}")
```

**After** (safe):
```bash
input_cost_per_token=$(awk -v rate="$input_cost_rate" 'BEGIN {print rate / 1000000}')
```

## Naming Clarifications

### `skills/beads/` → `skills/start/`

The main orchestration skill directory is renamed from `beads/` to `start/`. This yields the plugin command `/metaswarm:start` which is clear, non-stuttering, and semantically meaningful.

- The skill's YAML frontmatter `name:` field is updated to `start`
- The description triggers auto-invocation: "Use when starting work on any task, when the user mentions metaswarm, or when the user wants to begin tracked development work"
- `/metaswarm:start-task` (command) routes to the `start` skill

### Project-local `.beads/` directory — UNCHANGED

The `.beads/` directory in user projects is the BEADS knowledge base. It is NOT renamed. It remains `.beads/` with subdirectories `knowledge/`, `plans/`, `context/`. All 55+ references to `.beads/` in skills and commands remain valid because these reference the project-local directory, not the plugin skill directory.

### `scripts/beads-*.ts` — UNCHANGED for now

The TypeScript scripts retain their `beads-` prefix since they are BEADS-specific functionality. Renaming them is a future cosmetic change that doesn't affect functionality.

## Backward Compatibility

### Existing npm-installed users

- **Their projects keep working as-is** — the embedded `.claude/plugins/metaswarm/` directory still functions as a local plugin
- **They won't get automatic updates** — same as today, running a snapshot
- **No forced migration** — old and new can coexist. SessionStart hook gently nudges them

### Dual-plugin conflict handling

When both the old embedded plugin and new marketplace plugin are loaded:
- Skills from both locations appear in Claude Code's skill list
- The marketplace plugin takes precedence (user-scope > project-scope for plugins)
- The SessionStart hook detects this and strongly recommends migration
- Skills work correctly from either location — no functional breakage, just redundancy

### Transition plan

1. **v0.9.0 (final npm release)**: Publish npm package that:
   - Still works normally (init + install)
   - Prints deprecation notice on install: "metaswarm has moved to a Claude Code plugin. Install with: `/plugin marketplace add dsifry/metaswarm-marketplace`"
   - Updates README with migration instructions
   - Includes the security fixes (CI template, awk)

2. **v1.0.0 (plugin release)**: First marketplace release. Full plugin distribution. `/metaswarm:migrate` skill handles cleanup.

3. **v0.9.0 npm stays published indefinitely** — never yanked, just deprecated. Users who can't use the plugin system (air-gapped, old Claude Code version) still have a path.

### Version alignment

- npm v0.8.0 (current) → npm v0.9.0 (final, deprecated) → plugin v1.0.0 (first marketplace release)
- Going forward, only plugin versions are tracked. Semver continues from v1.0.0
- The migration skill validates: if `.metaswarm/project-profile.json` shows `metaswarm_version < 0.8.0`, warn that manual intervention may be needed

## Breaking Changes

| Component | Breaking? | Impact |
|-----------|-----------|--------|
| Skills (13) | No | Load from plugin cache — transparent. Path references updated to relative |
| Agents (18) | No | Co-located under `skills/start/agents/` — transparent |
| Commands (11) | Soft | `/start-task` works via shim. `/metaswarm-setup` → `/metaswarm:setup`. `/metaswarm-update-version` → `/metaswarm:update` |
| Rubrics (8) | No | Auto-discovered from plugin `rubrics/` dir. Also co-located in skills that reference them |
| Guides (6) | No | Auto-discovered from plugin `guides/` dir. Also co-located in skills that reference them |
| CLAUDE.md | No | Still project-local |
| bin/ and scripts/ | No | Still project-local (copied during setup) |
| Knowledge base (.beads/) | No | Still project-local |
| .coverage-thresholds.json | No | Still project-local |

## `bd` CLI Dependency

The `bd` CLI (BEADS) is used for knowledge priming, issue tracking, and self-reflection. It is NOT bundled with the metaswarm plugin — it is installed separately.

**When `bd` is not installed**:
- SessionStart hook skips knowledge priming (no error)
- `/metaswarm:prime` warns: "bd CLI not found. Install BEADS for knowledge base features."
- `/metaswarm:self-reflect` warns: "bd CLI required for self-reflection. See BEADS documentation."
- Core orchestration (start-task, design review, plan review, orchestrated execution) works without `bd`
- Issue tracking falls back to GitHub Issues via `gh`

**Whether `bd` requires Node.js**: `bd` is a Go binary distributed as a standalone executable. It does NOT require Node.js.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Relative path resolution in skills is fragile (first-attempt CWD bug, Issue #11011) | Medium | Co-locate resources with skills. Use `./` prefix consistently. Test all skill paths during validation |
| Users have both old embedded plugin + new marketplace plugin | Medium | SessionStart hook detects conflict. Marketplace plugin takes precedence. `/metaswarm:migrate` resolves |
| Marketplace auto-update pushes bad release | Medium | Pin marketplace.json to specific git tag + SHA. Rollback = update ref to previous tag |
| Setup skill can't write files in some permission modes | Low | Standard Write/Bash tools — works in all modes with user approval |
| BEADS plugin conflict (double bd prime) | Low | SessionStart hook validates BEADS plugin.json content, not just directory existence |
| Command shims in project conflict with existing commands | Low | Setup skill checks for existing commands, asks before overwriting |
| Co-located resource duplication gets stale | Low | `lib/sync-resources.js` build script keeps copies in sync from authoritative sources. CI validates no drift |
| Migration deletes user-customized files | Low | Content-hash verification + explicit user confirmation before any deletion |
| `${CLAUDE_PLUGIN_ROOT}` limitation changes in future Claude Code | Low | Only used in hooks.json (where it works). Skills use relative paths (no dependency on this variable) |

## Test Plan

### Unit-testable (shell/script tests)

- `session-start.sh` hook logic: BEADS dedup, new project detection, legacy detection
- CI template command validation (allowlist check)
- `estimate-cost.sh` awk safety
- `sync-resources.js` build script (verifies co-located copies match authoritative sources)
- Migration skill's content-hash verification logic

### Integration-testable (requires Claude Code)

- Plugin loads correctly from marketplace cache (`/plugin validate .`)
- All 13 skills discoverable via Skill tool
- All 11 commands appear in `/` autocomplete
- SessionStart hook fires and injects correct context
- Setup skill reads templates from plugin cache via relative paths
- Command shims correctly delegate to namespaced commands
- Subagents can read rubrics from co-located skill directories
- Migration skill correctly identifies and removes legacy files

### Manual validation

- End-to-end: fresh install → setup → start-task → orchestrated execution
- End-to-end: legacy npm install → migrate → verify skills still work
- Cross-session: verify auto-update delivers new version

## Success Criteria

- [ ] `npx metaswarm` is no longer required for new users
- [ ] Plugin installs via `/plugin marketplace add dsifry/metaswarm-marketplace`
- [ ] `/metaswarm:setup` fully replaces `npx metaswarm init` + `/metaswarm-setup`
- [ ] All 13 skills load correctly from plugin cache (verified with `/plugin validate .`)
- [ ] All 11 commands appear in autocomplete
- [ ] SessionStart hook detects new projects, legacy installs, and BEADS dedup
- [ ] PreCompact hook re-injects context before compaction
- [ ] `/metaswarm:migrate` cleanly transitions old installs with safety protocol
- [ ] `/metaswarm:status` reports accurate diagnostic information
- [ ] Existing npm-installed projects continue working without changes
- [ ] Architecture supports future CLI spokes without modifying shared skills
- [ ] CI template is safe from command injection
- [ ] No Node.js required for core functionality (install, setup, orchestration, quality gates)
- [ ] `lib/sync-resources.js` build script works and CI validates no co-located resource drift

## Implementation Tracking (from design review)

Items identified during design review that must be addressed during implementation:

1. **11 additional broken paths in agent definitions** — agent `.md` files under `skills/start/agents/` reference `.claude/rubrics/` and `guides/` paths. Must be updated to relative paths or have rubrics co-located in the agents directory. (CTO review, iteration 2)
2. **Phantom `typescript-patterns.md` reference** — `coder-agent.md` references `.claude/guides/typescript-patterns.md` which does not exist. Remove the reference or create the guide. (CTO review, iteration 2)
3. **BEADS dedup check** — use exact-match JSON parsing (`jq -r .name` or `node -e`) for plugin.json content verification, not substring grep. (Security review, iteration 2)
4. **Migration content hashing** — use SHA-256 with LF-normalized, trailing-whitespace-stripped content for deterministic cross-platform matching. (Security review, iteration 2)
5. **Marketplace SHA pinning** — add commit SHA to marketplace.json `source` field when supported. Document as known limitation if not. (Security review, iteration 2)
6. **PreCompact hook idempotency** — verify `session-start.sh` produces no side effects when run multiple times per session. (Security review, iteration 2)
7. **`lib/skills-core.js` scope** — define or defer. Not needed for v1.0 if all skill logic is in SKILL.md markdown. (CTO review, iteration 2)
8. **Test case: BEADS dedup detection** — dedicated test for plugin.json content verification logic. (CTO review, iteration 2)
9. **Test case: dual-plugin conflict** — manual test scenario for both embedded and marketplace plugin loaded simultaneously. (CTO review, iteration 2)
10. **PreCompact matcher validation** — confirm empty string `""` matches all compaction events per Claude Code documentation. (PM review, iteration 2)
11. **`rubrics/` and `guides/` are NOT plugin-auto-discovered** — only `skills/`, `commands/`, `agents/`, `hooks/` are auto-discovered. Top-level `rubrics/` and `guides/` dirs serve as authoritative sync sources only. Correct the "auto-discovery" language in the design. (Architect review, iteration 3)
12. **Use `"source": "github"` in marketplace.json** — change from `"source": "url", "url": "https://github.com/dsifry/metaswarm.git"` to `"source": "github", "repo": "dsifry/metaswarm"` since the repo is on GitHub. (Architect review, iteration 3)
13. **Hook output format** — `session-start.sh` must output JSON in `hookSpecificOutput.additionalContext` format (matching superpowers pattern). Document the output contract. (Architect review, iteration 3)
14. **Missing `commands/status.md`** — add to repo structure or document that `/metaswarm:status` is skill-only. (CTO review, iteration 3)
15. **`typescript-patterns.md` phantom scope** — reference appears in 4 files (coder-agent.md, architecture-rubric.md, security-review-rubric.md, code-review-rubric.md), not just 1. Expand item #2. (CTO review, iteration 3)
16. **`package.json` disposition after v1.0.0** — update `cli/metaswarm.js` to print deprecation message and exit, or remove `bin` field. (CTO review, iteration 3)
17. **`session-start.sh` fallback when neither `jq` nor `node` available** — safe default: skip BEADS dedup check, allow both to prime (harmless redundancy). (CTO review, iteration 3)
18. **`/start-task` should detect missing setup** — if `.metaswarm/project-profile.json` is absent, auto-route to `/metaswarm:setup` rather than relying solely on SessionStart hook. (Designer review, iteration 3)
