---
name: memory
description: Persistent memory system that survives auto-compaction and session restarts. Automatically loaded by hooks — agents update memory files during work.
auto_activate: true
---

# metaswarm Memory System

Persistent project memory that survives auto-compaction and session restarts. Memory is stored as simple markdown and JSON files in `.metaswarm/memory/` and `.metaswarm/session-state.json`.

**How it works:**
1. On session start → hooks load memory files into context automatically
2. Before compaction → hooks inject memory into the compaction summary
3. During work → agents update memory files at checkpoints
4. On session end → agent saves final state

No database. No dependencies. Just files that hooks read and agents write.

---

## Memory Files

All files live in `.metaswarm/memory/`:

| File | Purpose | Update frequency |
|------|---------|-----------------|
| **active-state.md** | What we're working on right now: task, phase, progress, blockers, key files | Every phase transition |
| **decisions.md** | Architecture/design decisions with reasoning | When a significant choice is made |
| **gotchas.md** | Project-specific pitfalls discovered through experience | When a bug or gotcha is found |
| **feedback.md** | User corrections and preferences | When the user corrects behavior |

Agents may create additional `.md` files in the directory for domain-specific memory. All `.md` files in the directory are loaded automatically.

## Session State (Machine-Readable)

`.metaswarm/session-state.json` tracks execution progress:

```json
{
  "task": "Implement user authentication",
  "phase": "IMPLEMENT",
  "completedSteps": ["Research auth libraries", "Design token flow", "Write unit tests"],
  "nextSteps": ["Implement JWT middleware", "Add refresh token rotation"],
  "fileScope": ["src/auth/*.ts", "src/middleware/jwt.ts"],
  "blockedBy": null,
  "lastUpdated": "2026-04-17T14:22:00Z"
}
```

---

## When to Update Memory

### MANDATORY checkpoints (do these or context is lost):

1. **Starting a new task** — Update `active-state.md` with task description, planned approach, key files
2. **Completing a phase** — Update `active-state.md` with what was done + what's next. Update `session-state.json`.
3. **Before stopping work** — Final update to `active-state.md` with full status so the next session can pick up
4. **User gives correction** — Save to `feedback.md` immediately (these are the easiest to lose and hardest to rediscover)

### RECOMMENDED checkpoints:

5. **Making a significant decision** — Save to `decisions.md` with reasoning (not just the choice)
6. **Discovering a gotcha** — Save to `gotchas.md` so future sessions don't hit the same trap
7. **Every 15-20 minutes of active work** — Quick update to `session-state.json` (phase + completed steps)

---

## How to Update

### active-state.md
Write the full current state. Replace the previous content — this is a snapshot, not a log.

```markdown
# Active State

> Last updated: 2026-04-17 14:30

## Current Task
Implement JWT authentication middleware for the API

## Phase
IMPLEMENT (WU-002 of 3)

## Completed Steps
- Researched jose vs jsonwebtoken — chose jose (lighter, ESM native)
- Designed token flow: access (15m) + refresh (7d) with rotation
- Created auth.test.ts with 12 test cases (all passing)

## Next Steps
- Implement JWT middleware in src/middleware/jwt.ts
- Add refresh token rotation endpoint
- Wire into existing route guards

## Blockers
None

## Key Files
- src/middleware/jwt.ts (creating)
- src/auth/token-service.ts (creating)
- src/auth/auth.test.ts (done)
- src/routes/auth.ts (needs update)
```

### session-state.json
Use node or any method to write valid JSON:

```bash
node -e "
const fs = require('fs');
fs.writeFileSync('.metaswarm/session-state.json', JSON.stringify({
  task: 'Implement JWT auth middleware',
  phase: 'IMPLEMENT',
  completedSteps: ['Research', 'Design', 'Tests'],
  nextSteps: ['JWT middleware', 'Refresh rotation'],
  fileScope: ['src/middleware/jwt.ts', 'src/auth/*.ts'],
  blockedBy: null,
  lastUpdated: new Date().toISOString()
}, null, 2));
"
```

### decisions.md
Append new decisions — don't replace old ones:

```markdown
## 2026-04-17: JWT library choice
**Context:** Need JWT auth for API, evaluating jose vs jsonwebtoken
**Choice:** jose
**Reasoning:** ESM-native, smaller bundle, actively maintained, supports EdDSA
**Impact:** All token operations use jose API. No CommonJS require() for auth.
```

### feedback.md
Append — each entry is a rule to follow:

```markdown
## Testing: Don't mock the database
**User said:** "Use real DB in tests, mocks burned us before"
**Rule:** Integration tests always hit a real database instance
**Why:** Mock/prod divergence caused a broken migration to pass tests
```

### gotchas.md
Append:

```markdown
## API: Rate limit uses sliding window, not fixed
**Trigger:** Sending >100 requests in quick succession
**Consequence:** 429 errors even if total count is under the per-minute limit
**Fix:** Space requests with exponential backoff. The window is 60s sliding, not calendar-minute.
```

---

## What NOT to Put in Memory

- **Code snippets** — the code is in files, reference the path instead
- **Full file contents** — too large, will bloat context. Use file paths.
- **Temporary debug state** — don't persist "I tried X and it didn't work" unless it's a gotcha
- **Things already in CLAUDE.md** — don't duplicate project instructions
- **Git history** — `git log` is authoritative, don't copy commit messages

## How Memory is Loaded

The `pre-compact.sh` hook reads all memory files and session-state.json. It runs on:
- **SessionStart** — memory is injected into the fresh session context
- **PreCompact** — memory is injected into the compaction summary (survives compression)

Files smaller than 200 bytes are skipped (assumed to be empty templates). This means memory only loads when there's real content — zero overhead for fresh projects.
