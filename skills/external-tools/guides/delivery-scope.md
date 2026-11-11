# Delivery Scope and Overengineering

The single source of truth for what may block delivery, how reviewers report findings, and when a review loop iterates, advances or escalates. Gates, rubrics and reviewer agents reference this guide and repeat only their own decision lines and escalation template.

## Policy

Optimize for getting testable software to users and accelerating learning.

**Block delivery only for:**

- a credible normal-usage failure
- a missing or contradictory requirement
- a broken key happy path
- an important error or recovery-path failure

**Do not expand the current work unit for:**

- theoretical states
- exhaustive race or corruption permutations
- speculative abstractions or security hardening
- polish that is not required for safe normal use

Record worthwhile hardening as follow-up work instead.

### Overengineering signals

1. repeated review/fix cycles without a new user-visible risk
2. tests for states the real storage or API cannot produce
3. abstractions added only to satisfy synthetic tests
4. validation growing faster than the feature
5. delaying integrated user testing for low-likelihood edge cases

Hitting the safety cap of 10 rounds is also reported as a signal.

### When a signal appears

1. Stop and restate the work unit's Definition of Done.
2. Classify each open concern as blocker or follow-up.
3. Prefer the smallest change in an existing owner.
4. Advance once the blocker criteria above are satisfied.

## Finding contract

Every review finding carries six core fields (the signal fields below are added to them):

```text
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
```

- **Title and description.** `title` is a single line of about 80 characters or fewer that names the finding. `description` is 1-3 sentences on what is wrong and why it matters. `evidence` stays the proof.
- **Long titles.** A title over ~80 characters is advisory, not malformed: the orchestrator may truncate it for tables, but never re-requests or escalates a finding over title length.
- **Verdict.** FAIL only if there is at least one `blocker: yes` finding; otherwise PASS. The design gate keeps APPROVED/NEEDS_REVISION, and NEEDS_REVISION follows the same rule as FAIL.
- **Findings without `protects` are advisory.** A critical or major finding that cannot name the credible user scenario or explicit requirement it protects is advisory, not a blocker. It becomes a follow-up.
- **Mapping from existing check tables.** Rubric tables keep their wording and are read as:
  - "BLOCKING if …" checks produce critical or major findings. They block only with `protects`.
  - "WARNING" checks produce minor findings.
- **Malformed or legacy output.** If a review's findings lack the contract fields (for example a FAIL in the old BLOCKING/WARNING shape, an external CLI that ignores the format, or a finding missing `title` or `description`, such as old-format output with a Codex `explanation` key and no title), the orchestrator re-requests the review once in the contract format, escalates with the raw output if it is still malformed, and never treats such a FAIL as PASS.
- **Missing criteria receipt.** A review of any verdict without a `Criteria applied:` line after its verdict heading (or, for a JSON reply, a `criteria_applied` field) is re-requested once. If it is still missing, the review is accepted as it is, and the gap is noted in the round report and becomes a follow-up: a missing receipt never blocks a gate. External CLI reviews (the Codex and Gemini adapters, which put the rubric in the prompt) and in-session reviews on hosts without subagents (Gemini) are exempt.

### Signal fields

The contract is the six core fields plus signal fields. The core six and their blocking rules do not change. Every finding carries `theme`; each `blocker: yes` finding also carries the rest:

```text
- needs_user: yes | no       # only the user can answer this
- origin: implementation | requirement | assumption
- assumption: <ledger id such as A3, or a quoted decision>   # required when origin is assumption
- theme: <short label>       # on every finding
```

- **Scope.** `needs_user`, `origin` and `assumption` are optional on non-blockers. Only blockers feed the Clarify signals.
- **Already answered.** Reviewers do not mark a question `needs_user` when the design's Confirmed section already answers it.
- **Set by the orchestrator, not the reviewers.** `canonicalTheme` (see Themes), `fix_induced: yes | no` (the blocker matches the orchestrator's record of the previous round's fix, kept as `lastFix`; a fresh reviewer cannot know what changed) and `mergedInto: <kept id>` on duplicates (see Clarify signals).
- **Re-request rule.** A blocker that lacks `needs_user` or `origin` gets one re-request, like malformed output. If the fields are still missing, they are treated as unknown, which triggers nothing. This is not an escalation, and the finding itself still counts as a blocker.

## Iteration rule

The orchestrator, not the reviewer, decides what happens after each round. `SAFETY_CAP = 10`: at most 10 rounds per gate occurrence. Each gate repeats these ordered lines; the first line that matches wins.

```text
after each review round (round = 1, 2, ...):
  file every minor/nit finding as a follow-up (see Follow-ups)
  1. no blocker: yes findings            → PASS, advance
  2. a Clarify signal (C1–C4) fires      → stop: misunderstanding analysis, Clarification report, wait for the user
  3. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal
  4. the same critical/major finding recurs after a fix attempt for it,
     or two reviewers rate the same finding blocker vs. non-blocker   → escalate
  5. an overengineering signal is present → restate the DoD and re-classify each blocker against the policy;
                                           any still names a credible scenario → escalate with a recommendation;
                                           otherwise downgrade them to follow-ups and advance
  6. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers
                                         → fix blockers, re-validate, FRESH review
  7. otherwise                           → fix blockers, re-validate, FRESH review
```

**Notes**

- **Single-reviewer gates** (orchestrated execution's Phase 3 adversarial review): the condition "≥2 independent reviewers" is simply false; there is no substitute. It is counted per work unit, so reviewers of other work units running in parallel don't count.
- **Severity disagreement.** Only disagreement that changes `blocker` escalates (rule line 4). A critical-vs-major or minor-vs-nit split changes no outcome, so it is not a trigger. If both reviewers rate a finding major and only one names `protects`, it counts only if their `blocker` fields differ.
- **"This round fixed"** means fixes made since the previous review that this round's reviewers reviewed. The first round has none.
- **What counts as a round.** Every re-review is one round. In Task Mode a re-review spawns fresh reviewer instances and all of the gate's reviewers re-run. In Team Mode (design gate) the persistent reviewers re-review; that still counts as a round.
- **"Re-validate"** means running VALIDATE again in orchestrated execution. In the plan and design gates it means revising the plan or design.
- **Where the report goes.** When the rule says clarify (line 2), use the Clarification report in the Clarify section. When it says escalate (lines 3, 4 or 5), use the escalation template. The Clarification report also says "cap hit" when the round is 10 or later, so that signal is not lost.

### Clarify signals

Line 2 fires when any of C1–C4 holds. They are evaluated per gate occurrence, after each round, on the last round's blockers. They count **distinct blockers**: after each round the orchestrator merges duplicates (the same canonical theme and the same defect, even when the evidence is worded differently) and records `mergedInto: <kept id>` on each duplicate. A merged blocker still counts once per reviewer for divergence, and C1 scans every blocker.

- **C1** (needs the user). A blocker has `needs_user: yes`, or `origin: assumption` with an `assumption` that is not in the ledger's Confirmed list. An `origin: assumption` blocker with no id counts as unconfirmed.
- **C2** (not converging). Total distinct blockers are non-decreasing over the last three rounds since `windowStart`, that is t[r] ≥ t[r-1] ≥ t[r-2] (three rounds since the window start are needed), or, for gates with ≥2 reviewers, divergence: this round's total distinct blockers did not fall (it is ≥ the previous in-window round's total), and one reviewer reports no blockers while another reviewer's count is higher than its own count in the previous round. A falling total never counts as divergence. A single-reviewer gate never diverges. Divergence needs at least 2 rounds inside the window, so after option 2 it cannot fire until two new rounds exist.
- **C3** (fix-induced). At least 2 distinct blockers in the round have `fix_induced: yes`. It applies only to rounds at or after `windowStart`.
- **C4** (recurring theme). One canonical theme that is not in `ackThemes` appears among the blockers of at least three rounds of the occurrence. The rounds do not need to be consecutive. `windowStart` does not reset C4; only `ackThemes` does. A blocker with no theme counts toward no theme.

C1 and C4 usually fire before C3 would. The history fields `windowStart`, `ackThemes` and `ackFindings` record what the user acknowledged (see Options and re-entry).

### Themes

Each finding has a free-text `theme`. From round 2 on, reviewers get the list of earlier canonical theme labels and reuse one when it fits. They do not see the earlier findings, so each review stays fresh. After each round the orchestrator maps every blocker's theme to a canonical theme id, by judgement, and records it as `canonicalTheme`. C4 counts `canonicalTheme`, and falls back to `theme` when it is missing.

Canonical themes also decide what an acknowledgement clears, because the `ackFindings` key is built from the theme. So the orchestrator gives a `needs_user` blocker that asks a **different question** from the acknowledged one its own new canonical theme. Only a re-raise of the same question keeps the acknowledged theme. The same applies to assumptions: a new assumption gets a new ledger id, and only the same id is cleared.

### Round history

The orchestrator keeps the round history and writes it after every round, one file per gate occurrence: `.beads/context/review-history/<gate>-<slug>-<occurrence>.json`. The slug is derived from the artifact's path, and the path is stored in the file.

```json
{"gate", "occurrence", "reviewers": n, "confirmed": [ids],
 "windowStart": r, "ackThemes": [ids], "ackFindings": [keys],
 "status": "active|clarify-pending|closed", "artifact": "<path>", "lastFix": "<summary>",
 "pendingClarify": null | {"round", "signals", "questions"},
 "rounds": [{"round", "fixedCriticalMajor", "recurring", "disputed", "overengineering",
             "findings": [{"reviewer", "severity", "blocker", "needs_user", "origin",
                           "assumption", "fix_induced", "theme", "canonicalTheme",
                           "id", "title", "evidence", "mergedInto"}]}]}
```

- **Reviewer labels** are stable role names across rounds, for example `PM` and `Architect`, never per-instance ids. Divergence compares a reviewer's count with its own count in the previous round, so a label that changes each round breaks it.
- **`windowStart`** is the next round number after the last acknowledgement. It may exceed the last round until a new round is recorded; the helper accepts that.
- **`reviewers`** must be set to the number of reviewers in the gate. C2 divergence is skipped unless `reviewers` is at least 2.
- **`confirmed`** must mirror the ids in the assumption ledger's Confirmed section. An `origin: assumption` blocker whose id is missing from it counts as unconfirmed for C1.
- **`ackFindings` key.** `<theme>:<assumption id>` whenever `assumption` is set, whatever the origin, and `<theme>:needs_user` otherwise. `<theme>` is `canonicalTheme`, falling back to `theme`. A key with an empty theme never counts as acknowledged, so every `needs_user` blocker needs a `canonicalTheme` for its acknowledgement to stick. Never the per-round finding id.
- **`recurring`, `disputed`, `overengineering`** are the orchestrator's per-round judgements for lines 4 and 5.
- **Status.**
  - `active` is the normal state. A Clarify sets `clarify-pending` and `pendingClarify`.
  - Answering (option 1) sets `closed`, clears `pendingClarify` and starts the next occurrence's file.
  - Keeping iterating (option 2) clears `pendingClarify` and returns the file to `active`.
  - At an escalation, "Clarify the requirement / re-brainstorm" is handled like a Clarify answer. "Revise" keeps the same occurrence, so the round count and cap continue. "Narrow scope" closes the file and starts a new occurrence on the narrowed artifact.
  - Defer, cancel and PASS set `closed`.
  - Starting a new occurrence for the same gate and artifact while an older file is not closed abandons the old one: it is set to `closed`. If several non-closed files exist for one gate and artifact, recovery uses the newest and closes the rest.
- **Recovery.** On start or resume, a gate loads only the non-closed file whose stored artifact path matches. If its status is `clarify-pending`, it re-asks the pending questions and does not iterate. Otherwise it runs the helper. When the last recorded round's result is `escalate`, the gate was waiting at an escalation, so it re-sends the escalation report and waits for the user's choice. On `overengineering-check`, redo the line-5 check first, and send the escalation report only if a blocker still names a credible scenario. Only `iterate` continues at the next round.

### The helper

`lib/review-rule.js` applies the rule to a history file, so the orchestrator does not do the signal arithmetic by hand:

```bash
# HISTORY is the path of the review-history file, e.g. HISTORY=.beads/context/review-history/<file>.json
RR=lib/review-rule.js; { [ -f ./lib/review-rule.js ] && grep -q '"name": *"metaswarm"' package.json 2>/dev/null; } || { RR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v metaswarm-agents.sh 2>/dev/null)")")}/lib/review-rule.js"; [ -f "$RR" ] || RR=lib/review-rule.js; }; node "$RR" "$HISTORY"
```

It prints `{line, action, signals, capHit}` and exits 0. `signals` is a list of `{id, detail}`. It computes PASS (line 1), clarify (line 2, from C1–C4), the cap (line 3) and the iterate lines (6 and 7). Recurring or disputed (line 4) and overengineering (line 5) need judgement, so they arrive as the per-round booleans. A `closed` file returns `action: closed` with no rule evaluation, and `clarify-pending` returns `action: re-ask` with `line` 2 and the current signals. `capHit` is true when the round is 10 or later, whichever line wins.

The actions are `pass` (line 1), `clarify` (line 2), `escalate` (lines 3 and 4), `overengineering-check` (line 5), `iterate` (lines 6 and 7), `re-ask` (status `clarify-pending`) and `closed` (status `closed`, with `line` null).

The helper exits 2 on bad input:

- no argument (usage error);
- an unreadable file or invalid JSON;
- no `rounds`, or an empty array;
- round numbers that are not integers >= 1 or not strictly increasing;
- `recurring`, `disputed`, `overengineering`, `blocker`, `needs_user` or `fix_induced` that is not yes, no, true or false;
- `fixedCriticalMajor` that is not a non-negative integer;
- a round that is not an object;
- `findings` that is not an array of objects;
- `reviewers` or `windowStart` that is not an integer >= 1;
- `status` other than active, clarify-pending or closed;
- `origin` other than implementation, requirement or assumption;
- `reviewer` that is not a string;
- `confirmed`, `ackThemes` or `ackFindings` that is not an array of strings;
- `mergedInto` that does not name another blocker of the same round that is itself unmerged (`null` means unmerged; merge chains and cycles are rejected);
- an `assumption` that is not a non-empty string (`null` and an empty string both exit 2).

Omit a field you do not know rather than writing `null`: `null` fails validation for the validated fields, and only `mergedInto` and `pendingClarify` accept it. On exit 2, fix the history file and run the helper again. Apply the rule by hand only if the helper cannot run.

This guide's rule block is authoritative and the helper implements it; a test compares the guide's rule block with the helper's exported `RULE_LINES`. A disagreement is a bug to fix, not a tie for the orchestrator to break. The command uses `lib/review-rule.js` in the current repo when that repo is metaswarm (`./lib/review-rule.js` exists and `package.json` is named `metaswarm`), so developing metaswarm never runs an older installed copy. Otherwise it takes the plugin root from `CLAUDE_PLUGIN_ROOT` if it is set, or from `metaswarm-agents.sh` on PATH (the plugin `bin/`), and falls back to `lib/review-rule.js` in the current repo. If neither file exists or Node is unavailable (a Codex symlink install has no `lib/`), the orchestrator applies the rule by hand.

## Follow-ups

Minor and nit findings, and blockers downgraded by rule line 5, never block. Record each one:

- When `bd` is available, file a BEADS task with `bd create --type task`, linked to the epic or work unit if one exists.
- If `bd` is unavailable or `bd create` fails, list the item in a `### Follow-ups` section of the gate output, so nothing is lost. The PR body carries that list.
- Open a GitHub issue only for an item estimated at more than a day.

## Clarify

Line 2 is a stop. When it fires, run the misunderstanding analysis, send the Clarification report, and wait for the user. Asking is not enough on its own: the questions must be better than the ones brainstorming missed.

While the answer is pending, mark the BEADS task waiting on the user and set `status: clarify-pending` with `pendingClarify` in the history file.

### Misunderstanding analysis

Run this before writing the Clarification report.

1. **Trace the assumptions.** Trace each load-bearing assumption to the user's words: quote the exact user message it came from, or mark it "agent-proposed, never confirmed".
2. **Find reframings.** State the goal in one sentence, with no mechanism in it. Then offer 1–3 alternative readings of the request, drawn from these patterns:
   - **A level mismatch:** the request is about *what* (a decision service), but it was read as *where or how* (every surface becomes a signing path).
   - **Over-reading scope:** "any surface" read as "every surface fully featured", or one issue bundled into three.
   - **A proposal read as a decision:** the agent's own proposal treated as the user's decision.
   - **A one-word acknowledgement taken as approval of a message with several parts.**
3. **Check the blockers against each reading.** For each blocker theme and each reframing, ask: would this blocker disappear under that reframing?
4. **Write the questions.** Ask at most about 3 questions. Each one names the reading it tests, the options, and which blockers each option removes. Do not ask what the Confirmed section already answers.

### Clarification report

```markdown
## Clarification needed: <gate> — <work unit or artifact>

**Signals fired**: <C1 needs the user | C2 not converging | C3 fix-induced | C4 recurring theme> — round <n>/10<; cap hit, if the round is 10 or later>

### Goal, in one sentence
<the goal, with no mechanism in it>

### Assumption trace
| Assumption | Source |
|------------|--------|
| <what the work rests on> | "<exact user words>" or agent-proposed, never confirmed |

### Readings
1. <reading, naming its pattern: level mismatch | over-reading scope | proposal read as a decision | one-word acknowledgement>

### Blocker themes against each reading
| Theme | Disappears under reading |
|-------|--------------------------|
| <theme> | <reading numbers, or none> |

### Questions
1. <question> — tests reading <n> — options: <A: removes <blockers>; B: removes <blockers>>

### Round history
| Round | Verdict | Blockers (critical/major) | Fixed this round | Signals (C1–C4) | Themes | Rule decision |
|-------|---------|---------------------------|------------------|-----------------|--------|---------------|
| 1     | FAIL    | 0 / 2                     | —                | C1              | <theme> | 2: clarify    |

### Options
1. **Answer** — answer the questions; the requirement is revised and a new gate occurrence starts
2. **Keep iterating** — the reading was right; record your answers and continue at rule line 3 (the cap), then the later lines in order, once no signal remains; any unanswered question is asked again
3. **Narrow scope** — move the contentious items to a new issue, then run a fresh review round on what remains
4. **Defer** — shelve this work for later; nothing moves
5. **Cancel** — abandon this work

**Recommendation**: <answer|keep iterating|narrow scope|defer|cancel> — <reason from the signals>
```

### Options and re-entry

1. **Answer.** The orchestrator updates the ledger, re-brainstorms or revises the artifact, and starts a **new gate occurrence** on it: a fresh round 1, and the cap resets. The previous occurrence's history is kept for reference and does not feed the new windows.
2. **Keep iterating.** The reading was right. Restate any answer the user gave and write it to the ledger's Confirmed section. The acknowledgement covers the C2 window and the C3 round, by moving the window start to the next round, and the specific canonical themes acknowledged for C4 (added to `ackThemes`). C1 cannot be acknowledged by type: only the specific questions the user answered are cleared, by adding their `ackFindings` keys. An acknowledged key clears re-raises of that question, meaning the same canonical theme with `needs_user` and no assumption id, or the same assumption id. A new question fires C1, because the orchestrator gives it a new canonical theme or a new assumption id (see Themes). The cap is not reset. After the acknowledgement, re-run the helper on the same round. Review continues at rule line 3 (the cap), then the later lines in order, only when no signal remains: every C1 key that fired has been answered by the user (their answer is recorded as the assumption id in `confirmed`) or is in `ackFindings`, recorded from their option-2 choice, and every C4 theme that fired is in `ackThemes`. A `needs_user` blocker clears only through `ackFindings`; `confirmed` clears only the unconfirmed-assumption part. The orchestrator never edits or removes a recorded round's findings to clear a signal. Otherwise line 2 still holds: ask the remaining questions again. The acknowledgement never returns to line 1 and never advances by itself.
3. **Narrow scope.** Move the contentious items to a new issue; the narrowed artifact starts a new occurrence with a fresh review round.
4. **Defer.** Shelve the work. The history file is closed.
5. **Cancel.** Abandon the work. The history file is closed.

Clarification never approves. There is no option that advances with open blockers, and any revised or narrowed artifact passes only through a fresh review round with no `blocker: yes` finding.

### Standing instructions

"Keep going", "use your judgment" and similar standing instructions never acknowledge a signal, answer a question or default a `needs_user` question. Only an answer to the specific question counts. While it waits, the orchestrator may keep working on parts the questions do not affect.

### Feed it back

- **Now.** The analysis and the user's answers go into the re-brainstorm, so the revised design states the confirmed reading in its Confirmed section.
- **For next time.** Record the pattern in each project's knowledge base through `/self-reflect` (type `gotcha`, tag `misunderstanding`), so it survives sessions and `/update`. Brainstorming loads those facts into its "Common misreadings" checklist (see `skills/brainstorming-extension/SKILL.md`) alongside the built-in patterns and checks them before it closes, so later sessions ask the question up front. `/self-reflect` also offers, without doing it automatically, to file a metaswarm GitHub issue so a general pattern can join the built-in list. Edit the built-in list only when the current repo is metaswarm itself.

## Escalation template

```markdown
## Review Escalation: <gate> — <work unit or artifact>

**Rule line**: <3 cap hit | 4 recurring/disputed | 5 overengineering signal>

### Remaining findings
- **Critical**: <title>: <description> — protects: <...> — evidence: <...>
- **Major**: <title>: <description> — protects: <...> — evidence: <...>
- **Minor**: <title> (follow-up filed)
- **Nit**: <title> (follow-up filed)

### Round history
| Round | Verdict | Blockers (critical/major) | Fixed this round | Signals (C1–C4) | Themes | Rule decision |
|-------|---------|---------------------------|------------------|-----------------|--------|---------------|
| 1     | FAIL    | 0 / 2                     | —                | —               | <theme> | 7: iterate    |

### Options
1. **Revise** — fix the remaining blockers (or the requirement they protect), then run a fresh review round
2. **Narrow scope** — move the contentious items to a new issue, then run a fresh review round on what remains
3. **Defer** — shelve this work for later; nothing advances
4. **Cancel** — abandon this work
5. **Clarify the requirement / re-brainstorm** — answer the open questions about the requirement; a new gate occurrence starts

**Recommendation**: <revise|clarify|narrow scope|defer|cancel> — <reason from the rule>
```

Line 2 never uses this template; it uses the Clarification report.

**Escalation never approves.** A gate passes only when a review round has no `blocker: yes` finding (rule line 1), or through rule line 5's downgrade. At an escalation the human decides how to change the work, choosing from the five options above. Any revised or narrowed plan, design or work unit gets a fresh review round, and it passes only by that round. There is no option that advances with open blockers. Never describe an escalated gate as approved, and never offer an option that skips the fresh round or accepts open blockers.
