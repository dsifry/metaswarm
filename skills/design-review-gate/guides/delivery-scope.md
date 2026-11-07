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

Every review finding carries four fields:

```text
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
```

- **Verdict.** FAIL only if there is at least one `blocker: yes` finding; otherwise PASS. The design gate keeps APPROVED/NEEDS_REVISION, and NEEDS_REVISION follows the same rule as FAIL.
- **Findings without `protects` are advisory.** A critical or major finding that cannot name the credible user scenario or explicit requirement it protects is advisory, not a blocker. It becomes a follow-up.
- **Mapping from existing check tables.** Rubric tables keep their wording and are read as:
  - "BLOCKING if …" checks produce critical or major findings. They block only with `protects`.
  - "WARNING" checks produce minor findings.
- **Malformed or legacy output.** If a review's findings lack the contract fields (for example a FAIL in the old BLOCKING/WARNING shape, or an external CLI that ignores the format), the orchestrator re-requests the review once in the contract format, escalates with the raw output if it is still malformed, and never treats such a FAIL as PASS.

## Iteration rule

The orchestrator, not the reviewer, decides what happens after each round. `SAFETY_CAP = 10`: at most 10 rounds per gate occurrence. Each gate repeats these ordered lines; the first line that matches wins.

```text
after each review round (round = 1, 2, ...):
  file every minor/nit finding as a follow-up (see Follow-ups)
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

**Notes**

- **Single-reviewer gates** (Phase 3 adversarial review): the condition "≥2 independent reviewers" is simply false; there is no substitute. It is counted per work unit, so reviewers of other work units running in parallel don't count.
- **Severity disagreement.** Only disagreement that changes `blocker` escalates (rule line 3). A critical-vs-major or minor-vs-nit split changes no outcome, so it is not a trigger. If both reviewers rate a finding major and only one names `protects`, it counts only if their `blocker` fields differ.
- **"This round fixed"** means fixes made since the previous review that this round's reviewers reviewed. The first round has none.
- **What counts as a round.** Every re-review is one round. In Task Mode a re-review spawns fresh reviewer instances and all of the gate's reviewers re-run. In Team Mode (design gate) the persistent reviewers re-review; that still counts as a round.
- **"Re-validate"** means running VALIDATE again in orchestrated execution. In the plan and design gates it means revising the plan or design.

## Follow-ups

Minor and nit findings, and blockers downgraded by rule line 5, never block. Record each one:

- When `bd` is available, file a BEADS task with `bd create --type task`, linked to the epic or work unit if one exists.
- If `bd` is unavailable or `bd create` fails, list the item in a `### Follow-ups` section of the gate output, so nothing is lost. The PR body carries that list.
- Open a GitHub issue only for an item estimated at more than a day.

## Escalation template

```markdown
## Review Escalation: <gate> — <work unit or artifact>

**Rule line**: <2 cap hit | 3 recurring/disputed | 5 overengineering signal>

### Remaining findings
- **Critical**: <finding> — protects: <...> — evidence: <...>
- **Major**: <finding> — protects: <...> — evidence: <...>
- **Minor**: <finding> (follow-up filed)
- **Nit**: <finding> (follow-up filed)

### Round history
| Round | Verdict | Blockers (critical/major) | Fixed this round | Rule decision |
|-------|---------|---------------------------|------------------|---------------|
| 1     | FAIL    | 0 / 2                     | —                | 6: iterate    |

**Recommendation**: <commit|another pass|human decision> — <reason from the rule>
```
