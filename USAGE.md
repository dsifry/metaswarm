# Usage Reference

## Agents

metaswarm provides 18 specialized agents, each with a defined role in the software development lifecycle.

### Orchestration Agents

| Agent | File | Role |
|---|---|---|
| **Swarm Coordinator** | `agents/swarm-coordinator-agent.md` | Meta-orchestrator for parallel work across worktrees. Assigns issues to worktrees, manages port allocation, detects file-level conflicts. |
| **Issue Orchestrator** | `agents/issue-orchestrator.md` | Main coordinator per issue. Creates BEADS epic, decomposes into tasks, delegates to specialist agents, manages workflow phases. |

### Research & Planning Agents

| Agent | File | Role |
|---|---|---|
| **Researcher** | `agents/researcher-agent.md` | Codebase exploration, pattern discovery, dependency analysis. |
| **Architect** | `agents/architect-agent.md` | Implementation planning, service structure design, pattern selection. |
| **Product Manager** | `agents/product-manager-agent.md` | Use case validation, user benefit review, scope verification. |
| **Designer** | `agents/designer-agent.md` | UX/API design review, developer experience, consistency. |
| **Security Design** | `agents/security-design-agent.md` | Threat modeling (STRIDE), auth/authz design, OWASP Top 10. |
| **CTO** | `agents/cto-agent.md` | TDD readiness review, plan approval, codebase alignment. |

### Implementation Agents

| Agent | File | Role |
|---|---|---|
| **Coder** | `agents/coder-agent.md` | TDD implementation (RED-GREEN-REFACTOR). 100% coverage required. |
| **Test Automator** | `agents/test-automator-agent.md` | Test generation and coverage enforcement. |

### Review Agents

| Agent | File | Role |
|---|---|---|
| **Code Reviewer** | `agents/code-review-agent.md` | Internal pre-PR review, pattern enforcement, test verification. |
| **Security Auditor** | `agents/security-auditor-agent.md` | Security code review, vulnerability scanning. |

### PR & Delivery Agents

| Agent | File | Role |
|---|---|---|
| **PR Shepherd** | `agents/pr-shepherd-agent.md` | PR lifecycle: CI monitoring, review comment handling, thread resolution. |

### Support Agents

| Agent | File | Role |
|---|---|---|
| **Knowledge Curator** | `agents/knowledge-curator-agent.md` | Extracts learnings from PRs, updates knowledge base. |
| **Metrics** | `agents/metrics-agent.md` | Analytics collection, weekly reports. |
| **Slack Coordinator** | `agents/slack-coordinator-agent.md` | Slack notifications and human communication. |
| **SRE** | `agents/sre-agent.md` | Infrastructure monitoring, performance optimization. |
| **Customer Service** | `agents/customer-service-agent.md` | User support and issue triage. |

## Skills

Skills are orchestration behaviors that coordinate multiple agents.

### Design Review Gate

**Path**: `skills/design-review-gate/SKILL.md`

Spawns 5 agents in parallel to review a design document:

```text
/project:review-design <path-to-spec>
```

- PM, Architect, Designer, Security, CTO review simultaneously
- All 5 must APPROVE
- Max 3 iterations before human escalation
- Catches architectural issues before implementation begins

### PR Shepherd

**Path**: `skills/pr-shepherd/SKILL.md`

Autonomously monitors a PR through to merge:

```text
/project:pr-shepherd <pr-number>
```

- Polls CI status
- Fixes linting/type errors
- Responds to review comments
- Resolves discussion threads
- Reports when ready for human approval

### Handling PR Comments

**Path**: `skills/handling-pr-comments/SKILL.md`

Systematic workflow for addressing review feedback:

```text
/project:handle-pr-comments <pr-number>
```

- Categorizes comments by priority
- Addresses actionable items
- Marks out-of-scope items with rationale
- Resolves threads after addressing

## Commands

| Command | Description |
|---|---|
| `/project:prime` | Load relevant knowledge before starting work |
| `/project:start-task <id>` | Begin a BEADS-tracked task with full workflow |
| `/project:review-design <path>` | Run the 5-agent Design Review Gate |
| `/project:self-reflect` | Extract learnings from recent PR reviews |
| `/project:pr-shepherd <pr>` | Monitor PR through to merge |
| `/project:handle-pr-comments <pr>` | Address PR review feedback |
| `/project:create-issue` | Create a GitHub issue with agent instructions |

## BEADS CLI Reference

Core commands for task tracking:

```bash
# Issue Management
bd create "Title" --type epic|task|bug --priority 1-5
bd show <id>
bd update <id> --status open|in_progress|blocked|closed
bd close <id> --reason "Done"
bd list --status open

# Dependencies
bd dep add <task> <blocks>    # task blocks other work
bd ready                       # Show unblocked tasks
bd blocked                     # Show blocked tasks

# Knowledge
bd prime                       # Load all relevant knowledge
bd prime --keywords "auth"     # Filter by keyword
bd prime --work-type impl      # Filter by work type

# Sync
bd sync                        # Sync with git
bd export                      # Export to JSONL
```

## Knowledge Base

### File Schema

All files in `knowledge/` use JSONL format:

```json
{
  "id": "unique-identifier",
  "type": "pattern|gotcha|decision|anti-pattern|codebase-fact|api-behavior",
  "fact": "Clear description of the knowledge",
  "recommendation": "What to do about it",
  "confidence": "high|medium|low",
  "provenance": [{"source": "human|agent|review", "reference": "PR #123"}],
  "tags": ["relevant", "tags"],
  "affectedFiles": ["src/path/to/file.ts"],
  "createdAt": "2026-01-01T00:00:00Z"
}
```

### Knowledge Categories

| File | Purpose | Example |
|---|---|---|
| `patterns.jsonl` | Reusable best practices | "Use factory functions for mock creation" |
| `gotchas.jsonl` | Common pitfalls | "API returns 200 on soft failures" |
| `decisions.jsonl` | Architectural choices | "Chose Zustand over Redux for simplicity" |
| `anti-patterns.jsonl` | What to avoid | "Never use `as any` for type casting" |
| `codebase-facts.jsonl` | Code-specific behaviors | "Auth middleware runs before route handlers" |
| `api-behaviors.jsonl` | External API quirks | "Rate limit is 100 req/min on free tier" |

## Coverage Enforcement

metaswarm supports configurable test coverage thresholds that block PR creation and task completion. This ensures agents cannot ship code that drops coverage below your project's standards.

### Setup

Copy the template to your project root:

```bash
cp templates/coverage-thresholds.json .coverage-thresholds.json
```

### Configuration

Edit `.coverage-thresholds.json` to set your thresholds and coverage command:

```json
{
  "thresholds": {
    "lines": 100,
    "branches": 100,
    "functions": 100,
    "statements": 100
  },
  "enforcement": {
    "command": "pnpm test:coverage",
    "blockPRCreation": true,
    "blockTaskCompletion": true
  }
}
```

| Field | Description |
|---|---|
| `thresholds.lines` | Minimum line coverage percentage |
| `thresholds.branches` | Minimum branch coverage percentage |
| `thresholds.functions` | Minimum function coverage percentage |
| `thresholds.statements` | Minimum statement coverage percentage |
| `enforcement.command` | Shell command to run coverage (e.g., `pytest --cov`, `cargo tarpaulin`, `go test -cover`) |
| `enforcement.blockPRCreation` | If `true`, agents cannot create a PR until all thresholds pass |
| `enforcement.blockTaskCompletion` | If `true`, agents cannot mark a task complete until all thresholds pass |

### How Agents Use It

When `.coverage-thresholds.json` exists in the project root:

1. **Before pushing or creating a PR**, agents run the `enforcement.command`
2. If any threshold is not met, the agent **stops and fixes coverage** before proceeding
3. The task-completion-checklist enforces this as a blocking gate

### Single Source of Truth

Your test runner config (e.g., `vitest.config.ts`, `jest.config.js`, `pyproject.toml`) can read thresholds directly from `.coverage-thresholds.json` to avoid duplication. Example for Vitest:

```typescript
import fs from "node:fs";
import path from "node:path";

const coverageConfig = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, ".coverage-thresholds.json"), "utf-8"),
);

export default defineConfig({
  test: {
    coverage: {
      thresholds: coverageConfig.thresholds,
    },
  },
});
```

This way both agents and CI enforce the same thresholds from a single file.

## Rubrics

Quality standards used by review agents:

| Rubric | Used By | Covers |
|---|---|---|
| `code-review-rubric.md` | Code Review Agent | Style, patterns, error handling, testing |
| `architecture-rubric.md` | Architect Agent | Service design, coupling, scalability |
| `security-review-rubric.md` | Security Auditor | OWASP Top 10, auth, data handling |
| `plan-review-rubric.md` | CTO Agent | TDD readiness, completeness, alignment |
| `test-coverage-rubric.md` | Test Automator | Coverage, edge cases, mock quality |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/beads-fetch-pr-comments.ts` | Fetch PR review comments from GitHub |
| `scripts/beads-self-reflect.ts` | Generate knowledge base statistics |
| `bin/pr-comments-check.sh` | Verify all review comments addressed |
| `bin/pr-comments-filter.sh` | Filter actionable vs non-actionable comments |

## Workflow Phases

The full orchestration lifecycle:

| Phase | Agent(s) | Output |
|---|---|---|
| 1. Research | Researcher | Codebase analysis, pattern inventory |
| 2. Planning | Architect | Implementation plan with tasks |
| 3. Design Review | PM + Architect + Designer + Security + CTO (parallel) | APPROVE/REVISE verdicts |
| 4. Implementation | Coder | TDD code with 100% coverage |
| 5. Code Review | Code Reviewer + Security Auditor | Review findings |
| 6. PR Creation | Issue Orchestrator | GitHub PR |
| 7. PR Shepherd | PR Shepherd | CI fixes, comment responses |
| 8. Closure | Knowledge Curator | Knowledge base updates |
