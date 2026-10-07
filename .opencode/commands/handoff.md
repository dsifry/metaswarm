---
description: Analyze the session and write a self-contained handoff document so a fresh agent can resume the work — outputs a single "Read XXX.md and do YYY." sentence
---

# Handoff

Analyze the current session and everything we are working on, then write a single comprehensive markdown document containing all the context, files, specs, designs, plans, and decisions a **fresh agent with no prior context** would need to get fully up to speed and take action. Finish by emitting one unambiguous handoff sentence.

## Usage

```text
/handoff
```

Optionally pass focus hints:

```text
/handoff focus on the auth refactor only
```

## What This Does

Invokes the metaswarm `handoff` skill, which:

1. **Reconstructs the objective** — what the user is trying to accomplish, the Definition of Done, and why.
2. **Loads persisted state** — folds in `.beads/plans/active-plan.md`, `.beads/context/*`, and `bd prime --work-type recovery` if present.
3. **Establishes current status** — done/verified vs. in-progress vs. not-started, plus the real working-tree state (`git status`, recent commits, unpushed/uncommitted changes).
4. **Identifies required reading** — every spec, design, plan, code `file:line`, and test the next agent must read, with *why* and *what to look for*.
5. **Writes the document** to `docs/handoffs/handoff-<YYYY-MM-DD-HHmm>.md`.
6. **Emits one sentence** of the exact form:

   ```text
   Read docs/handoffs/handoff-2026-06-17-1432.md and do <concrete next action>.
   ```

## Output Contract

- A self-contained handoff document (so the next agent needs to read **only that one file**).
- Exactly one closing sentence: `Read <path>.md and do <YYY>.` where `<YYY>` is one concrete, immediately-actionable next step — never "continue the work".

## When to Use

- A session is ending or context is about to be compacted.
- Switching sessions, machines, or agents mid-task.
- Pausing complex work you want to resume cleanly later.
- The user explicitly asks for a handoff.

## Related

- `skills/handoff/SKILL.md` — the full skill definition (method, document template, anti-patterns).
- `/prime` — loads context **into** a session (the inverse of this command).
- `/self-reflect` — captures durable *learnings* into the knowledge base (vs. this task's *transient* state).
