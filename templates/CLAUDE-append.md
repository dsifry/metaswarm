
## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration with Claude Code. It provides 18 specialized agents, a 9-phase development workflow, and quality gates that enforce TDD, coverage thresholds, and spec-driven development.

### Workflow

- **Non-trivial tasks** (features, multi-file changes): Create a GitHub Issue with a spec, then tell Claude: `Work on issue #N. Use the full metaswarm orchestration workflow.`
- **Simple tasks** (single-file fixes, quick changes): `/project:start-task`

### Available Commands

| Command | Purpose |
|---|---|
| `/project:start-task` | Begin tracked work on a task |
| `/project:prime` | Load relevant knowledge before starting |
| `/project:review-design` | Trigger parallel design review gate (5 agents) |
| `/project:pr-shepherd <pr>` | Monitor a PR through to merge |
| `/project:self-reflect` | Extract learnings after a PR merge |
| `/project:handle-pr-comments` | Handle PR review comments |
| `/project:brainstorm` | Refine an idea before implementation |
| `/project:create-issue` | Create a well-structured GitHub Issue |

### Testing & Quality

- **TDD is mandatory** — Write tests first, watch them fail, then implement
- **100% test coverage required** — Enforced via `.coverage-thresholds.json` as a blocking gate before PR creation and task completion
- **Coverage source of truth** — `.coverage-thresholds.json` defines thresholds. Update it if your spec requires different values. The orchestrator reads it during validation — this is a BLOCKING gate.
