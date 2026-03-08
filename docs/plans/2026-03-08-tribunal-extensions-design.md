# Tribunal — Metaswarm Fork Design Document

**Date**: 2026-03-08
**Status**: Approved
**Fork point**: metaswarm commit `03ce5da`

Tribunal is a fork of [metaswarm](https://github.com/dsifry/metaswarm) by Daniel Sifry that adds three features: layered configuration, brainstorming debate, and intelligent agent selection. It also renames and rebrands the project.

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Name | Tribunal | Clean, memorable, no conflicts in AI tooling space |
| Layered config model | Common → CLI tool-specific overrides | Agents are CLI tools (Claude, Gemini, Codex), not roles |
| Config file format | Single `tribunal.yaml` with namespaced sections | Simple, one file to manage, YAGNI |
| Debate style | Round-robin orchestrated, fixed rounds | Predictable cost, orchestrator mediates all exchanges |
| Orchestrator | Whichever CLI the user starts from | Natural UX, no cross-CLI process spawning |
| Agent selection strategy | Weighted decay scoring + historical learning | Adapts to tool updates without manual resets |
| Escalation | Dynamic based on scores, not hardcoded order | Best-performing tool goes first |
| Health checks | Pre-flight + per-task dispatch | Tokens expire, rate limits reset mid-session |
| Auth model | Subscription-based CLI logins, verified at startup | No API keys needed |
| License | MIT, dual copyright (jpeggdev + Daniel Sifry) | MIT requires preserving original copyright |

---

## Feature 1: Layered Configuration

### Config file: `tribunal.yaml`

Lives at project root. The system reads `common` first, then deep-merges the active CLI tool's block on top. Any key in the tool block overrides the same key in `common`.

```yaml
# tribunal.yaml
common:
  timeout_seconds: 300
  sandbox: docker
  coverage:
    lines: 100
    branches: 100
    functions: 100
    statements: 100
  enforcement:
    command: "pnpm test:coverage"
    block_pr_creation: true
    block_task_completion: true
  debate:
    rounds: 2
    agents: [architect, security, cto]
    allow_extra_round: true
  agent_selection:
    strategy: weighted_decay
    decay_rate: 0.1
    min_samples: 3
    static_priority:
      default: [gemini, codex, claude]
      implementation: [gemini, codex, claude]
      review: [claude, gemini, codex]
      planning: [claude, codex, gemini]
      testing: [gemini, codex, claude]
  escalation:
    max_retries: 3
    max_total_attempts: 7
    alert_user_on_exhaustion: true
  health_check:
    per_task: true

claude:
  timeout_seconds: 600
  role: orchestrator

gemini:
  timeout_seconds: 180
  sandbox: none
  coverage:
    branches: 90

codex:
  sandbox: platform
```

### Resolution logic

```
effective_config = deep_merge(common, tool_specific[active_cli])
```

- **Scalar values**: tool-specific wins
- **Objects**: recursively merged (e.g., `gemini.coverage.branches: 90` only overrides `branches`, not `lines`/`functions`/`statements`)
- **Arrays**: tool-specific replaces entirely (no array merging — keeps it predictable)
- **Missing tool block**: just use `common` as-is

### Where it's read

- **Session start hook** — loads config, determines active CLI, resolves effective config
- **Orchestrated execution** — reads coverage thresholds, timeouts, sandbox mode
- **Debate skill** — reads round count, participating agents
- **Agent selection** — reads escalation settings, static priorities

### Migration from metaswarm

The existing `.coverage-thresholds.json` and `.metaswarm/external-tools.yaml` get consolidated into `tribunal.yaml`. A migration command (`tribunal migrate`) reads the old files and generates the new config.

---

## Feature 2: Brainstorming Debate

### Where it fits in the pipeline

```
User gives task
    ↓
Research phase (Researcher agent explores codebase)
    ↓
DEBATE PHASE (NEW)
    ↓
Design Review Gate (5 agents approve/reject)
    ↓
Planning → Execution → PR
```

The debate happens after research (so agents have context) and before the design review gate (so the gate reviews a design that's already been challenged).

### How it works

**Round 1 — Proposals**

The orchestrator sends each debate agent the research findings + task description and asks: "Propose a solution." Agents run in parallel. Each returns a structured proposal:

```markdown
## Proposal from [Agent]
### Approach
[Description of the solution]
### Trade-offs
- Pro: ...
- Con: ...
### Estimated complexity
[Low / Medium / High]
### Risk areas
[What could go wrong]
```

**Round 2 — Critiques**

The orchestrator shares ALL proposals with each agent and asks: "Critique these proposals, rank them, defend or revise your own." Agents run in parallel. Each returns:

```markdown
## Critique from [Agent]
### Ranking
1. [Agent X's proposal] — [why]
2. [Agent Y's proposal] — [why]
3. [Agent Z's proposal] — [why]
### Revised position
[Stick with mine / Switch to X's / Hybrid of X+Y]
### Blocking concerns
[Anything that would make a proposal fail]
```

**Synthesis**

The orchestrator consolidates:
1. Tallies rankings across all agents
2. Identifies consensus or split decisions
3. Notes any blocking concerns
4. Presents a summary to the user with a recommendation:

```markdown
## Debate Summary

### Consensus: [Agent X's approach] (3/3 agents ranked it #1)
— or —
### Split Decision: [Agent X] vs [Agent Y] (2-1 split)

### Recommendation
[Orchestrator's pick based on rankings + trade-offs]

### Blocking concerns raised
- [Any concerns that need resolution]

Proceed with this approach? [Yes / Pick a different one / Another round]
```

The user picks the winner. That approach feeds into the design review gate.

### Configuration

```yaml
common:
  debate:
    rounds: 2
    agents: [architect, security, cto]
    allow_extra_round: true
```

Default debate agents: `architect`, `security`, `cto`. The Product Manager and Designer join later at the design review gate. Configurable — add or remove agents in the list.

### New skill

`skills/debate/SKILL.md` — defines the two-round workflow, proposal/critique templates, synthesis logic. Auto-activates after research phase completes.

---

## Feature 3: Intelligent Agent Selection

### Performance logging

Every task completion or failure is logged to `tribunal-stats.jsonl` (project root, gitignored):

```jsonl
{"timestamp":"2026-03-08T14:32:00Z","tool":"codex","task_type":"implementation","success":false,"duration_seconds":120,"files_changed":0,"failure_reason":"timeout during async database migration - tool generated synchronous code that deadlocked","failure_category":"async_patterns","tags":["database","migration","async"],"tool_self_report":"completed successfully"}
```

**Who fills in failure context:**
- The orchestrator always fills in `failure_category` and `tags` based on what it observed during validation (test failures, type errors, scope violations, timeouts)
- If the failing tool self-reported a reason, it's captured in `tool_self_report` but kept separate since we don't trust self-reports as ground truth

### Weighted score with decay

```
score(tool, task_type) = Σ (outcome_i × decay_weight_i) / Σ decay_weight_i

where:
  outcome_i = 1.0 (success) or 0.0 (failure)
  decay_weight_i = e^(-λ × age_in_days)
  λ = configurable decay rate (default: 0.1, meaning ~37% weight at 10 days old)
```

### Failure pattern matching

Before picking a tool, the selector checks historical failures for tag overlap with the current task:

```
Current task tags: ["database", "migration", "async"]

codex failure history for "implementation":
  - 3 failures tagged ["database", "async"] in last 14 days
  → penalty applied: score × 0.5

gemini failure history for "implementation":
  - 0 failures tagged ["database", "async"]
  → no penalty
```

A tool can score well overall but get deprioritized for a specific kind of task based on failure patterns.

### Minimum samples threshold

If a tool has fewer than `min_samples` (default: 3) results for a task type, the system uses the static priority from config instead of the calculated score.

### Selection flow

```
Task arrives (e.g., type: "implementation", tags: ["database", "async"])
    ↓
Health check all configured tools
    ↓
Filter to healthy tools only
    ↓
For each healthy tool:
  - Has enough samples? → use weighted score with failure pattern penalty
  - Not enough samples? → use static priority from config
    ↓
Pick highest scoring tool
    ↓
On failure → log result with failure context, try next best
    ↓
All tools exhausted after max_total_attempts? → alert user
```

### Escalation

Dynamic based on scores — not a fixed chain. The system always tries the highest-scoring available tool next. If a tool just failed this task, it goes to the back of the line for this task.

### `tribunal benchmark` command

```bash
tribunal benchmark                    # research all task types
tribunal benchmark --task-type coding # focus on one type
```

Searches the web for recent benchmarks and community consensus on CLI tool performance. Outputs a ranked summary with sources. Optionally updates `static_priority` in `tribunal.yaml` so defaults start informed.

**Future enhancement**: allow benchmark results to influence live scores as a weighted prior, not just static defaults. This would let a tool that benchmarks well jump ahead without waiting for the current leaders to fail.

### `tribunal stats` command

```bash
tribunal stats                  # show scores per tool per task type
tribunal stats reset [tool]     # wipe history for a tool
tribunal stats export           # dump raw JSONL
```

### Configuration

```yaml
common:
  agent_selection:
    strategy: weighted_decay
    decay_rate: 0.1
    min_samples: 3
    static_priority:
      default: [gemini, codex, claude]
      implementation: [gemini, codex, claude]
      review: [claude, gemini, codex]
      planning: [claude, codex, gemini]
      testing: [gemini, codex, claude]
  escalation:
    max_retries: 3
    max_total_attempts: 7
    alert_user_on_exhaustion: true
```

### New files

- `skills/agent-selection/SKILL.md` — scoring logic, selection flow, escalation rules
- `commands/stats.md` — stats CLI command
- `commands/benchmark.md` — web benchmark command
- `tribunal-stats.jsonl` — performance log (gitignored)

---

## Feature 4: Renaming & Migration

### What changes

| From | To |
|------|----|
| Repo name `metaswarm` | `tribunal` |
| Config dir `.metaswarm/` | `.tribunal/` |
| `.coverage-thresholds.json` + `.metaswarm/external-tools.yaml` | `tribunal.yaml` |
| CLI `metaswarm init/setup/detect` | `tribunal init/setup/detect` |
| All internal "metaswarm" references | "tribunal" |
| Plugin manifests | Updated |
| CLAUDE.md, GEMINI.md, AGENTS.md | Rebranded |
| GitHub repo `jpeggdev/metaswarm` | `jpeggdev/tribunal` |

### New files

| File | Purpose |
|------|---------|
| `tribunal.yaml` | Unified layered config |
| `tribunal-stats.jsonl` | Agent performance log (gitignored) |
| `skills/debate/SKILL.md` | Brainstorming debate skill |
| `skills/agent-selection/SKILL.md` | Intelligent selection skill |
| `commands/stats.md` | Stats CLI command |
| `commands/benchmark.md` | Web benchmark command |
| `ATTRIBUTION.md` | Credit to metaswarm |

### New commands

| Command | Purpose |
|---------|---------|
| `tribunal migrate` | Upgrade from metaswarm config to tribunal.yaml |
| `tribunal stats` | View/reset/export agent performance data |
| `tribunal benchmark` | Research tool capabilities from web |

### What stays the same

- All 18 agent persona files (references updated)
- 9-phase workflow structure
- 4-phase execution loop (IMPLEMENT → VALIDATE → REVIEW → COMMIT)
- BEADS integration
- Rubrics
- Knowledge base format
- Human escalation patterns
- TDD enforcement

### Migration command: `tribunal migrate`

1. Reads `.coverage-thresholds.json` → writes `tribunal.yaml` common coverage section
2. Reads `.metaswarm/external-tools.yaml` → writes tool-specific sections in `tribunal.yaml`
3. Renames `.metaswarm/` → `.tribunal/`
4. Updates CLAUDE.md/GEMINI.md/AGENTS.md references
5. Reports what changed

### License & Attribution

**LICENSE** (dual copyright):
```
Copyright (c) 2026 jpeggdev
Copyright (c) 2025 Daniel Sifry (metaswarm)

MIT License...
```

**ATTRIBUTION.md**:
```markdown
# Attribution

Tribunal is a fork of [metaswarm](https://github.com/dsifry/metaswarm)
by Daniel Sifry, licensed under the MIT License.

Original project: https://github.com/dsifry/metaswarm
Fork point: commit 03ce5da (2026-03-08)
```

**README.md** includes: "Tribunal is built on [metaswarm](https://github.com/dsifry/metaswarm) by Daniel Sifry."
