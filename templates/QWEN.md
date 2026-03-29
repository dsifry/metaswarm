# QWEN.md Template for metaswarm

This file provides project context for Qwen Code CLI when using metaswarm.

## Project Overview

<!-- Describe your project's purpose, main technologies, and architecture -->

## Building and Running

<!-- Document key commands for building, running, and testing -->

```bash
# Example:
npm install      # Install dependencies
npm run build    # Build the project
npm test         # Run tests
```

## Development Conventions

<!-- Describe coding styles, testing practices, and contribution guidelines -->

## metaswarm Integration

This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration.

### Available Skills

| Invoke | Purpose |
|---|---|
| `$start` | Begin tracked work on a task |
| `$setup` | Interactive guided setup |
| `$brainstorming-extension` | Refine an idea before implementation |
| `$design-review-gate` | Design review |
| `$plan-review-gate` | Adversarial plan review |
| `$orchestrated-execution` | 4-phase execution loop |
| `$pr-shepherd` | Monitor PR through to merge |
| `$handling-pr-comments` | Handle PR review comments |
| `$create-issue` | Create GitHub Issue |
| `$status` | Run diagnostic checks |

### Quality Gates

- **TDD mandatory** — Write tests first, then implement
- **Coverage thresholds** — Defined in `.coverage-thresholds.json`
- **NEVER** use `--no-verify` on git commits
- **ALWAYS** push changes before ending session

### Session Completion

When ending a work session:

```bash
git pull --rebase
git push
git status  # Must show "up to date with origin"
```
