---
name: beads-orchestration
description: Multi-agent orchestration for GitHub Issues using BEADS task tracking
auto_activate: true
triggers:
  - "work on issue"
  - "start issue"
  - "@beads"
  - "agent-ready label"
---

# BEADS Multi-Agent Orchestration Skill

This skill coordinates a swarm of specialized AI agents to autonomously handle GitHub Issues from creation to merged PR.

---

## Quick Start

### Start Work on a GitHub Issue

```bash
# User triggers via any of:
@beads start #123
bd start 123
/project:beads-start 123
```

### Check BEADS Status

```bash
bd ready          # Show tasks ready to work
bd list           # Show all tasks
bd stats          # Show project statistics
bd doctor         # Check system health
```

---

## Agent Roster

| Agent                     | Role                           | Spawned When                       |
| ------------------------- | ------------------------------ | ---------------------------------- |
| **Issue Orchestrator**    | Main coordinator per Issue     | Issue receives `agent-ready` label |
| **Researcher Agent**      | Codebase exploration           | Orchestrator creates research task |
| **Architect Agent**       | Implementation planning        | Research complete                  |
| **Product Manager Agent** | Use case & user benefit review | Design review gate (parallel)      |
| **Designer Agent**        | UX/API design review           | Design review gate (parallel)      |
| **Security Design Agent** | Security threat modeling       | Design review gate (parallel)      |
| **CTO Agent**             | TDD readiness & plan review    | Design review gate (parallel)      |
| **Coder Agent**           | TDD implementation             | Design review gate approved        |
| **Code Review Agent**     | Internal code review           | Implementation complete            |
| **Security Auditor**      | Security review (code)         | Implementation complete            |
| **PR Shepherd**           | PR lifecycle management        | PR created                         |

See `agents/` directory for detailed agent definitions.

---

## Design Review Gate (NEW)

For complex features created via brainstorming, an automatic **Design Review Gate** ensures quality before implementation:

```
Design Document Created
        │
        ▼
┌─────────────────────────────────────────────────┐
│           DESIGN REVIEW GATE                     │
│                                                  │
│  Spawns in PARALLEL:                            │
│  • Architect Agent (technical architecture)     │
│  • Designer Agent (UX/API design)               │
│  • CTO Agent (TDD readiness)                    │
│                                                  │
│  ALL THREE must approve to proceed              │
└─────────────────────────────────────────────────┘
        │
        ├── Any NEEDS_REVISION? → Iterate on design (max 3x)
        │
       ALL APPROVED
        │
        ▼
   Create BEADS Epic → Begin Implementation
```

### Triggering the Design Review Gate

The gate is automatically triggered when:

- `superpowers:brainstorming` completes and commits a design doc
- User runs `/project:review-design <path-to-design.md>`

### Review Criteria by Agent

| Agent           | Focus Areas                                                |
| --------------- | ---------------------------------------------------------- |
| Product Manager | Use case clarity, user benefits, scope, success metrics    |
| Architect       | Service architecture, dependencies, patterns, integration  |
| Designer        | API design, UX flows, developer experience, consistency    |
| Security Design | Threat modeling, auth/authz, data protection, OWASP Top 10 |
| CTO             | TDD readiness, codebase alignment, completeness, risks     |

### Iteration Protocol

- **Max 3 iterations** before human escalation
- Each iteration: revise design → re-run all reviewers
- Escalation options: Override / Defer / Cancel

See `your-project:design-review-gate` skill for full details.

---

## Orchestrated Execution

After design review approval, implementation follows the **4-phase execution loop** per work unit. This replaces the previous linear "implement then review" flow with rigorous independent validation and adversarial review.

### The Pattern

For each work unit (a discrete, spec-driven change with DoD items):

1. **IMPLEMENT** — Coding subagent executes against the spec using TDD
2. **VALIDATE** — Orchestrator independently runs quality gates (tsc, eslint, vitest). **Never trust subagent self-reports.**
3. **ADVERSARIAL REVIEW** — Fresh review subagent checks against spec contract. Binary PASS/FAIL. Uses `adversarial-review-rubric.md`.
4. **COMMIT** — Only after adversarial PASS

On FAIL: fix → re-validate → spawn **fresh** reviewer (max 3 retries → escalate to human).

### Key Principles

- **Trust nothing, verify everything**: The orchestrator runs validation commands directly, never asks the coding subagent "did the tests pass?"
- **Spec as contract**: DoD items are the contract. Adversarial reviewers check exact compliance with file:line evidence.
- **Fresh reviewers**: On re-review after FAIL, a NEW reviewer instance is spawned with no memory of the previous review. Prevents anchoring bias.
- **Human checkpoints**: Planned pauses at critical boundaries (schema changes, security code, first use of new patterns). The orchestrator waits for explicit human approval before continuing.

### Final Comprehensive Review

After all work units pass individually, a final cross-unit review catches integration issues:
- Combined diff across all work units
- Full test suite (not just per-unit tests)
- Cross-unit type consistency and import conflicts
- Coverage thresholds

See `orchestrated-execution` skill for the full pattern, including work unit decomposition, parallel execution, recovery protocol, and anti-patterns.

---

## Workflow Overview

```
GitHub Issue #123 (agent-ready label)
        │
        ▼
┌─────────────────────────────────────┐
│       Issue Orchestrator             │
│  Creates BEADS epic, delegates work  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       Research Phase                 │
│  Researcher Agent explores codebase  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       Planning Phase                 │
│  Architect Agent creates plan        │
└─────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│              DESIGN REVIEW GATE (PARALLEL)                     │
│                                                                │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────┐ │
│  │   PM    │ │ Architect│ │ Designer │ │ Security │ │  CTO  │ │
│  │(users)  │ │  (tech)  │ │ (UX/API) │ │ (threats)│ │ (TDD) │ │
│  └─────────┘ └──────────┘ └──────────┘ └──────────┘ └───────┘ │
│                                                                │
│  ALL FIVE must approve (max 3 iterations)                      │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       Work Unit Decomposition        │
│  Break plan into work units w/ DoD   │
│  Build dependency graph              │
└─────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│           ORCHESTRATED EXECUTION LOOP (per work unit)          │
│                                                                │
│   ┌──────────┐    ┌──────────┐    ┌──────────────┐   ┌──────┐ │
│   │IMPLEMENT │───→│ VALIDATE │───→│  ADVERSARIAL │──→│COMMIT│ │
│   │(Coder)   │    │(Orchest.)│    │   REVIEW     │   │      │ │
│   └──────────┘    └──────────┘    └──────┬───────┘   └──────┘ │
│        ▲                                 │ FAIL                │
│        └─────────────────────────────────┘                     │
│                                                                │
│   Trust nothing. Verify everything. Review adversarially.      │
│   See: orchestrated-execution skill for full details           │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│   Final Comprehensive Review         │
│   Cross-unit integration check       │
│   Full test suite + type check       │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│   PR Creation (Auto-Shepherd)        │
│   bin/create-pr-with-shepherd.sh     │
│   → Auto-invokes pr-shepherd skill   │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       PR Shepherd (Automatic)        │
│  Monitors CI, handles reviews,       │
│  resolves threads automatically      │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       Human Approval & Merge         │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│       Close Epic & Extract Learnings │
└─────────────────────────────────────┘
```

### GTG (Good-To-Go) Merge Gate

GTG is the final merge gate. It consolidates CI status, comment classification, and thread resolution into a single deterministic check. Agents should use it as the primary readiness signal:

```bash
# Check if PR is ready to merge
gtg <PR_NUMBER> --format json \
  --exclude-checks "Merge Ready (gtg)" \
  --exclude-checks "CodeRabbit" \
  --exclude-checks "Cursor Bugbot" \
  --exclude-checks "claude"
```

**Statuses**: `READY` (merge), `ACTION_REQUIRED` (fix comments), `UNRESOLVED_THREADS` (resolve threads), `CI_FAILING` (fix CI). The `action_items` array tells agents exactly what to fix.

**GTG reports, agents act**: GTG does not resolve threads or fix code. After addressing feedback, agents must resolve threads themselves via the GraphQL mutation documented in `handle-pr-comments.md` (Section 3: Resolving Review Threads). GTG will report `READY` on the next check once threads are resolved.

If the CI check is stale: `gh workflow run gtg.yml -f pr_number=<PR_NUMBER>`

### Automatic PR Review Cycles

When a PR is created via `bin/create-pr-with-shepherd.sh`, the script outputs instructions to start monitoring:

1. **Creates the PR** with proper title/body
2. **Start pr-shepherd** using `/project:pr-shepherd <pr-number>`
3. **PR Shepherd monitors**: CI status, review comments, thread resolution
4. **Auto-fixes**: Lint, type errors, test failures in your code
5. **Reports when ready**: All CI green, all threads resolved

For manually-created PRs, invoke `/project:pr-shepherd <pr-number>` to start the monitoring cycle.

---

## BEADS Commands Reference

### Issue Management

```bash
# Create epic for GitHub Issue
bd create "Feature: User Auth" --type epic --issue 123

# Create task under epic
bd create "Research auth patterns" --type task --parent bd-abc123

# Add dependency
bd dep add <blocked-task> <blocking-task>

# Update status
bd update <task-id> --status open|in_progress|blocked|closed

# Close with reason
bd close <task-id> --reason "Completed successfully"
```

### Task Discovery

```bash
# Show ready (unblocked) tasks
bd ready --json

# List all tasks under epic
bd list --parent <epic-id>

# Show blocked tasks
bd blocked

# Show task details
bd show <task-id> --json
```

### Labels for Custom States

```bash
# Waiting for human input
bd label add <task-id> waiting:human

# Waiting for CI
bd label add <task-id> waiting:ci

# Agent failed, needs intervention
bd label add <task-id> agent:failed

# Review iteration tracking
bd label add <task-id> review:iteration-1
```

### Sync Operations

```bash
# Check sync status
bd sync --status

# Pull updates from main
bd sync --from-main

# Export to JSONL
bd export
```

---

## Starting Work on an Issue

### Step 1: Verify Issue is Ready

```bash
# Check Issue has agent-ready label
gh issue view 123 --json labels | jq '.labels[].name' | grep agent-ready
```

### Step 2: Create BEADS Epic

```bash
# Get Issue details
ISSUE=$(gh issue view 123 --json title,body,number)

# Create epic linked to Issue
bd create "$(echo $ISSUE | jq -r .title)" --type epic --issue 123 --json
```

### Step 3: Post Acknowledgment

```bash
gh issue comment 123 --body "🤖 Agent claiming this issue. BEADS epic created."
```

### Step 4: Spawn Issue Orchestrator

Use the Task tool to spawn the Issue Orchestrator agent:

```typescript
Task({
  subagent_type: "general-purpose",
  description: "Issue Orchestrator for #123",
  prompt: `You are the ISSUE ORCHESTRATOR agent.

Read the agent definition at:
.claude/plugins/your-project/skills/beads/agents/issue-orchestrator.md

Your task:
- Epic ID: <epic-id>
- GitHub Issue: #123
- Begin the orchestration workflow

Follow the workflow phases exactly as specified.`,
});
```

---

## Human Escalation Protocol

### When to Escalate

1. **Ambiguous Requirements**: Issue lacks clarity
2. **Conflicting Constraints**: Can't satisfy all requirements
3. **Risk Decision**: Security or data concerns
4. **Blocked > 1 Hour**: External dependency needed
5. **3 Failed Iterations**: Agent can't resolve issue

### How to Escalate

```bash
# Mark task as waiting
bd update <task-id> --status blocked
bd label add <task-id> waiting:human

# Post to GitHub Issue
gh issue comment <number> --body "$(cat <<'EOF'
## 🤖 Agent Request: <type>

**Task**: <task-id>
**Question**: <clear question>

### Options
1. **Option A**: <description>
2. **Option B**: <description>

### Agent Recommendation
<recommendation>

---
Reply: `@beads approve <task-id>` or `@beads respond <task-id> <option>`
EOF
)"
```

### Human Response Patterns

```bash
# Approve a blocked task
@beads approve bd-abc123

# Respond with choice
@beads respond bd-abc123 "Use option A"

# Request changes
@beads request-changes bd-abc123 "Need more error handling"

# Defer to later
@beads defer bd-abc123 "Discuss in Monday standup"
```

---

## Agent Spawning Patterns

### Sequential Spawning

```typescript
// Spawn Researcher first
const researchResult = await Task({
  subagent_type: "general-purpose",
  description: "Research for issue #123",
  prompt: researcherPrompt,
});

// Then spawn Architect with research output
const planResult = await Task({
  subagent_type: "general-purpose",
  description: "Planning for issue #123",
  prompt: architectPrompt + researchResult,
});
```

### Parallel Spawning

```typescript
// Spawn Code Review and Security Audit in parallel
const [reviewResult, securityResult] = await Promise.all([
  Task({
    subagent_type: "general-purpose",
    description: "Code review for #123",
    prompt: codeReviewPrompt,
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Security audit for #123",
    prompt: securityAuditPrompt,
  }),
]);
```

---

## Knowledge Integration

### CRITICAL: Prime Before Starting Work

**ALL agents MUST prime their context before starting ANY work.** This prevents bad assumptions and ensures alignment with established patterns.

```bash
# General prime (loads critical rules + gotchas)
bd prime

# Prime for specific files you'll modify
bd prime --files "src/lib/services/*.ts" "src/api/routes/*.ts"

# Prime for specific topic
bd prime --keywords "authentication" "jwt"

# Prime for work type
bd prime --work-type planning     # Before planning
bd prime --work-type implementation  # Before coding
bd prime --work-type review       # Before reviewing
bd prime --work-type research     # Before exploring

# Combined (most thorough)
bd prime --files "<files>" --keywords "<topic>" --work-type <type>
```

The prime command outputs relevant facts categorized as:

- **MUST FOLLOW**: Critical rules (NEVER/ALWAYS/MUST statements)
- **GOTCHAS**: Common pitfalls to avoid
- **PATTERNS**: Best practices for this codebase
- **DECISIONS**: Architectural choices

### After Completing Work

Run self-reflection to extract learnings:

```bash
# Fetch recent PR comments
GITHUB_TOKEN=$(gh auth token) npx tsx scripts/beads-fetch-pr-comments.ts --days 7

# Use self-reflect skill to evaluate and add learnings
/project:self-reflect
```

Or spawn Knowledge Curator agent:

```typescript
Task({
  subagent_type: "general-purpose",
  description: "Extract learnings from epic",
  prompt: `Review completed epic <epic-id> and extract learnings.

FIRST: Run \`bd prime --work-type review\` to load context.

Then analyze:
- What patterns were used?
- What gotchas were discovered?
- What should future agents know?

Use the knowledge capture service to store learnings.`,
});
```

---

## Recursive Orchestration

For large epics, orchestrators can spawn sub-orchestrators. The pattern:

```text
Epic (Issue Orchestrator)
├── Sub-Epic A (Sub-Orchestrator)
│   ├── Task A1
│   └── Task A2
├── Sub-Epic B (Sub-Orchestrator)
│   ├── Task B1
│   └── Task B2
└── Integration Task (blocked by A + B)
```

**When to decompose**: If an epic has more than 5-7 tasks or spans multiple domains (e.g., frontend + backend + schema), split into sub-epics.

```bash
# Create sub-epics under parent epic
bd create "Sub-Epic: API layer" --type epic --parent <parent-epic-id>
bd create "Sub-Epic: UI components" --type epic --parent <parent-epic-id>

# Each sub-epic gets its own orchestrator
# The parent orchestrator coordinates completion
```

Each sub-epic's orchestrator follows the same workflow (research → plan → review → implement → PR) independently. The parent orchestrator monitors progress and coordinates the final integration.

---

## Success Criteria Checklist

Before closing an epic, verify ALL:

- [ ] Work units decomposed with DoD items and file scopes
- [ ] Each work unit passed the 4-phase execution loop
- [ ] All adversarial reviews resulted in PASS
- [ ] Final comprehensive review completed (cross-unit integration)
- [ ] All human checkpoints acknowledged
- [ ] All BEADS tasks under epic are closed
- [ ] PR is created and linked to GitHub Issue
- [ ] All CI checks are passing
- [ ] All PR comments are addressed
- [ ] All PR threads are resolved
- [ ] Human has approved merge
- [ ] PR is merged to main
- [ ] GitHub Issue is closed
- [ ] Learnings extracted to knowledge base

---

## Troubleshooting

### Task Stuck in Progress

```bash
# Check task status
bd show <task-id> --json

# Check for orphaned agent
# If agent failed, reset and retry
bd update <task-id> --status open
bd label remove <task-id> agent:failed
```

### Circular Dependencies

```bash
# Run doctor to detect
bd doctor

# If found, restructure dependencies
bd dep remove <task1> <task2>
```

### BEADS Sync Issues

```bash
# Check sync status
bd sync --status

# Force export
bd export

# Pull from main
bd sync --from-main
```

---

## Directory Structure

```
.claude/plugins/your-project/skills/beads/
├── SKILL.md                    # This file
└── agents/
    ├── issue-orchestrator.md   # Main coordinator (runs 4-phase loop)
    ├── researcher-agent.md     # Codebase exploration
    ├── architect-agent.md      # Implementation planning
    ├── product-manager-agent.md # Use case & user benefit review
    ├── designer-agent.md       # UX/API design review
    ├── security-design-agent.md # Security threat modeling
    ├── cto-agent.md            # TDD readiness review
    ├── coder-agent.md          # TDD implementation
    ├── code-review-agent.md    # Internal code review (collaborative + adversarial modes)
    ├── security-auditor-agent.md # Security review (implementation)
    └── pr-shepherd-agent.md    # PR lifecycle management

.claude/plugins/your-project/skills/orchestrated-execution/
└── SKILL.md                    # 4-phase execution loop pattern

.claude/plugins/your-project/skills/design-review-gate/
└── SKILL.md                    # Design review gate orchestrator

.claude/plugins/your-project/skills/brainstorming-extension/
└── SKILL.md                    # Hooks brainstorming to review gate

.claude/commands/
└── review-design.md            # /project:review-design command

.claude/rubrics/
├── plan-review-rubric.md       # Used by CTO Agent
├── code-review-rubric.md       # Used by Code Review Agent (collaborative mode)
└── adversarial-review-rubric.md # Used by Code Review Agent (adversarial mode)

.beads/
├── beads.db                    # SQLite database
├── issues.jsonl                # Issue/task data
└── knowledge/                  # Curated learnings
    ├── codebase-facts.jsonl
    ├── patterns.jsonl
    └── anti-patterns.jsonl
```
