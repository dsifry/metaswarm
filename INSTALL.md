# Installation

## Recommended: Plugin Marketplace

The fastest way to install metaswarm. Works with Claude Code, Gemini CLI, and Codex CLI.

```bash
claude plugin add dsifry/metaswarm
```

Then open Claude Code in your project and run:

```text
/setup
```

Claude will:
- Detect your language, framework, test runner, linter, and CI system
- Ask 3-5 targeted questions (coverage thresholds, external tools, etc.)
- Create CLAUDE.md, coverage config, and command shims for your project
- Set up external AI tools and visual review if requested
- Write a project profile for future updates

To update metaswarm later:

```text
/update
```

## Prerequisites

1. **Claude Code** — [Install Claude Code](https://docs.anthropic.com/en/docs/claude-code)
2. **BEADS CLI** (`bd`) — Git-native issue tracking
   ```bash
   curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
   ```
3. **GitHub CLI** (`gh`) — For PR automation
   ```bash
   brew install gh   # macOS
   gh auth login
   ```
4. **Superpowers Plugin** (optional) — See [External Dependencies](#external-dependencies)

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
   claude plugin add dsifry/metaswarm
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

## Legacy: npm Installation (Deprecated)

> **Deprecated:** The npm installation method is deprecated as of v0.9.0 and will be removed in a future version. Use the plugin marketplace method above instead. The npm package now prints a deprecation warning on install.

```bash
npx metaswarm init --full
```

This runs the legacy installer that copies all files with default configuration. You'll need to manually customize CLAUDE.md and coverage settings for your project. **New users should use `claude plugin add dsifry/metaswarm` instead.**

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
