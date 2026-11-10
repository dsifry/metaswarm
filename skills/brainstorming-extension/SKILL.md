---
name: brainstorming-extension
description: Loads the assumption ledger and misreadings checklist at the start of brainstorming, and enforces the design review gate when a project-sized design doc is committed — bridges superpowers:brainstorming into the metaswarm quality pipeline
auto_activate: true
triggers:
  - "start of brainstorming (any session, any size)"
  - "project-sized design doc committed (docs/plans/*-design.md or docs/superpowers/specs/*-design.md)"
---

# Brainstorming Extension - Mandatory Review Gate Bridge

## Purpose

This skill bridges `superpowers:brainstorming` into the metaswarm quality pipeline by enforcing the Design Review Gate when brainstorming writes and commits a project-sized design doc. Only project-sized work reaches the gate; quick tasks, chat-only designs and short design docs for small changes skip it (see [`guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). Without this bridge, brainstorming flows directly into `writing-plans`, bypassing the 6-agent design review that catches architectural, security, and requirements issues before expensive implementation begins.

**This is a critical workflow enforcement point, not a passive extension.**

## During brainstorming (every session)

Load this skill at the start of brainstorming, for every brainstorming session regardless of size. Quick tasks, chat-only designs and short design docs for small changes skip the project-sized design review gate below, but they do not skip this section. Follow it before any design is presented or committed.

### Assumption ledger and confirmation

Write an assumption ledger into the design doc when there is one, so the reviewers and the user can see what the design rests on. For a chat-only design, keep the ledger in the conversation, restated in a message, and in the plan when one exists.

```markdown
## Assumptions (unconfirmed)
- A1. <what the design assumes> — source: agent-proposed | "<exact user words>"

## Confirmed
- A2. <the reading or decision> — confirmed by the user: "<exact user words>"
```

- Every load-bearing assumption gets an id (A1, A2, ...) in **Assumptions (unconfirmed)**. It moves to **Confirmed** only when the user confirms that specific point.
- The confirmation rule: a one-word acknowledgement of a message with several parts confirms nothing ("good", "ok" confirm no specific point); restate any answer that changes the design, in your own words, and get it confirmed before it goes in **Confirmed**; never label an agent proposal as a user decision.
- When the design changes, keep the ledger current. Reviewers do not mark a question `needs_user` when **Confirmed** already answers it.

When the work skips brainstorming, the issue orchestrator keeps the same ledger in the plan's Assumptions section.

### Common misreadings

Run this checklist before the design is committed or presented. For each pattern, ask whether the design could be a misreading of the user's request, and ask the user if it could. The checklist is the 4 built-in patterns below plus the patterns this project has learned.

**Load the project's learned patterns first.** They are facts in the project's knowledge base, type `gotcha`, tagged `misunderstanding`:

```bash
[ -d .beads/knowledge ] && find .beads/knowledge -maxdepth 1 -name '*.jsonl' -exec grep -h '"misunderstanding"' {} + |
  if command -v jq >/dev/null 2>&1; then jq -Rr 'fromjson? | select((.tags // []) | index("misunderstanding")) | .fact'; else cat; fi
```

Skip this step when `.beads/knowledge/` is missing. `find` avoids a shell error when no `.jsonl` file exists, and `fromjson?` skips a malformed line instead of dropping every fact after it. Without `jq` the command prints the matching JSON lines: read the `fact` value of each. Treat each fact as one more item on the checklist.

1. **Level mismatch (what vs. how).** The request is about *what* (a decision service), but the design reads it as *where or how* (every surface becomes a signing path).
2. **Over-reading scope.** "Any surface" read as "every surface fully featured", or one issue bundled into three.
3. **A proposal read as a decision.** The agent's own proposal treated as the user's decision.
4. **A one-word acknowledgement taken as approval of a message with several parts.**

Learned patterns live in each project's knowledge base, so they survive sessions and `/update`. `/self-reflect` records each one as a `gotcha` tagged `misunderstanding` in `.beads/knowledge/gotchas.jsonl`, and offers, without doing it automatically, to file a GitHub issue on `dsifry/metaswarm` so a general pattern can join the built-in list. Edit the built-in list above only when the current repo is metaswarm itself.

### Re-brainstorm after a Clarification

When a Clarification report exists (the severity rule fired a Clarify signal, or the user chose "Clarify the requirement / re-brainstorm" at an escalation), brainstorming takes the report and the user's answers as input. Restate the answers, get the restatement confirmed, and record the confirmed reading in the design's Confirmed section. Then run the Common misreadings checklist on the revised design. The revised design starts a new gate occurrence with a fresh review round.

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
    │  6 parallel review agents:              │
    │  • Product Manager (use cases)          │
    │  • Architect (architecture)             │
    │  • Designer (UX/API)                    │
    │  • Security Design (threats)            │
    │  • UX Reviewer (user flows, UI states)  │
    │  • CTO (TDD readiness)                  │
    │                                         │
    │  ALL SIX must APPROVE                   │
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

YAML frontmatter triggers (`auto_activate`, `triggers`) are metadata hints — Claude Code does not enforce them automatically. Instead, this enforcement works through three redundant mechanisms. The same routing lines also load this skill at the start of brainstorming, for the assumption ledger and the Common misreadings checklist, so they apply before any design exists:

### 1. CLAUDE.md Template (Primary)

The CLAUDE.md template contains a "Workflow Enforcement (MANDATORY)" section that explicitly states:

> After a project-sized design doc is committed: STOP → Run Design Review Gate → Wait for all 6 agents to APPROVE → Only then proceed

This instruction is loaded into every conversation and overrides conflicting skill instructions. The template and its append variants also carry a "During brainstorming" line that loads this skill at the start of brainstorming.

### 2. start-task Command (Secondary)

The `/start-task` command's Problem Definition Phase includes an explicit "Design Review Gate (project-sized designs only)" block that requires the gate once a project-sized design doc is committed. Its routing line also loads this skill at the start of brainstorming.

### 3. This Skill Document (Reference)

When this skill is loaded (either by name or auto-activation), it provides the detailed procedure below.

---

## Procedure: After a Project-Sized Design Doc Is Committed

When brainstorming writes and commits a project-sized design doc (see [`guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)):

### Step 1: Announce the Gate

```markdown
## Design Review Gate Activated

Your design document has been committed. Before proceeding to implementation,
I'll run it through our 6-agent review panel.

Spawning reviews (each `roleType("design-reviewer")`, role in the prompt):
- Product Manager Agent (use case/requirements validation)
- Architect Agent (technical architecture)
- Designer Agent (UX/API design)
- Security Design Agent (threat modeling/security review)
- UX Reviewer (user flows, UI states, integration wiring)
- CTO Agent (TDD readiness)

This typically takes 2-3 minutes...
```

### Step 2: Invoke the Design Review Gate

Invoke the `design-review-gate` skill with the path to the design document. This spawns all 6 review agents in parallel.

### Step 3: Report Results

**If ALL APPROVED:**

```markdown
## Design Review Gate: PASSED

All six reviewers have approved your design!

| Agent           | Verdict  | Notes                                 |
| --------------- | -------- | ------------------------------------- |
| Product Manager | APPROVED | Clear use cases, measurable benefits  |
| Architect       | APPROVED | Clean architecture, follows patterns  |
| Designer        | APPROVED | Good API design, clear error states   |
| Security Design | APPROVED | No high-risk threats, mitigations OK  |
| UX Reviewer     | APPROVED | Flows, UI states and wiring defined   |
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
- When a Clarify signal fires (the user is needed, or the reviews are not converging): stop, run the misunderstanding analysis, and send the Clarification report (see the metaswarm plugin's `guides/delivery-scope.md`). For option 1 (Answer), re-brainstorm with the user's answers (see Re-brainstorm after a Clarification); option 2 keeps the same occurrence and continues the review
- When the severity rule escalates (cap hit, or a recurring or disputed blocker): Escalate to human decision (Revise / Clarify the requirement / re-brainstorm / Narrow scope / Defer / Cancel). Neither a Clarify nor an escalation approves: a revised design gets a fresh review round

---

## Skip Conditions

Quick tasks, chat-only designs and short design docs for small changes never reach the gate: they skip it automatically by size (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). A project-sized design doc always goes through the gate; there is no user-requested exception. If the user thinks the work is not project-sized, re-size it during brainstorming (superpowers lets them choose a smaller size) instead of bypassing the gate.

---

## Related Skills

- `superpowers:brainstorming` — The upstream skill this bridges from
- `design-review-gate` — The 6-agent review implementation
- `plan-review-gate` — The next gate in the pipeline: runs once writing-plans has written the plan, before writing-plans presents the plan (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md))
- `orchestrated-execution` — The execution framework after planning
