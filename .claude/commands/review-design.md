# Review Design Command

Run the design review gate on a design document to get feedback from Product Manager, Architect, Designer, Security Design, and CTO agents.

## Usage

```bash
/review-design <path-to-design-doc>
```

## Examples

```bash
# Review a specific design document
/review-design docs/plans/2026-01-11-contact-assistant-design.md

# Review the most recent design document
/review-design --latest

# Re-run review after revisions
/review-design docs/plans/2026-01-11-contact-assistant-design.md --iteration 2
```

## What This Does

1. **Validates the design document exists** and is in the expected format
2. **Spawns five review agents in parallel**:
   - **Product Manager Agent** - Validates use cases and user benefits
   - **Architect Agent** - Reviews technical architecture
   - **Designer Agent** - Reviews UX, API design, developer experience
   - **Security Design Agent** - Reviews security threats and mitigations
   - **CTO Agent** - Reviews TDD readiness, codebase alignment
3. **Aggregates results** from all five agents
4. **Reports outcome** with blockers, suggestions, and next steps

## Arguments

| Argument              | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `<path>`              | Path to design document (required unless --latest)           |
| `--latest`            | Review most recent design doc in docs/plans/                 |
| `--iteration N`       | Mark as iteration N of review cycle                          |
| `--skip-agent <name>` | Skip specific agent (pm, architect, designer, security, cto) |

## Review Verdicts

### APPROVED

All agents approve. Output includes:

- Summary of what each agent reviewed
- Non-blocking suggestions for future improvement
- Next steps for implementation

### NEEDS_REVISION

One or more agents found blocking issues. Output includes:

- List of blocking issues by agent
- Questions requiring clarification
- Iteration count (max 3 before escalation)

### ESCALATED

After 3 iterations without approval:

- Summary of remaining blockers
- Options: Override / Defer / Cancel

## Integration

### After Brainstorming

This command is automatically invoked by the brainstorming extension skill after `superpowers:brainstorming` commits a design document.

### Manual Invocation

Use this command to:

- Review an existing design document
- Re-run reviews after making revisions
- Run partial reviews (skip specific agents)

### With BEADS

When design is approved, offers to:

- Create BEADS epic linked to design doc
- Create tasks for implementation phases
- Set up worktree for isolated development

## Agent Details

### Product Manager Agent

Focuses on:

- Use case clarity (WHO/WANTS/SO THAT format)
- Measurable user benefits
- Scope definition (MVP vs nice-to-have)
- Success metrics validation

### Architect Agent

Focuses on:

- Service architecture patterns
- Dependency flow
- Technical correctness
- Integration points

### Designer Agent

Focuses on:

- API/interface design quality
- User experience (if applicable)
- Developer experience
- Pattern consistency

### Security Design Agent

Focuses on:

- Threat modeling (STRIDE)
- Authentication/authorization design
- Data protection and privacy
- OWASP Top 10 compliance

### CTO Agent

Focuses on:

- TDD readiness (RED-GREEN-REFACTOR)
- Codebase alignment (CLAUDE.md)
- Completeness of specification
- Risk assessment

## Success Criteria

The review gate passes when:

- [ ] All five agents return APPROVED
- [ ] All blocking issues resolved
- [ ] All clarifying questions answered
- [ ] Design document updated with revisions (if any)

## Troubleshooting

### "Design document not found"

Ensure the path is correct and the file exists:

```bash
ls -la docs/plans/
```

### "Agent timed out"

Individual agents have 3-minute timeout. If timeout occurs:

1. Check design document isn't too large
2. Try running agents sequentially with `--sequential`
3. Check for network/API issues

### "Stuck in review loop"

After 3 iterations, use `--force-override` to proceed anyway (documents technical debt).

## Related Commands

- `/review-this` - General CTO review (more detailed, single reviewer)
- `/create-issue` - Create GitHub issue from approved design
- `/start-task` - Begin implementation of approved design

## Related Skills

- `your-project:design-review-gate` - The gate implementation
- `your-project:brainstorming-extension` - Auto-triggers this after brainstorming
- `superpowers:brainstorming` - The design creation skill
