# Installation

## Prerequisites

### Required

1. **Claude Code** — [Install Claude Code](https://docs.anthropic.com/en/docs/claude-code)

2. **BEADS CLI** (`bd`) — Git-native issue tracking
   ```bash
   curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
   bd --version  # Should show v0.40+
   ```

3. **GitHub CLI** (`gh`) — PR automation
   ```bash
   brew install gh   # macOS
   gh auth login
   ```

4. **Node.js 20+** — For automation scripts
   ```bash
   node --version  # Should show v20+
   ```

### Optional

- **Slack** — For agent notifications (see `templates/beads-developer-setup.md`)

## Installation Methods

### Method 1: Copy Into Your Project (Recommended)

This integrates metaswarm directly into your project's Claude Code configuration.

```bash
# Clone metaswarm
git clone https://github.com/dsifry/metaswarm.git /tmp/metaswarm-install

# Navigate to your project
cd your-project

# Copy agent definitions
mkdir -p .claude/plugins/metaswarm/skills/beads/agents
cp /tmp/metaswarm-install/agents/* .claude/plugins/metaswarm/skills/beads/agents/
cp /tmp/metaswarm-install/ORCHESTRATION.md .claude/plugins/metaswarm/skills/beads/SKILL.md

# Copy skills
cp -r /tmp/metaswarm-install/skills/* .claude/plugins/metaswarm/skills/

# Copy commands (these become /project:command-name in Claude Code)
mkdir -p .claude/commands
cp /tmp/metaswarm-install/commands/* .claude/commands/

# Copy rubrics
mkdir -p .claude/rubrics
cp /tmp/metaswarm-install/rubrics/* .claude/rubrics/

# Copy automation scripts
cp /tmp/metaswarm-install/scripts/* scripts/
cp /tmp/metaswarm-install/bin/* bin/
chmod +x bin/*.sh

# Initialize BEADS
bd init

# Set up knowledge base
mkdir -p .beads/knowledge
cp /tmp/metaswarm-install/knowledge/* .beads/knowledge/

# Clean up
rm -rf /tmp/metaswarm-install
```

### Method 2: Git Submodule

Keep metaswarm as a submodule for easy updates.

```bash
cd your-project
git submodule add https://github.com/dsifry/metaswarm.git .metaswarm

# Symlink what you need
ln -s .metaswarm/agents .claude/plugins/metaswarm/skills/beads/agents
ln -s .metaswarm/commands/* .claude/commands/
ln -s .metaswarm/rubrics/* .claude/rubrics/
```

### Method 3: Reference Only

Use metaswarm as a reference and copy only the pieces you need. Start with:

1. `ORCHESTRATION.md` — The workflow guide
2. `agents/issue-orchestrator.md` — The main coordinator
3. `skills/design-review-gate/SKILL.md` — The parallel review pattern
4. `rubrics/code-review-rubric.md` — Quality standards

## Plugin Registration

Create `.claude/plugins/metaswarm/.claude-plugin/plugin.json`:

```json
{
  "name": "metaswarm",
  "version": "1.0.0",
  "description": "Multi-agent orchestration framework",
  "skills": [
    {
      "name": "beads",
      "path": "skills/beads/SKILL.md"
    },
    {
      "name": "design-review-gate",
      "path": "skills/design-review-gate/SKILL.md"
    },
    {
      "name": "pr-shepherd",
      "path": "skills/pr-shepherd/SKILL.md"
    },
    {
      "name": "handling-pr-comments",
      "path": "skills/handling-pr-comments/SKILL.md"
    }
  ]
}
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
