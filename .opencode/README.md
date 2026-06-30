# OpenCode Integration

This directory contains the OpenCode integration assets for metaswarm.

## Installation

```bash
npx metaswarm init --opencode
```

Or include OpenCode when installing for all platforms:

```bash
npx metaswarm init --all
```

After installation, run project setup:

```bash
npx metaswarm setup --opencode
```

This generates `opencode.json` and copies the referenced command and agent files into `.opencode/commands/` and `.opencode/agents/`.

## What's Registered

| Type | Count | Items |
|------|-------|-------|
| Commands | 3 | start-task, prime, review-design |
| Agents | 2 | issue-orchestrator, architect-agent |

## POC Scope

This is a Proof-of-Concept integration. 3 of 13 commands and 2 of 19 agents are active.
Remaining items will be added incrementally in follow-up PRs.

### Deferred to Follow-up PRs

- BEADS integration via `.opencode/plugins`
- Session hooks (`experimental.session.compacting`, session events)
- Skills discovery (`skill` tool wiring)
- `.opencode/plugins/*.ts` plugin system
- Full command roster (remaining 10 commands)
- Full agent roster (remaining 17 agents)
