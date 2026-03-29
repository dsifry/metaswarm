## metaswarm

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration with Qwen Code CLI.

### Available Skills

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work |
| `$setup` | Interactive setup |
| `$brainstorming-extension` | Refine ideas |
| `$design-review-gate` | Design review |
| `$plan-review-gate` | Plan review |
| `$orchestrated-execution` | 4-phase execution |
| `$pr-shepherd` | PR monitoring |
| `$handling-pr-comments` | Handle review comments |
| `$create-issue` | Create GitHub Issue |
| `$status` | Diagnostic checks |

### Quality Gates

- TDD mandatory
- Coverage thresholds in `.coverage-thresholds.json`
- Never use `--no-verify` on commits
- Always push before session end
