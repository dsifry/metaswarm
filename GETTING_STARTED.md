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

## One-Shot Build: From Empty Repo to Working App

The fastest way to see metaswarm in action is to give it a project to build from scratch. Here's the full recipe.

### 1. Set up the project

```bash
mkdir my-new-app && cd my-new-app
git init
npm init -y        # or whatever your stack needs
npx metaswarm init --with-husky --with-ci

# Create the GitHub repo
gh repo create my-new-app --public --source=. --push
```

### 2. Write a spec as a GitHub Issue

Create an issue that describes what you want built. The more specific the better — include acceptance criteria (Definition of Done items) so the agents know exactly what "done" means.

```bash
gh issue create --title "Build a real-time collaborative todo list with AI chat" --body "$(cat <<'SPEC'
## Overview

Build a web-based todo list application with real-time sync across tabs/devices
and an AI chat interface powered by the Claude SDK that lets users manage their
todos through natural language.

## Tech Stack

- **Backend**: Node.js with Hono framework
- **Frontend**: React with Vite
- **Database**: SQLite via better-sqlite3
- **Real-time**: Server-Sent Events (SSE)
- **AI**: Anthropic Claude SDK (@anthropic-ai/sdk)
- **Testing**: Vitest

## Definition of Done

1. Users can create, complete, and delete todo items via the UI
2. Todo items persist in SQLite and survive server restarts
3. Changes sync in real-time across multiple browser tabs via SSE
4. Users can chat with an AI assistant that can read and modify their todos
5. AI responses stream in real-time (not buffered)
6. All API endpoints have input validation
7. 100% test coverage on backend services
8. CI pipeline runs tests and lint on every push
9. Clean responsive UI that works on mobile

## File Scope

- src/server/ — Backend API and SSE
- src/client/ — React frontend
- src/shared/ — Shared types
- src/server/**/*.test.ts — Backend tests
SPEC
)"
```

### 3. Tell Claude Code to build it

Open Claude Code in the project directory and give it one prompt:

```text
Work on issue #1. Use the full metaswarm orchestration workflow:
research the codebase, create an implementation plan, run the design
review gate, decompose into work units, and execute each through the
4-phase loop (implement, validate, adversarial review, commit).
Set human checkpoints after the database schema and after the AI
integration. When all work units pass, create a PR.
```

That's it. The Issue Orchestrator takes over:

1. **Research** — Scans your (empty) project, notes the tech stack from the issue
2. **Plan** — Architect agent creates an implementation plan with work units
3. **Design Review** — 5 agents review the plan in parallel (PM, Architect, Designer, Security, CTO)
4. **Decompose** — Breaks the plan into work units with DoD items and dependencies
5. **Execute** — For each work unit: implement with TDD, validate independently, adversarial review against DoD
6. **Checkpoints** — Pauses after schema setup and AI integration for your review
7. **Final Review** — Cross-unit integration check after all units pass
8. **PR** — Creates the PR and starts shepherding

### 4. Review at checkpoints

The orchestrator will pause at the checkpoints you specified. You'll see a report like:

```text
## Checkpoint: Database Schema Complete

### Completed Work Units
| WU   | Title              | Review          |
| ---- | ------------------ | --------------- |
| WU-1 | Project scaffolding| Adversarial PASS|
| WU-2 | SQLite schema      | Adversarial PASS|

### What Comes Next
- WU-3: REST API endpoints
- WU-4: SSE real-time sync
- WU-5: AI chat integration

Action required: Reply to continue, or provide feedback.
```

Review what was built, give feedback if needed, then reply to continue.

### 5. Merge and ship

After all work units pass and the final comprehensive review is clean, the PR Shepherd monitors CI and handles any review comments. When everything is green, you merge.

### What just happened

In one prompt, metaswarm:
- Decomposed your spec into discrete work units with dependency ordering
- Implemented each unit with TDD (tests first, then code)
- Independently validated every unit (ran tsc, eslint, vitest itself — never trusted the coding agent)
- Had a fresh adversarial reviewer verify each unit against the spec with file:line evidence
- Paused for your review at the critical points you specified
- Ran a final cross-unit integration check
- Created and shepherded a PR

You described what you wanted. The system figured out how to build it.

### Tips for writing good one-shot specs

- **Be specific about DoD items.** "Users can create todos" is better than "todo functionality works." Agents verify exactly what you write.
- **Name your tech stack.** Don't make agents guess. Say "Hono + React + SQLite", not "pick a framework."
- **Set file scope.** Tell agents where code should live. This prevents sprawl and makes adversarial review effective.
- **Use human checkpoints.** Put them after risky or foundational work (database schema, auth, AI integration). You can always continue quickly, but you can't easily undo.
- **Start with a working spec, not a vague idea.** If you're not sure what you want yet, use `/project:brainstorm` first to refine the idea, then create the issue from the brainstorming output.

---

## The Pieces (Step by Step)

The rest of this guide walks through metaswarm's components individually. If you just ran the one-shot build above, you've already seen all of these in action.

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
