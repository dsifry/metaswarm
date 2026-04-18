---
name: shared-memory
description: Cross-project SQLite+FTS5 memory shared between multiple Claude Code installations. Complements the file-based `memory` skill with searchable long-term store and cross-team handoffs.
auto_activate: false
---

# metaswarm Shared Memory

Cross-project, cross-team memory backed by SQLite+FTS5. Complements the
file-based `memory` skill — use it when you need:

- Memory that survives across projects, machines, or team rotations
- Full-text search across past learnings
- Cross-team handoffs (team-1 → team-2 etc.)
- Lease-based task coordination (prevents two teams grabbing the same issue)

Everything is single-file SQLite at `~/.claude/shared-memory/learnings.db` with
WAL mode. No server, no daemon.

## Installation

```bash
# 1. Install the store library
cp lib/store.js ~/.claude/shared-memory/lib/store.js

# 2. Install CLIs
cp bin/memory ~/bin/memory
cp bin/handoff ~/bin/handoff
cp bin/agent-team ~/bin/agent-team
chmod +x ~/bin/memory ~/bin/handoff ~/bin/agent-team

# 3. Install SessionStart hook (optional, surfaces memory at session start)
cp hooks/session-start-memory.js ~/.claude/hooks/session-start-memory.js
# then register in ~/.claude/settings.json under "SessionStart"
```

Requires `better-sqlite3` somewhere on the node path (the lib probes common
install locations automatically).

## CLI Reference

### memory — put/find/recent

```bash
memory put --scope global|project:<name> --type semantic|episodic|procedural \
           --title "..." --body "..." [--tags t1,t2] [--key stable-key]
memory find "<query>" [--scope X] [--type X] [--limit N]
memory recent [--limit 10]
memory show <id-or-key>
```

### handoff — structured cross-team handoffs

```bash
handoff send --to team-1 --title "..." --phase qa --summary "..." \
             --locked "path1,path2" --next "step1|step2"
handoff inbox [--team team-1]
handoff show <id>
handoff ack <id>
```

### agent-team — lease-based task coordination

```bash
agent-team claim AGE-123 [--for 60] [--as team-2] [--note "..."]
agent-team release AGE-123
agent-team list [--team team-1]
agent-team expire
agent-team status
```

## Schema

- `scope`: `global` or `project:<name>`
- `type`:
  - `semantic` — stable facts (who owns what, current architecture)
  - `episodic` — events with timestamps (handoffs, leases, incidents)
  - `procedural` — rules ("never use PowerShell for Danish text")
- `tags`: comma-separated, free-form
- FTS5 index covers `title`, `body`, `tags`

## When to Use vs. File-Based `memory`

| Use-case | Skill |
|----------|-------|
| Project-local state, active task | `memory` (markdown files) |
| Cross-project learnings, facts | `shared-memory` |
| Handoffs between teams | `shared-memory` (handoff CLI) |
| Task claim/lease coordination | `shared-memory` (agent-team CLI) |
| Full-text search across history | `shared-memory` |

Both can run side-by-side — they do not conflict.
