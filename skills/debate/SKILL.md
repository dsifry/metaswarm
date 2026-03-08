---
name: debate
description: Multi-agent brainstorming debate — agents propose solutions, critique each other, and reach consensus before design review
auto_activate: true
triggers:
  - after:research
  - "debate"
  - "brainstorm debate"
---

# Multi-Agent Brainstorming Debate

## Purpose

Runs a structured multi-agent debate after the research phase completes and before the design review gate. Multiple agents (architect, security, CTO, etc.) independently propose solutions, critique each other's proposals, and converge toward consensus. The user makes the final call on which approach to pursue.

This prevents single-perspective designs from reaching the review gate, catches architectural blind spots early, and gives the user visibility into trade-offs before committing to an approach.

---

## Pipeline Position

```
Research → DEBATE → Design Review Gate → Planning → Execution → PR
```

```text
┌─────────────────────────────────────┐
│       Research Phase                 │
│  Researcher Agent explores codebase  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────┐
│              DEBATE PHASE                        │
│                                                  │
│  Round 1: Each agent proposes a solution         │
│  Round 2: Each agent critiques all proposals     │
│  Synthesis: Orchestrator tallies & recommends    │
│  User picks approach                             │
│                                                  │
│  (Optional extra round if configured)            │
└─────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────┐
│           DESIGN REVIEW GATE                     │
│  Selected approach reviewed by 5+ agents         │
│  ALL must approve to proceed                     │
└─────────────────────────────────────────────────┘
        │
        ▼
   Planning → Execution → PR
```

---

## Configuration

Reads from `tribunal.yaml` in the project root:

```yaml
common:
  debate:
    rounds: 2
    agents: [architect, security, cto]
    allow_extra_round: true
```

| Field              | Type     | Default                      | Description                                        |
| ------------------ | -------- | ---------------------------- | -------------------------------------------------- |
| `rounds`           | integer  | `2`                          | Number of debate rounds (1 = proposals only, 2 = proposals + critiques) |
| `agents`           | string[] | `[architect, security, cto]` | Agent roles participating in the debate             |
| `allow_extra_round`| boolean  | `true`                       | Whether the user can request one additional round   |

If `tribunal.yaml` does not exist or has no `debate` section, the debate phase is skipped entirely.

---

## Procedure

### Pre-Debate: Load Context

Before spawning debate agents, the orchestrator gathers:

1. **Research findings** — Full output from the researcher agent
2. **Task description** — The original issue/task being solved
3. **Knowledge** — Relevant codebase facts, patterns, and anti-patterns from `bd prime`

All debate agents receive identical context. No agent gets privileged information.

---

### Round 1: Proposals

Spawn each debate agent **in parallel** with identical context. Each agent independently proposes a solution.

**Prompt template for each agent:**

```markdown
You are the [AGENT ROLE] participating in a design debate.

## Task
[Task description]

## Research Findings
[Research output]

## Your Job
Propose a solution to this task. Be specific and concrete.

## Output Format (follow exactly)

## Proposal from [Your Role]
### Approach
[Description of the solution — what to build and how]
### Trade-offs
- Pro: [advantage 1]
- Pro: [advantage 2]
- Con: [disadvantage 1]
- Con: [disadvantage 2]
### Estimated complexity
[Low / Medium / High]
### Risk areas
[What could go wrong]
```

Wait for all agents to complete Round 1 before proceeding to Round 2.

---

### Round 2: Critiques

Share **ALL** Round 1 proposals with each agent. Each agent critiques all proposals, ranks them, and may revise their own position.

**Prompt template for each agent:**

```markdown
You are the [AGENT ROLE] reviewing proposals in a design debate.

## Task
[Task description]

## All Proposals
[All Round 1 proposals, labeled by agent]

## Your Job
Critique all proposals. Rank them. Defend or revise your own position.

## Output Format (follow exactly)

## Critique from [Your Role]
### Ranking
1. [Best proposal's agent] — [why this is best]
2. [Second best's agent] — [why]
3. [Third's agent] — [why]
### Revised position
[Stick with mine / Switch to X's / Hybrid of X+Y — explain why]
### Blocking concerns
[Any issues that would make a proposal fail in practice, or "None"]
```

Wait for all agents to complete Round 2 before synthesis.

---

### Synthesis

The orchestrator (not a subagent) consolidates all Round 2 critiques:

1. **Tally rankings** — Count how many agents ranked each proposal #1
2. **Check for consensus** — Do a majority of agents agree on the top approach?
3. **Identify blocking concerns** — Collect all blocking concerns raised by any agent
4. **Present summary to user**

**Summary format:**

```markdown
## Debate Summary (Round [N] of [total])

### [Consensus / Split Decision]

**Top ranked: [Agent]'s approach** ([X]/[total] agents ranked it #1)
[Brief description of the approach]

**Runner-up: [Agent]'s approach** ([Y]/[total] agents ranked it #1)
[Brief description]

### Key Trade-offs
- [Top approach] is [pro] but [con]
- [Runner-up] is [pro] but [con]

### Blocking Concerns
- [Concern 1, raised by Agent X]
- [Concern 2, raised by Agent Y]
— or —
- None raised

### Recommendation
[Orchestrator's pick and reasoning]

**Options:**
1. Proceed with recommendation
2. Pick a different approach
3. Request another debate round
```

---

### User Decision

| Option | Action |
| ------ | ------ |
| **1. Proceed with recommendation** | Use the recommended approach as the basis for the design document |
| **2. Pick a different approach** | User specifies which approach (or hybrid). Orchestrator formats that as the design document |
| **3. Request another debate round** | Only available if `allow_extra_round: true` AND an extra round has not already been used. Runs another critique round with updated positions, then re-synthesizes |

If the user picks Option 3 but `allow_extra_round` is `false` or has already been used, inform the user:

```markdown
Extra debate rounds are not available (allow_extra_round is disabled or already used).
Please pick Option 1 or 2.
```

---

### Post-Debate

1. **Format winning approach as design document** — The selected approach is expanded into a full design document suitable for the design review gate
2. **Save full transcript** — The complete debate transcript (all proposals, critiques, synthesis, and user decision) is saved alongside the design document for reference

---

## Agent Failure Handling

| Scenario | Action |
| -------- | ------ |
| Agent fails during Round 1 | Proceed without that agent's proposal (minimum 2 agents needed) |
| Agent fails during Round 2 | Exclude from ranking tally, note the gap in synthesis |
| Fewer than 2 agents succeed in Round 1 | Skip the debate entirely, alert user, fall through to design review gate with whatever proposal is available |

When an agent fails, log the failure but do not retry within the debate — retries would delay all other agents who are waiting for the round to complete.

---

## Anti-Patterns

| Anti-Pattern | Why It's Bad | What to Do Instead |
| ------------ | ------------ | ------------------- |
| **Anchoring bias** — sharing proposals sequentially instead of in parallel | Later agents anchor on earlier proposals instead of thinking independently | Always spawn Round 1 agents in parallel with identical context |
| **Orchestrator picks without user** — auto-selecting the top-ranked approach | Removes human agency from a high-stakes design decision | Always present options and wait for explicit user choice |
| **Unlimited rounds** — letting debate continue indefinitely | Debate becomes bikeshedding; delays actual implementation | Hard cap at `rounds` + 1 (if `allow_extra_round`). After that, user must decide |
| **Skipping for "simple" tasks** — bypassing debate because the task seems easy | "Simple" tasks often have hidden complexity that only surfaces in debate | If debate is configured in `tribunal.yaml`, run it. Users can skip explicitly if they choose |

---

## Related Skills

- `research` — Upstream: provides the research findings that feed into debate context
- `design-review-gate` — Downstream: reviews the design document produced from the winning approach
- `brainstorming-extension` — Bridges brainstorming into the quality pipeline; invokes debate when configured
- `config` — Manages `tribunal.yaml` where debate settings are stored
