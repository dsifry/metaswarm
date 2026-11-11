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
| design Architect | API contract | 1/3 | 1/3 | 3/3 |

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

**Limits.** Each cell has only 3 trials. Delivering the criteria is deterministic, because they are text in the agent definition. Applying them is not: the receipt is self-reported, and with fixes 1+3 the reviewer opened its rubric in only 5 of 9 runs. Collaborative-mode code review has no scenario. If misses show up in real use, a hook that injects the template into Agent calls is the fallback.
