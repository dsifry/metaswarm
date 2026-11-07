# Beads - AI-Native Issue Tracking

Welcome to Beads! This repository uses **Beads** for issue tracking - a modern, AI-native tool designed to live directly in your codebase alongside your code.

## What is Beads?

Beads is issue tracking that lives in your repo, making it perfect for AI coding agents and developers who want their issues close to their code. No web UI required - everything works through the CLI and integrates seamlessly with git.

**Learn more:** [github.com/steveyegge/beads](https://github.com/steveyegge/beads)

## Quick Start

### Essential Commands

```bash
# Create new issues
bd create "Add user authentication"

# View all issues
bd list

# View issue details
bd show <issue-id>

# Update issue status
bd update <issue-id> --status in_progress
bd close <issue-id> --reason "Done"

# If a Dolt remote is configured: push your changes (local-only workspaces need no sync)
bd dolt push
```

### Working with Issues

Issues in Beads are:

- **Git-native**: Stored in `.beads/issues.jsonl` and synced like code
- **AI-friendly**: CLI-first design works perfectly with AI coding agents
- **Branch-aware**: Issues can follow your branch workflow
- **Always in sync**: Auto-syncs with your commits

## Why Beads?

**AI-Native Design**

- Built specifically for AI-assisted development workflows
- CLI-first interface works seamlessly with AI coding agents
- No context switching to web UIs

**Developer Focused**

- Issues live in your repo, right next to your code
- Works offline, syncs when you push
- Fast, lightweight, and stays out of your way

**Git Integration**

- Automatic sync with git commits
- Branch-aware issue tracking
- Intelligent JSONL merge resolution

## Get Started with Beads

### Install the standalone beads plugin (recommended)

```bash
# Install from the Claude Code marketplace
/plugin install beads    # from steveyegge/beads marketplace
```

The beads plugin runs `bd prime` on SessionStart and PreCompact (bd workflow context and any `bd remember` memories; metaswarm's knowledge comes from `/prime`). It records architectural decisions as decision issues (`bd create "<title>" --type decision -d "<rationale>"`) and ships a `@task-agent` that autonomously finds and completes ready tasks.

### Or install the CLI directly

```bash
curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# Initialize in your repo
bd init

# Create your first issue
bd create "Try out Beads"
```

### Housekeeping: compaction

Squash old Dolt history (recent commits are kept; preview first):

```bash
bd compact --dry-run
bd compact --force
```

Plain `bd compact` only rewrites Dolt history.

To summarize old **closed** bd issues locally (agent-driven, no API key needed),
analyze the candidates, write a summary, then apply it per issue:

```bash
bd admin compact --analyze --json
bd admin compact --apply --id <id> --summary <file>
```

Only `bd admin compact --auto` needs an API key. Neither command touches `.beads/knowledge`. Every `bd admin` command requires server mode (`bd init --server`); it isn't available in bd's default embedded mode.

## Learn More

- **Documentation**: [github.com/steveyegge/beads/docs](https://github.com/steveyegge/beads/tree/main/docs)
- **Marketplace Plugin**: [steveyegge/beads](https://github.com/steveyegge/beads)
- **Quick Start Guide**: Run `bd quickstart`
- **Examples**: [github.com/steveyegge/beads/examples](https://github.com/steveyegge/beads/tree/main/examples)

---

_Beads: Issue tracking that moves at the speed of thought_
