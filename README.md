# metaswarm

A self-improving multi-agent orchestration framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Coordinate 18 specialized AI agents through a complete software development lifecycle, from issue to merged PR, with recursive orchestration, parallel review gates, and a git-native knowledge base.

## What Is This?

metaswarm is an extraction of a production-tested agentic orchestration system. It has been proven in the field writing production-level code with 100% test coverage, mandatory TDD, multi-reviewed spec-driven development, and SDLC best practices across hundreds of PRs. It provides:

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

## Self-Learning System

metaswarm doesn't just execute — it learns from every session and gets smarter over time.

### Automatic Reflection

After every PR merge, the self-reflect workflow (`/project:self-reflect`) analyzes what happened:

- **Code review feedback** — Extracts patterns, gotchas, and anti-patterns from reviewer comments (both human and automated) and writes them back to the knowledge base as structured JSONL entries
- **Build and test failures** — Captures what broke and why, so agents avoid the same mistakes in future tasks
- **Architectural decisions** — Records the rationale behind choices so future agents understand the "why", not just the "what"

### Conversation Introspection

The reflection system also introspects into the Claude Code session itself, looking for:

- **User repetition** — When a user corrects the same behavior multiple times or repeats instructions, this signals an opportunity for a new skill or command. The system flags these as candidates for automation.
- **User disagreements** — When a user rejects or overrides Claude's recommendation, the system captures the user's preferred approach as a knowledge base entry, so agents align with the user's intent in future sessions.
- **Friction points** — Repeated manual steps that could be codified into reusable workflows.

These signals feed back into the knowledge base and can generate proposals for new skills, updated rubrics, or revised agent behaviors.

### Selective Knowledge Priming

The knowledge base grows continuously, but agents don't load all of it. The `bd prime` command uses **selective retrieval** — filtering by affected files, keywords, and work type to load only the relevant subset:

```bash
# Only loads knowledge relevant to auth files and implementation work
bd prime --files "src/api/auth/**" --keywords "authentication" --work-type implementation
```

This means the knowledge base can grow to hundreds or thousands of entries without consuming context window. Agents get precisely the facts they need — the 5 critical gotchas for the files they're about to touch, not the entire institutional memory.

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

metaswarm stands on the shoulders of two key projects:

- **[BEADS](https://github.com/steveyegge/beads)** by [Steve Yegge](https://github.com/steveyegge) — The git-native, AI-first issue tracking system that serves as the coordination backbone for all agent task management, dependency tracking, and knowledge priming in metaswarm. BEADS made it possible to treat issue tracking as a first-class part of the codebase rather than an external service.

- **[Superpowers](https://github.com/obra/superpowers)** by [Jesse Vincent](https://github.com/obra) and contributors — The agentic skills framework and software development methodology that provides foundational skills metaswarm builds on, including brainstorming, test-driven development, systematic debugging, and plan writing. Superpowers demonstrated that disciplined agent workflows aren't overhead — they're what make autonomous development reliable.

metaswarm was created by [Dave Sifry](https://linkedin.com/in/dsifry), founder of Technorati, Linuxcare, and Warmstart, and former tech executive at Lyft and Reddit. Extracted from a production multi-tenant SaaS codebase where it has been writing production-level code with 100% test coverage, TDD, and spec-driven development across hundreds of autonomous PRs.
