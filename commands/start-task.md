# Start Task

Determine task complexity and use appropriate workflow for efficient development.

## Usage

```text
/project:start-task <task-description>
```

## Steps

### 0. Pre-Task Checklist

Before starting any new task:

**Knowledge Priming (CRITICAL)**:

- [ ] Run BEADS prime: `bd prime --keywords "<task-keywords>" --work-type planning`
- [ ] Review MUST FOLLOW rules and GOTCHAS before proceeding
- [ ] Note any relevant patterns or decisions that constrain the approach

**PR Check**:

- [ ] Check if there are active PRs with pending comments
- [ ] Ask: "Before we start the new task, should we check if there are any PR comments to address?"
- [ ] If yes, run: `gh pr list --author @me --state open`
- [ ] Check each PR for new CodeRabbit comments

### 1. Task Assessment

**Use extended thinking** to analyze the task complexity before asking the user.

Consider:

- Number of files likely to be modified
- Whether database changes are needed
- Impact on existing functionality
- Testing requirements
- Integration points

Then ask the user to confirm your assessment:

> **Proposed complexity**: [Simple / Complex] - Does this match your expectation?

**Simple Task (streamlined flow):**

- Bug fixes
- Small UI tweaks
- Minor text/copy changes
- Simple configuration updates
- Adding basic validation
- Fixing linting/test issues

**Complex Task (full checklist + BEADS epic):**

- New features with database changes
- New API endpoints
- Complex UI components
- Background job modifications
- Onboarding flow changes
- Multi-file refactoring
- Performance optimizations

### 2. Simple Task Flow

If user confirms it's a simple task:

#### Essential Steps

- [ ] Read relevant docs if unfamiliar with area
- [ ] Check existing patterns for similar functionality
- [ ] Make the change following existing patterns
- [ ] Write/update tests if logic changes
- [ ] Run tests, lint, and build
- [ ] Create simple PR with clear description

### 3. Complex Task Flow

If it's a complex task:

- Create a BEADS epic: `bd create --title "<task>" --type epic --priority 2`
- Use the full task completion checklist
- Consider breaking into smaller tasks as BEADS sub-issues
- Use extended thinking for planning
- Create detailed implementation plan

#### Multi-Agent Orchestration (for large features)

For complex tasks requiring multiple phases, consider spawning sub-agents:

**Model specialization guidance:**

| Model  | Best For                                                  |
| ------ | --------------------------------------------------------- |
| Opus   | Orchestration, architecture, security analysis, synthesis |
| Sonnet | Code analysis, implementation, code review, feature work  |
| Haiku  | Metrics collection, simple analysis, data processing      |

**Pattern**: Spawn parallel sub-agents for independent work (e.g., code review + security audit), sequential agents for dependent phases (research -> planning -> implementation).

### 4. Task Escalation

If a "simple task" becomes complex during implementation:

- Stop and reassess
- Create a BEADS epic: `bd create --title "<task>" --type epic --priority 2`
- Switch to full checklist workflow
- Inform user of complexity change
- Consider breaking into multiple PRs
