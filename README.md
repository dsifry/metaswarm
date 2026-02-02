# metaswarm

A multi-agent orchestration framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Coordinate 18 specialized AI agents through a complete software development lifecycle — from issue to merged PR — with recursive orchestration, parallel review gates, and a git-native knowledge base.

## What Is This?

metaswarm is an extraction of a production-tested agentic orchestration system. It provides:

- **18 specialized agent personas** (Researcher, Architect, Coder, Security Auditor, PR Shepherd, etc.)
- **A structured 8-phase workflow**: Research → Plan → Design Review Gate → Implement → Code Review → PR Creation → PR Shepherd → Closure & Learning
- **Parallel Design Review Gate**: 5 specialist agents (PM, Architect, Designer, Security, CTO) review in parallel with a 3-iteration cap before human escalation
- **Recursive orchestration**: Swarm Coordinators spawn Issue Orchestrators, which spawn sub-orchestrators for complex epics (swarm of swarms)
- **Git-native task tracking**: Uses [BEADS](https://github.com/steveyegge/beads) (`bd` CLI) for issue/task management, dependencies, and knowledge priming
- **Knowledge base**: JSONL-based fact store for patterns, gotchas, decisions, and anti-patterns — agents prime from this before every task
- **Quality rubrics**: Standardized review criteria for code, architecture, security, testing, and planning
- **PR lifecycle automation**: Autonomous CI monitoring, review comment handling, and thread resolution

## Architecture

```text
GitHub Issue (agent-ready label)
        │
        ▼
┌─────────────────────────────────┐
│  Swarm Coordinator               │
│  - Assign to worktree            │
│  - Spawn Issue Orchestrator      │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│  Issue Orchestrator              │
│  - Create BEADS epic             │
│  - Decompose into tasks          │
└─────────────────────────────────┘
        │
        ▼
  Research → Plan → Design Review Gate (5 parallel reviewers)
        │
        ▼
  Implement (TDD) → Code Review + Security Audit
        │
        ▼
  PR Creation → PR Shepherd (auto-monitors to merge)
        │
        ▼
  Closure → Knowledge Extraction (feedback loop)
```

## Repository Structure

```text
metaswarm/
├── ORCHESTRATION.md          # Main orchestration workflow guide
├── agents/                   # 18 agent persona definitions
│   ├── issue-orchestrator.md
│   ├── swarm-coordinator-agent.md
│   ├── researcher-agent.md
│   ├── architect-agent.md
│   ├── coder-agent.md
│   ├── code-review-agent.md
│   ├── security-auditor-agent.md
│   ├── pr-shepherd-agent.md
│   └── ... (18 total)
├── skills/                   # Orchestration skills
│   ├── design-review-gate/   # Parallel 5-agent review
│   ├── pr-shepherd/          # PR lifecycle automation
│   ├── handling-pr-comments/ # Review comment workflow
│   ├── brainstorming-extension/
│   └── create-issue/
├── commands/                 # Claude Code slash commands
│   ├── prime.md              # Knowledge priming
│   ├── start-task.md         # Begin tracked work
│   ├── review-design.md      # Trigger design review gate
│   ├── self-reflect.md       # Extract learnings
│   └── ...
├── rubrics/                  # Quality review standards
│   ├── code-review-rubric.md
│   ├── architecture-rubric.md
│   ├── security-review-rubric.md
│   ├── plan-review-rubric.md
│   └── test-coverage-rubric.md
├── knowledge/                # Knowledge base schema + templates
│   ├── README.md
│   ├── patterns.jsonl
│   ├── gotchas.jsonl
│   ├── decisions.jsonl
│   └── ...
├── scripts/                  # Automation scripts
├── bin/                      # Shell utilities
├── templates/                # Setup templates
├── INSTALL.md
├── GETTING_STARTED.md
├── USAGE.md
└── CONTRIBUTING.md
```

## Quick Start

```bash
# 1. Install BEADS CLI
curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# 2. Clone metaswarm
git clone https://github.com/dsifry/metaswarm.git

# 3. Copy into your project (see INSTALL.md for details)
cp -r metaswarm/agents/ your-project/.claude/agents/
cp -r metaswarm/skills/ your-project/.claude/skills/
cp -r metaswarm/commands/ your-project/.claude/commands/
cp -r metaswarm/rubrics/ your-project/.claude/rubrics/

# 4. Initialize BEADS in your project
cd your-project && bd init

# 5. Prime your first agent
bd prime
```

See [INSTALL.md](INSTALL.md) for detailed setup and [GETTING_STARTED.md](GETTING_STARTED.md) for your first orchestrated workflow.

## Design Principles

1. **Knowledge-Driven Development** — Agents prime from the knowledge base before every task, reducing repeated mistakes
2. **Parallel Review Gates** — Independent specialist reviewers run concurrently, not sequentially
3. **Recursive Orchestration** — Orchestrators spawn sub-orchestrators for any level of complexity
4. **Agent Ownership** — Each agent owns its lifecycle; the orchestrator delegates, not micromanages
5. **BEADS as Source of Truth** — All task state lives in BEADS; agents coordinate via database, not messages
6. **Test-First Always** — TDD is mandatory, not optional
7. **Git-Native Everything** — Issues, knowledge, specs all in version control
8. **Human-in-the-Loop** — Automatic escalation after 3 failed iterations or ambiguous decisions

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [BEADS](https://github.com/steveyegge/beads) CLI (`bd`) v0.40+
- Node.js 20+ (for scripts)
- GitHub CLI (`gh`) for PR automation

## License

MIT

## Acknowledgments

Extracted from a production multi-tenant SaaS development workflow. The orchestration patterns have been validated across hundreds of PRs with autonomous agent delivery.
