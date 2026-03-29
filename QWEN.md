# metaswarm — Qwen Code Context

## Project Overview

**metaswarm** is a multi-agent orchestration framework for AI coding assistants (Claude Code, Google Gemini CLI, OpenAI Codex CLI, and Qwen Code CLI). It coordinates 18 specialized AI agents through a complete software development lifecycle — from GitHub Issue to merged PR — with TDD enforcement, parallel review gates, and git-native knowledge management.

### Core Capabilities

- **18 specialized agent personas**: Researcher, Architect, Coder, Security Auditor, PR Shepherd, Knowledge Curator, etc.
- **Structured 9-phase workflow**: Research → Plan → Design Review Gate → Work Unit Decomposition → Orchestrated Execution → Final Review → PR Creation → PR Shepherd → Closure & Learning
- **4-Phase Execution Loop**: Each work unit runs through IMPLEMENT → VALIDATE → ADVERSARIAL REVIEW → COMMIT with independent validation
- **Parallel Design Review Gate**: 6 specialist agents (PM, Architect, Designer, Security, UX Reviewer, CTO) review in parallel
- **Git-native task tracking**: Uses BEADS (`bd` CLI) for issue/task management, dependencies, and knowledge priming
- **Knowledge base**: JSONL-based fact store for patterns, gotchas, decisions, and anti-patterns
- **Quality rubrics**: Standardized review criteria for code, architecture, security, testing, and spec compliance
- **External AI tool delegation**: Optionally delegate to Codex CLI or Gemini CLI for cost savings and cross-model adversarial review
- **Visual review**: Playwright-based screenshot capture for reviewing web UIs

### Repository Structure

```
metaswarm/
├── agents/                    # 18 agent persona definitions
├── skills/                    # 13 orchestration skills (start, design-review-gate, orchestrated-execution, etc.)
├── commands/                  # Slash commands for Claude Code and Gemini CLI
├── rubrics/                   # Quality review standards
├── guides/                    # 6 development pattern guides
├── knowledge/                 # Knowledge base schema and templates
├── templates/                 # Setup templates and configs
├── lib/                       # Platform detection, sync, setup scripts
├── cli/                       # Cross-platform installer (npx metaswarm)
├── bin/                       # Shell scripts and utilities
├── tests/                     # Test suite
├── CLAUDE.md                  # Claude Code project instructions
├── AGENTS.md                  # Codex CLI project instructions
├── GEMINI.md                  # Gemini CLI extension context
└── package.json               # npm package manifest
```

## Building and Running

### Installation

**Claude Code (recommended):**
```bash
claude plugin marketplace add dsifry/metaswarm-marketplace
claude plugin install metaswarm
```

**Gemini CLI:**
```bash
gemini extensions install https://github.com/dsifry/metaswarm.git
```

**Codex CLI:**
```bash
curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.codex/install.sh | bash
```

**Qwen Code CLI:**
```bash
curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.qwen/install.sh | bash
```

**All platforms:**
```bash
npx metaswarm init
```

### Available Commands

| Command | Description |
|---|---|
| `/start-task` or `$start` | Begin tracked work on a task |
| `/setup` or `$setup` | Interactive guided project setup |
| `/status` or `$status` | Run 9 diagnostic checks |
| `/prime` | Load relevant knowledge before work |
| `/review-design <path>` | Trigger 6-agent Design Review Gate |
| `/plan-review-gate` | Adversarial plan review (3 reviewers) |
| `/pr-shepherd <pr-number>` | Monitor PR through to merge |
| `/handle-pr-comments <pr-number>` | Handle PR review comments |
| `/create-issue` | Create well-structured GitHub Issue |
| `/self-reflect` | Extract learnings from recent PRs |

### BEADS Issue Tracking

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
bd prime              # Load relevant knowledge before work
```

### Development Workflow

1. **Start a task**: Run `/start-task` and describe what you want in plain English
2. **Research phase**: Researcher agent explores codebase
3. **Planning phase**: Architect creates implementation plan
4. **Plan Review Gate**: 3 adversarial reviewers validate (Feasibility, Completeness, Scope & Alignment)
5. **Design Review Gate** (for complex features): 6 parallel reviewers
6. **Work Unit Decomposition**: Break into discrete units with DoD items
7. **Orchestrated Execution**: Per work unit: IMPLEMENT → VALIDATE → ADVERSARIAL REVIEW → COMMIT
8. **Final Review**: Cross-unit integration check
9. **PR Creation**: Auto-shepherd monitors CI and review comments
10. **Closure**: Extract learnings to knowledge base

## Development Conventions

### Quality Gates (MANDATORY)

- **After brainstorming** → MUST run Design Review Gate before planning
- **After any plan** → MUST run Plan Review Gate before presenting to user
- **TDD is mandatory** → Write tests first, watch them fail, then implement
- **Coverage thresholds** → `.coverage-thresholds.json` is the single source of truth. BLOCKING gate.
- **NEVER** use `--no-verify` on git commits
- **NEVER** use `git push --force` without explicit user approval
- **NEVER** self-certify — orchestrator validates independently
- **ALWAYS** follow TDD, STAY within file scope

### Session Completion (Landing the Plane)

When ending a work session, you MUST:

1. **File issues for remaining work** — Create issues for follow-ups
2. **Run quality gates** (if code changed) — Tests, linters, builds
3. **Update issue status** — Close finished work, update in-progress
4. **PUSH TO REMOTE** — This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** — Clear stashes, prune remote branches
6. **Verify** — All changes committed AND pushed
7. **Hand off** — Provide context for next session

**CRITICAL**: Work is NOT complete until `git push` succeeds. Never stop before pushing.

### Test Coverage

Coverage thresholds are defined in `.coverage-thresholds.json`:

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

Agents are blocked from creating PRs or marking tasks complete until all thresholds pass.

### Knowledge Priming

Before ANY task, agents MUST prime context:

```bash
# General prime
bd prime

# Prime for specific files
bd prime --files "src/api/**/*.ts"

# Prime for topic
bd prime --keywords "authentication"

# Prime for work type
bd prime --work-type implementation
bd prime --work-type review
bd prime --work-type planning
```

### Orchestrated Execution Rules

When executing work units with a written spec and DoD items:

1. **Trust nothing, verify everything** — Orchestrator runs `tsc`, `eslint`, `vitest` directly
2. **Fresh reviewers** — On re-review after FAIL, spawn NEW reviewer with no prior context
3. **Max 3 retries** — After 3 FAILs, escalate to human with failure history
4. **Respect file scope** — Verify with `git diff --name-only`
5. **Human checkpoints** — Pause at planned boundaries (schema, security, external deps)
6. **Update SERVICE-INVENTORY.md** — Track new services/factories/modules after each commit
7. **Maintain project context** — Pass context document to each coder subagent

### External AI Tools (Optional)

When configured (`.metaswarm/external-tools.yaml`), the orchestrator can delegate to:
- **OpenAI Codex CLI** — For implementation tasks
- **Google Gemini CLI** — For implementation or adversarial review

Cross-model review ensures the writer is always reviewed by a different AI model.

### Visual Review

For tasks with visual output (web UIs, presentations), use `$visual-review` to capture screenshots via Playwright:

```bash
npx playwright install chromium  # Prerequisite
```

## Key Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Codex CLI project instructions and quick reference |
| `CLAUDE.md` | Claude Code project instructions |
| `GEMINI.md` | Gemini CLI extension context |
| `QWEN.md` | This file — Qwen Code CLI project instructions |
| `ORCHESTRATION.md` | Points to `skills/start/SKILL.md` (main orchestration skill) |
| `GETTING_STARTED.md` | Step-by-step guide for first-time users |
| `USAGE.md` | Full reference for all agents, skills, and commands |
| `CONTRIBUTING.md` | How to contribute agents, skills, rubrics |
| `.coverage-thresholds.json` | Test coverage thresholds (blocking gate) |
| `skills/start/SKILL.md` | Main entry point — workflow guide + 18 agent personas |

## Qwen Code CLI Notes

- **Enable skills**: Run with `--experimental-skills` flag: `qwen --experimental-skills`
- **Skill location**: Skills are symlinked to `~/.qwen/skills/`
- **Invoke with `$name`**: Use `$start`, `$setup`, etc. (matches SKILL.md `name` field)
- **Sequential execution**: Design reviews and adversarial reviews run sequentially (not parallel like Claude)
- **Quality gates**: Same rubrics and criteria apply — execution mode differs, not thoroughness

See `.qwen/README.md` for full installation and usage details.

## Agent Roster

| Agent | Role |
|---|---|
| **Swarm Coordinator** | Meta-orchestrator for parallel work across worktrees |
| **Issue Orchestrator** | Main coordinator per issue |
| **Researcher** | Codebase exploration, pattern discovery |
| **Architect** | Implementation planning |
| **Product Manager** | Use case & user benefit review |
| **Designer** | UX/API design review |
| **Security Design** | Threat modeling (STRIDE) |
| **CTO** | TDD readiness & plan review |
| **Coder** | TDD implementation |
| **Code Reviewer** | Internal code review |
| **Security Auditor** | Security code review |
| **PR Shepherd** | PR lifecycle management |
| **Knowledge Curator** | Extract learnings from PRs |
| **Test Automator** | Test generation and coverage |
| **Metrics** | Analytics collection |
| **Slack Coordinator** | Notifications and communication |
| **SRE** | Infrastructure monitoring |
| **Customer Service** | User support and triage |

## Requirements

- One of: Claude Code, Gemini CLI, or Codex CLI
- Node.js 18+ (for automation scripts)
- BEADS CLI (`bd`) v0.40+ — for task tracking (recommended)
- GitHub CLI (`gh`) — for PR automation (recommended)
- Playwright — for visual review (optional, `npx playwright install chromium`)
