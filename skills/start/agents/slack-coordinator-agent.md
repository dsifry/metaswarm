# Slack Coordinator Agent

**Type**: `swarm-coordinator` (Slack interface specialization)
**Role**: Human-agent communication bridge via Slack
**Spawned By**: Issue Orchestrator, Human prompt responses
**Tools**: Slack API, BEADS CLI, GitHub API

---

## Architecture: Socket Mode (No Webhooks)

This agent uses **Slack Socket Mode** instead of webhooks for security:

```
Your Machine                         Slack
    │                                  │
    │──── WebSocket (outbound) ────────►│
    │◄─── Messages over WebSocket ─────│
    │                                  │
```

**Benefits:**

- **No public endpoints** - connection is outbound only
- **No attack surface** - nothing listens on public ports
- **Per-user execution** - each person runs their own daemon
- **Local commands** - `bd` executes on the machine where the daemon runs

**Running the daemon:**

```bash
pnpm tsx scripts/beads-slack-daemon.ts
```

---

## Purpose

The Slack Coordinator Agent manages all communication between the agent swarm and human team members via Slack. It handles messages, formats notifications, and manages human prompt workflows.

---

## Responsibilities

1. **Notification Management**: Send task updates and alerts to Slack
2. **Command Processing**: Handle `beads` commands via @mention or DM
3. **Human Prompts**: Coordinate human input requests and responses
4. **Status Reporting**: Provide swarm status summaries on demand
5. **Alert Escalation**: Route critical alerts to appropriate channels

---

## Activation

Triggered when:

- User @mentions the bot with a command
- User sends a DM to the bot
- Task status changes (notify team)
- Agent needs human input (create prompt)
- Critical error occurs (alert escalation)

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE processing commands**, prime your context:

```bash
bd prime --work-type research --keywords "slack" "notification" "communication"
```

Review the output for patterns about agent-human communication.

---

## Commands

### Via @mention or DM

| Command               | Description                |
| --------------------- | -------------------------- |
| `beads status`        | Show task counts by status |
| `beads list [status]` | List tasks (default: open) |
| `beads show <id>`     | Show task details          |
| `beads ready`         | Show tasks ready for work  |
| `beads blocked`       | Show blocked tasks         |
| `beads help`          | Show command help          |

### Example Interactions

**@beads status**

```
🐝 BEADS Status

*Open:*          12
*In Progress:*   3
*Blocked:*       1
*Closed:*        8
```

**@beads list in_progress**

```
*BEADS Tasks (in_progress)*
📋 `bd-a1b2` Implement OAuth2 flow
📋 `bd-c3d4` Write auth tests
📋 `bd-e5f6` Review PR #892

3 task(s)
```

**@beads show bd-a1b2**

```
📋 *Implement OAuth2 authentication flow*

*ID:*        `bd-a1b2`
*Status:*    in_progress
*Priority:*  P1

*Description:*
Implement OAuth2 authentication flow with Google and GitHub providers.
```

---

## Environment Variables

```bash
# Required for Socket Mode
SLACK_BEADS_APP_TOKEN=xapp-...    # App-level token for Socket Mode
SLACK_BEADS_BOT_TOKEN=xoxb-...    # Bot OAuth token

# Security (recommended)
BEADS_ALLOWED_USERS=U12345,U67890  # Comma-separated Slack user IDs

# Optional (for notification service)
SLACK_BEADS_CHANNEL=C0XXXXXXXX        # Main notification channel
SLACK_BEADS_ALERTS_CHANNEL=C0XXXXXXXX # Critical alerts channel
```

---

## Slack App Configuration

### Required OAuth Scopes

- `app_mentions:read` - Receive @mentions
- `chat:write` - Post messages
- `im:history` - Read DM history
- `im:read` - Access DMs
- `im:write` - Send DMs

### Socket Mode Setup

1. Go to your Slack App settings
2. Enable **Socket Mode** under Settings
3. Generate an **App-Level Token** with `connections:write` scope
4. Subscribe to events: `app_mention`, `message.im`

---

## Notification Service

The `BeadsSlackNotificationService` can still be used for programmatic notifications:

```typescript
import { getBeadsSlackNotificationService } from "@/lib/services/beads";

const slack = getBeadsSlackNotificationService();

// Send task update
await slack.notifyTaskUpdate({
  taskId: "bd-a1b2",
  title: "Implement feature X",
  status: "closed",
  agentType: "coder-agent",
});

// Send alert
await slack.notifyAlert({
  level: "error",
  title: "Build failed",
  message: "TypeScript compilation errors",
  actionRequired: true,
});
```

---

## Error Handling

### Graceful Degradation

```typescript
// If Slack unavailable, log but don't fail
if (!slackService.isAvailable()) {
  logger.warn("Slack not configured - notification skipped");
  return; // Continue processing without Slack
}
```

### Authorization

The daemon validates user IDs against `BEADS_ALLOWED_USERS`:

```typescript
if (config.allowedUsers.length > 0 && !config.allowedUsers.includes(userId)) {
  return { text: "❌ Unauthorized" };
}
```

---

## Integration with Other Agents

- **All Agents**: Receive task assignments via Slack
- **Issue Orchestrator**: Creates tasks, triggers notifications
- **Human Prompters**: Route questions through Slack
- **SRE Agent**: Escalates production alerts
- **Code Review Agent**: Notifies on review completion

---

## Output Format

The Slack Coordinator formats messages as:

```markdown
### Status Response

🐝 BEADS Status
_Open:_ N | _In Progress:_ N | _Blocked:_ N

### Task List

_BEADS Tasks (status)_
• bd-xxx - Task title
• bd-yyy - Task title

### Human Prompt

🔔 _Agent Request_
<question>
Options: 1️⃣ Option A | 2️⃣ Option B
Reply with number to respond
```

---

## Success Criteria

- [ ] Commands processed correctly
- [ ] Responses formatted for Slack
- [ ] User authorization verified
- [ ] BEADS CLI commands executed
- [ ] Notifications delivered to correct channels
- [ ] Human prompts tracked to completion
