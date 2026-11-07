# BEADS Developer Setup Guide

This guide helps you set up BEADS (Bug/Enhancement Agent Delegation System) on your local machine for multi-agent orchestration with Claude Code.

## Prerequisites

- **Claude Code** installed and configured
- **Node.js** 18+ with pnpm (for metaswarm-specific scripts)
- **Git** configured with SSH access to the repo
- **Slack workspace** access (for Slack integration)

---

## Quick Start

### Install the standalone beads plugin

```bash
# Install the beads plugin from the Claude Code marketplace
/plugin install beads    # from steveyegge/beads marketplace

# Verify BEADS CLI is installed
bd --version

# Check system health
bd doctor

# View current issues
bd list
```

The standalone beads plugin (matching your bd version, bd ≥ 1.0.4) automatically runs `bd prime` (bd workflow context and `bd remember` memories) via built-in SessionStart and PreCompact hooks. Knowledge-base facts come from metaswarm's `/prime` command, which reads `.beads/knowledge/` directly — no priming scripts needed.

---

## Environment Setup

### Step 1: Copy the environment template

```bash
cp .env.example .env.local
```

### Step 2: Add BEADS-specific variables

Add these to your `.env.local` file:

```bash
# =============================================================================
# BEADS Multi-Agent Orchestration
# =============================================================================

# Slack Integration (Socket Mode - secure, no webhooks needed)
# Get these from your Slack App settings: https://api.slack.com/apps
SLACK_BEADS_APP_TOKEN=xapp-1-...         # App-level token (connections:write scope)
SLACK_BEADS_BOT_TOKEN=xoxb-...           # Bot OAuth token

# Security: Comma-separated Slack user IDs who can run commands
# Find your user ID: Click your profile in Slack -> "..." -> "Copy member ID"
BEADS_ALLOWED_USERS=U12345678,U87654321

# Notification channels (optional)
SLACK_BEADS_CHANNEL=C0XXXXXXXX           # Main notifications channel
SLACK_BEADS_ALERTS_CHANNEL=C0XXXXXXXX    # Critical alerts channel
```

### Step 3: Create Slack App (if not exists)

1. Go to https://api.slack.com/apps
2. Click **Create New App** -> **From scratch**
3. Name it "BEADS" and select your workspace

#### Enable Socket Mode

1. Go to **Settings** -> **Socket Mode**
2. Enable Socket Mode
3. Generate an App-Level Token with `connections:write` scope
4. Copy the `xapp-...` token to `SLACK_BEADS_APP_TOKEN`

#### Add Bot Scopes

Go to **OAuth & Permissions** and add these Bot Token Scopes:

- `app_mentions:read` - Receive @mentions
- `chat:write` - Send messages
- `im:history` - Read DM history
- `im:read` - Access DMs
- `im:write` - Send DMs

#### Subscribe to Events

Go to **Event Subscriptions** and subscribe to:

- `app_mention`
- `message.im`

#### Install to Workspace

1. Go to **Install App**
2. Click **Install to Workspace**
3. Copy the Bot User OAuth Token to `SLACK_BEADS_BOT_TOKEN`

---

## Running the Slack Daemon

The Slack daemon uses **Socket Mode** (outbound WebSocket) - no public endpoints or webhooks needed.

### Start the daemon

```bash
# In a dedicated terminal (or use tmux/screen)
pnpm tsx scripts/beads-slack-daemon.ts
```

You should see:

```text
BEADS Slack daemon connected!
Listening for commands...
```

### Test it works

In Slack, DM the bot or @mention it:

```text
@beads status
@beads help
```

### Run as background service (optional)

```bash
# Using nohup
nohup pnpm tsx scripts/beads-slack-daemon.ts > /tmp/beads-daemon.log 2>&1 &

# Or with pm2
pm2 start scripts/beads-slack-daemon.ts --interpreter="npx" --interpreter-args="tsx"
```

---

## Weekly Reports Crontab

The metrics agent can generate weekly reports. Set up a cron job:

### Option 1: User crontab

```bash
crontab -e
```

Add this line (runs every Monday at 9am):

```cron
0 9 * * 1 cd /path/to/your-project && npx tsx scripts/beads-weekly-report.ts >> /tmp/beads-weekly.log 2>&1
```

---

## Using BEADS with Claude Code

### Automatic bd Context

The standalone beads plugin (matching your bd version, bd ≥ 1.0.4) automatically runs `bd prime` on SessionStart and PreCompact via built-in hooks. That restores the bd workflow reference and any `bd remember` memories; no manual configuration is needed.

If the beads plugin is installed, metaswarm's session hook detects it and skips its own `bd prime` call to avoid duplicate context.

### Knowledge Priming with `/prime`

metaswarm's `/prime` command loads knowledge-base facts from `.beads/knowledge/*.jsonl`, filtered with `jq` by keyword (over each fact and its tags), file (over its affected files) and work type (over its fact type):

```text
/prime                                   # critical rules and gotchas
/prime implementation src/api/auth/      # implementation work touching these files
/prime debugging webhook                 # debugging work on a topic
```

For recovery after context loss: if bd is installed, `bd prime` (bd context); then read `.beads/plans/active-plan.md` and `.beads/context/*.md`; then `/prime` for knowledge.

### Common Workflows

#### 1. Start a new task

```bash
# Check what's available
bd ready

# Claim a task
bd update <task-id> --status in_progress
```

Then prime your context: `/prime` (metaswarm knowledge priming) for implementation work on "relevant keywords".

#### 2. Create tasks from a GitHub issue

```bash
# Create an epic
bd create --title "Issue #123: Feature X" --type epic --priority 2

# Add sub-tasks
bd create --title "Research existing patterns" --type task --parent <epic-id>
bd create --title "Implement core logic" --type task --parent <epic-id>
bd create --title "Write tests" --type task --parent <epic-id>
```

#### 3. Complete work

```bash
# Close completed tasks
bd close <task-id> --reason "Implementation complete"

# Record architectural decisions
bd create "Chose X over Y" --type decision -d "Because Z"
```

#### 4. Housekeeping (occasional)

Squash old Dolt history (recent commits are kept; preview first):

```bash
bd compact --dry-run
bd compact --force
```

Plain `bd compact` only rewrites Dolt history.

To summarize old **closed** bd issues locally (agent-driven, no API key needed):

```bash
bd admin compact --analyze --json
bd admin compact --apply --id <id> --summary <file>
```

Only `bd admin compact --auto` needs an API key. Neither command touches `.beads/knowledge`.

---

## Directory Structure

```text
.beads/
  config.yaml           # BEADS configuration (managed by beads plugin)
  issues.jsonl          # Issue database
  metadata.json         # Repo metadata
  knowledge/            # Knowledge base
    codebase-facts.jsonl
    patterns.jsonl
    gotchas.jsonl
    decisions.jsonl
    api-behaviors.jsonl
  temp/                 # Temporary files (gitignored)

scripts/
  beads-fetch-pr-comments.ts          # Fetch PR review comments from GitHub (metaswarm-specific)
  beads-fetch-conversation-history.ts  # Extract conversation history from Claude Code sessions (metaswarm-specific)
```

---

## Troubleshooting

### "bd: command not found"

```bash
# Install the beads plugin from Claude Code marketplace
/plugin install beads    # from steveyegge/beads marketplace

# Or install BEADS CLI directly
curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
```

### Slack daemon won't connect

1. Verify tokens are set:

   ```bash
   echo $SLACK_BEADS_APP_TOKEN
   echo $SLACK_BEADS_BOT_TOKEN
   ```

2. Check Socket Mode is enabled in Slack App settings

3. Verify app is installed to workspace

### Knowledge priming returns no facts

```bash
# Check knowledge base exists
ls -la .beads/knowledge/

# Verify facts are loaded
wc -l .beads/knowledge/*.jsonl
```

### "Permission denied" on Slack commands

Add your Slack user ID to `BEADS_ALLOWED_USERS` in `.env.local`:

```bash
# Find your ID in Slack: Profile -> "..." -> "Copy member ID"
BEADS_ALLOWED_USERS=U12345678
```

---

## Slack Commands Reference

| Command                | Description                |
| ---------------------- | -------------------------- |
| `@beads status`        | Show task counts by status |
| `@beads list [status]` | List tasks (default: open) |
| `@beads show <id>`     | Show task details          |
| `@beads ready`         | Show tasks ready for work  |
| `@beads blocked`       | Show blocked tasks         |
| `@beads help`          | Show command help          |

---

## BEADS CLI Reference

```bash
# Finding work
bd ready                    # Show issues ready to work
bd list --status=open       # All open issues
bd list --status=in_progress # Active work

# Creating & updating
bd create --title="..." --type=task --priority=2
bd update <id> --status=in_progress
bd close <id> --reason="Done"

# Dependencies
bd dep add <issue> <depends-on>
bd blocked                  # Show blocked issues

# Project health
bd stats                    # Statistics
bd doctor                   # Health check
```

---

## Support

- **BEADS CLI docs**: https://github.com/steveyegge/beads

---

_Last updated: March 2026_
