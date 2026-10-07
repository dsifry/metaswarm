# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework for OpenCode. It provides 19 specialized agents, 18 commands, 13 skills, BEADS MCP integration, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

Start by priming context with relevant knowledge, then begin tracked work:

```text
/prime
/start-task <task-description>
```

This primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### Design review

After writing a design document, you can request a parallel 5-agent review:

```text
/design-review-gate <path-to-design-doc>
```

The gate spawns five reviewers via the `task` tool — `product-manager-agent`, `architect-agent`, `designer-agent`, `security-design-agent`, `cto-agent` — and aggregates their verdicts. Use `--skip-agent <name>` to skip a reviewer.

### Plan review

After any implementation plan is drafted, the adversarial plan review gate runs automatically with 3 reviewers (Feasibility, Completeness, Scope & Alignment). All must PASS before the plan is presented.

### Available Commands

| Command | Purpose |
|---|---|
| `/setup` | Interactive project setup — detects your project, configures metaswarm, writes project-local files |
| `/start` | Begin tracked work — primes context, guides scoping, picks right process level |
| `/start-task` | Begin tracked work on a task with complexity assessment |
| `/prime` | Load relevant knowledge from the BEADS knowledge base before starting work |
| `/review-design` | Architecture-focused design review (single `@architect-agent`) |
| `/design-review-gate` | Parallel 5-agent design review gate (PM, Architect, Designer, Security, CTO) |
| `/plan-review-gate` | Adversarial plan review with 3 independent reviewers |
| `/orchestrated-execution` | 4-phase execution loop for work units - IMPLEMENT, VALIDATE, ADVERSARIAL REVIEW, COMMIT |
| `/self-reflect` | Semantic summarization and context compaction via BEADS |
| `/handoff` | Create structured handoff document for next agent/session |
| `/pr-shepherd` | Monitor a PR through to merge - handles reviews, CI, conflicts |
| `/brainstorm` | Structured brainstorming with design review gate trigger |
| `/update` | Update metaswarm to latest version in this project |
| `/status` | Run diagnostic checks on project health |
| `/create-issue` | Create a well-structured GitHub Issue with metaswarm context |
| `/handle-pr-comments` | Process and respond to PR review comments systematically |
| `/external-tools-health` | Check health and availability of external AI tools (Codex, Gemini) |

### Available Agents (use `@agent-name` to invoke)

| Agent | Purpose |
|---|---|
| `@issue-orchestrator` | Main coordinator per issue — spawns sub-agents, runs 4-phase execution loop |
| `@architect-agent` | Reviews technical architecture and creates implementation plans |
| `@product-manager-agent` | Defines product requirements, prioritizes features, owns product vision |
| `@researcher-agent` | Deep research across sources, synthesizes findings into reports |
| `@cto-agent` | Strategic technical decisions, architecture approval, risk assessment |
| `@security-design-agent` | Threat modeling, security architecture review, secure design patterns |
| `@code-review-agent` | Adversarial code review focusing on correctness, security, maintainability |
| `@sre-agent` | Reliability, observability, incident response, capacity planning |
| `@metrics-agent` | Defines and tracks SLIs/SLOs, builds dashboards, analyzes system metrics |
| `@slack-coordinator-agent` | Manages Slack communications, incident channels, stakeholder updates |
| `@coder-agent` | Implements code changes following TDD, writes tests first |
| `@pr-shepherd-agent` | Shepherds PRs through review, CI, merge — handles comments, conflicts |
| `@release-engineer-agent` | Manages releases, versioning, changelogs, deployment pipelines |
| `@customer-service-agent` | Handles user feedback, support tickets, feature requests triage |
| `@test-automator-agent` | Writes and maintains test suites, enforces coverage thresholds |
| `@security-auditor-agent` | Security audits, vulnerability scanning, compliance checks |
| `@swarm-coordinator-agent` | Orchestrates multi-agent swarms for complex parallel work |
| `@designer-agent` | UX/UI design, design systems, accessibility, user research |
| `@knowledge-curator-agent` | Maintains BEADS knowledge base — patterns, decisions, gotchas, facts |

### BEADS Integration (MCP)

BEADS tools are available natively via MCP:

- `@bd_ready` — Find available work items
- `@bd_show <id>` — View issue details
- `@bd_prime [query]` — Load relevant knowledge
- `@bd_sync` — Sync knowledge base with remote
- `@bd_knowledge_list [type]` — List knowledge by type (pattern, gotcha, decision, etc.)

### Skills Discovery

13 skills are auto-discovered from `.opencode/skills/`:
- `start`, `setup`, `prime`, `review-design`, `design-review-gate`
- `plan-review-gate`, `orchestrated-execution`, `self-reflect`, `handoff`
- `pr-shepherd`, `brainstorm`, `update`, `status`, `create-issue`
- `handle-pr-comments`, `external-tools-health`

## Platform Conventions

The metaswarm command and agent prompts are written for Claude Code. When you follow them, translate these conventions to OpenCode equivalents:

| Claude Code convention | OpenCode equivalent |
|---|---|
| `Task()` subagent spawn | `task` tool with `subagent_type` (e.g., `subagent_type: "architect-agent"`) |
| `@agent-name` mentions | `task` tool with the registered subagent name |
| `@beads start #N` / `@beads approve` | `bd start #N` / `bd approve` (BEADS CLI directly) |
| `CLAUDE.md` instruction file | `AGENTS.md` + this file |
| Team Mode (`TeamCreate`/`SendMessage`) | Not available — always use Task Mode (`task` tool) |

Rules that must not be diluted when translating:

- Adversarial reviewers are ALWAYS fresh `task` tool calls — never reused, never resumed, never given prior context.
- Never pass `--dangerously-skip-permissions` or auto-approve write permissions.
- Spawn one `task` call per agent; do not impersonate multiple roles in a single agent's response.

## Current Limitations

- Session hooks (compacting, session events) are not configured — OpenCode does not yet support native hooks
- Plugin marketplace not available — OpenCode has no `opencode plugin install` command