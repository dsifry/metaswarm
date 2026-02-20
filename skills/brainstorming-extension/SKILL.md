---
name: brainstorming-extension
description: Enforces design review gate after brainstorming — bridges superpowers:brainstorming into the metaswarm quality pipeline
auto_activate: true
triggers:
  - after:superpowers:brainstorming
  - "design document committed"
---

# Brainstorming Extension - Mandatory Review Gate Bridge

## Purpose

This skill bridges `superpowers:brainstorming` into the metaswarm quality pipeline by enforcing the Design Review Gate after any design document is created. Without this bridge, brainstorming flows directly into `writing-plans`, bypassing the 5-agent design review that catches architectural, security, and requirements issues before expensive implementation begins.

**This is a critical workflow enforcement point, not a passive extension.**

---

## The Problem This Solves

`superpowers:brainstorming` has a built-in terminal state: "The ONLY skill you invoke after brainstorming is writing-plans." This creates a pipeline bypass:

```text
WITHOUT this extension (broken flow):

superpowers:brainstorming
    └── Commits design doc
          └── writing-plans (DIRECTLY — no review!)
                └── executing-plans
                      └── Implementation begins on UNREVIEWED design
```

```text
WITH this extension (correct flow):

superpowers:brainstorming
    └── Commits design doc
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
    ALL APPROVED? ────No────► Iterate on design (max 3)
          │
         Yes
          │
          ▼
    writing-plans → plan-review-gate → orchestrated-execution
```

---

## How Enforcement Works

YAML frontmatter triggers (`auto_activate`, `triggers`) are metadata hints — Claude Code does not enforce them automatically. Instead, this enforcement works through three redundant mechanisms:

### 1. CLAUDE.md Template (Primary)

The CLAUDE.md template contains a "Workflow Enforcement (MANDATORY)" section that explicitly states:

> After brainstorming: STOP → Run Design Review Gate → Wait for all 5 agents to APPROVE → Only then proceed

This instruction is loaded into every conversation and overrides conflicting skill instructions.

### 2. start-task Command (Secondary)

The `/start-task` command's Problem Definition Phase includes an explicit "MANDATORY HANDOFF" block that requires the design review gate after brainstorming.

### 3. This Skill Document (Reference)

When this skill is loaded (either by name or auto-activation), it provides the detailed procedure below.

---

## Procedure: After Brainstorming Completes

When `superpowers:brainstorming` commits a design document:

### Step 1: Announce the Gate

```markdown
## Design Review Gate Activated

Your design document has been committed. Before proceeding to implementation,
I'll run it through our 5-agent review panel.

Spawning reviews:
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
(Iteration 1 of 3)
```

### Step 4: Iterate or Proceed

- If NEEDS_REVISION: Help user address issues, re-run gate (max 3 iterations)
- If ALL APPROVED: Proceed to planning phase
- After 3 failed iterations: Escalate to human decision (Override / Defer / Cancel)

---

## Skip Conditions

The review gate can be skipped ONLY when:

- The user explicitly requests it ("skip the review gate")
- AND the agent confirms with the user before skipping
- AND the design is genuinely simple (< 1 day of work, < 3 files)

---

## Related Skills

- `superpowers:brainstorming` — The upstream skill this bridges from
- `design-review-gate` — The 5-agent review implementation
- `plan-review-gate` — The next gate in the pipeline (after writing-plans)
- `orchestrated-execution` — The execution framework after planning
