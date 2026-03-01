# Installation

metaswarm works with Claude Code, Gemini CLI, and Codex CLI. Install for one platform or all three.

## Claude Code (Plugin Marketplace)

```bash
claude plugin marketplace add dsifry/metaswarm-marketplace
claude plugin install metaswarm
```

Then in Claude Code:

```text
/setup
```

## Gemini CLI (Extension)

```bash
gemini extensions install https://github.com/dsifry/metaswarm.git
```

Then in Gemini CLI:

```text
/metaswarm:setup
```

## Codex CLI (Skills)

```bash
curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.codex/install.sh | bash
```

Then in Codex CLI:

```text
$setup
```

## Cross-Platform Installer

Detect all installed CLIs and install metaswarm for each:

```bash
npx metaswarm init
```

Or target a specific platform:

```bash
npx metaswarm init --claude
npx metaswarm init --codex
npx metaswarm init --gemini
```

After installing, set up your project:

```bash
npx metaswarm setup
```

## Platform Comparison

| Feature | Claude Code | Gemini CLI | Codex CLI |
|---|---|---|---|
| Install method | Plugin marketplace | `gemini extensions install` | Clone + symlink |
| Commands | `/start-task` | `/metaswarm:start-task` | `$start` |
| Instruction file | `CLAUDE.md` | `GEMINI.md` | `AGENTS.md` |
| Parallel agents | Full (`Task()`) | Experimental | Sequential only |
| Setup command | `/setup` | `/metaswarm:setup` | `$setup` |

## Prerequisites

1. **One of**: Claude Code, Gemini CLI, or Codex CLI
2. **BEADS CLI** (`bd`) — Git-native issue tracking (recommended)
   ```bash
   curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
   ```
3. **GitHub CLI** (`gh`) — For PR automation (recommended)
   ```bash
   brew install gh   # macOS
   gh auth login
   ```
4. **Superpowers Plugin** (optional, Claude Code only) — See [External Dependencies](#external-dependencies)

## External Dependencies

metaswarm's skills reference these external skills from the [superpowers](https://github.com/obra/superpowers) Claude Code plugin:

| Skill | Used By | Purpose |
|---|---|---|
| `superpowers:brainstorming` | Design Review Gate, Brainstorming Extension | Collaborative design ideation before implementation |
| `superpowers:test-driven-development` | PR Shepherd, Coder Agent | RED-GREEN-REFACTOR implementation cycle |
| `superpowers:systematic-debugging` | PR Shepherd | Four-phase bug investigation framework |
| `superpowers:writing-plans` | Design Review Gate, Brainstorming Extension | Detailed implementation plan generation |
| `superpowers:using-git-worktrees` | Design Review Gate | Isolated workspace creation for parallel dev |

**Install superpowers** (follow their README for current instructions):
```bash
# See: https://github.com/obra/superpowers
claude plugin add obra/superpowers
```

**Without superpowers**: metaswarm still works — the core orchestration (agents, BEADS, review gates, rubrics) is self-contained. The superpowers references are in skill trigger chains and can be removed or replaced with your own equivalents.

## Optional: External AI Tools

metaswarm can delegate implementation and review tasks to **Codex CLI** (OpenAI) and **Gemini CLI** (Google) for cost savings and cross-model adversarial review. This is entirely optional — metaswarm works fine without any external tools.

**Quick setup:**

```bash
npm i -g @openai/codex @google/gemini-cli
```

After installing, see [`templates/external-tools-setup.md`](templates/external-tools-setup.md) for the full configuration guide (authentication, model selection, budget controls, and routing options).

To verify your setup, run the health check command in Claude Code:

```text
/external-tools-health
```

This checks that each tool is installed, authenticated, and responsive.

## Upgrading to v0.9.0

v0.9.0 moved metaswarm from npm distribution to the Claude Code plugin marketplace. If you're on an older version, follow the instructions for your situation:

### From v0.7.x or v0.8.x (npm-installed)

This is the most common upgrade path. Your project has metaswarm files in `.claude/plugins/metaswarm/` that were copied there by `npx metaswarm init`.

1. **Install the plugin:**
   ```bash
   claude plugin marketplace add dsifry/metaswarm-marketplace
   claude plugin install metaswarm
   ```

2. **Run the migration** in Claude Code:
   ```text
   /migrate
   ```
   This detects old `.claude/plugins/metaswarm/` files, verifies content matches the plugin versions, and removes the redundant copies. Your project-specific files (CLAUDE.md, `.coverage-thresholds.json`, `.beads/`, `bin/`, `scripts/`) are never touched. All removals are staged with `git rm` — nothing is permanently deleted until you commit.

3. **Verify the migration:**
   ```text
   /status
   ```

4. **Review and commit** the cleanup when you're satisfied.

**Command name changes:** The old `/metaswarm-setup` and `/metaswarm-update-version` commands have been renamed to `/setup` and `/update`. Legacy aliases are preserved, so old names still work, but new projects should use the short names.

### From v0.6.x or earlier (npm-installed, no guided setup)

These versions used `npx metaswarm init --full` without the guided setup skill. Follow the same steps as v0.7.x/v0.8.x above, then re-run `/setup` to take advantage of the interactive configuration:

```text
/setup
```

This re-detects your project and applies any configuration improvements from newer versions. It won't overwrite your existing customizations — it prompts before making changes.

### Already on v0.9.0 (plugin-installed)

Just update in Claude Code:

```text
/update
```

This checks for new versions, shows what changed, and updates all component files while preserving your customizations.

### Automatic legacy detection

If you skip the manual migration, the session-start hook will detect the old npm installation when you open Claude Code and prompt you to run `/migrate`. You can also run `/status` at any time to check for legacy files.

## Check Installation Status

```text
/status
```

This runs 9 diagnostic checks: plugin version, project setup, command shims, legacy install detection, BEADS plugin, bd CLI, external tools, coverage thresholds, and Node.js.

## npm Package (Cross-Platform Installer)

The npm package (`npx metaswarm`) is now the cross-platform installer. It detects your installed CLIs and installs metaswarm for each.

```bash
npx metaswarm init          # Auto-detect and install for all CLIs
npx metaswarm setup         # Set up project (writes instruction files)
npx metaswarm detect        # Show which CLIs are available
```

## Customizing for Your Project

After installation, the `/setup` command handles most customization automatically. For manual customization:

### Agent Commands (in `agents/coder-agent.md`)

| Placeholder | Example: TypeScript | Example: Python | Example: Rust |
|---|---|---|---|
| Test runner | `pnpm test` | `pytest` | `cargo test` |
| Linter | `pnpm lint` | `ruff check .` | `cargo clippy` |
| Formatter | `pnpm prettier --check .` | `ruff format --check .` | `cargo fmt --check` |
| Type checker | `pnpm typecheck` | `mypy .` | (built into `cargo check`) |
| Build | `pnpm build` | `python -m build` | `cargo build` |

### Coverage Thresholds (in `.coverage-thresholds.json`)

```json
{
  "thresholds": {
    "lines": 100,
    "branches": 100,
    "functions": 100,
    "statements": 100
  },
  "enforcement": {
    "command": "pnpm test:coverage",
    "blockPRCreation": true,
    "blockTaskCompletion": true
  }
}
```

Set `enforcement.command` to your project's coverage command (e.g., `pytest --cov`, `cargo tarpaulin`, `go test -cover`). When this file exists, agents must pass all thresholds before pushing or creating PRs.

## Verify Installation

```bash
# Check BEADS is working
bd status

# Check knowledge base
bd prime

# In Claude Code, verify commands are available
# Type / and you should see start-task, review-design, etc.
```

## Next Steps

- [GETTING_STARTED.md](GETTING_STARTED.md) — Run your first orchestrated workflow
- [USAGE.md](USAGE.md) — Full usage reference
