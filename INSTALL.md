# Installation

## Quick Install

```bash
cd your-project
npx metaswarm init
```

This single command:
- Copies agent definitions → `.claude/plugins/metaswarm/skills/beads/agents/`
- Copies ORCHESTRATION.md → `.claude/plugins/metaswarm/skills/beads/SKILL.md`
- Copies skills → `.claude/plugins/metaswarm/skills/`
- Copies commands → `.claude/commands/`
- Copies rubrics → `.claude/rubrics/`
- Copies knowledge templates → `.beads/knowledge/`
- Copies scripts → `scripts/` and `bin/`
- Copies templates → `.claude/templates/`
- Generates `plugin.json`
- Makes `bin/*.sh` executable
- Runs `bd init` (if BEADS CLI is available)

Existing files are never overwritten — if a file already exists, it is skipped with a message.

## Prerequisites

You only need **Node.js 18+** to run `npx metaswarm init`. The following are needed for the full workflow:

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
# The superpowers plugin installs into ~/.claude/plugins/
# See: https://github.com/obra/superpowers
```

**Without superpowers**: metaswarm still works — the core orchestration (agents, BEADS, review gates, rubrics) is self-contained. The superpowers references are in skill trigger chains and can be removed or replaced with your own equivalents.

## Alternative Installation Methods

### Manual Copy

If you prefer to copy files manually:

```bash
git clone https://github.com/dsifry/metaswarm.git /tmp/metaswarm-install
cd your-project

mkdir -p .claude/plugins/metaswarm/skills/beads/agents
cp /tmp/metaswarm-install/agents/* .claude/plugins/metaswarm/skills/beads/agents/
cp /tmp/metaswarm-install/ORCHESTRATION.md .claude/plugins/metaswarm/skills/beads/SKILL.md
cp -r /tmp/metaswarm-install/skills/* .claude/plugins/metaswarm/skills/
mkdir -p .claude/commands && cp /tmp/metaswarm-install/commands/* .claude/commands/
mkdir -p .claude/rubrics && cp /tmp/metaswarm-install/rubrics/* .claude/rubrics/
mkdir -p scripts bin && cp /tmp/metaswarm-install/scripts/* scripts/ && cp /tmp/metaswarm-install/bin/* bin/
chmod +x bin/*.sh
mkdir -p .beads/knowledge && cp /tmp/metaswarm-install/knowledge/* .beads/knowledge/
bd init
rm -rf /tmp/metaswarm-install
```

### Method 3: Git Submodule

```bash
cd your-project
git submodule add https://github.com/dsifry/metaswarm.git .metaswarm

# Symlink what you need
ln -s .metaswarm/agents .claude/plugins/metaswarm/skills/beads/agents
ln -s .metaswarm/commands/* .claude/commands/
ln -s .metaswarm/rubrics/* .claude/rubrics/
```

### Method 4: Reference Only

Copy only what you need. Start with:

1. `ORCHESTRATION.md` — The workflow guide
2. `agents/issue-orchestrator.md` — The main coordinator
3. `skills/design-review-gate/SKILL.md` — The parallel review pattern
4. `rubrics/code-review-rubric.md` — Quality standards

## Plugin Registration

If you used `npx metaswarm init`, the plugin manifest is generated automatically at `.claude/plugins/metaswarm/.claude-plugin/plugin.json`.

For manual installations, create that file:

```json
{
  "name": "metaswarm",
  "version": "0.1.0",
  "description": "Multi-agent orchestration framework for Claude Code",
  "skills": ["skills/beads/SKILL.md"]
}
```

## Customizing for Your Project

After installation, metaswarm needs to be adapted to your project's language, framework, and conventions. You can do this manually or let an agent do it.

### Agent-Driven Customization

Give this prompt to Claude Code in your project:

```text
I've installed metaswarm (multi-agent orchestration framework) into this project.
Please customize it for this specific project:

1. Read our project's README, package.json/Cargo.toml/pyproject.toml/go.mod (whichever exists)
   to understand our language, framework, test runner, and linter.

2. Update these files with project-specific details:
   - .claude/plugins/metaswarm/skills/beads/agents/coder-agent.md
     → Replace TDD commands with our test runner (e.g., pytest, cargo test, go test)
     → Replace linter references with our linter (e.g., ruff, clippy, golangci-lint)
   - .claude/rubrics/code-review-rubric.md
     → Add our language's idioms and style guide references
   - .claude/rubrics/test-coverage-rubric.md
     → Set coverage thresholds appropriate for our project
   - .claude/rubrics/architecture-rubric.md
     → Add our framework's architectural patterns

3. Seed the knowledge base with initial facts:
   - .beads/knowledge/patterns.jsonl → Add 3-5 patterns from our codebase
   - .beads/knowledge/decisions.jsonl → Add key architectural decisions
   - .beads/knowledge/codebase-facts.jsonl → Add framework/language specifics

4. Update .claude/commands/prime.md if our project uses different
   file extensions or directory conventions.

Do NOT change the orchestration workflow itself — only adapt the
language-specific and project-specific details.
```

### Manual Customization Checklist

If you prefer to customize by hand, update these areas:

#### 1. Agent Commands (in `agents/coder-agent.md`)

| Placeholder | Example: TypeScript | Example: Python | Example: Rust |
|---|---|---|---|
| Test runner | `pnpm test` | `pytest` | `cargo test` |
| Linter | `pnpm lint` | `ruff check .` | `cargo clippy` |
| Formatter | `pnpm prettier --check .` | `ruff format --check .` | `cargo fmt --check` |
| Type checker | `pnpm typecheck` | `mypy .` | (built into `cargo check`) |
| Build | `pnpm build` | `python -m build` | `cargo build` |

#### 2. Rubric Language (in `rubrics/`)

Replace language-specific guidance:

- **code-review-rubric.md**: Add your language's idioms (e.g., "prefer `itertools` over manual loops" for Python)
- **architecture-rubric.md**: Add your framework's patterns (e.g., "use Django signals for cross-app events")
- **security-review-rubric.md**: Add language-specific vulnerabilities (e.g., SQL injection patterns differ between ORMs)

#### 3. Knowledge Base Seeding (in `knowledge/`)

Add initial entries to each JSONL file. See `knowledge/README.md` for the schema. Minimum recommended:

- **3-5 patterns** — Your project's established coding patterns
- **2-3 decisions** — Key architectural choices and their rationale
- **1-2 gotchas** — Known pitfalls specific to your stack

#### 4. Task Completion Checklist (in `templates/task-completion-checklist.md`)

Replace the validation commands with your project's equivalents:

```markdown
## Before marking complete:
- [ ] `your-test-command` passes
- [ ] `your-lint-command` passes
- [ ] `your-type-check-command` passes (if applicable)
- [ ] `your-build-command` succeeds
```

## Verify Installation

```bash
# Check BEADS is working
bd status

# Check knowledge base
bd prime

# In Claude Code, verify commands are available
# Type /project: and you should see prime, start-task, review-design, etc.
```

## Next Steps

- [GETTING_STARTED.md](GETTING_STARTED.md) — Run your first orchestrated workflow
- [USAGE.md](USAGE.md) — Full usage reference
