# Plan: Severity-gated review iteration + Delivery Scope & Overengineering policy (Issue #54)

**Spec:** GitHub issue #54. The issue is the approved spec. This plan resolves its open points and splits the work into units.

**Branch:** `feat/54-severity-gated-review`.

**Version:** ships in **0.13.0**, which isn't tagged yet, so there is no version bump. The CHANGELOG entry goes under `## 0.13.0`.

**Revision:** 6 (gate PASSED in round 6).

- **Round 1:** Feasibility FAIL, Completeness FAIL, Scope PASS. 5 major blockers, all fixed.
- **Round 2:** Feasibility FAIL, Completeness FAIL, Scope PASS. 2 major blockers, both fixed below, plus folded-in minor findings:
  - the external-tool adapters hard-code the old BLOCKING/WARNING contract
  - the broad sweep patterns match unrelated text

- **Round 3:** Feasibility PASS, Scope PASS, Completeness FAIL. 1 major blocker: the gates' own reviewer output formats (the design-gate `ReviewResult` interface and its 5 persona JSON schemas, the plan-gate per-reviewer format, and the Phase 3 PASS/FAIL outcome lines) were not migrated to the contract. It is fixed below as DoD 3.10, and the minors are folded in.

- **Round 4:** Feasibility PASS, Scope PASS, Completeness FAIL. 1 major blocker: `design-reviewer.md` tells reviewers to follow the persona files' old output format. Fixed in DoD 2.4 by having the contract override the persona format. The minors are folded in.
- **Round 4 decision:** iterate (rule line 4: a major was fixed).
- **Round 5:** Feasibility PASS, Scope PASS, Completeness FAIL. 1 major blocker, of the same type as rounds 3 and 4: `adversarial-reviewer.md` Step A5's "exact format" template still uses BLOCKING/WARNING. Rather than fix one more file, DoD 3.11 closes the whole type. It sets one repo-wide assertion that no file driving behaviour keeps an old-shape output template. The minors are folded in.
- **Round 5 decision:** iterate (rule line 4: a major was fixed).
- **Round 6:** Feasibility PASS, Completeness PASS, Scope PASS → rule line 1: **PASS, advance**. The minor findings were folded in as clarifications.

In rounds 1 and 2 the rule said iterate, because two reviewers reported real blockers and majors were fixed. In round 3 it said iterate (rule line 4/6), because a real major blocker remained and is now fixed.

## Resolved decisions

1. **Safety cap = 10 review rounds per gate occurrence.** This is the user's decision; the issue suggested 5. Hitting the cap is reported as an overengineering signal.
2. **One source of truth: `guides/delivery-scope.md`.** It holds the policy text, the finding contract (`severity`, `protects`, `evidence`, `blocker`) and the iteration rule.
   - Gates, rubrics and agents reference it. They repeat only the decision lines and their own escalation template.
   - `lib/sync-resources.js` mirrors it into **5** skills: `orchestrated-execution`, `plan-review-gate`, `design-review-gate`, `start` and `external-tools`. `external-tools` is included because its synced rubric references the guide.
   - `sync-resources.js` creates the destination dirs, and no test pins the `GUIDE_SYNC` count.
3. **The reviewer contract also goes into the agent files.** Since #53, reviewer instructions live in these files. The issue's file list predates that.
   - `agents/adversarial-reviewer.md`
   - `agents/plan-reviewer.md`
   - `agents/design-reviewer.md`
   - their `skills/start/agents/` copies
4. **External-tool review gets the same contract,** because Codex and Gemini review verdicts feed the same Phase 3 loop. That covers:
   - `rubrics/external-tool-review-rubric.md`
   - the prompt footers the adapters append after the rubric:
     - `skills/external-tools/adapters/codex.sh:306-316`: "Classification: BLOCKING or WARNING … FAIL if any BLOCKING"
     - `skills/external-tools/adapters/gemini.sh:305-321`: the same footer, plus the JSON schema `"classification": "BLOCKING|WARNING"`

   Nothing parses `classification` (checked `_common.sh`, `SKILL.md` and `tests/`), so only prompt text changes.
5. **Follow-ups for minor and nit findings.**
   - When `bd` is available, file a BEADS task (`bd create --type task`), linked to the epic or WU if one exists.
   - Otherwise, list them in a `### Follow-ups` section in the gate output. orchestrated-execution's pre-PR guidance carries them into the PR body (DoD 3.9).
   - Open a GitHub issue only for an item estimated at more than a day.
6. **The Recovery Protocol is scoped to VALIDATE.** Today the 3-attempt Recovery Protocol covers both VALIDATE failures and review failures:
   - `orchestrated-execution/SKILL.md:389` "3 attempts per gate"
   - Step 1 phases IMPLEMENT/VALIDATE/REVIEW
   - the Step 4 template's REVIEW row

   This plan rescopes it explicitly:
   - **VALIDATE failures** (tests, coverage, lint, typecheck) keep 3 attempts, then escalation, plus coder model escalation.
   - **REVIEW failures** follow the severity rule with the 10-round cap.

   On FAIL step 6 (coder escalation) stays word for word, because `tests/agents/test-escalation.sh` asserts its strings.
7. **Sweep beyond the issue's file list.** These files hard-code a fixed review-iteration count and must change:
   - `skills/start/SKILL.md`
   - `agents/issue-orchestrator.md` + mirror
   - `agents/cto-agent.md` + mirror
   - `skills/brainstorming-extension/SKILL.md`
   - `commands/review-design.md`
   - `commands/start-task.md`
   - `README.md`, `USAGE.md`, `GETTING_STARTED.md`
   - `docs/index.html:833` ("three iterations to converge")
   - `rubrics/code-review-rubric.md:319-320` ("Maximum Iterations: 3"), synced to `skills/start/rubrics/`
   - `guides/agent-coordination.md:223` ("3 retries per gate", a rule statement), synced to 4 mirrors

   **VALIDATE retry wording stays but is reworded to name VALIDATE:**
   - the "Recovery: Max 3 retries" lines in `commands/start-task.md` and `USAGE.md`
   - `agents/issue-orchestrator.md:292,611` + mirror

   **Review-loop lines switch to the severity rule:**
   - `issue-orchestrator.md:224,514`
   - `README.md:12` ("3-iteration cap")
   - `README.md:216` ("escalation after 3 failed iterations")
8. **Out of scope:**
   - `.claude/commands/*`. These are this repo's own stale local shims; #53 didn't update them either, and `/setup` regenerates them.
   - The descriptive "2-3 iterations" and "5 reviewers x 3 iterations" cost examples at `guides/agent-coordination.md:78,138`.
   - CHANGELOG history.
   - The external-tools implementer escalation ladder (`skills/external-tools/SKILL.md:206-222`, `templates/external-tools-setup.md:293`). It decides *who implements* after failures, not how many review rounds run. It is unchanged here and filed as a follow-up: count only `blocker: yes` FAILs toward the ladder.
9. **Instruction files carry the core rule inline plus a reference to the guide.** The inline part is about 6 lines. In user projects the guide is only available inside the plugin, so the rule must be usable without opening it. This applies to:
   - root `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
   - the 6 `templates/*` instruction files, synced to `skills/setup/templates/`
10. **Dogfood.** This issue's own plan-gate and WU review rounds apply the new rule. Each round's verdicts, severities and the rule's decision are recorded in a `## Review rounds` section of the PR body, which is the verification for this decision.
11. **Backward compatibility.**
    - Verdict words stay as they are: PASS/FAIL, and APPROVED/NEEDS_REVISION for the design gate. NEEDS_REVISION is valid only with at least one `blocker: yes` finding, the same as FAIL. Only the per-finding fields change.
    - No code parses BLOCKING/WARNING or `classification`. The adapter changes are prompt text only, and the orchestrator reads the reviewer's output.
    - Projects set up earlier pick up the new template text on `/update` or `/setup`, the same as any template change.
    - Rollback is a plain revert. No data or config migration is involved.

## Finding contract (written once in the guide, referenced elsewhere)

```text
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
```

**Verdict.** FAIL only if there is at least one `blocker: yes`. A critical or major finding without `protects` is downgraded to advisory.

**Malformed or legacy output.** Examples are a FAIL whose findings lack the contract fields, or an external CLI that ignores the footer. The orchestrator re-requests the review once in the contract format. If the output is still malformed, it escalates with the raw output. It never treats such a FAIL as PASS. The guide states this in one sentence.

**Path to the guide from rubrics.** The rubrics are byte-synced to `skills/*/rubrics/`, so they name the guide as "`guides/delivery-scope.md` (plugin root; `../guides/delivery-scope.md` from a skill's `rubrics/` dir)". Every skill that receives a synced rubric is also a guide mirror destination.

**Mapping from the existing check tables.**
- "BLOCKING if …" checks produce critical or major findings. They block only with `protects`.
- "WARNING" checks produce minor findings.
- Each rubric states this mapping once, above its tables. The check tables themselves are not rewritten.
- Each rubric's **Verdict** section and **Output Format** template, which reviewers copy, are updated: FAIL ⇔ at least one `blocker: yes`, and the template shows the 4 fields.

**Removed from both adversarial rubrics** (`adversarial-review-rubric.md` and `plan-review-rubric-adversarial.md`): "When in doubt, it's BLOCKING… Err on the side of FAIL".

## Iteration rule (canonical in the guide; each gate repeats these ordered lines)

```text
after each review round (round = 1, 2, ...):
  file every minor/nit finding as a follow-up (decision 5)
  1. no blocker: yes findings            → PASS, advance
  2. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal
  3. the same critical/major finding recurs after a fix attempt for it,
     or two reviewers rate the same finding blocker vs. non-blocker   → escalate
  4. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers
                                         → fix blockers, re-validate, FRESH review
  5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;
                                           any still names a credible scenario → escalate with a recommendation;
                                           otherwise downgrade them to follow-ups and advance
  6. otherwise                           → fix blockers, re-validate, FRESH review
```

**Single-reviewer gates** (Phase 3 adversarial review): condition "≥2 independent reviewers" is simply false. There is no substitute. The condition is counted **per work unit**: reviewers of other work units that ran in parallel don't count.

**"Re-validate"** means running VALIDATE again in orchestrated-execution. In the plan and design gates it means revising the plan or design.

**"This round fixed"** means fixes made since the previous review that this round's reviewers reviewed. The first round has none.

**What counts as a round.** Every re-review is one round. In Task Mode a re-review spawns fresh reviewer instances, and all reviewers of the gate re-run. In Team Mode (design gate) the persistent reviewers re-review, which is unchanged and still counts as a round.

**Follow-up fallback.** If `bd create` fails, the item goes into the `### Follow-ups` section, so nothing is lost.

**Escalation template.**
- Group the remaining findings as Critical / Major / Minor / Nit.
- Include a round history.
- End with `**Recommendation**: <commit|another pass|human decision> — <reason from the rule>`.

## Work units

### WU1: Policy guide, sync wiring, instruction-file references

**Files:**
- NEW `guides/delivery-scope.md`
- `lib/sync-resources.js`: a new `GUIDE_SYNC` entry with 5 dests
- the 5 new mirrors, which are generated
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
- `templates/{CLAUDE,CLAUDE-append,AGENTS,AGENTS-append,GEMINI,GEMINI-append}.md` and their `skills/setup/templates/` mirrors, which are generated
- NEW `tests/agents/test-review-iteration-policy.sh`, Cycle 1 section

**DoD:**
- 1.1 The guide contains:
  - the block-only-for list
  - the do-not-expand list
  - all 5 overengineering signals
  - the when-a-signal-appears steps
  - the finding contract and table mapping
  - the ordered iteration rule with `SAFETY_CAP = 10`
  - the single-reviewer note
  - the follow-up rule
  - the "findings without protects are advisory" clause
- 1.2 `node lib/sync-resources.js --check` passes, and the 5 mirrors exist.
- 1.3 All 9 instruction files contain a "Delivery Scope" section that references `guides/delivery-scope.md` and states the iterate / stop / escalate rule inline.
- 1.4 The guide, its mirrors and the new "Delivery Scope" sections in the 9 instruction files contain no literal `general-purpose`, no `roleType(` and no `Task({` blocks. This keeps `test-no-general-purpose.sh` and `tests/agents/role-type-manifest.txt` unchanged.

### WU2: Reviewer contract (rubrics and reviewer agents)

**Files:**
- `rubrics/{adversarial-review-rubric,plan-review-rubric-adversarial,external-tool-review-rubric,code-review-rubric}.md`, plus their synced copies
- `agents/{adversarial-reviewer,plan-reviewer,design-reviewer,cto-agent}.md` and their `skills/start/agents/` mirrors
- `skills/external-tools/adapters/{codex,gemini}.sh` (the prompt footer and the JSON schema only)
- the test file, Cycle 2 section

**DoD:**
- 2.1 Each of the 3 adversarial and external rubrics defines:
  - the 4-level severity scale
  - that `protects:` is required for critical and major findings
  - the blocker definition
  - the table mapping
  - that unjustified findings are advisory
  - a reference to `guides/delivery-scope.md`
  - its Verdict section and Output Format template, updated to the 4 fields
- 2.1a Both adapter footers:
  - ask for `severity`, `protects`, `evidence` and `blocker`, and FAIL only on `blocker: yes`
  - no longer contain "FAIL if any BLOCKING"

  The Gemini JSON schema no longer has `"classification": "BLOCKING|WARNING"`. `tests/codex`, `tests/gemini` and `tests/agents/test-adapter-models.sh` still pass.
- 2.2 **Neither** `adversarial-review-rubric.md` nor `plan-review-rubric-adversarial.md` contains "When in doubt, it's BLOCKING" or "Err on the side of FAIL". The same holds for their mirrors.
- 2.3 `code-review-rubric.md` drops "Maximum Iterations: 3" and "After 3 rounds", and references the severity rule instead.
- 2.4 The 3 reviewer agents, in both `agents/` and `skills/start/agents/`, state the finding contract in their output rules and reference the guide.
  - The plugin-root copies use `guides/delivery-scope.md`; the skill copies use `./guides/delivery-scope.md`.
  - The "max 3 iterations" lines and their `### Maximum Iterations: 3` headings are replaced, in `adversarial-reviewer.md` (69, 464, 481) and `cto-agent.md` (200, 202), by a reference to the orchestrator's severity rule, in both copies.
  - `design-reviewer.md` says NEEDS_REVISION requires at least one `blocker: yes` finding. It also says: "Use the persona file for its checklist and criteria only. The finding contract and the blocker-based verdict **replace** the persona file's output format and NEEDS_REVISION criteria." The persona files themselves are not rewritten.
  - `plan-reviewer.md` points to `rubrics/plan-review-rubric-adversarial.md` instead of the collaborative `plan-review-rubric.md`. The skill copy uses `./rubrics/…`, so `lib/sync-resources.js` `RUBRIC_SYNC` gains the destination `skills/start/rubrics/plan-review-rubric-adversarial.md`.
  - The test checks that each contract clause is present in **both** copies. It does not byte-compare them, because the mirrors intentionally differ in their `./` path prefixes.

- 2.5 **Every old-shape reviewer template and classification statement in WU2's files is migrated** to the 4 fields, in both copies, so the WU3 assertion (3.11) passes:
  - `agents/adversarial-reviewer.md`: line 43 ("Issue classification: BLOCKING / WARNING") and Step A5's "exact format" template (`FAIL (BLOCKING)`, `### BLOCKING Issues`, `### WARNINGS`).
  - `rubrics/adversarial-review-rubric.md`: the "Every issue found is classified as BLOCKING or WARNING" statement and table, the `(BLOCKING / WARNING threshold)` headings at lines 98 and 107 (renamed to `(blocker threshold)`), and the "Issue severity … BLOCKING / WARNING" row at line 194.
  - `rubrics/plan-review-rubric-adversarial.md`: the matching statement at line 34.
  - `rubrics/external-tool-review-rubric.md`: line 59 ("Every finding (BLOCKING or WARNING) MUST include") and the `### BLOCKING Issues` output section.
  - The adapters, covered by 2.1a.

### WU3: Gate skills

**Scope:** the iteration rule, the cap, the overengineering check, escalation, spawn prompts, follow-ups, removal of contradictions, and the Recovery Protocol scope.

**Files:**
- `skills/orchestrated-execution/SKILL.md`
- `skills/plan-review-gate/SKILL.md`
- `skills/design-review-gate/SKILL.md`
- the test file, Cycle 3 and Cycle 4 sections

**DoD:**
- 3.1 Each gate contains:
  - the ordered decision lines: PASS / cap / escalate / iterate / overengineering / otherwise
  - "10 rounds"
  - the overengineering check
  - a reference to `./guides/delivery-scope.md`
- 3.2 Each gate's reviewer spawn prompt includes the blocker criteria and the finding contract.
- 3.3 Each gate's escalation template groups findings by severity and includes `**Recommendation**:`.
- 3.4 Each gate says that minor and nit findings become follow-ups, following decision 5.
- 3.5 **No fixed review-iteration count remains in the files that drive behaviour.** Those files are the 3 gates, the rubrics and the reviewer agents, plus their mirrors. WU3's Cycle 3 section (not WU4) holds the permanent exact-phrase test, so WU3 can verify itself. WU4 adds `agents/issue-orchestrator.md` and its mirror to the test's file list once it edits them. It checks case-sensitive fixed strings, confirmed against the lines actually removed:
  - `max 3 iterations`, `Max 3 iterations`, `max 3x`, `max 3 →`, `(max 3)` (whole file; the VALIDATE branch is reworded to name VALIDATE, so it doesn't match), `max 3 retries`, `Max 3 retry cycles`
  - `of 3)`, `of 3.`, `N of 3`, `1 of 3`, `Re-review attempt 1/3`, `3/3 iterations`
  - `After 3 iterations`, `after 3 iterations`, `After 3 rounds`, `after 3 rounds`, `After 3 review cycles`, `Rounds 2-3`, `Round 4: Escalation`
  - `Maximum Iterations: 3`, `Max retries (3) exceeded`, `Gate completed within 3 iterations`, `After 3 FAILs`

  The VALIDATE Recovery Protocol's own 3-attempt wording is reworded to name VALIDATE, so it doesn't match. It covers orchestrated-execution §9 Steps 1–4 and the VALIDATE branch of the line-370 diagram.

  The REVIEW branch of that diagram and line 191 ("FRESH review → max 3 → escalate") move to the severity rule.
- 3.6 **Contradicting text is rewritten.** The test asserts each old phrase is absent:
  - `orchestrated-execution`:
    - the MUST-NOT example "found issues but they're minor, committing anyway". It is replaced with "committing with an unresolved `blocker: yes` finding".
    - anti-pattern #12. It is reworded to "treating a `blocker: yes` FAIL as advisory".
    - "Any single BLOCKING issue means overall FAIL", which becomes "Any `blocker: yes` finding means overall FAIL".
  - `plan-review-gate`:
    - anti-pattern #3 ("the issues are minor"). It is reworded to "downgrading a justified blocker without the rule".
    - anti-pattern #6. It becomes "Severity-gated iteration, cap 10".
    - the 3× "Any single BLOCKING issue…" lines, reworded the same way.
    - the "= BLOCKING FAIL" criteria in the spawn prompts, which become "= blocker (major; protects: <the check's requirement>)".
  - `design-review-gate`: the equivalent lines, where present.
- 3.7 **Recovery Protocol scoped per decision 6.**
  - These name VALIDATE as the scope of the 3-attempt cap:
    - the "Max retries: 3 attempts per gate" line (389)
    - Step 1 and Step 3
    - the Step 4 template ("Failed After 3 Attempts", 786)
  - REVIEW failures point to the severity rule.
  - These On FAIL lines are rewritten to the severity rule:
    - step 5 ("Max 3 retry cycles", 397)
    - the "Re-review attempt 1/3, 2/3" counter (400)
    - "Attempt 2 of 3" (410–413)
    - "Max retries (3) exceeded" (414)
    - line 191 in the overview box
    - the checklist lines 849 and 859
  - On FAIL step 6 stays word for word.
  - `test-escalation.sh` passes.
- 3.8 All existing suites still pass, including the `test-no-general-purpose.sh` SITES anchors. Every edited anchor line keeps its `roleType("…")`. If an edited spawn prompt has to change a `roleType(` count, regenerate `tests/agents/role-type-manifest.txt` with `--write-manifest` and review the diff. The manifest is in scope for WU3 and WU4 only for that purpose.
- 3.9 orchestrated-execution's pre-PR and PR guidance says the PR body includes the `### Follow-ups` list (decision 5).
- 3.11 **No old-shape reviewer output remains anywhere.** This closes the whole category of finding from rounds 3–5.
  - **Template migration** is done in WU2 (DoD 2.5). WU3 only holds this assertion.
  - **Repo-wide assertion.** The permanent test asserts that none of these strings appear in any `agents/*.md`, `rubrics/*.md`, `skills/*/SKILL.md`, `skills/*/rubrics/*.md`, `skills/start/agents/*.md` or `skills/external-tools/adapters/*.sh`:
    - `### BLOCKING Issues`
    - `FAIL (BLOCKING)`
    - `BLOCKING or WARNING`
    - `BLOCKING / WARNING`
    - `blockers: string[]`
    - `classified as BLOCKING`
    - `"classification": "BLOCKING`
    - `"blockers": [`
  - **Exceptions.** The design-persona briefs are excluded by name (`product-manager-agent`, `designer-agent`, `security-design-agent`, `architect-agent`, `cto-agent`). `design-reviewer.md` overrides their output format (2.4), and they stay checklists.
  - **"BLOCKING if …" check tables.** They stay as they are, interpreted through the mapping note. The mapping note is also added once above the check tables in `skills/plan-review-gate/SKILL.md`.
  - **Phase 3 spawn prompt.** "Do NOT suggest improvements" becomes "Report every finding with the 4 fields; minor/nit findings are recorded as follow-ups, not suggestions", so follow-ups are captured.
- 3.10 **Reviewer output formats are migrated to the contract.** The test asserts the 4 field names appear in each format, and the old shapes are gone.
  - **design-review-gate:** `ReviewResult` replaces `blockers: string[]` with `findings: Finding[]`, where `Finding = { severity; protects; evidence; blocker }`. `suggestions` and `questions` are kept for non-finding notes.
    - Each of the 5 persona JSON return schemas replaces `"blockers": [...]` with the same `"findings"` array.
    - "If any NEEDS_REVISION" becomes "if any `blocker: yes` finding".
    - The NEEDS_REVISION and Escalation templates group findings by severity, each tagged with its agent.
  - **plan-review-gate:** the "Per-Reviewer Output" format lists findings with the 4 fields. The Consolidated FAIL template groups blockers by severity, tagged by reviewer, and shows the rule's decision.
  - **orchestrated-execution:** the Phase 3 outcome lines ("PASS (zero BLOCKING issues) / FAIL (any BLOCKING issue)", 322–323) become `blocker: yes` based. The adversarial review prompt asks for the 4 fields.
  - **issue-orchestrator** (WU4): the reviewer-prompt line "Any single BLOCKING issue means overall FAIL" (283) gets the same rewording, and "Max 3 retries per work unit: After 3 FAILs" (292) moves to the severity rule, in both copies.

### WU4: Sweep remaining references and CHANGELOG

**Files:**
- `skills/start/SKILL.md`, including lines 83, 111, 162 and 313
- `skills/brainstorming-extension/SKILL.md`, including lines 56, 157 and 162
- `agents/issue-orchestrator.md` + mirror
- `commands/review-design.md`
- `commands/start-task.md`
- `README.md`, `USAGE.md`, `GETTING_STARTED.md`
- `docs/index.html`
- `guides/agent-coordination.md` (line 223) + its 4 mirrors, via sync
- `CHANGELOG.md`
- the test file, sweep section

**DoD:**
- 4.1 **Docs and commands: a one-time sweep, not a permanent test.** Before WU4 is committed, run `grep -rniE 'max 3|3 iterations|of 3|3 rounds|3 retries|three iterations'` over:
  - `skills/`, `agents/`, `commands/`, `guides/`, `rubrics/`, `templates/`
  - `README.md`, `USAGE.md`, `GETTING_STARTED.md`, `docs/index.html`

  Review every remaining hit by hand and record the result in the WU4 commit message. Allowed hits are:
  - the reworded VALIDATE lines
  - `agent-coordination.md:78,138`
  - unrelated text such as "max 30 minutes", "max 3 levels", "Max 3-4 parameters"

  The permanent phrase test (3.5) covers only the files that drive behaviour.
  - `commands/review-design.md`: ESCALATED is reached via the severity rule (escalate condition or the 10-round cap). `--force-override` is offered on any escalation.
  - `GETTING_STARTED.md:250` "max 3 rounds" moves to the severity rule.
- 4.2 These describe the severity rule and the 10-round cap:
  - `README.md` lines 12 and 216
  - `docs/index.html`
  - the `USAGE.md` and `GETTING_STARTED.md` gate descriptions

  The test does not pin doc prose. 4.1's sweep and the WU4 review verify this.
- 4.3 The CHANGELOG `## 0.13.0` section has a #54 entry.
- 4.4 The enforcement command in `.coverage-thresholds.json` passes. It runs all suites, `bash tests/lib/coverage-gate.sh` and `node lib/sync-resources.js --check`.

## Dependencies

WU1 → WU2 → WU3 → WU4, run sequentially. Every unit references the guide that WU1 creates, and they share the one test file.

## Verification

- `tests/agents/test-review-iteration-policy.sh`. It is new, follows the style of the existing `tests/agents/*.sh` scripts, and matches the enforcement glob `tests/*/test-*.sh`.
- The full enforcement command.
- `node lib/sync-resources.js --check`.
- The only JS change is a data entry in `sync-resources.js`, so the `node --test` coverage for `metaswarm-usage` is unaffected.

## Lifecycle and human checkpoints

1. The plan review gate runs. The user approves the plan and chooses the execution method.
2. WU1–WU4, each with VALIDATE and adversarial review under the new rule.
3. `/self-reflect`, and commit the KB.
4. A PR whose body includes a `## Review rounds` table and a `### Follow-ups` list.
5. `/pr-shepherd`. Every comment is addressed and its thread replied to individually.
6. Squash-merge on the user's go-ahead.
