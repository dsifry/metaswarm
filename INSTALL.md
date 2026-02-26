# Installation

## Recommended: Plugin Marketplace

The fastest way to install metaswarm:

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

## Migrating from npm Installation

If you previously installed metaswarm via `npx metaswarm init`, run:

```text
/migrate
```

This detects old `.claude/plugins/metaswarm/` files, verifies content matches, removes stale copies, and creates project-local command shims pointing to the plugin.

## Check Installation Status

```text
/status
```

This runs 9 diagnostic checks: plugin version, project setup, command shims, legacy install detection, BEADS plugin, bd CLI, external tools, coverage thresholds, and Node.js.

## Legacy: npm Installation (Deprecated)

> **Note:** The npm installation method is deprecated and will be removed in a future version. Use the plugin marketplace method above instead.

```bash
npx metaswarm init --full
```

This runs the legacy installer that copies all files with default configuration. You'll need to manually customize CLAUDE.md and coverage settings for your project.

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
