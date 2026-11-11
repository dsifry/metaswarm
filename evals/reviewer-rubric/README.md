# Reviewer rubric eval (#105)

This eval asks whether a fresh reviewer subagent applies its rubric and role criteria when the orchestrator's prompt doesn't name them. Orchestrators often paraphrase the gate templates, or send "Read <brief> and follow it exactly" with a brief that names no rubric. Issue #105 found reviewers that ran without their criteria: only 1 of 73 design reviewers and 0 of 36 adversarial reviewers opened their rubric in one session.

## How it works

Each scenario in `scenarios/<name>/` has three files:

- `fixture.sh` builds a tiny git repo with planted defects. Each defect sits outside the prompt's stated focus but inside the role's criteria.
- `prompt.txt` is the paraphrased reviewer prompt. It names no rubric. The `*-redirect` variants instead point the reviewer at a shared brief and say "follow it exactly".
- `meta.json` gives the agent type, the rubric or persona name used to detect a read, and regex checks for each planted defect. Each check is a list of patterns, and every pattern must match the reviewer's reply. A `(?i)` or `(?is)` prefix sets the JS flags.

`run.sh` starts a fresh headless session for each trial:

```bash
claude -p --plugin-dir <tree> --setting-sources project
```

Metaswarm is loaded from `<tree>`, and the user's installed plugins are not loaded. The session spawns the reviewer agent with `prompt.txt` unchanged. `score.js` then reads the stream-json log and records:

- whether the agent was spawned;
- whether it read its rubric or persona;
- whether the `Criteria applied:` receipt is present;
- each defect check;
- the cost.

Defect checks ignore the receipt line (or `criteria_applied` field) and criteria-check rows that passed or were N/A (table rows and JSON `criteria_check` entries), so a row naming a checklist item counts only when it FAILs. A rubric read means reading the file's text: `Read`, a `cat`/`sed`/`head`-style Bash command, or `Grep` in content mode. A `Glob`, a file-listing `Grep`, `find` or `ls` only locates the file and doesn't count.

After the PR review, these scoring rules and tighter check patterns were applied to every saved trial. Two cells changed, both in the baseline: "read rubric or persona" went from 3/12 to 2/12, because one trial only globbed for the file. Redirect Architect "API contract" went from 1/3 to 0/3, because its old match was a 429 mentioned in a different finding. Every other result in the tables below stands.

## Running it

```bash
evals/reviewer-rubric/run.sh <label> [trials=3] [plugin-dir=repo root] [scenario...]
# e.g. compare a branch against main:
evals/reviewer-rubric/run.sh branch 3 .
evals/reviewer-rubric/run.sh main 3 ../metaswarm-main design-cto-redirect
```

Results land in `results/<label>/<scenario>/`: one `trial-N.jsonl` and `trial-N.score.json` per trial, a `summary.json`, and a `report.md` for each label. The `results/` directory is gitignored. Set `EVAL_OUT` to write the results elsewhere.

**It calls the model and costs money**, about $0.35–0.45 per trial with Opus reviewers. Run it by hand. It never runs in CI. `score.js` has unit tests (`tests/lib/eval-score.test.mjs`, 100% coverage). `run.sh` and the fixtures call the model, so they have no unit tests.

## Results (2026-11-10, 3 trials per cell)

The variants were built from the branch before the change:

- **fix 1:** role criteria embedded in the `design-reviewer` and `plan-reviewer` definitions.
- **fix 3:** a `Criteria applied:` receipt line in all three reviewer definitions.
- **table:** design reviewers also fill in a `### Criteria check` table with one row per checklist item.

Plain prompts:

| Scenario | Check | Baseline | Fix 1 | Fix 3 | Fix 1+3 |
|---|---|---|---|---|---|
| adversarial | `any` rated a blocker, as the rubric requires | 0/3 | n/a | 3/3 | (= fix 3) |
| adversarial | file scope / untested DoD item | 3/3, 3/3 | n/a | 3/3, 3/3 | (= fix 3) |
| design Architect | API contract (status codes, errors) | 0/3 | 2/3 | 0/3 | 3/3 |
| design CTO | no test plan (TDD readiness) | 0/3 | 3/3 | 2/3 | 3/3 |
| plan Completeness | missed caller / unknown currency | 3/3, 2/3 | 3/3, 3/3 | 3/3, 3/3 | 3/3, 3/3 |
| all | read rubric or persona | 2/12 | 0/9 | 12/12 | 5/9 |
| all | receipt present | 0/12 | 0/9 | 12/12 | 9/9 |

Redirect prompts ("read the brief and follow it exactly"):

| Scenario | Check | Baseline | Fix 1+3 | Fix 1+3 + table |
|---|---|---|---|---|
| design CTO | no test plan | 0/3 | 3/3 | 3/3 |
| design Architect | API contract | 0/3 | 1/3 | 3/3 |

"n/a" means fix 1 does not change `adversarial-reviewer.md`, whose definition already embeds its rubric. "(= fix 3)" marks cells that were not run: their tree is identical to fix 3's for that scenario.

What the results show:

- **Reading the persona file isn't enough.** In the baseline, the CTO reviewer read `cto-agent.md` 3 times out of 3. It never mentioned tests, though "TDD Readiness (CRITICAL)" is that role's first criterion. The prompt's focus areas pushed it out.
- **Criteria in the agent definition (fix 1)** reach every fresh subagent, whatever the orchestrator writes. That fixes the role-criteria gaps.
- **The receipt (fix 3)** makes the reviewer open its rubric, which fixes severity drift. The adversarial reviewer rated `any` minor until it read the rubric, even though its definition already contains the rubric text.
- **The criteria table** stops a single checklist item being skipped under a redirect brief.
- **Not tested:** fix 2 (mandatory templates on the orchestrator) and a hook. The prompts used here, paraphrases and redirects that name no rubric, are the cases fix 2 would guard against, and the shipped variant handles them.

## Branch validation (2026-11-10)

The branch as shipped, 3 trials per cell (6 where a cell was re-run):

| Scenario | Defect checks | Notes |
|---|---|---|
| adversarial | scope 3/3, untested 3/3, `any` blocker 3/3 | The first branch run scored 0/3 on the `any` check. The receipt said "read the rubric if it is not in this file", and the definition summarises the rubric, so reviewers skipped it. The receipt now comes first and says the rubric file's classification tables set severity (re-run 3/3). |
| design Architect, plain / redirect | duplicate service 3/3 / 3/3, API contract 3/3 / 3/3 | |
| design CTO, plain / redirect | no test plan 3/3 / 3/3, vague success 3/3 / 3/3 | |
| plan Completeness, plain | missed caller 3/3, unsupported currency 3/3 | Without a criteria table, the first branch runs scored 4/6. `plan-reviewer` now fills in a `### Criteria check` table too (re-run 3/3). |
| plan Completeness, redirect | missed caller 3/3, unsupported currency 0/3 | The brief says "keep the plan simple, no hypothetical hardening". Each reviewer still filled in the "Edge cases considered" row; one judged the closed set of three currencies enough. The criterion was applied but reached a different conclusion, so this does not count as a skipped criterion. |

The adversarial and plan re-runs used a scratch copy of the branch with the final text. The commits that followed apply the same text.

## Remaining roles (2026-11-11)

Scenarios for the roles not run above: the PM, Designer, Security and UX design reviewers, the Feasibility and Scope & Alignment plan reviewers, and a Collaborative-mode code review. Code review uses `adversarial-reviewer` with no mode named, so its default, Collaborative, applies with `code-review-rubric`. Each scenario plants two defects inside the role's criteria, and the prompt focuses elsewhere. Baseline is the tree before #105 (c51e08d). Shipped is main after #106 (5fadf25). 3 trials per cell, 42 trials in total, $16.38.

| Scenario | Planted defects | Baseline | Shipped |
|---|---|---|---|
| design PM | no use cases / theming and marketplace beyond the goal | 3/3, 3/3 | 3/3, 3/3 |
| design Designer | API unlike the existing `Result<T>` pattern / cryptic `ERR_42` codes | 3/3, 2/3 | 3/3, 3/3 |
| design Security | no ownership check (IDOR) / full headers logged | 3/3, 3/3 | 3/3, 3/3 |
| design UX | no empty, loading or error states / no wiring into the app shell | 2/3, 1/3 | 3/3, 3/3 |
| plan Feasibility | fabricated `mailer.ts` / undefined `npm run test:unit` | 3/3, 3/3 | 3/3, 3/3 |
| plan Scope & Alignment | yargs migration / YAML and CSV formats, both unrequested | 3/3, 3/3 | 3/3, 3/3 |
| code review (Collaborative) | `any` parameter rated HIGH / `toBeDefined()`-only test | 3/3, 3/3 | 3/3, 3/3 |
| all | read rubric or persona | 10/21 | 21/21 |
| all | receipt present | 0/21 | 21/21 |

What the results show:

- **The UX and Designer gaps close.** The baseline UX reviewer read its persona file in all 3 trials, but still missed the UI states in 1 and the app-shell wiring in 2. It stayed on the visual-hierarchy focus. Every shipped trial filled in those checklist rows and failed them. The Designer gap was smaller: 2 of 3 baseline trials flagged the cryptic error codes.
- **The other five roles show no gap.** The baseline already caught every planted defect for PM, Security, Feasibility, Scope & Alignment and code review. These defects may have been too obvious to separate the variants. The shipped trees caught all of them too, so nothing regressed.
- **Receipt and rubric reads:** the receipt went from 0/21 to 21/21, and rubric or persona reads from 10/21 to 21/21.

Every hit and miss was checked by reading the reply, not only the regex. The first scoring pass got several cells wrong, in both directions. Code review scored 1/3 and 2/3 for `any` rated HIGH, but all six trials did rate it HIGH. One UX trial matched `App.tsx` cited for a different finding, and one Designer trial matched "opaque token" from a pagination finding. The patterns were fixed before the tables above were scored. `tests/lib/eval-score.test.mjs` compiles every pattern. It also checks that no scenario's checks match an empty review, or a reply that mentions a check's topic without reporting the defect (for example, "Empty states and app shell wiring look fine", or a MEDIUM `any` finding followed by a HIGH finding about something else).

**Limits.** Each cell has only 3 trials. Delivering the criteria is deterministic, because they are text in the agent definition. Applying them is not: the receipt is self-reported, and with fixes 1+3 the reviewer opened its rubric in only 5 of 9 runs. If misses show up in real use, a hook that injects the template into Agent calls is the fallback.
