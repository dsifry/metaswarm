# Research Selection

metaswarm has two research roles (the deep one runs as two arms), a citation checker, and a context check mode of the codebase researcher. This guide is the single rubric for picking them in the research phase and in brainstorming. The agent files carry only a pointer back here. (Coder tiers for IMPLEMENT are in `guides/coder-selection.md`.)

| Role type | Claude default | Use for |
|---|---|---|
| `codebase-researcher` | `sonnet` (a brief may ask for `haiku` for a narrow lookup) | Code facts: what exists in the repo, patterns, dependencies, prior art in the repo, with file:line citations |
| `deep-researcher` | `fable` | Design research for user-facing features, new major capabilities and other high-stakes designs, using the lenses in `rubrics/deep-research-rubric.md` |
| `deep-researcher-second` | `opus` | The second arm of dual-arm deep research: same brief and rubric, a second model |
| `citation-checker` | `haiku` | A mechanical check of every citation in a research report before its findings are used |
| `researcher` | `sonnet` | Deprecated alias for `codebase-researcher`, kept for one release |

Models come from `.metaswarm/models.yaml` (`roles.codebase-researcher`, `roles.deep-researcher`, `roles.deep-researcher-second`, `roles.citation-checker`). `roles.researcher` is still read for one release: when `roles.codebase-researcher.claude` is not set, it is the `codebase-researcher` model. Role types are resolved per "Role type resolution" in `guides/agent-coordination.md`.

The second deep-research arm is its own role type, `deep-researcher-second`, rather than a per-call model override, because in metaswarm each role's model lives in its agent frontmatter and `models.yaml` (the same reason `supercoder` is its own role). Set `roles.deep-researcher-second.claude` to change the second arm's model.

The context check is a mode of `codebase-researcher`, not its own role: it needs the same model (sonnet), the same read-only tools and the same skill (reading code in context). Separate roles exist here only where the default model differs (`citation-checker` on haiku, the second deep-research arm on opus).

## Which researcher

- **Code facts only** (a bug, a refactor, "where is X", an issue that changes existing behaviour): `codebase-researcher`.
- **A user-facing feature, a new major capability, or another design that matters**: `codebase-researcher` and dual-arm deep research (`deep-researcher` + `deep-researcher-second`) **in parallel**, then merge the findings. The deep-research brief names the lenses:
  - Product lens for anything user-facing;
  - Design lens when there is more than one reasonable shape;
  - Capability lens for new major capabilities and platform changes.
- **A narrow lookup** (one symbol, one count, one file): `codebase-researcher` with a brief that asks for `haiku`.

The `deep-researcher` does not survey code; it uses the `codebase-researcher`'s report (or asks the orchestrator for the code facts it still needs). A blind judge is optional: use one only when two reports must be compared or merged and they disagree.

## Dual-arm deep research (default)

For deep research the default is two deep-researchers on the same brief, in parallel: `deep-researcher` (fable) and `deep-researcher-second` (opus). The orchestrator merges their findings into one report: keep every fact either arm found, and where they disagree, check the source and keep what it supports. The merged report then goes through the citation check and the context check.

**Founder's rationale (2026-11-23):** getting the facts right in design research is critical, and the two arms were complementary in the blind test (facts Opus 8 vs Fable 7; design Fable 8 vs Opus 7.5; each found a decisive fact the other missed). A second arm costs less than a design built on a missed fact.

**Single arm (fable only)** is the option for small or low-stakes designs: a brief that changes one surface, is easy to reverse, and has no founder question riding on it. Say in the brief that it is single-arm and why.

## Pipeline

researcher(s) → citation check → context check → apply corrections → design

1. The researchers: `codebase-researcher`, plus dual-arm deep research for a design that matters. Merge the deep-research arms.
2. Citation check: `citation-checker` (haiku) on each report.
3. Context check: `codebase-researcher` (sonnet) in its context check mode on each report.
4. Apply the corrections from both checks to the findings.
5. Only then use the findings in the design, plan or decision.

All of these are orchestrator steps: a subagent cannot spawn subagents.

## Citation check (orchestrator step)

After any `codebase-researcher` or `deep-researcher` report whose findings feed a design, plan or decision, the orchestrator spawns a `citation-checker` (`roleType("citation-checker")`) on that report. It is an orchestrator step because a subagent cannot spawn subagents; a researcher never calls it itself.

- The checker opens every cited line, range, doc section, bead id and count and returns MATCH, NEAR (with the correct line), WRONG (with what the lines say) or COUNT (a grep recount).
- NEAR and WRONG corrections are applied to the findings before they are used. A WRONG that a conclusion rests on sends that point back to the researcher.
- It never judges reasoning or design.
- **Known limit:** a mechanical check catches wrong lines and counts, but not a contextually wrong attribution (a correct line about a test fleet cited for a production rule). The `deep-researcher` rubric keeps an attribution self-check for that, and the context check below runs after it.

## Context check

After the citation check, the orchestrator spawns a `codebase-researcher` (`roleType("codebase-researcher")`, sonnet) in its context check mode on the report. For each MATCH or NEAR citation it reads the cited lines plus their surrounding section and gives one verdict:

- **SCOPE**: the line is about a different thing than the claim applies it to (test fleet vs production, one company vs all, Mac vs fleet, a default vs a requirement).
- **ACTOR**: the wrong actor (who writes, approves or supplies).
- **TENSE**: a plan or future work unit stated as built, or a plan line that is stale against the code. For any plan or spec line that describes how code behaves, the checker must find and follow the actual code path (the entry point, then each fallback) before accepting it.
- **STRENGTH**: the claim is stronger than the source ("never", "only", "must").
- **OK**: the context supports the claim.

It prioritises load-bearing claims: suppliers, blockers, "reusable as-is", and the defaults behind founder questions. Its corrections are applied with the citation check's before the findings are used.

Why it exists (2026-11-23): an Opus judge found context errors that the mechanical check missed: a test-fleet line cited for a production rule about who writes ops.env; "the customer creates the Slack app" when the founder does today; and a stale plan line, "create without --import fails seat start", that the code contradicts. 

**Live test (2026-11-23, one sample).** A Sonnet context check on the two design-research reports, after the Haiku citation check: 116k tokens, 138 s, 47 claims checked.
- It caught all 3 context errors the Opus judge had found: the test-fleet ops.env line used as the rule for who writes it (SCOPE); "the customer creates the Slack app" when the founder does (ACTOR); "the customer approves" read into a line that says only "human step-up" (STRENGTH).
- It found about 20 more that the judge and the citation check did not, for example: a test-fleet mailbox design presented as RepoFortify's and the customer default; an approval service listed as "reusable" though it is gated on realCompany; install warnings counted as blockers though they are log-only.
- It missed one, and the miss matters (the worked example for TENSE). Plan line P:2419 says "create without --import fails seat start". The code contradicts it: the launcher falls back to the image's model-registry (fleetlaunch/pi.go:62-69, seat.go:52, staged by stage-context.sh:2775). The checker endorsed the stale plan line: it said it checked code where plan lines describe code, but it did not follow that code path. Hence the TENSE rule: find and follow the actual code path, entry point then each fallback.

## Evidence (2026-11-23)

All of these are single samples. Treat them as a reason for the defaults, not as a benchmark.

**Deep research, Opus vs Fable.** Same design-research brief, blind head-to-head, one sample:

| | Opus | Fable |
|---|---|---|
| Codebase facts | 8/10 | 7/10 |
| Design value | 7.5/10 | 8/10 |
| Tokens and time | 216k, 4.5 min | 159k, 2 min |

The two reports were complementary: each found a decisive fact the other missed. Hence the default pattern for important designs: `codebase-researcher` + dual-arm deep research (Fable and Opus) in parallel, findings merged, then the citation and context checks (optionally a blind judge when reports disagree).

**Codebase research, Sonnet vs Haiku.** Same facts-only brief, blind Opus judge: Sonnet 8/10 (138k tokens, 108 s) vs Haiku 7/10 (132k tokens, 65 s). Citation accuracy was about equal (Sonnet 22/26 exact, Haiku 24/29 exact). Haiku's coverage was weaker: it missed the most-used company switch and the "v0 has no work unit" fact. So the default stays `sonnet`; `haiku` is for narrow lookups only.

**Citation checker (Haiku).** Run on two Opus/Fable research reports, it checked about 120 citations, against the judge's 21.
- It caught 4 of the judge's 5 known errors: a wrong file:line, two line offsets, and a count of 12 vs 14 call sites.
- It missed the 1 contextual mis-attribution.
- It found 5 more WRONG citations the judge never checked; the Opus judge had wrongly passed one of them.
- Cost: 186k Haiku tokens, about 5 min. The Opus judge took 99k tokens.

## Cost notes

- Fable costs 2x Opus per token, and the dual-arm default adds an Opus run on top. Run deep research for designs that matter, not for code lookups; use a single arm for small or low-stakes designs.
- `citation-checker` on Haiku is cheap per token but reads every cited line; give it the report and the repo, nothing else.

## Deprecated alias

`researcher` is a Deprecated alias for `codebase-researcher` for one release: the agent file is a thin pointer, role type resolution maps it, and `roles.researcher` in `.metaswarm/models.yaml` is still read. New spawns use `codebase-researcher`.

## Spawn log

Log research spawns in the same spawn log as coders (see "Spawn log" in `guides/coder-selection.md`), so model comparisons stay measurable.
