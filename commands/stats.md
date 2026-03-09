---
name: stats
description: Display agent performance scores and history
---

# /stats

Display performance scores, selection basis, and trends for all configured CLI tools.

## Usage

```text
/stats                  Show current scores for all tools
/stats reset [tool]     Wipe history (all tools or a specific one)
/stats export           Dump raw tribunal-stats.jsonl to stdout
```

## Behavior

1. Reads `tribunal-stats.jsonl` from the project root
2. Runs `lib/agent-scorer.js` with current config from `tribunal.yaml`
3. Displays a summary table of all available tools

## Example Output

```text
Agent Performance Scores
========================

Tool      Score   Basis          Samples   Recent Trend
-------   -----   ----------     -------   ------------
gemini    0.92    weighted_decay    12      +++ (3/3 recent)
codex     0.71    weighted_decay     8      ++- (2/3 recent)
claude    0.67    static             1      n/a

Task type: implementation
Last updated: 2026-03-08T12:00:00Z
```

### Column Descriptions

- **Score** — Composite score from 0.0 to 1.0
- **Basis** — `weighted_decay` (data-driven) or `static` (insufficient samples, using priority order)
- **Samples** — Total observations for this tool + task type
- **Recent Trend** — Last 3 outcomes: `+` success, `-` failure

## Reset

`/stats reset` clears all history. `/stats reset codex` removes only codex entries. This is useful after major config changes or when a tool has been upgraded.

## Export

`/stats export` outputs the raw JSONL file for external analysis or backup.
