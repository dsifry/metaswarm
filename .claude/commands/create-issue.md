# Create GitHub Issue

Create a comprehensive, well-structured GitHub issue with embedded agent instructions for autonomous PR lifecycle management.

## Usage

```text
/project:create-issue [type] [description]
```

**Arguments** (optional - will prompt if not provided):

- `type`: `feature`, `bug`, or `refactor`
- `description`: Brief description of the issue

## Examples

```bash
# Interactive mode (prompts for all details)
/project:create-issue

# With type specified
/project:create-issue feature

# With type and description
/project:create-issue bug "Login fails when email contains plus sign"
```

## What This Does

1. **Gathers context** through interactive questions
2. **Generates comprehensive issue** with all required sections:
   - Problem/Feature specification with clear scope
   - Technical specification (types, schemas, APIs)
   - TDD Implementation Plan with test-first cycles
   - Error handling matrix
   - Files to create/modify
   - Acceptance criteria checklist
   - **Agent Instructions** for complete PR lifecycle
3. **Creates GitHub issue** with appropriate labels
4. **Returns issue number** for tracking

## Steps

1. **Activate the create-issue skill**:
   Load and follow the create-issue skill definition.

2. **Gather information** through the interactive flow:
   - Issue type (Feature/Bug/Refactor)
   - Brief description
   - Complexity estimate
   - Related files/services

3. **Generate issue content** using appropriate template

4. **Create issue** via `gh issue create`

## Why Agent Instructions Matter

Every issue includes an "Agent Instructions" section that ensures:

- **Complete lifecycle**: From implementation through merge
- **All comments addressed**: Including trivial/nitpicks and out-of-scope
- **Individual responses**: Every thread gets a reply
- **Iteration until done**: Wait for reviews, iterate, don't auto-resolve
- **Issue creation for deferred work**: > 1 day = new issue

This makes issues self-contained work packets that agents can execute autonomously while maintaining quality standards.

## Issue Structure

All generated issues follow this structure:

```text
## Summary
## Problem / Bug Report
## Architecture Decision (features/refactors)
## Technical Specification
## TDD Implementation Plan / Test Cases
## Error Handling
## Implementation Phases
## Files to Create/Modify
## Acceptance Criteria
## Agent Instructions  <-- CRITICAL for autonomous work
## Related Issues
## References
```

## Labels

Issues are automatically labeled based on type and complexity:

| Type     | Labels                              |
| -------- | ----------------------------------- |
| Feature  | `enhancement`, `complexity:[level]` |
| Bug      | `bug`, `priority:[level]`           |
| Refactor | `refactor`, `complexity:[level]`    |

## Related Commands

- `/project:handle-pr-comments` - Handle PR review feedback
- `/project:pr-shepherd` - Monitor PR through to merge
- `/project:create-pr` - Create comprehensive PR
- `/project:start-task` - Start working on an existing issue
