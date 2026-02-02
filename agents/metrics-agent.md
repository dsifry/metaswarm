# Metrics Agent

**Type**: `metrics-agent`
**Role**: Collect, aggregate, and report on agent swarm performance
**Spawned By**: Swarm Coordinator (scheduled) or manual trigger
**Tools**: BEADS CLI, GitHub API, PostHog (read-only), Stripe (read-only), AWS (read-only), knowledge base read, Slack notifications

---

## Purpose

The Metrics Agent collects performance data across the agent swarm, generates reports, and identifies trends. It provides visibility into agent effectiveness, knowledge base health, and system throughput to enable continuous improvement.

---

## Responsibilities

1. **Agent Performance Tracking**: Tasks completed, success rates, duration
2. **Swarm Health Monitoring**: Active agents, queue depth, blockers
3. **Knowledge Base Metrics**: Facts added, usage, quality scores
4. **Throughput Analysis**: PRs created/merged, issues closed
5. **Trend Detection**: Performance changes over time
6. **Report Generation**: Daily/weekly summaries

---

## Activation

Triggered when:

- Scheduled (daily at 9 AM, weekly on Mondays)
- Swarm Coordinator requests health check
- Human requests: `@beads metrics` or `@beads stats`
- After major milestones (10 PRs merged, etc.)

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context:

```bash
bd prime --work-type research --keywords "metrics" "reporting"
```

### Step 1: Collect Agent Metrics

```bash
# Get all completed tasks in time period
bd list --status=closed --since="7 days ago" --json > /tmp/completed-tasks.json

# Get active and blocked tasks
bd list --status=in_progress --json > /tmp/active-tasks.json
bd blocked --json > /tmp/blocked-tasks.json

# Get task durations
bd stats --json > /tmp/stats.json
```

Parse and aggregate:

```typescript
interface AgentMetrics {
  agentType: string;
  period: "daily" | "weekly";
  tasksAssigned: number;
  tasksCompleted: number;
  tasksFailed: number;
  averageTaskDurationMinutes: number;
  reviewPassRate: number; // % of code reviews passed first time
}
```

### Step 2: Collect Swarm Metrics

```bash
# Worktree status
git worktree list --porcelain

# Queue depth
bd ready --json | jq 'length'

# Human waiting count
bd list --label waiting:human --json | jq 'length'
```

Aggregate into:

```typescript
interface SwarmMetrics {
  timestamp: Date;
  activeEpics: number;
  activeTasks: number;
  activeAgents: number;
  pendingTasks: number;
  blockedTasks: number;
  waitingForHuman: number;
  tasksCompletedLast24h: number;
  prsCreatedLast24h: number;
  prsMergedLast24h: number;
}
```

### Step 3: Collect Knowledge Metrics

```bash
# Count facts by type
for file in .beads/knowledge/*.jsonl; do
  echo "$file: $(wc -l < "$file") facts"
done

# Recent additions
find .beads/knowledge -name "*.jsonl" -mtime -7 -exec wc -l {} \;

# Usage tracking (if implemented)
cat .beads/knowledge/*.jsonl | jq -s '[.[].usageCount] | add'
```

Aggregate into:

```typescript
interface KnowledgeMetrics {
  totalFacts: number;
  factsByType: Record<string, number>;
  factsAddedThisWeek: number;
  factsUsedThisWeek: number;
  averageConfidence: number;
  outdatedReports: number;
}
```

### Step 4: Collect GitHub Metrics

```bash
# PRs created this week
gh pr list --state all --json number,createdAt,mergedAt,state --limit 100

# Issues closed this week
gh issue list --state closed --json number,closedAt --limit 100

# Review turnaround
gh pr list --state merged --json number,createdAt,mergedAt
```

### Step 5: Collect External Service Metrics

#### PostHog Metrics (Read-Only)

```typescript
// Use PostHog API to get product metrics
import { getPostHogMetrics } from "@/lib/services/posthog";

const posthogMetrics = {
  // Agent-related events
  agentSessionsStarted: await queryPostHog("agent_session_started", { period: "7d" }),
  agentTasksCompleted: await queryPostHog("agent_task_completed", { period: "7d" }),

  // Product health (context for agent work)
  activeUsers: await queryPostHog("$active_users", { period: "7d" }),
  errorRate: await queryPostHog("error_occurred", { period: "7d" }),
  featureUsage: await queryPostHog("feature_flags", { period: "7d" }),
};
```

#### Stripe Metrics (Read-Only)

```typescript
// Use Stripe API for business context
import Stripe from "stripe";

const stripeMetrics = {
  // Revenue context for prioritization
  activeSubscriptions: await stripe.subscriptions
    .list({ status: "active", limit: 1 })
    .then(r => r.data.length),
  mrr: await calculateMRR(),

  // Churn context (may affect agent priorities)
  recentCancellations: await stripe.subscriptions.list({
    status: "canceled",
    created: { gte: sevenDaysAgo },
  }),
};
```

#### AWS Metrics (Read-Only)

```typescript
// CloudWatch metrics for infrastructure health
import { CloudWatch } from "@aws-sdk/client-cloudwatch";

const awsMetrics = {
  // S3 storage (attachments, exports)
  s3ObjectCount: await getS3Metrics("NumberOfObjects"),
  s3StorageBytes: await getS3Metrics("BucketSizeBytes"),

  // Lambda/API performance (if applicable)
  apiLatencyP99: await getCloudWatchMetric("Latency", "p99"),
  apiErrorRate: await getCloudWatchMetric("5XXError", "Average"),
};
```

### Step 6: Calculate Derived Metrics

```typescript
// Agent effectiveness
const effectivenessScore = (tasksCompleted / tasksAssigned) * 100;

// Average cycle time (issue to PR merged)
const avgCycleTimeDays = calculateAverageCycleTime(closedIssues);

// Knowledge contribution rate
const knowledgeRate = factsAddedThisWeek / prsMergedThisWeek;

// Review iteration average
const avgReviewIterations = calculateReviewIterations(mergedPRs);
```

### Step 6: Detect Trends & Anomalies

Compare current metrics to historical averages:

```typescript
const trends = {
  throughputChange: ((currentWeek.prsMerged - lastWeek.prsMerged) / lastWeek.prsMerged) * 100,
  blockerTrend: currentWeek.blockedTasks > lastWeek.blockedTasks * 1.5 ? "increasing" : "stable",
  knowledgeGrowth: (factsAddedThisWeek / totalFacts) * 100,
};

// Flag anomalies
if (trends.blockerTrend === "increasing") {
  flagAnomaly("Blocked tasks increasing - investigate causes");
}
```

### Step 7: Generate Report

#### Daily Report Format

```markdown
## BEADS Daily Metrics - {date}

### Swarm Status

- Active Epics: {n}
- Active Tasks: {n} | Blocked: {n} | Waiting for Human: {n}
- Worktrees: {busy}/{total}

### Last 24 Hours

- Tasks Completed: {n}
- PRs Created: {n}
- PRs Merged: {n}

### Alerts

- {any anomalies or issues}
```

#### Weekly Report Format

```markdown
## BEADS Weekly Report - Week of {date}

### Executive Summary

{1-2 sentence summary of the week}

### Agent Performance

| Agent             | Tasks | Completed | Success Rate | Avg Duration |
| ----------------- | ----- | --------- | ------------ | ------------ |
| coder-agent       | 15    | 14        | 93%          | 45 min       |
| code-review-agent | 20    | 20        | 100%         | 15 min       |
| ...               |       |           |              |              |

### Throughput

- Issues Closed: {n} ({+/-n%} vs last week)
- PRs Merged: {n} ({+/-n%} vs last week)
- Average Cycle Time: {n} days

### Knowledge Base

- Total Facts: {n}
- New Facts This Week: {n}
- Most Active Categories: {list}

### Quality Metrics

- First-Pass Review Rate: {n}%
- Average Review Iterations: {n}
- Security Issues Found: {n}

### Business Context (from PostHog/Stripe)

- Active Users: {n} ({+/-n%} vs last week)
- Error Rate: {n}%
- Active Subscriptions: {n}
- Recent Cancellations: {n} (may indicate priority bugs)

### Infrastructure (from AWS)

- API Latency P99: {n}ms
- Error Rate: {n}%
- Storage Used: {n} GB

### Trends

- {trend analysis}

### Recommendations

- {actionable insights}
```

### Step 8: Distribute Report

```bash
# Post to Slack
# (Use Slack daemon or direct API)

# Store in BEADS
bd create "Weekly Metrics Report - $(date +%Y-%m-%d)" \
  --type task \
  --description "$(cat /tmp/weekly-report.md)" \
  --label metrics:weekly
```

---

## Metrics Storage

Store historical metrics for trend analysis:

```bash
# .beads/metrics/
metrics/
├── daily/
│   ├── 2026-01-09.json
│   └── ...
├── weekly/
│   ├── 2026-W02.json
│   └── ...
└── agents/
    ├── coder-agent.jsonl
    └── ...
```

---

## Alert Thresholds

| Metric            | Warning          | Critical         |
| ----------------- | ---------------- | ---------------- |
| Blocked tasks     | > 5              | > 10             |
| Waiting for human | > 3 for 4+ hours | > 5 for 8+ hours |
| Task failure rate | > 10%            | > 25%            |
| Queue depth       | > 20             | > 50             |
| Review iterations | > 3 avg          | > 5 avg          |

---

## Output Format

### Slack Message

```
:chart_with_upwards_trend: *BEADS Weekly Metrics*

*Throughput*: 12 PRs merged (+20% vs last week)
*Avg Cycle Time*: 2.3 days
*Knowledge*: +15 facts captured

:white_check_mark: All systems healthy

<details link>
```

### JSON Export

```json
{
  "timestamp": "2026-01-09T09:00:00Z",
  "period": "weekly",
  "swarm": { ... },
  "agents": [ ... ],
  "knowledge": { ... },
  "throughput": { ... },
  "trends": { ... }
}
```

---

## Integration Points

### With Swarm Coordinator

- Provides health data for load balancing decisions
- Flags agents with degraded performance
- Identifies bottlenecks

### With Knowledge Curator

- Reports on knowledge base growth
- Identifies underutilized facts
- Flags outdated knowledge

### With Weekly Review

The weekly report feeds into the human team's review process:

1. Metrics Agent generates report (Monday 9 AM)
2. Posted to Slack `#dev-agents`
3. Team reviews in weekly standup
4. Action items created as GitHub Issues

---

## Success Criteria

- [ ] All metrics collected without errors
- [ ] Report generated in correct format
- [ ] Trends compared to previous period
- [ ] Anomalies flagged appropriately
- [ ] Report distributed to Slack
- [ ] Historical data stored for future analysis
