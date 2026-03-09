---
name: agent-selection
auto_activate: false
triggers:
  - "choose agent"
  - "select tool"
  - "which agent"
  - "agent ranking"
  - "tool scoring"
  - "best agent for"
---

# Agent Selection Skill

Intelligent routing of tasks to the best CLI tool based on historical performance data, weighted decay scoring, and failure pattern matching.

## Purpose

When multiple CLI tools (Gemini CLI, OpenAI Codex, Claude Code, etc.) are available, this skill determines which tool is most likely to succeed for a given task type and tag set. It replaces static ordering with data-driven selection that adapts over time.

## Configuration

Scoring parameters are read from `tribunal.yaml` under the `scoring` key:

```yaml
scoring:
  min_samples: 3          # Minimum observations before using data-driven scoring
  decay_rate: 0.1         # Exponential decay rate (lambda) per day
  failure_penalty_window: 14  # Days to look back for failure patterns
  failure_penalty_step: 0.15  # Score reduction per matching failure
  failure_penalty_floor: 0.3  # Minimum penalty multiplier
  static_priority:
    - gemini
    - codex
    - claude
```

## Scoring Algorithm

### Weighted Decay Formula

For tools with at least `min_samples` observations:

```text
raw_score = sum(outcome_i * e^(-lambda * age_i)) / sum(e^(-lambda * age_i))
confidence = weight_total / (weight_total + 1)
score = confidence * raw_score + (1 - confidence) * 0.5
```

Where:
- `outcome_i` is 1 for success, 0 for failure
- `age_i` is days since the observation timestamp
- `lambda` is `decay_rate` from config
- Confidence blending regresses old/sparse data toward a 0.5 neutral baseline

### Failure Pattern Penalty

After computing the base score, apply a penalty for recent failures matching the current task tags:

1. Find failures in the last `failure_penalty_window` days
2. Keep only those with >50% tag overlap with the current task
3. Penalty multiplier = `max(failure_penalty_floor, 1.0 - count * failure_penalty_step)`
4. Final score = base_score * penalty_multiplier

### Static Fallback

When a tool has fewer than `min_samples` observations, its score is derived from its position in `static_priority`:

```text
score = (total_tools - position_index) / total_tools
```

Position 0 (first in list) gets the highest score.

## Selection Flow

```text
Task arrives with type + tags
        |
        v
Load tribunal-stats.jsonl
        |
        v
For each available tool:
  |
  +-- samples < min_samples? --> Use static priority score
  |
  +-- samples >= min_samples? --> Compute weighted decay score
        |                              |
        |                              v
        |                     Apply failure pattern penalty
        |                              |
        v                              v
    Collect all scores
        |
        v
  Sort descending by score
        |
        v
  Return ranked list
```

## Logging Format

Each task execution appends a JSONL entry to `tribunal-stats.jsonl`:

```json
{
  "timestamp": "2026-03-08T12:00:00Z",
  "tool": "codex",
  "task_type": "implementation",
  "success": true,
  "tags": ["database", "migration"],
  "failure_reason": null,
  "failure_category": null,
  "tool_self_report": "completed in 45s, all tests pass"
}
```

Fields:
- **timestamp** — ISO 8601 UTC timestamp
- **tool** — CLI tool name (gemini, codex, claude)
- **task_type** — Category (implementation, review, test, refactor, debug)
- **success** — Boolean outcome
- **tags** — Array of relevant topic tags
- **failure_reason** — Free-text description if failed
- **failure_category** — Structured category (timeout, syntax_error, test_failure, etc.)
- **tool_self_report** — Optional self-reported status from the tool

## Usage

### CLI Command

```bash
node lib/agent-scorer.js \
  --stats tribunal-stats.jsonl \
  --task-type implementation \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 \
  --task-tags "database,async"
```

### Sample Output

```json
{
  "ranking": [
    { "tool": "gemini", "score": 0.92, "basis": "weighted_decay", "samples": 12 },
    { "tool": "codex", "score": 0.71, "basis": "weighted_decay", "samples": 8 },
    { "tool": "claude", "score": 0.67, "basis": "static", "samples": 1 }
  ],
  "task_type": "implementation",
  "timestamp": "2026-03-08T12:00:00.000Z"
}
```

### Programmatic Usage

```javascript
const { scoreTools, loadStats } = require('./lib/agent-scorer');

const stats = loadStats('tribunal-stats.jsonl');
const ranking = scoreTools(
  stats,
  'implementation',
  ['gemini', 'codex', 'claude'],
  ['gemini', 'codex', 'claude'],
  3,    // minSamples
  0.1,  // decayRate
  ['database', 'async']  // taskTags
);
```

## Related Skills

- **external-tools** — Dispatches tasks to the selected CLI tool
- **config** — Reads scoring parameters from tribunal.yaml
- **status** — Displays current agent health and availability
