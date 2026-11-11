# Reviewer rubric eval (#105)

This eval asks whether a fresh reviewer subagent applies its rubric and role criteria when the orchestrator's prompt doesn't name them. Orchestrators often paraphrase the gate templates, or send "Read <brief> and follow it exactly" with a brief that names no rubric. Issue #105 found reviewers that ran without their criteria: only 1 of 73 design reviewers and 0 of 36 adversarial reviewers opened their rubric in one session.

## How it works

Each scenario in `scenarios/<name>/` has three files:

- `fixture.sh` builds a tiny git repo with planted defects. Each defect sits outside the prompt's stated focus but inside the role's criteria.
- `prompt.txt` is the paraphrased reviewer prompt. It names no rubric. The `*-redirect` variants instead point the reviewer at a shared brief and say "follow it exactly".
- `meta.json` gives the agent type, the rubric or persona name used to detect a read, and a one-sentence description of each planted defect.

`run.sh` starts a fresh headless session for each trial:

```bash
claude -p --plugin-dir <tree> --setting-sources project
```

Metaswarm is loaded from `<tree>`, and the user's installed plugins are not loaded. The session spawns the reviewer agent with `prompt.txt` unchanged. `score.js` then reads the stream-json log and records:

- whether the agent was spawned;
- whether it read its rubric or persona;
- whether the `Criteria applied:` receipt is present;
- whether the reply reports each planted defect, as decided by the judge;
- the cost, including the judge's.

The first three come from the tool calls and the reply's first lines, and are checked in code. A rubric read means reading the file's text: `Read`, a `cat`/`sed`/`head`-style Bash command, or `Grep` in content mode. A `Glob`, a file-listing `Grep`, `find` or `ls` only locates the file and doesn't count.

### The defect judge

Whether a reply reports a defect is a judgment about meaning, and every run produces new wordings. So after each trial, `run.sh` sends the reviewer's reply and the scenario's defect descriptions to Haiku (`claude -p --model haiku`, no tools, JSON-schema output). Haiku answers `reported` true or false for each defect, with a supporting quote. `trial-N.judge.json` keeps the verdict and quotes. A failed judge call is retried once. If it fails again, the trial is marked unjudged: its defect checks are null and it is neither a catch nor a miss. Defect cells count judged trials only, and the report's Judged column shows how many that is. Set `JUDGE_MODEL` to use another model. The judge costs about $0.001 a trial.

Until #109, the defect checks were regexes. They missed some correct wordings and accepted some denials, and patching them for one wording broke others.

### Calibration

`calibrate.js` measures how often the judge agrees with hand-checked labels. It costs about $0.10 per 100 labels:

```bash
node evals/reviewer-rubric/calibrate.js                    # calibration/replies.json
node evals/reviewer-rubric/calibrate.js labels.json out.json
```

There are two label sets:

- **`calibration/replies.json`:** 122 short replies, each labelled for one defect. They are the wordings that broke the regexes in #108 and #109. Many are deliberately tricky: denials, approvals, and a defect mentioned inside a finding about something else.
- **The 135 saved trials from the tables below (282 defect labels).** These are labelled with the verdicts confirmed by reading the replies. They live with the gitignored results, not in the repo.

Two runs with the shipped prompt, on 2026-11-11:

| Label set | Judge agreed |
|---|---|
| Saved trials | 279/282, the same 3 disagreements in both runs |
| Tricky replies | 118/121 and 114/121 (one call failed each run) |

**Saved trials.** In the 3 disagreements, reading the replies again showed the judge was clearly right once. The other two are borderline, but the judge's reading holds up. The tables below are corrected for these (see "Corrections").

**Tricky replies.** Most of the judge's misses vary from run to run, which is Haiku's own variance. One reply was missed in both runs: "No ownership check found", labelled as reporting the IDOR. Its wording is ambiguous.

**The judge is a model and not deterministic.** It is about 99% accurate on real reviewer replies. Its verdicts and quotes are saved with each trial, so a cell can be checked quickly. Before you report a cell, read the replies behind it, or at least the judge's quotes. Re-run `calibrate.js` after changing the judge prompt, a defect description or `JUDGE_MODEL`.

### Corrections (2026-11-11)

The judge found three trials that the earlier regex scoring and hand-reading got wrong. Reading those replies again:

- **Designer baseline, cryptic error codes:** 2/3 becomes 3/3. This one is borderline. Trial 2's major finding is about the error status being typed as a number while the codes are strings, and it adds that "the made-up numeric codes tell them nothing they can act on".
- **Plan Completeness, first branch runs:** 4/6 becomes 5/6. This one is clear. One reply asks "what happens with a missing or invalid code" in a minor finding.
- **Plan Completeness redirect, unsupported currency:** 0/3 becomes 1/3. This one is borderline. Its FAIL row says the plan "doesn't say what happens to existing callers that pass no currency", framed as backward compatibility.

The tables below are updated.

## Running it

```bash
evals/reviewer-rubric/run.sh <label> [trials=3] [plugin-dir=repo root] [scenario...]
# e.g. compare a branch against main:
evals/reviewer-rubric/run.sh branch 3 .
evals/reviewer-rubric/run.sh main 3 ../metaswarm-main design-cto-redirect
```

Results land in `results/<label>/<scenario>/`: one `trial-N.jsonl` and `trial-N.score.json` per trial, a `summary.json`, and a `report.md` for each label. The `results/` directory is gitignored. Set `EVAL_OUT` to write the results elsewhere.

**It calls the model and costs money**, about $0.35–0.45 per trial with Opus reviewers, plus about $0.001 for the judge. Run it by hand. It never runs in CI. `score.js` builds the judge prompt and schema, checks the verdict and computes calibration agreement, and has unit tests (`tests/lib/eval-score.test.mjs`, 100% coverage). `run.sh`, `calibrate.js` and the fixtures call the model, so they have no unit tests.

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
| plan Completeness, plain | missed caller 3/3, unsupported currency 3/3 | Without a criteria table, the first branch runs scored 5/6. `plan-reviewer` now fills in a `### Criteria check` table too (re-run 3/3). |
| plan Completeness, redirect | missed caller 3/3, unsupported currency 1/3 (borderline) | The brief says "keep the plan simple, no hypothetical hardening". Each reviewer still filled in the "Edge cases considered" row; one judged the closed set of three currencies enough. The criterion was applied but reached a different conclusion, so this does not count as a skipped criterion. The 1/3 is a reviewer whose "Rollback/backward compat" row flags callers that pass no currency (see "Corrections"). |

The adversarial and plan re-runs used a scratch copy of the branch with the final text. The commits that followed apply the same text.

## Remaining roles (2026-11-10)

Scenarios for the roles not run above: the PM, Designer, Security and UX design reviewers, the Feasibility and Scope & Alignment plan reviewers, and a Collaborative-mode code review. Code review uses `adversarial-reviewer` with no mode named, so its default, Collaborative, applies with `code-review-rubric`. Each scenario plants two defects inside the role's criteria, and the prompt focuses elsewhere. Baseline is the tree before #105 (c51e08d). Shipped is main after #106 (5fadf25). 3 trials per cell, 42 trials in total, $16.38.

| Scenario | Planted defects | Baseline | Shipped |
|---|---|---|---|
| design PM | no use cases / theming and marketplace beyond the goal | 3/3, 3/3 | 3/3, 3/3 |
| design Designer | API unlike the existing `Result<T>` pattern / cryptic `ERR_42` codes | 3/3, 3/3 | 3/3, 3/3 |
| design Security | no ownership check (IDOR) / full headers logged | 3/3, 3/3 | 3/3, 3/3 |
| design UX | no empty, loading or error states / no wiring into the app shell | 2/3, 1/3 | 3/3, 3/3 |
| plan Feasibility | fabricated `mailer.ts` / undefined `npm run test:unit` | 3/3, 3/3 | 3/3, 3/3 |
| plan Scope & Alignment | yargs migration / YAML and CSV formats, both unrequested | 3/3, 3/3 | 3/3, 3/3 |
| code review (Collaborative) | `any` parameter rated HIGH / `toBeDefined()`-only test | 3/3, 3/3 | 3/3, 3/3 |
| all | read rubric or persona | 10/21 | 21/21 |
| all | receipt present | 0/21 | 21/21 |

What the results show:

- **The UX gap closes.** The baseline UX reviewer read its persona file in all 3 trials, but still missed the UI states in 1 and the app-shell wiring in 2. It stayed on the visual-hierarchy focus. Every shipped trial filled in those checklist rows and failed them.
- **The other six roles show no gap.** The baseline already caught every planted defect for PM, Designer, Security, Feasibility, Scope & Alignment and code review. (The Designer baseline was first reported as 2/3. See "Corrections" above.) These defects may have been too obvious to separate the variants. The shipped trees caught all of them too, so nothing regressed.
- **Receipt and rubric reads:** the receipt went from 0/21 to 21/21, and rubric or persona reads from 10/21 to 21/21.

These runs were scored with the regex checks that the judge has since replaced, then checked by reading the replies. The regexes got several cells wrong in both directions, which is why they were replaced. The judge agreed with all 84 defect labels for these 42 trials, after the Designer correction above.

**Limits.** Each cell has only 3 trials. Delivering the criteria is deterministic, because they are text in the agent definition. Applying them is not: the receipt is self-reported, and with fixes 1+3 the reviewer opened its rubric in only 5 of 9 runs. If misses show up in real use, a hook that injects the template into Agent calls is the fallback.
