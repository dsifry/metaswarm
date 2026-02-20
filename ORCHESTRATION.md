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
/beads-start 123
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
│  • UX Reviewer (user flows, integration WUs)    │
│  • CTO Agent (TDD readiness)                    │
│                                                  │
│  ALL must approve to proceed                    │
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
- User runs `/review-design <path-to-design.md>`

### Review Criteria by Agent

| Agent           | Focus Areas                                                |
| --------------- | ---------------------------------------------------------- |
| Product Manager | Use case clarity, user benefits, scope, success metrics    |
| Architect       | Service architecture, dependencies, patterns, integration  |
| Designer        | API design, UX flows, developer experience, consistency    |
| Security Design | Threat modeling, auth/authz, data protection, OWASP Top 10 |
| UX Reviewer     | User flows, text wireframes, integration WUs, empty/error states |
| CTO             | TDD readiness, codebase alignment, completeness, risks     |

### Iteration Protocol

- **Max 3 iterations** before human escalation
- Each iteration: revise design → re-run all reviewers
- Escalation options: Override / Defer / Cancel

See `your-project:design-review-gate` skill for full details.

---

## Team Mode Coordination

When multiple Claude Code sessions are active on the same repository (e.g., parallel worktrees), metaswarm automatically enters **Team Mode**. In Team Mode, agents behave as persistent teammates with context retention across sessions and direct inter-agent messaging for coordination. Mode detection is automatic based on the presence of concurrent sessions.

For the full Team Mode protocol — including message routing, context sharing, and conflict resolution — see `guides/agent-coordination.md`.

---

## Plan Review Gate

After the Architect creates an implementation plan and before it reaches the Design Review Gate, the plan passes through the **Plan Review Gate**. Three adversarial reviewers validate the plan independently:

| Reviewer | Focus |
| --- | --- |
| **Feasibility** | Technical viability, dependency risks, resource constraints |
| **Completeness** | Missing work units, untested edge cases, gaps in Definition of Done |
| **Scope & Alignment** | Plan stays within issue scope, aligns with codebase conventions |

All 3 must APPROVE before the plan proceeds. See `skills/plan-review-gate/SKILL.md` for the full skill definition.

---

## Orchestrated Execution

After design review approval, implementation follows the **4-phase execution loop** per work unit. This replaces the previous linear "implement then review" flow with rigorous independent validation and adversarial review.

### Core Principle

**Trust nothing. Verify everything. Review adversarially.**

### Plan Validation (Pre-Flight)

Before submitting to the Design Review Gate, the orchestrator runs a pre-flight checklist covering architecture, dependency graph, API contracts, security, UI/UX, and external dependencies. This catches structural issues (missing service layer, wrong dependency graph, oversized WUs) before spending agent cycles on review.

### The 4-Phase Loop

For each work unit (a discrete, spec-driven change with DoD items):

1. **IMPLEMENT** — Coding subagent executes against the spec using TDD, with the Project Context Document
2. **VALIDATE** — Orchestrator independently runs quality gates (tsc, eslint, vitest, coverage enforcement from `.coverage-thresholds.json`). **Never trust subagent self-reports.** Quality gates are **blocking state transitions**, not advisory.
3. **ADVERSARIAL REVIEW** — Fresh review subagent checks against spec contract. Binary PASS/FAIL with file:line evidence. Uses `adversarial-review-rubric.md`. When external tools are configured, cross-model review ensures the writer is always reviewed by a different AI model (see External Tools section below).
4. **COMMIT** — Only after adversarial PASS. Updates `SERVICE-INVENTORY.md` and Project Context Document.

On FAIL: fix → re-validate → spawn **fresh** reviewer (max 3 retries → escalate to human). There is NO path from FAIL to COMMIT without passing through the retry loop.

### When to Use Orchestrated Execution

- The task has a **written spec** with enumerable Definition of Done items
- The implementation involves **multiple work units** (3+ logical changes)
- You need **independent verification** — subagent self-reports aren't sufficient
- The changes are **high-stakes** (schema changes, security, new architectural patterns)
- You want **proactive human checkpoints** at planned review points

### When NOT to Use It

- Single-file bug fixes or copy changes
- Tasks without a written spec or DoD items
- Quick prototyping or exploratory work
- Tasks where the overhead of decomposition exceeds the work itself

For simple tasks, the standard linear flow (implement → code review → PR) works fine.

### Key Concepts

**Work Unit Decomposition**: Break the implementation plan into discrete work units, each with:
- A spec section and enumerated DoD items
- A declared file scope (which files it may modify)
- Dependencies on other work units
- An optional human checkpoint flag

**Independent Validation**: The orchestrator runs `tsc`, `eslint`, and `vitest` directly — it does NOT ask the coding subagent "did the tests pass?" and accept the answer.

**Adversarial Review**: Fundamentally different from collaborative code review. The reviewer is an independent auditor checking spec compliance, not a helpful colleague suggesting improvements. Binary PASS/FAIL verdict. Evidence required (file:line references).

**Fresh Reviewer Rule**: On re-review after FAIL, a NEW reviewer instance is spawned with no memory of the previous review. This prevents anchoring bias.

**Human Checkpoints**: Planned pauses at critical boundaries (schema changes, security code, first use of new patterns). The orchestrator waits for explicit human approval before continuing.

**Final Comprehensive Review**: After all work units pass, a cross-unit review catches integration issues that per-unit reviews miss.

See `orchestrated-execution` skill for the complete pattern, including work unit structure, parallel execution, recovery protocol, and anti-patterns.

---

## External AI Tools (Optional)

When external AI CLI tools are configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI. This enables cost savings through cheaper models and cross-model adversarial review that eliminates single-model blind spots.

### How It Integrates

External tools slot directly into the existing 4-phase execution loop:

- **Phase 1 (IMPLEMENT)**: The orchestrator may delegate to an external tool instead of spawning a Claude subagent. The tool works in an isolated git worktree.
- **Phase 2 (VALIDATE)**: Unchanged — the orchestrator independently runs all quality gates regardless of who implemented.
- **Phase 3 (ADVERSARIAL REVIEW)**: Cross-model review — the writer is always reviewed by a different model (e.g., Codex writes, Gemini + Claude review).
- **Phase 4 (COMMIT)**: Unchanged — merge worktree branch after all phases pass.

### Escalation Chain

The orchestrator adapts based on tool availability:

| Available Tools | Escalation Chain | Max Attempts |
|---|---|---|
| Both Codex + Gemini | A(2) → B(2) → Claude(1) → user | 5 |
| One tool only | Tool(2) → Claude(1) → user | 3 |
| No tools | Claude → user (existing behavior) | unchanged |

Each escalated model receives the previous model's branch as a reference. See `skills/external-tools/SKILL.md` for the full skill definition.

### Health Check

```bash
/external-tools-health
```

Checks installation, authentication, and reachability of all configured adapters.

---

## Visual Review

The `visual-review` skill enables agents to take screenshots of web pages, presentations, and UIs using Playwright for visual inspection. This bridges the gap where agents cannot see rendered output.

### Usage

The skill is triggered when tasks involve visual output (web UIs, Reveal.js presentations, landing pages, email templates). It captures screenshots at configurable viewport sizes, and agents analyze them for layout, typography, colors, spacing, and content issues.

### Prerequisites

```bash
npx playwright install chromium
```

For remote/headless environments, the skill serves screenshots via HTTP file server so users can view them in their local browser.

See `skills/visual-review/SKILL.md` for the complete workflow.

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
┌─────────────────────────────────────┐
│       Plan Review Gate               │
│  3 adversarial reviewers:            │
│  Feasibility, Completeness,         │
│  Scope & Alignment                   │
│  ALL 3 must approve                  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│   External Dependency Detection      │
│   Scans spec for API keys/creds     │
│   Prompts user to configure them    │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│   Plan Validation (Pre-Flight)       │
│   Architecture, deps, API contracts  │
│   Security, UI/UX, external deps    │
└─────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    DESIGN REVIEW GATE (PARALLEL)                          │
│                                                                           │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ ┌───────┐ │
│  │   PM    │ │ Architect│ │ Designer │ │ Security │ │UX Revw.│ │  CTO  │ │
│  │(users)  │ │  (tech)  │ │ (UX/API) │ │ (threats)│ │(flows) │ │ (TDD) │ │
│  └─────────┘ └──────────┘ └──────────┘ └──────────┘ └────────┘ └───────┘ │
│                                                                           │
│  ALL SIX must approve (max 3 iterations)                                  │
└──────────────────────────────────────────────────────────────────────────┘
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
2. **Start pr-shepherd** using `/pr-shepherd <pr-number>`
3. **PR Shepherd monitors**: CI status, review comments, thread resolution
4. **Auto-fixes**: Lint, type errors, test failures in your code
5. **Reports when ready**: All CI green, all threads resolved

For manually-created PRs, invoke `/pr-shepherd <pr-number>` to start the monitoring cycle.

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
/self-reflect
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

- [ ] Plan validation (pre-flight) passed before design review
- [ ] External dependencies identified and user prompted for credentials
- [ ] Work units decomposed with DoD items and file scopes
- [ ] Each work unit passed the 4-phase execution loop
- [ ] All quality gates enforced as blocking state transitions (no advisory skips)
- [ ] Coverage thresholds met per `.coverage-thresholds.json`
- [ ] All adversarial reviews resulted in PASS (with fresh reviewer on re-review)
- [ ] `SERVICE-INVENTORY.md` updated with all new services/factories/modules
- [ ] Project Context Document maintained and passed to each coder subagent
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

.claude/plugins/your-project/skills/plan-review-gate/
└── SKILL.md                    # 3 adversarial reviewers validate plans

.claude/plugins/your-project/skills/external-tools/
├── SKILL.md                    # External AI tool delegation
└── adapters/
    ├── _common.sh              # Shared adapter helpers (14 functions)
    ├── codex.sh                # OpenAI Codex CLI adapter
    └── gemini.sh               # Google Gemini CLI adapter

.claude/plugins/your-project/skills/visual-review/
└── SKILL.md                    # Playwright-based visual review

guides/
├── agent-coordination.md       # Team Mode, inter-agent messaging
├── git-workflow.md             # Branch naming, commit conventions
├── testing-patterns.md         # TDD workflow, mock strategies
├── coding-standards.md         # Language idioms, naming conventions
├── worktree-development.md     # Parallel development with worktrees
└── build-validation.md         # Pre-push checks, CI pipeline

.claude/commands/
└── review-design.md            # /review-design command

.claude/rubrics/
├── plan-review-rubric.md       # Used by CTO Agent
├── code-review-rubric.md       # Used by Code Review Agent (collaborative mode)
├── adversarial-review-rubric.md # Used by Code Review Agent (adversarial mode)
└── external-tool-review-rubric.md  # Used by cross-model adversarial review

.claude/templates/
├── CLAUDE.md                   # Full CLAUDE.md template for new projects
├── CLAUDE-append.md            # Metaswarm section to append to existing CLAUDE.md
├── UI-FLOWS.md                 # User flow and wireframe documentation template
├── .gitignore                  # Standard Node.js/TypeScript ignores
├── .env.example                # Environment variable documentation template
├── SERVICE-INVENTORY.md        # Service/factory/module tracking template
└── ci.yml                      # CI pipeline template

.beads/
├── beads.db                    # SQLite database
├── issues.jsonl                # Issue/task data
└── knowledge/                  # Curated learnings
    ├── codebase-facts.jsonl
    ├── patterns.jsonl
    └── anti-patterns.jsonl
```
