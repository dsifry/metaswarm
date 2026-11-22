# Coder Selection

metaswarm has three coder tiers and a debugger. This guide is the single rubric the orchestrator uses to pick one for an IMPLEMENT phase or a review-fix round. The agent files carry only a pointer back here.

| Tier | Role type | Claude default | Use for |
|---|---|---|---|
| Mechanical | `mechanical-coder` | `haiku` | Small, fully specified, behaviour-preserving edits |
| Default | `coder` | `sonnet` | Everything else |
| Super | `supercoder` | `opus` | Particularly hard work units (the one Opus coder definition) |
| Debugger | `debugger` | `fable` | Root-cause investigation only; it never implements the fix |

Models come from `.metaswarm/models.yaml` (`roles.mechanical-coder`, `roles.coder`, `roles.supercoder`, `roles.debugger`). Role types are resolved per [Role type resolution](./agent-coordination.md#role-type-resolution).

## mechanical-coder: ALL of these must hold

1. No change to production behaviour.
2. Edits are limited to test expectations, fixtures, generated files, doc and line citations, comments, or renames that the brief fully specifies.
3. The brief names the exact files and the expected result.
4. No security boundary is touched.

If any one fails, it is not a `mechanical-coder` job. The `mechanical-coder` stops and reports "needs coder" if the brief turns out to require a design decision or a production behaviour change.

## supercoder: ANY of these

1. The work unit is a security boundary, a concurrency or locking protocol, a crypto or auth path, or a cross-component protocol change.
2. The previous round's blockers were fix-induced (the C3 signal in [`delivery-scope.md`](./delivery-scope.md)).
3. The same theme failed review twice.
4. The coder failed VALIDATE `escalation.coder.after_failures` times (the existing escalation, default 2).
5. The coder reported BLOCKED.

## debugger: ANY of these

1. The same defect or theme survived a fix attempt (a recurrence, or the C4 signal).
2. The failure is intermittent or flaky, or is a race.
3. Tests pass but the live or integrated system fails.
4. The failure crosses components and nobody can yet name the faulty one.
5. The coder reported BLOCKED on "can't find why".

Do NOT use `debugger` for a failure whose cause is already plain in the error output.

The `debugger` investigates and designs; it does not implement. It reads code, runs tests and runs probes or reproductions, writing only to a scratch directory, never to the repo. It returns the root cause with evidence (the reproduction, the exact lines, and why the earlier fix did not hold), the class of the bug and a structural test that would catch it, and a complete fix design. That design goes to a fresh coder of the tier this rubric picks. If the `debugger` cannot reach a root cause it says what it ruled out and what to probe next; it never guesses.

Cost note: Fable costs 2x Opus per token. Give each `debugger` run one narrow question and a brief with the symptoms and everything already ruled out.

## coder: everything else

When unsure, use `coder`.

## Moving between tiers

- `mechanical-coder` fails validation once: re-do the work with `coder`.
- `coder` to `supercoder`: per the escalation rule above (`escalation.coder.after_failures`, or any other `supercoder` condition).
- Never step down within a round. A round that started on a higher tier finishes on that tier; the tier may be re-chosen at the start of the next round.

Every move is a fresh spawn with a complete brief. A coder is never resumed for a new round (see the fix-brief checklist in the orchestrated-execution skill).

## Configuration and backward compatibility

`escalation.coder.after_failures` in `.metaswarm/models.yaml` still sets how many failed VALIDATE attempts trigger the move to `supercoder`. `escalation.coder.claude` is still honoured: when `roles.supercoder.claude` is not set, it is the Claude model of the `supercoder` role. When both are set, `roles.supercoder.claude` wins. There is no per-call `model` override on `coder` any more; `supercoder` is the one definition of the Opus coder.

## Spawn log

Log every spawn (coder, reviewer, debugger) with these fields: `ts, wu, round, role, model, tokens, outcome, claim_matched`. `claim_matched` records whether the agent's "passes" claim matched the orchestrator's own check of the same commands. Keep the field set fixed so tier and model comparisons, such as Opus vs Fable, can be measured instead of argued.

Head-to-head method: give the same work unit to two models in separate worktrees, review both with fresh adversarial reviewers, and merge the better one. Log both runs.
