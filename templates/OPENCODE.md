# Project Instructions

This project uses [metaswarm](https://github.com/dsifry/metaswarm), a multi-agent orchestration framework for OpenCode. It provides specialized agents, commands, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

## How to Work in This Project

### Starting work

Start by priming context with relevant knowledge, then begin tracked work:

```text
/prime
/start-task <task-description>
```

This primes the agent with relevant knowledge, guides you through scoping, and picks the right level of process for the task.

### Design review (limited in this POC)

After writing a design document, you can request a review:

```text
/review-design
```

> **POC limitation:** the full parallel review gate uses 5 specialist reviewers
> (PM, Architect, Designer, Security, CTO). In this POC only `@architect-agent`
> is registered, so `/review-design` runs a single architecture-focused review,
> not the full 5-agent gate. The remaining reviewers will be added in follow-up PRs.

### Available Commands

| Command | Purpose |
|---|---|
| `/prime` | Load relevant knowledge from the BEADS knowledge base |
| `/start-task` | Begin tracked work on a task with complexity assessment |
| `/review-design` | Architecture-focused design review (single `@architect-agent` in this POC, not the full 5-agent gate) |

### Available Agents

| Agent | Purpose |
|---|---|
| `@issue-orchestrator` | Main coordinator per issue — spawns sub-agents, runs 4-phase execution loop |
| `@architect-agent` | Reviews technical architecture and creates implementation plans |

## POC Scope

This is an initial POC integration. 3 of 13 commands and 2 of 19 agents are registered. Remaining commands and agents will be added incrementally in follow-up PRs.

## Current Limitations

- BEADS integration via `.opencode/plugins` is not yet implemented
- Session hooks (compacting, session events) are not configured
- Skills discovery is not wired
- The full agent roster (17 remaining) is not registered
