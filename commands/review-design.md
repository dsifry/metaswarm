---
description: Trigger the parallel design review gate with 5 specialist reviewers
---

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
2. **Spawns five review agents in parallel** (each `roleType("design-reviewer")`, role in the prompt):
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
| `--latest`            | Review the newest dated design doc in `docs/plans/` or `docs/superpowers/specs/` |
| `--iteration N`       | Mark as iteration N of review cycle                          |
| `--skip-agent <name>` | Skip specific agent (pm, architect, designer, security, cto) |

### Finding the latest design doc

`--latest` looks at `docs/plans/*-design.md` and `docs/superpowers/specs/*-design.md`, considers only names that start with `YYYY-MM-DD-`, and picks the newest by that date prefix (file modification time is unreliable after a clone). Ties on date are broken by the rest of the basename, then by the full path.

<!-- latest-design-doc:start -->
```bash
(
  # Absent folders are skipped; a folder that exists but can't be read is an error.
  list=$(
    for d in docs/plans docs/superpowers/specs; do
      [ -d "$d" ] || continue
      find "$d" -maxdepth 1 -type f \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*-design.md' ||
        { echo "Cannot read $d" >&2; exit 2; }
    done
  ) || exit 2
  latest=$(printf '%s\n' "$list" |
    awk 'NF { n = $0; sub(".*/", "", n); print n "\t" $0 }' |
    LC_ALL=C sort | tail -n 1 | cut -f2)
  if [ -n "$latest" ]; then
    printf '%s\n' "$latest"
  else
    echo "No design doc found in docs/plans/ or docs/superpowers/specs/"
    false
  fi
)
```
<!-- latest-design-doc:end -->

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
- Round count (severity-gated iteration, cap 10 rounds; see the metaswarm plugin's `guides/delivery-scope.md`)

### ESCALATED

Reached via the severity rule: an escalate condition (a recurring or disputed blocker, or a blocker that survives the overengineering check) or the 10-round cap:

- Summary of remaining blockers
- Options: Revise / Narrow scope / Defer / Cancel. Escalation never approves: a revised or narrowed design gets a fresh review round

## Integration

### After a Project-Sized Design Doc Is Committed

This command is automatically invoked by the brainstorming extension skill when brainstorming commits a project-sized design doc (see the metaswarm plugin's `guides/workflow-enforcement.md`).

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
ls -la docs/plans/ docs/superpowers/specs/
```

### "Agent timed out"

Individual agents have 3-minute timeout. If timeout occurs:

1. Check design document isn't too large
2. Try running agents sequentially with `--sequential`
3. Check for network/API issues

### "Stuck in review loop"

On any escalation (including the 10-round cap), the human chooses Revise, Narrow scope, Defer or Cancel. There is no way to advance with open blockers: a revised or narrowed design gets a fresh review round and passes only by that round.

## Related Commands

- `/review-this` - General CTO review (more detailed, single reviewer)
- `/create-issue` - Create GitHub issue from approved design
- `/start-task` - Begin implementation of approved design

## Related Skills

- `your-project:design-review-gate` - The gate implementation
- `your-project:brainstorming-extension` - Auto-triggers this when brainstorming commits a project-sized design doc
- `superpowers:brainstorming` - The design creation skill
