---
name: brainstorming-extension
description: Enforces the design review gate when brainstorming commits a project-sized design doc — bridges superpowers:brainstorming into the metaswarm quality pipeline
auto_activate: true
triggers:
  - "project-sized design doc committed (docs/plans/*-design.md or docs/superpowers/specs/*-design.md)"
---

# Brainstorming Extension - Mandatory Review Gate Bridge

## Purpose

This skill bridges `superpowers:brainstorming` into the metaswarm quality pipeline by enforcing the Design Review Gate when brainstorming writes and commits a project-sized design doc. Only project-sized work reaches the gate; quick tasks, chat-only designs and short design docs for small changes skip it (see [`guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). Without this bridge, brainstorming flows directly into `writing-plans`, bypassing the 5-agent design review that catches architectural, security, and requirements issues before expensive implementation begins.

**This is a critical workflow enforcement point, not a passive extension.**

---

## The Problem This Solves

`superpowers:brainstorming` ends by handing off to `writing-plans`: in superpowers 6.4.1 a terminal-state rule on the Architectural path says writing-plans is the only skill invoked next, and in 7.x an approved design doc leads to writing-plans. For a project-sized design doc this creates a pipeline bypass:

```text
WITHOUT this extension (broken flow):

superpowers:brainstorming
    └── Commits a project-sized design doc
          └── writing-plans (DIRECTLY — no review!)
                └── executing-plans
                      └── Implementation begins on UNREVIEWED design
```

```text
WITH this extension (correct flow):

superpowers:brainstorming
    └── Commits a project-sized design doc
          │
          ▼
    ┌─────────────────────────────────────────┐
    │  MANDATORY DESIGN REVIEW GATE           │
    │  (Enforced by CLAUDE.md + start-task)   │
    │                                         │
    │  5 parallel review agents:              │
    │  • Product Manager (use cases)          │
    │  • Architect (architecture)             │
    │  • Designer (UX/API)                    │
    │  • Security Design (threats)            │
    │  • CTO (TDD readiness)                 │
    │                                         │
    │  ALL FIVE must APPROVE                  │
    └─────────────────────────────────────────┘
          │
          ▼
    ALL APPROVED? ────No────► Iterate on design (severity-gated, cap 10)
          │
         Yes
          │
          ▼
    writing-plans (plan written) → plan-review-gate → (gate PASS) present plan + execution menu → orchestrated-execution
    (the gate runs before writing-plans presents the plan; see ./guides/workflow-enforcement.md)
```

---

## How Enforcement Works

YAML frontmatter triggers (`auto_activate`, `triggers`) are metadata hints — Claude Code does not enforce them automatically. Instead, this enforcement works through three redundant mechanisms:

### 1. CLAUDE.md Template (Primary)

The CLAUDE.md template contains a "Workflow Enforcement (MANDATORY)" section that explicitly states:

> After a project-sized design doc is committed: STOP → Run Design Review Gate → Wait for all 5 agents to APPROVE → Only then proceed

This instruction is loaded into every conversation and overrides conflicting skill instructions.

### 2. start-task Command (Secondary)

The `/start-task` command's Problem Definition Phase includes an explicit "Design Review Gate (project-sized designs only)" block that requires the gate once a project-sized design doc is committed.

### 3. This Skill Document (Reference)

When this skill is loaded (either by name or auto-activation), it provides the detailed procedure below.

---

## Procedure: After a Project-Sized Design Doc Is Committed

When brainstorming writes and commits a project-sized design doc (see [`guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)):

### Step 1: Announce the Gate

```markdown
## Design Review Gate Activated

Your design document has been committed. Before proceeding to implementation,
I'll run it through our 5-agent review panel.

Spawning reviews (each `roleType("design-reviewer")`, role in the prompt):
- Product Manager Agent (use case/requirements validation)
- Architect Agent (technical architecture)
- Designer Agent (UX/API design)
- Security Design Agent (threat modeling/security review)
- CTO Agent (TDD readiness)

This typically takes 2-3 minutes...
```

### Step 2: Invoke the Design Review Gate

Invoke the `design-review-gate` skill with the path to the design document. This spawns all 5 review agents in parallel.

### Step 3: Report Results

**If ALL APPROVED:**

```markdown
## Design Review Gate: PASSED

All five reviewers have approved your design!

| Agent           | Verdict  | Notes                                 |
| --------------- | -------- | ------------------------------------- |
| Product Manager | APPROVED | Clear use cases, measurable benefits  |
| Architect       | APPROVED | Clean architecture, follows patterns  |
| Designer        | APPROVED | Good API design, clear error states   |
| Security Design | APPROVED | No high-risk threats, mitigations OK  |
| CTO             | APPROVED | TDD specs present, ready to implement |

### Next Steps
1. Create epic for this feature
2. Create implementation plan (writing-plans)
3. Run plan through Plan Review Gate (3 adversarial reviewers)
4. Set up worktree for isolated development
5. Begin orchestrated execution

Ready to proceed? [Yes / No]
```

**If ANY NEEDS_REVISION:**

```markdown
## Design Review Gate: NEEDS REVISION

Some reviewers found issues that need to be addressed.

### Blocking Issues
[Agent-specific issues listed here]

### Questions Requiring Answers
[Questions listed here]

---

Please revise the design document and I'll re-run the review gate.
(Round 1; severity-gated iteration, cap 10 rounds)
```

### Step 4: Iterate or Proceed

- If NEEDS_REVISION (at least one `blocker: yes` finding): Help user address the blockers, re-run gate. Iteration is severity-gated (cap 10 rounds; see the metaswarm plugin's `guides/delivery-scope.md`)
- If ALL APPROVED: Proceed to planning phase
- When the severity rule escalates (cap hit, or a recurring or disputed blocker): Escalate to human decision (Revise / Narrow scope / Defer / Cancel). Escalation never approves: a revised design gets a fresh review round

---

## Skip Conditions

Quick tasks, chat-only designs and short design docs for small changes never reach the gate: they skip it automatically by size (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). A project-sized design doc always goes through the gate; there is no user-requested exception. If the user thinks the work is not project-sized, re-size it during brainstorming (superpowers lets them choose a smaller size) instead of bypassing the gate.

---

## Related Skills

- `superpowers:brainstorming` — The upstream skill this bridges from
- `design-review-gate` — The 5-agent review implementation
- `plan-review-gate` — The next gate in the pipeline: runs once writing-plans has written the plan, before writing-plans presents the plan (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md))
- `orchestrated-execution` — The execution framework after planning
