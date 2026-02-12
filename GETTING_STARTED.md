# Getting Started

This guide walks you through your first metaswarm-orchestrated workflow.

## Step 1: Install metaswarm

```bash
cd your-project
npx metaswarm init
```

That's it — one command installs everything. 18 agents, 6 skills, 7 commands, 6 rubrics, knowledge templates, automation scripts, and BEADS task tracking, all scaffolded into your project.

Verify it worked:

```bash
ls .beads/knowledge/
# patterns.jsonl  gotchas.jsonl  decisions.jsonl  ...
```

Add your first knowledge entry:

```bash
echo '{"id": "pattern-001", "type": "pattern", "fact": "All API routes require authentication middleware", "recommendation": "Always add authMiddleware() to new route handlers", "confidence": "high", "tags": ["api", "auth"]}' >> .beads/knowledge/patterns.jsonl
```

## Step 2: Create Your First Tracked Issue

```bash
# Create an epic
bd create "Add user profile page" --type epic --priority 2

# Create tasks under it
bd create "Research existing user data model" --type task --parent <epic-id>
bd create "Design profile API endpoints" --type task --parent <epic-id>
bd create "Implement profile service" --type task --parent <epic-id>
bd create "Build profile UI components" --type task --parent <epic-id>

# Add dependencies
bd dep add <design-task> <research-task>
bd dep add <implement-task> <design-task>
bd dep add <ui-task> <implement-task>

# Check what's ready to work on
bd ready
```

## Step 3: Run the Orchestration Workflow

In Claude Code, start the workflow:

```text
> /project:start-task <task-id>
```

This triggers the full pipeline:
1. **Prime** — Loads relevant knowledge for the task
2. **Research** — Explores your codebase for related patterns
3. **Plan** — Creates an implementation plan
4. **Review** (if complex) — Runs the Design Review Gate
5. **Implement** — TDD implementation
6. **Review** — Code review + security audit
7. **PR** — Creates PR with auto-shepherd

## Step 4: Try the Design Review Gate

For a more complex feature, trigger the parallel review manually:

```text
> /project:review-design docs/specs/my-feature.md
```

Five agents review in parallel:
- **PM**: Validates use cases and scope
- **Architect**: Checks service design and patterns
- **Designer**: Reviews API/UX design
- **Security**: Threat modeling (STRIDE)
- **CTO**: TDD readiness and alignment

Each produces an APPROVE/REVISE verdict. All five must approve, or the plan iterates (max 3 rounds before human escalation).

## Step 4.5: Orchestrated Execution (for Complex Tasks)

When your task has a **written spec with Definition of Done items** (e.g., after the Design Review Gate approves a plan), use orchestrated execution for rigorous, verified implementation.

The orchestrator breaks the plan into **work units** and runs each through a 4-phase loop:

```text
IMPLEMENT → VALIDATE → ADVERSARIAL REVIEW → COMMIT
```

What makes this different from just "implement and review":

1. **Independent validation** — The orchestrator runs tests and type checks itself, never trusting the coding agent's self-report
2. **Adversarial review** — A fresh reviewer checks each DoD item with file:line evidence. Binary PASS/FAIL, not subjective quality assessment
3. **Fresh reviewers** — On re-review after failure, a new reviewer is spawned with zero memory of the previous review
4. **Human checkpoints** — Planned pauses at critical boundaries (schema changes, security code) where you review before the agent continues

**When to use it**: Multi-unit features with a spec, risky changes, anything where "it works, trust me" isn't good enough.

**When NOT to use it**: Single-file fixes, quick prototypes, tasks without a clear spec. For these, the simple task flow in Step 3 is the right choice.

See `skills/orchestrated-execution/SKILL.md` for the full pattern, and `rubrics/adversarial-review-rubric.md` for how adversarial reviews differ from standard code reviews.

## Step 5: Use Knowledge Priming

Before any task, prime your agent with relevant context:

```text
> /project:prime
```

Or with specific filters:

```bash
bd prime --files "src/api/**/*.ts" --keywords "authentication" --work-type implementation
```

This outputs prioritized knowledge:
1. **MUST FOLLOW** — Critical rules
2. **GOTCHAS** — Common pitfalls
3. **PATTERNS** — Best practices
4. **DECISIONS** — Architectural constraints

## Step 6: Set Up Coverage Enforcement

Use the `--with-coverage` flag (or `--with-husky` / `--with-ci` which imply it):

```bash
npx metaswarm init --with-husky --with-ci
```

This copies `.coverage-thresholds.json` to your project root, sets up Husky with a pre-push hook, and creates a CI coverage workflow. Edit `.coverage-thresholds.json` to set your coverage command and thresholds.

You can also set up just the thresholds file:

```bash
npx metaswarm init --with-coverage
```

When `.coverage-thresholds.json` exists, agents will be blocked from creating PRs or marking tasks complete until all coverage thresholds pass.

For details on the three enforcement gates, see [docs/coverage-enforcement.md](docs/coverage-enforcement.md).

## Step 7: Monitor a PR

After creating a PR, let the PR Shepherd monitor it:

```text
> /project:pr-shepherd 42
```

The shepherd:
- Monitors CI status
- Handles review comments
- Resolves threads
- Reports when ready to merge

## Step 8: Extract Learnings

After a PR is merged, extract learnings for the knowledge base:

```text
> /project:self-reflect
```

This analyzes recent PR review comments and suggests new knowledge entries for patterns, gotchas, and decisions.

## Customization

### Adding Your Own Agents

Create a new `.md` file in `agents/`:

```markdown
# My Custom Agent

## Role
Brief description of the agent's specialty.

## Responsibilities
- What this agent does
- What it produces

## Process
1. Step-by-step workflow
2. What to check
3. What to produce

## Output Format
Description of expected deliverables.
```

### Adding Rubrics

Create a `.md` file in `rubrics/` with scoring criteria that agents reference during reviews.

### Adding Knowledge

Append JSONL entries to the appropriate file in `knowledge/`:

```json
{"id": "gotcha-my-api", "type": "gotcha", "fact": "The payments API returns 200 even on failure", "recommendation": "Always check the response body status field, not HTTP status", "confidence": "high", "tags": ["payments", "api"]}
```

## What's Next

- [USAGE.md](USAGE.md) — Full reference for all agents, skills, and commands
- [ORCHESTRATION.md](ORCHESTRATION.md) — The complete orchestration workflow specification
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute back
