# metaswarm

Multi-agent orchestration framework for software development. 18 specialized agents, 13 skills, quality gates, TDD enforcement.

## Getting Started

Run `/metaswarm:start-task` to begin tracked work, or `/metaswarm:setup` to configure metaswarm for this project.

## Available Commands

| Command | Purpose |
|---|---|
| `/metaswarm:start-task` | Begin tracked work on a task |
| `/metaswarm:prime` | Load relevant knowledge before starting |
| `/metaswarm:review-design` | Trigger design review gate (5 reviewers) |
| `/metaswarm:pr-shepherd` | Monitor a PR through to merge |
| `/metaswarm:self-reflect` | Extract learnings after a PR merge |
| `/metaswarm:handle-pr-comments` | Handle PR review comments |
| `/metaswarm:brainstorm` | Refine an idea before implementation |
| `/metaswarm:create-issue` | Create a well-structured GitHub Issue |
| `/metaswarm:external-tools-health` | Check status of external AI tools |
| `/metaswarm:setup` | Interactive guided setup |
| `/metaswarm:status` | Run diagnostic checks |

## Workflow

For complex features, describe what you want with a Definition of Done and say:
`Use the full metaswarm orchestration workflow.`

This runs: Research -> Plan -> Design Review Gate -> Work Unit Decomposition -> Orchestrated Execution (4-phase loop per unit) -> Final Review -> PR.

## Quality Gates (MANDATORY)

- **After brainstorming** -> MUST run `/metaswarm:review-design` before planning
- **After any plan** -> MUST run Plan Review Gate before presenting to user
- **Before finishing branch** -> MUST run `/metaswarm:self-reflect` before PR
- **Coverage** -> `.coverage-thresholds.json` is the single source of truth. BLOCKING gate.
- **TDD is mandatory** -> Write tests first, watch them fail, then implement

## Rules

- NEVER use `--no-verify` on git commits
- NEVER use `git push --force` without explicit user approval
- ALWAYS follow TDD
- STAY within declared file scope

## Platform Notes

Gemini CLI has limited sub-agent support. When sub-agents are unavailable:
- Design review runs sequentially (each reviewer in-session one at a time)
- Adversarial review uses rubrics as structured checklists
- Quality of review is maintained through rubric structure

See `skills/start/references/platform-adaptation.md` for the full cross-platform guide.
