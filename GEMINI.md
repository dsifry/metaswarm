# tribunal

Multi-agent orchestration framework for software development. 18 specialized agents, 13 skills, quality gates, TDD enforcement.

## Getting Started

Run `/tribunal:start-task` to begin tracked work, or `/tribunal:setup` to configure tribunal for this project. In Gemini CLI, all commands use the `/tribunal:<command>` prefix.

## Available Commands

| Command | Purpose |
|---|---|
| `/tribunal:start-task` | Begin tracked work on a task |
| `/tribunal:prime` | Load relevant knowledge before starting |
| `/tribunal:review-design` | Trigger design review gate (5 reviewers) |
| `/tribunal:pr-shepherd` | Monitor a PR through to merge |
| `/tribunal:self-reflect` | Extract learnings after a PR merge |
| `/tribunal:handle-pr-comments` | Handle PR review comments |
| `/tribunal:brainstorm` | Refine an idea before implementation |
| `/tribunal:create-issue` | Create a well-structured GitHub Issue |
| `/tribunal:external-tools-health` | Check status of external AI tools |
| `/tribunal:setup` | Interactive guided setup |
| `/tribunal:status` | Run diagnostic checks |

## Workflow

For complex features, describe what you want with a Definition of Done and say:
`Use the full tribunal orchestration workflow.`

This runs: Research -> Brainstorm -> Design Review Gate -> Plan -> Plan Review Gate -> Execute -> Final Review -> PR.

## Quality Gates (MANDATORY)

- **After brainstorming** -> MUST run `/tribunal:review-design` before planning
- **After any plan** -> MUST run Plan Review Gate before presenting to user
- **Before finishing branch** -> MUST run `/tribunal:self-reflect` before PR
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
