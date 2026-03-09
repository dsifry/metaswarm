---
name: benchmark
description: Fetch and compare CLI tool benchmark data
---

# $benchmark

Search for recent CLI tool benchmarks and synthesize results into a ranked summary.

## Usage

```text
$benchmark                          Benchmark all task types
$benchmark --task-type implementation  Benchmark a specific task type
$benchmark --update-config          Update static_priority in tribunal.yaml based on results
```

## Behavior

1. Performs a web search for recent CLI tool benchmark results (Gemini CLI, OpenAI Codex, Claude Code, etc.)
2. Collects scores from recognized benchmark sources (SWE-bench, HumanEval, coding competitions, etc.)
3. Synthesizes findings into a ranked summary table
4. Optionally updates `static_priority` in `tribunal.yaml` to reflect benchmark rankings (updates each task type: default, implementation, review, planning, testing)

## Example Output

```text
CLI Tool Benchmark Summary
==========================

Source: SWE-bench Verified (2026-03)
  1. claude    — 72.0%
  2. codex     — 69.1%
  3. gemini    — 65.4%

Source: HumanEval (2026-02)
  1. gemini    — 92.3%
  2. claude    — 91.1%
  3. codex     — 88.7%

Composite Ranking (averaged):
  1. claude    — 81.6
  2. gemini    — 78.9
  3. codex     — 78.9

Current static_priority:
  default: gemini, codex, claude
  implementation: gemini, codex, claude
  review: claude, gemini, codex
  planning: claude, codex, gemini
  testing: gemini, codex, claude

Suggested static_priority (all task types):
  claude, gemini, codex

Run $benchmark --update-config to apply the suggested order.
```

## Options

| Flag | Description |
|------|-------------|
| `--task-type <type>` | Filter benchmarks to a specific task type (implementation, review, planning, testing) |
| `--update-config` | Write suggested `static_priority` to `tribunal.yaml` |
| `--sources` | List recognized benchmark sources |

## Future Enhancements

- Benchmark results feeding directly into live scoring as prior weights
- Automated periodic benchmark checks via scheduled tasks
- Per-task-type benchmark weighting (e.g., SWE-bench weighted higher for implementation tasks)
