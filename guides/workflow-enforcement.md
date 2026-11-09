# Workflow Enforcement

How metaswarm's quality gates fit around superpowers' brainstorming and writing-plans skills. This is the canonical copy; other files point here instead of restating it.

## Two pipelines

metaswarm has two entry points, and the Design Review Gate reviews a different artifact in each:

| Pipeline | Started by | Order | The Design Review Gate reviews |
|---|---|---|---|
| Brainstorming path | `/start-task`, `/brainstorm` (superpowers brainstorming and writing-plans) | brainstorming → Design Review Gate (project-sized design doc only) → writing-plans → Plan Review Gate → execution method menu | the committed design doc |
| Full orchestration | "Use the full metaswarm orchestration workflow" (issue-orchestrator, `orchestrated-execution`) | Research → Plan → Plan Review Gate → Design Review Gate → Work Unit Decomposition → orchestrated execution → Final Review → PR | the plan; there is no separate design doc |

The sections below describe the brainstorming path's triggers. In full orchestration, both gates always run, in the order shown.

**After a Design Review Gate revision.** In full orchestration, the gate reviews the plan. If the Design Review Gate revises the plan, run the Plan Review Gate again on the revised plan (fresh reviewers) before presenting it; a revision that fails it goes back through both gates. On the brainstorming path the gate revises the design doc, not a plan, so nothing re-runs: the Plan Review Gate still runs on the plan writing-plans writes from the approved design doc.

## Supported superpowers versions

superpowers 6.4.1 or later. Tested with 7.0.2.

Brainstorming sizes its output to the work. Only project-sized work reaches the Design Review Gate.

| superpowers version | Brainstorming outcome | Design Review Gate? |
|---|---|---|
| 6.4.x spike | Probe in chat | No |
| 6.4.x Bounded | Short design in chat | No |
| 6.4.x Architectural | Written spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, committed | Yes |
| 7.x quick task | No doc | No |
| 7.0.0 small change | Description in chat | No |
| 7.0.1+ small change | Short design doc `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, committed | No |
| 7.x project | Full written design (builder check) `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, committed | Yes |

"Project-sized" means brainstorming sized the work as a project (the Architectural path in 6.4.x, "a project" in 7.x) and committed its design doc. Committing a doc alone is not enough, because 7.0.1+ also commits short docs for small changes.

## Design Review Gate trigger

Run the Design Review Gate only for project-sized work: brainstorming sized the work as a project (superpowers 6.4.x Architectural path; 7.x "a project", the full written design) and committed its design doc. Quick tasks, chat-only designs and short design docs for small changes (superpowers 7.0.1+) skip the gate.

The gate watches two locations:

`docs/plans/*-design.md` and `docs/superpowers/specs/*-design.md`

A short design doc in a watched folder does not trigger the gate on its own; the size brainstorming stated decides. `/review-design <path>` can still review any doc on request.

`/review-design --latest` picks the newest dated design doc across both. Review any other design doc manually with `/review-design <path>`.

The gate runs before writing-plans, even if brainstorming says to invoke writing-plans next.

## Plan Review Gate intercept

Run the Plan Review Gate after the plan is written and before writing-plans presents the plan: do not link the plan, ask the user to review it, or offer an execution choice until all 3 reviewers PASS.

writing-plans ends with its own "Execution Handoff" (present in superpowers 6.4.1 and in 7.x). It links the plan, asks the user to review it and offers Subagent-driven or Native execution. metaswarm intercepts after the plan file is written and before that handoff. Once the gate passes, metaswarm presents the plan and its own execution menu.

## Execution method menu

metaswarm's 3-option menu, kept in the project's CLAUDE.md ("Execution Method Choice"), replaces writing-plans' 2-option handoff. Option 3 is the one that maps to writing-plans' Native choice:

**Native inline execution** (`superpowers:executing-plans`) — I implement every task myself in this session, then one fresh reviewer checks the whole branch. Cheapest and fastest; no independent review until the end.
