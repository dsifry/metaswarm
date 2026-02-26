# Brainstorm

Invoke the metaswarm brainstorming extension skill, which wraps `superpowers:brainstorming` with metaswarm's design review gate handoff.

## Usage

```text
/brainstorm <idea or problem description>
```

## Behavior

1. If `superpowers:brainstorming` is available, invoke it for the collaborative design process
2. After brainstorming commits a design document, **automatically trigger the design review gate** (`/metaswarm:review-design`)
3. Wait for all 5 review agents to approve before proceeding to planning

If superpowers is not installed, provide standalone brainstorming guidance:
- Ask clarifying questions one at a time
- Propose 2-3 approaches with trade-offs
- Present design sections for approval
- Write design doc to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Trigger design review gate

## Related

- `/metaswarm:review-design` — triggered automatically after brainstorming
- `superpowers:brainstorming` — the underlying brainstorming skill (if available)
