---
description: Refine an idea into a design with brainstorming, then run the design review gate for project-sized designs
---

# Brainstorm

Invoke the metaswarm brainstorming extension skill, which wraps `superpowers:brainstorming` with metaswarm's design review gate handoff.

## Usage

```text
/brainstorm <idea or problem description>
```

## Behavior

1. If `superpowers:brainstorming` is available, invoke it for the collaborative design process, and load the `brainstorming-extension` skill at the start of brainstorming (not only after the commit) for its assumption ledger and Common misreadings checklist; they apply to every brainstorming session regardless of size
2. When brainstorming writes and commits a project-sized design doc, **automatically trigger the design review gate** (`/metaswarm:review-design`); quick tasks, chat-only designs and short design docs for small changes skip it (see the metaswarm plugin's `guides/workflow-enforcement.md`)
3. Wait for all 6 review agents to approve before proceeding to planning

If superpowers is not installed, provide standalone brainstorming guidance, and apply the assumption ledger, the confirmation rule and the Common misreadings checklist from `metaswarm:brainstorming-extension`:
- Ask clarifying questions one at a time
- Propose 2-3 approaches with trade-offs
- Present design sections for approval
- Write design doc to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` (superpowers' default) or `docs/plans/YYYY-MM-DD-<topic>-design.md`; the design review gate watches both
- Trigger design review gate (project-sized design docs only)

## Related

- `/metaswarm:review-design` — triggered automatically when brainstorming commits a project-sized design doc
- `superpowers:brainstorming` — the underlying brainstorming skill (if available)
