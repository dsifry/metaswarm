# Agent Coordination Guide

This guide defines two coordination modes for the BEADS multi-agent swarm. Both modes produce identical work products; only the dispatch mechanism changes.

---

## 1. Mode Detection

At the start of any orchestration workflow, check your available tools:

- **If `TeamCreate` and `SendMessage` are available** --> Use Team Mode
- **Otherwise** --> Use Task Mode (follow existing workflow exactly as documented)

This is a single check at workflow start. There is no runtime switching between modes. Task Mode incurs zero overhead -- it is the existing workflow unchanged.

```text
Workflow starts
      |
      v
  TeamCreate and SendMessage available?
      |
   +--+--+
   | YES |  --> Team Mode (persistent teammates, direct messaging)
   +--+--+
      |
   +--+--+
   | NO  |  --> Task Mode (existing workflow, zero changes)
   +-----+

In EITHER mode:
  - Adversarial reviewers = ALWAYS fresh Task()
  - BEADS = source of truth
  - Quality gates = blocking
  - Human checkpoints = mandatory
```

**Key principle**: The work itself (what agents do) is identical in both modes. Only HOW agents are spawned and communicate changes. Every skill file documents both modes; Team Mode is preferred when available, Task Mode is the zero-cost fallback.

---

## 2. Team Naming Convention

Teams are scoped to the orchestration level that creates them:

| Level                          | Team Name Pattern          | Example                   |
| ------------------------------ | -------------------------- | ------------------------- |
| Initiative (Swarm Coordinator) | `swarm-{initiative-id}`    | `swarm-auth-overhaul`     |
| Issue (Issue Orchestrator)     | `issue-{issue-number}`     | `issue-123`               |
| Design Review                  | `review-{design-doc-name}` | `review-user-auth-design` |

Teams are ephemeral -- created at workflow start, deleted after completion. BEADS remains the durable record.

---

## 3. Task Mode (Default)

Task Mode is the baseline coordination mechanism. It uses fire-and-forget `Task()` subagents. This mode is always available and requires no special tooling.

### How It Works

1. **Orchestrator spawns subagent** via `Task()` with full context in the prompt
2. **Subagent executes** independently -- no cross-agent communication
3. **Subagent returns result** to the orchestrator upon completion
4. **Orchestrator proceeds** to the next step in the workflow

### Characteristics

- Each subagent gets the complete context it needs in its spawn prompt
- No persistent state between subagent invocations (cold start every time)
- Sequential handoffs go through the orchestrator (researcher result fed into architect prompt)
- Parallel work uses parallel `Task()` calls (e.g., design review panel)
- This is the current behavior documented in all agent and skill files

### When Task Mode Is Sufficient

Task Mode works well for most workflows. The overhead of cold starts only becomes significant when:
- The same agent needs to work on multiple sequential units (e.g., a coder across work units)
- Design reviews require multiple iteration cycles (5 reviewers x 3 iterations = 15 cold starts)
- A PR shepherd needs to persist through a long CI/review lifecycle

---

## 4. Team Mode (Enhanced)

Team Mode uses persistent teammates with context retention and direct inter-agent messaging. It is preferred when `TeamCreate` and `SendMessage` tools are available.

### How It Works

1. **Orchestrator creates a team** via `TeamCreate("{team-name}")`
2. **Specialists join as named teammates** (e.g., `researcher`, `architect`, `coder`, `shepherd`)
3. **Teammates communicate directly** via `SendMessage` -- no orchestrator bottleneck for handoffs
4. **Teammates retain context** across multiple work items within the same team session
5. **Orchestrator coordinates** phase gates, conflict resolution, and shutdown
6. **Graceful teardown** via `shutdown_request` to all teammates, then `TeamDelete`

### Key Benefits Over Task Mode

| Benefit                     | Description                                                                 |
| --------------------------- | --------------------------------------------------------------------------- |
| **No cold starts**          | Coder retains context from WU-001 when starting WU-002                     |
| **Direct handoffs**         | Researcher sends findings directly to architect via `SendMessage`           |
| **Persistent PR shepherd**  | Stays alive through entire PR lifecycle without `run_in_background`         |
| **Efficient review cycles** | Design reviewers retain context across iterations (saves N cold starts)     |
| **Async coordination**      | Teammates send status updates without blocking the orchestrator             |

### Swarm Coordinator as Team Lead

The Swarm Coordinator creates an initiative-level team and spawns Issue Orchestrators as persistent teammates:

1. `TeamCreate("swarm-{initiative-id}")`
2. Spawn orchestrators as named teammates (`orch-123`, `orch-456`)
3. Broadcast file/schema conflicts via `SendMessage(type: "broadcast")`
4. Receive async updates ("PR merged", "blocked") from orchestrators
5. Enforce phase gates ("Phase 1 complete, Phase 2 may begin")
6. Graceful shutdown: `shutdown_request` to each orchestrator, then `TeamDelete`

### Issue Orchestrator as Sub-Team Lead

The Issue Orchestrator creates an issue-level team and spawns specialist agents:

1. `TeamCreate("issue-{number}")`
2. Spawn specialists: `researcher`, `architect`, `coder`, `shepherd`
3. Direct handoff: researcher completes, sends findings to `architect` directly
4. Persistent coder: retains context across work units (no cold start between WU-001 and WU-002)
5. Persistent shepherd: stays alive through the PR lifecycle, sends async status updates
6. Graceful shutdown: `shutdown_request` to all teammates, then `TeamDelete`

### Design Review as Review Team

The Design Review Gate creates a review-level team with all reviewers as persistent teammates:

1. `TeamCreate("review-{design-doc-name}")`
2. Spawn reviewers as named teammates (e.g., `pm`, `architect`, `designer`, `security`, `cto`)
3. Collect verdicts via `SendMessage` to the orchestrator
4. On revision: message "revised design, please re-review" -- reviewers retain context from previous round
5. After approval: `shutdown_request` to all reviewers, then `TeamDelete`

This is where Team Mode provides the biggest efficiency gain: design reviews often require 2-3 iterations, and persistent reviewers avoid re-reading the entire design document each cycle.

---

## 5. BEADS + Team TaskList Bridging

BEADS and Team TaskLists serve different purposes and must be kept in sync during Team Mode.

### Separation of Concerns

| Concern         | BEADS                                  | Team TaskList                            |
| --------------- | -------------------------------------- | ---------------------------------------- |
| **Purpose**     | Canonical record of WHAT (durable)     | Dispatch of WHO/WHEN (ephemeral)         |
| **Persistence** | Survives across sessions, syncs to git | Deleted with `TeamDelete` after workflow |
| **Visibility**  | Visible to all agents, all sessions    | Visible only to team members             |
| **Updates**     | `bd create`, `bd close`, `bd update`   | `TaskCreate`, `TaskUpdate`               |

### Bridge Protocol (Team Mode Only)

1. **Create BEADS task** --> `bd create "WU-001: <title>" --type task`
2. **Create matching Team task** --> `TaskCreate({ subject: "WU-001: <title>", metadata: { beads_id: "<beads-task-id>" } })`
3. **Teammate completes Team task** --> `TaskUpdate({ taskId: "<team-task-id>", status: "completed" })` + `SendMessage` to orchestrator
4. **Orchestrator closes BEADS task** --> `bd close <beads-task-id> --reason "4-phase loop complete. PASS."`

### Rule: Orchestrator Owns BEADS Updates

The orchestrator is the ONLY agent that updates BEADS. Teammates report completion via `SendMessage` or `TaskUpdate` on the Team TaskList; the orchestrator then runs `bd close` on the corresponding BEADS task.

**Why**: This prevents race conditions and ensures a single source of truth. BEADS tracks the canonical state; Team TaskList is just a dispatch mechanism.

### Task Mode

Bridging is not needed in Task Mode. Subagents update BEADS directly as they do today -- the `Task()` return value carries the completion signal.

---

## 6. Adversarial Reviewer Isolation Rule

**Adversarial reviewers MUST be fresh `Task()` instances on EVERY review pass -- even in Team Mode.**

This is the single most important invariant in the entire coordination system. Violating it destroys the adversarial review's value.

### The Rule

- ALWAYS a fresh `Task()` instance
- NEVER a teammate
- NEVER resumed from a previous agent
- NEVER given previous review findings or prior context
- A new reviewer sees ONLY: spec, DoD items, and git diff

### Why

This prevents **anchoring bias**, where a reviewer unconsciously checks for previously-found issues rather than reviewing independently. After a FAIL --> fix --> re-validate cycle, the next reviewer MUST be a completely new `Task()` instance with zero memory of prior reviews.

### Applies In Both Modes

```text
Task Mode:  Fresh Task() on every review pass     (natural behavior)
Team Mode:  Fresh Task() on every review pass     (explicit override of team pattern)
```

**There are no exceptions to this rule.**

---

## 7. Preserved Invariants

These rules MUST NOT change in either coordination mode. They are mode-agnostic and non-negotiable.

### Critical: Adversarial Reviewer Isolation

See Section 6. ALWAYS a fresh `Task()` instance on every single review pass. Never a teammate. Never resumed. Never given context about what previous reviewers found.

### Mode-Agnostic Rules

| Invariant                       | Description                                                                    |
| ------------------------------- | ------------------------------------------------------------------------------ |
| **Orchestrator-run validation** | Validation is always run directly by the orchestrator, never delegated         |
| **BEADS lifecycle**             | Create --> in_progress --> close lifecycle is identical in both modes           |
| **4-phase execution loop**      | IMPLEMENT --> VALIDATE --> ADVERSARIAL REVIEW --> COMMIT is mode-agnostic      |
| **Knowledge priming**           | `bd prime` runs before all agent work in both modes                            |
| **Human checkpoints**           | Planned pauses require explicit human approval in both modes                   |
| **Quality gates**               | Coverage, lint, typecheck, tests -- all blocking state transitions             |
| **Pipeline pattern**            | Push + PR + shepherd immediately after each agent completes, don't batch       |
| **Phase gate rule**             | Next phase starts only after ALL previous phase PRs are squash-merged          |
| **Max retry + escalation**      | 3 retries per gate, then escalate to human with full failure history           |
| **File scope verification**     | `git diff --name-only` check after every implementation                        |

### Invariant Rationale

These invariants exist because they encode hard-won lessons about multi-agent coordination failure modes:

- **Orchestrator-run validation** prevents subagents from self-certifying their own work
- **BEADS lifecycle** ensures every piece of work has a durable, auditable trail
- **4-phase loop** prevents the "implement and hope" anti-pattern
- **Knowledge priming** prevents agents from making decisions in ignorance of established patterns
- **Human checkpoints** keep humans in the loop at critical decision points
- **Quality gates as blocking** prevents "I'll fix it later" accumulation of tech debt
- **Max retry + escalation** prevents infinite loops when an agent cannot solve a problem

---

## Quick Reference: Mode Comparison

```text
+---------------------------+----------------------------+----------------------------+
|                           |       TASK MODE            |       TEAM MODE            |
+---------------------------+----------------------------+----------------------------+
| Availability              | Always                     | When TeamCreate +          |
|                           |                            | SendMessage available      |
+---------------------------+----------------------------+----------------------------+
| Agent lifecycle           | Fire-and-forget            | Persistent teammates       |
+---------------------------+----------------------------+----------------------------+
| Context retention         | None (cold start each)     | Retained across work items |
+---------------------------+----------------------------+----------------------------+
| Communication             | Via orchestrator only      | Direct SendMessage         |
+---------------------------+----------------------------+----------------------------+
| Adversarial reviewer      | Fresh Task() (natural)     | Fresh Task() (enforced)    |
+---------------------------+----------------------------+----------------------------+
| BEADS updates             | Subagent direct            | Orchestrator only          |
+---------------------------+----------------------------+----------------------------+
| Team TaskList bridging    | Not needed                 | Required (see Section 5)   |
+---------------------------+----------------------------+----------------------------+
| Overhead                  | Zero (existing behavior)   | Team setup/teardown        |
+---------------------------+----------------------------+----------------------------+
| Best for                  | Simple issues, single WU   | Multi-WU, iterative review |
+---------------------------+----------------------------+----------------------------+
```
