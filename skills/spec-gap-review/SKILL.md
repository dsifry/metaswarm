---
name: spec-gap-review
description: Critical review of implementation guides, architecture docs, UX specs, infrastructure plans, memory designs, roadmaps, and other design documents against the current repository. Use when Codex needs to audit a spec for doc/code drift, missing prerequisites, stale external assumptions, schema or contract mismatches, or phase readiness; run a stable rubric, score readiness, cite file:line evidence, and prioritize problems instead of confirming that the document looks good.
---

# Spec Gap Review

Review a document against implementation reality, not against its own aspirations. Prefer finding misleading completeness, infeasible sequencing, stale assumptions, and contract drift over summarizing what the document says.

## Review Contract

Every run must produce:

- `Overall readiness` out of `100`
- `Quality` out of `100`
- `Completeness` out of `100`
- The fixed core rubric scores below
- A small set of doc-type focus checks
- A round-aware improvement path to `100`

Do not replace the core rubric with an ad hoc checklist. Tailor the findings, not the scorecard.

## Workflow

1. Classify the target document.
   Typical classes: strategy, implementation guide, memory design, UX/API contract, infrastructure/deployment plan, long-lived/background-agent plan.
2. Run the stable core rubric first.
   Read [references/rubric-patterns.md](references/rubric-patterns.md) when you want doc-type focus checks and common failure modes.
3. Add `2-4` doc-type focus checks.
   These checks deepen the review but do not replace the core scorecard. Keep them unscored unless the user explicitly asks for extra scoring.
   For implementation guides, strongly prefer:
   - intra-doc consistency
   - producer → carrier → consumer trace for new fields or telemetry
   - command/artifact operability
   - upstream status truthfulness
4. Ground the review in local reality first.
   Read the target doc, then check the current repo surface it claims to describe.
   Typical hotspots:
   - `package.json`
   - `src/`
   - `tests/`
   - `.claude/agents/`
   - sample artifacts such as `reviews/`
   - current types and schemas in `src/types/`
5. Run an explicit intra-doc consistency sweep.
   Compare the document's own types, pseudocode, commands, examples, file lists, validation steps, and acceptance criteria against each other.
   Prefer finding doc-vs-doc contradictions that would mislead an implementer, even when the repo has not been touched yet.
6. For each newly introduced counter, schema field, telemetry field, or status enum, trace the full producer → carrier → consumer path.
   Verify the doc defines:
   - where the value is produced
   - where it is stored or returned
   - how it is threaded through intermediate types or configs
   - where it is finally rendered, consumed, or asserted
   Do not treat a field as "specified" if any hop is missing.
7. Check volatile external claims only when needed.
   Browse only for unstable or authoritative facts such as API limits, pricing, model capabilities, product approvals, regulations, or vendor docs.
   Prefer official or primary sources.
   Include exact dates in the report when a claim is time-sensitive.
8. Verify upstream status claims whenever the document says another doc, design, PR, bead, phase, or gate is `approved`, `ready`, `closed`, `in progress`, or similar.
   Check the referenced source's current status line and, when available, its latest sibling companion review instead of trusting the target doc's narration.
9. For later-round reviews, compare against the latest prior review for the same doc.
   Look for sibling `*-codexreview.md` files, earlier review sections, or user-provided prior reviews.
   Carry forward unresolved gap IDs.
   Only award recovered points when the document or repo evidence actually changed.
10. Write a critical report.
   Make findings primary.
   Distinguish clearly between:
   - what the current repo does
   - what the document claims
   - what is merely future intent
11. Validate every file:line reference if you save a review file.
   Use the bundled validator script after writing markdown with `#L...` links.

## Core Rubric

Score every dimension on `0-5`. Convert the score to points with `(score / 5) * weight`.

| Dimension | Weight | Full-credit standard |
| --- | ---: | --- |
| Scope clarity and decision usefulness | 15 | The document makes the intended change, boundaries, assumptions, and decisions unambiguous. |
| Completeness of behavior, flows, and edge cases | 20 | Happy paths, failure paths, lifecycle states, and edge cases are covered without material blind spots. |
| Contract and schema specificity | 15 | Interfaces, schemas, invariants, and data ownership are precise enough to implement and test. |
| Repo alignment and current-state accuracy | 20 | Claims about the current codebase, files, types, scripts, and capabilities match reality. |
| Technical feasibility and dependency realism | 15 | Dependencies, prerequisites, external services, and migration assumptions are realistic and available. |
| Sequencing, verification, and operational readiness | 15 | The plan can be executed safely, tested clearly, and operated without hidden prerequisite work. |

### Score Meanings

- `0/5`: Missing or unsupported.
- `1/5`: Actively misleading for implementation.
- `2/5`: Exploratory and useful for ideas, but not safe as a build spec.
- `3/5`: Usable with material cleanup.
- `4/5`: Mostly implementation-ready, with limited tightening needed.
- `5/5`: Implementation-ready, evidenced, and aligned with the repo.

## Rollups

- `Overall readiness /100` = sum of all weighted points.
- `Quality /100` = normalized weighted subtotal of:
  - scope clarity and decision usefulness
  - repo alignment and current-state accuracy
  - technical feasibility and dependency realism
  - sequencing, verification, and operational readiness
- `Completeness /100` = normalized weighted subtotal of:
  - completeness of behavior, flows, and edge cases
  - contract and schema specificity
  - sequencing, verification, and operational readiness

Do not award `100/100` unless:

- every core rubric dimension is `5/5`
- no `P0` or `P1` issue remains open
- all major claims are backed by repo evidence or dated external sources
- the plan includes a concrete verification path

## Multi-Round Progression

When reviewing the same plan across multiple rounds:

- Mark the first pass as `Round 1 - Baseline`.
- Create stable gap IDs such as `G01`, `G02`, `G03`.
- On later rounds, keep the same gap ID if the issue still exists.
- Mark each gap as `closed`, `partial`, `open`, or `new`.
- Show score deltas for:
  - `Overall readiness`
  - `Quality`
  - `Completeness`
  - each core rubric dimension
- Include a `Path to 100` section that lists the exact missing evidence or revisions needed to recover the remaining points.
- Keep the recommended next actions capped at the `5` highest-leverage fixes.
- If a prior review is unavailable, say so explicitly and treat the run as a new baseline.

## Review Standards

- Treat the document as a spec unless it is clearly labeled brainstorming.
- Penalize docs that present future-state design as current behavior.
- Penalize duplicated schema definitions that can silently drift.
- Penalize precise external quotas or pricing embedded without date/source hygiene.
- Penalize command examples, CLI invocations, file paths, and artifact locations that cannot be executed or committed as written.
- Penalize intra-doc inconsistencies with the same seriousness as doc-vs-repo drift when they would mislead implementation.
- Penalize new counters or telemetry fields that lack a complete producer → carrier → consumer path.
- Prefer repo evidence over narrative confidence.
- Call out when a migration plan starts from an imagined baseline instead of the actual codebase.
- When a document is conceptually good but operationally weak, say so directly.
- Do not hide low scores behind a flattering summary.
- Do not mark a gap closed just because the document acknowledges it. Close it only when the spec actually resolves it.
- Do not keep re-penalizing a deliberate design choice just because an alternative might be better. If the choice is internally consistent, repo-aligned, and operationally workable, treat it as a tradeoff, not a standing gap.

## Critical-Only Mode

If the user asks to focus on critical errors, correctness issues, blockers, or "not nitpicks":

- Prioritize open `P0` and `P1` issues only.
- Include `P2` only when it is factually incorrect, contradicts the repo, or blocks execution/validation.
- Compress or omit praise, closed-gap recap, and non-blocking cleanup commentary.
- Keep the scorecard and rollups, but let the findings section stay short if only a few critical issues remain.

## Output Shape

Use this structure unless the user asks for a different format:

1. `Round status`: round number, prior review reference if any, and whether this is a baseline or delta review.
2. `Executive summary`: `2-3` sentences.
3. `Rollups`: `Overall readiness`, `Quality`, `Completeness`, and score deltas when applicable.
4. `Core scorecard`: every rubric dimension with `score`, `weight`, `points`, and `delta`.
5. `Gap tracker`: stable gap IDs with status (`closed`, `partial`, `open`, `new`) and points recoverable.
6. `Detailed findings`: grouped by rubric area with file:line references.
7. `Prioritized issues`: `P0` to `P3`.
8. `Path to 100`: exact changes needed to recover the remaining points.
9. `Recommended next actions`: the smallest set of changes most likely to move the score materially next round.

## Severity Model

- `P0`: Fundamentally wrong or dangerous for implementation.
- `P1`: Will cause real delivery, correctness, or maintenance problems.
- `P2`: Important quality gap that should be fixed before the next phase.
- `P3`: Nice to have or cleanup.

## Score Bands

- `<60`: Not safe as a build spec.
- `60-79`: Directionally useful, but still high-risk.
- `80-94`: Usable with material cleanup.
- `95-99`: Nearly implementation-ready.
- `100`: Implementation-ready and fully evidenced for the current repo state.

## Saving Review Files

When the user wants written feedback in-repo:

- Save next to the source doc with suffix `-codexreview.md` unless the user specifies otherwise.
- If a sibling `-codexreview.md` already exists and the user asks to save the latest review, update that file in place with a new round-aware delta review unless the user explicitly asks for a separate file.
- Keep the report self-contained.
- After writing, run:

```bash
python3 scripts/validate_line_links.py <review-file> [<review-file> ...]
```

- Fix any out-of-range or missing targets before closing.

## Reporting Tips by Doc Type

- Implementation guide:
  Use focus checks for intra-doc consistency, producer/carrier/consumer trace for new fields, command/CLI consistency, git/artifact operability, upstream gate/status truthfulness, and whether the migration starts from the code that exists.
- Strategy:
  Use focus checks for API assumptions, architecture realism, domain coverage, phase sequencing, and whether the roadmap starts from the code that exists.
- Memory:
  Use focus checks for schema correctness, privacy/isolation, SQL validity, storage/backend claims, and operational prerequisites.
- UX/API:
  Use focus checks for contract realism, request/response drift, schema duplication, resume/error claims, and sample output integrity.
- Infrastructure:
  Use focus checks for project-structure drift, scripts and config realism, storage/auth/deploy prerequisites, and stale pricing/quota claims.
- Long-lived agent plans:
  Use focus checks for baseline assumptions, prerequisite systems, migration usefulness, checkpoint/job realism, and evaluation/self-improvement claims.

## References

- Read [references/rubric-patterns.md](references/rubric-patterns.md) when you want doc-type focus checks, common failure modes, and gap-recovery ideas.
- Use `scripts/validate_line_links.py` to check saved markdown references deterministically.
