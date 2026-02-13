---
name: brainstorming-extension
description: Project extension to superpowers:brainstorming - auto-triggers design review gate after design completion
auto_activate: true
triggers:
  - after:superpowers:brainstorming
  - "design document committed"
---

# Brainstorming Extension - Automatic Review Gate

## Purpose

This skill extends `superpowers:brainstorming` to automatically trigger the design review gate after a design document is created. It ensures complex features go through Product Manager, Architect, Designer, Security Design, and CTO review before implementation begins.

**This is a project-specific extension that hooks into the superpowers brainstorming skill.**

---

## How It Works

The standard brainstorming flow:

```text
superpowers:brainstorming
    │
    ├── Collaborative Q&A
    ├── Design sections with validation
    ├── Write to docs/plans/YYYY-MM-DD-<topic>-design.md
    └── Commit to git
          │
          ▼
    "Ready to set up for implementation?"
```

With this extension:

```text
superpowers:brainstorming
    │
    ├── Collaborative Q&A
    ├── Design sections with validation
    ├── Write to docs/plans/YYYY-MM-DD-<topic>-design.md
    └── Commit to git
          │
          ▼
    ┌─────────────────────────────────────────┐
    │  AUTOMATIC DESIGN REVIEW GATE           │
    │  (design-review-gate)                   │
    │                                         │
    │  Spawns in parallel:                    │
    │  • Product Manager Agent (use cases)    │
    │  • Architect Agent (architecture)       │
    │  • Designer Agent (UX/API)              │
    │  • Security Design Agent (threats)      │
    │  • CTO Agent (TDD readiness)            │
    │                                         │
    │  Iterates until ALL FIVE approve        │
    └─────────────────────────────────────────┘
          │
          ▼
    ALL APPROVED? ────No────► Iterate on design
          │
         Yes
          │
          ▼
    "Ready to set up for implementation?"
```

---

## Activation

This skill auto-activates when:

1. `superpowers:brainstorming` completes and commits a design document
2. A file matching `docs/plans/*-design.md` is created and committed
3. User explicitly says "review this design" or "run review gate"

---

## Extension Behavior

### After Design Document Commit

When a design document is committed, this extension:

1. **Detects completion** - Monitors for commits to `docs/plans/*-design.md`

2. **Announces review gate**:

   ```markdown
   ## Design Review Gate Activated

   Your design document has been committed. Before proceeding to implementation,
   I'll run it through our review agents to ensure it's ready.

   Spawning reviews:

   - Product Manager Agent (use case/requirements validation)
   - Architect Agent (technical architecture)
   - Designer Agent (UX/API design)
   - Security Design Agent (threat modeling/security review)
   - CTO Agent (TDD readiness)

   This typically takes 2-3 minutes...
   ```

3. **Spawns review agents** - Uses design-review-gate skill

4. **Aggregates results** - Combines feedback from all five agents

5. **Reports outcome**:

   **If APPROVED:**

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
   2. Set up worktree for isolated development
   3. Begin implementation

   Ready to proceed? [Yes / No]
   ```

   **If NEEDS_REVISION:**

   ```markdown
   ## Design Review Gate: NEEDS REVISION

   Some reviewers found issues that need to be addressed.

   ### Blocking Issues

   #### Architect Agent

   - [Issue 1]
   - [Issue 2]

   #### Security Design Agent

   - [Missing rate limits]

   #### CTO Agent

   - [Missing TDD specs]

   ### Questions Requiring Answers

   - [Question 1]

   ---

   Please revise the design document and I'll re-run the review gate.
   (Iteration 1 of 3)
   ```

---

## Integration Points

### With superpowers:brainstorming

This extension runs AFTER brainstorming completes but BEFORE the "ready for implementation?" prompt.

### With design-review-gate

Delegates the actual review work to the design-review-gate skill.

### With Task Tracking

After approval, can automatically:

- Create epic linked to design doc
- Create tasks for each implementation phase
- Set up dependencies

---

## Configuration

### Skip Review Gate

For truly simple designs (< 1 day of work), the review gate can be skipped:

```markdown
User: "This is a simple fix, skip the review gate"
```

Agent will ask for confirmation before skipping.

### Force Review Gate

Even for non-brainstorming contexts:

```markdown
User: "/project:review-design docs/plans/2026-01-11-my-design.md"
```

---

## Success Metrics

The extension is working correctly when:

- [ ] Every brainstorming session that produces a design doc triggers review gate
- [ ] All five agents (PM, architect, designer, security, CTO) are spawned
- [ ] Blocking issues must be resolved before implementation
- [ ] Approved designs have clear next steps

---

## Troubleshooting

### Review Gate Not Triggering

Check:

1. Was a design document committed? (`git log --oneline -5`)
2. Is the file in `docs/plans/` with `-design.md` suffix?
3. Did brainstorming complete normally?

### Agents Taking Too Long

Each agent should complete within 2-3 minutes. If longer:

1. Check agent output for errors
2. May need to reduce design document size
3. Can run agents sequentially instead of parallel

### Stuck in Review Loop

After 3 iterations, the gate will escalate to human decision:

- Override and proceed anyway
- Defer the feature
- Cancel the feature

---

## Example Session

```markdown
User: "Let's design a new feature for contact tagging"

[brainstorming skill runs...]
[Q&A, design sections, validation...]

Claude: "I've committed the design document to docs/plans/2026-01-11-contact-tagging-design.md"

## Design Review Gate Activated

Spawning review agents...

[2 minutes later]

## Design Review Gate: PASSED

All five reviewers approved! Ready to set up for implementation?

User: "Yes"

Claude: "I'll create an epic and set up a worktree..."
```

---

## Related Skills

- `superpowers:brainstorming` - The skill this extends
- `design-review-gate` - The review gate implementation
- `superpowers:writing-plans` - Used after approval for detailed plans
