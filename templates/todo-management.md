# Task Management Guide

This guide covers best practices for using BEADS (`bd` CLI) to track progress on tasks. BEADS is the single source of truth for task tracking in your project.

**Do NOT use TodoWrite, TodoRead, or TaskCreate tools.** Use BEADS exclusively.

## Task Management with BEADS

**CRITICAL**: Always maintain accurate issue status to ensure task completion and proper tracking.

## When to Use BEADS

Use `bd create`, `bd update`, and `bd close` to track progress on tasks:

### Use BEADS for:

- Complex multi-step tasks (3+ distinct steps)
- Non-trivial and complex tasks requiring careful planning
- Features, bugs, and epics
- Multiple tasks provided by user (numbered or comma-separated)
- Tasks requiring systematic tracking
- When you need to maintain state across a long conversation

### Skip BEADS for:

- Single, straightforward tasks
- Trivial tasks where tracking provides no benefit
- Tasks completable in less than 3 trivial steps
- Purely conversational or informational requests

## Checking Available Work

Check current task list frequently, especially:

- At the beginning of conversations: `bd ready`
- Before starting new tasks: `bd list --status=open`
- After completing tasks: `bd ready` (find next work)
- When uncertain about next steps: `bd list --status=in_progress`
- **Before any context switch or branch change**

## Updating Task Status

Update task status in real-time:

- Mark tasks as `in_progress` BEFORE starting work: `bd update <id> --status=in_progress`
- Only have ONE task `in_progress` at a time
- Mark as closed IMMEDIATELY after finishing: `bd close <id> --reason="..."`
- Use for tasks with 3+ steps or requiring systematic tracking
- **NEVER leave tasks as `in_progress` when switching context**

## Task Management Rules

### 1. No Abandoned Tasks

If you can't complete a task, update it with notes:

```bash
bd update <id> --notes="Blocked on X. Remaining: Y and Z."
```

### 2. Context Switches

Before changing branches or starting new work:

- Check all `in_progress` tasks: `bd list --status=in_progress`
- Either close them or update with notes
- Inform user of any incomplete work

### 3. Task Handoff

When a task needs user action:

- Update with clear next steps: `bd update <id> --notes="Needs user decision on X"`
- Notify user explicitly

### 4. Dependencies

When tasks depend on each other:

```bash
bd dep add <issue> <depends-on>  # issue depends on depends-on
bd blocked                        # show all blocked issues
```

## Task States

- **open**: Task not yet started
- **in_progress**: Currently working on (limit to ONE at a time)
- **closed**: Task finished successfully

## BEADS Workflow Example

```bash
1. bd ready              # Check available work
2. bd show <id>          # Review issue details
3. bd update <id> --status=in_progress  # Claim it
4. # Complete the work
5. bd close <id> --reason="Completed in commit <SHA>"
6. bd ready              # Find next task
7. bd sync               # Push BEADS changes to git
```

## Creating New Tasks

```bash
# Single task
bd create --title="Implement feature X" --type=task --priority=2

# Multiple related tasks (use parallel subagents for efficiency)
bd create --title="Implement feature X" --type=feature
bd create --title="Write tests for X" --type=task
bd dep add <tests-id> <feature-id>  # Tests depend on feature
```

## Integration with Other Workflows

- Before creating PRs: Ensure all related BEADS issues are closed
- Before context switches: Review and update all in_progress items
- During long tasks: Periodically update progress with `bd update <id> --notes="..."`
- After completing features: Close all related issues: `bd close <id1> <id2> ...`
- At session end: Always run `bd sync`
