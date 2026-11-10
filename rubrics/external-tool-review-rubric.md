# External Tool Cross-Model Review Rubric

**Used By**: External tool adapters (Codex CLI, Gemini CLI, Claude) acting as adversarial reviewers
**Purpose**: Evaluate code changes produced by a different AI model against the task spec
**Version**: 1.0

---

## Overview

This rubric is used when one AI model reviews code written by a different AI model.
The reviewer has no shared context with the writer — it sees only the diff, spec, and
this rubric. The reviewer must be adversarial: assume nothing works until proven otherwise.

## Verdict

Every cross-model review produces exactly one verdict:

| Verdict | Meaning | Criteria |
| --- | --- | --- |
| **PASS** | Code meets the spec | Zero `blocker: yes` findings |
| **FAIL** | Code does not meet the spec | At least one `blocker: yes` finding |

FAIL if and only if there is at least one `blocker: yes` finding. Findings with `blocker: no` (minor, nit, or advisory critical/major) are reported but never cause FAIL.

## Finding Contract

The policy, the finding contract and the iteration rule live in `guides/delivery-scope.md` (plugin root; `../guides/delivery-scope.md` from a skill's `rubrics/` dir). Every finding carries six fields:

```text
- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty
```

Signal fields (see "Signal fields" in the guide) are added to the six core fields. Every finding carries `theme`; each `blocker: yes` finding also carries `needs_user`, `origin` and, when the origin is an assumption, `assumption`:

```text
- theme: <short label>       # on every finding; reuse an earlier theme label when one fits
- needs_user: yes | no       # blockers only: yes only if just the user can answer it
- origin: implementation | requirement | assumption   # blockers only
- assumption: <ledger id such as A3, or a quoted decision>   # required when origin is assumption
```

Do not mark a question `needs_user` when the design's Confirmed section already answers it.

- **`protects:` is required for critical and major findings.** It names the credible user scenario, explicit requirement or DoD item the finding protects.
- **Blocker definition.** A finding is a blocker (`blocker: yes`) only if its severity is critical or major AND `protects` is non-empty. Minor and nit findings are never blockers.
- **Unjustified findings are advisory.** A critical or major finding that cannot name what it protects is advisory, not a blocker. It becomes a follow-up and does not cause FAIL.
- **Mapping from the checklist below.** The checklist keeps its wording and is read as:
  - "BLOCKING if …" checks produce critical or major findings. They block only with `protects`. An unmet acceptance criterion or broken functionality reads the same way.
  - "WARNING" checks produce minor findings. Style issues and non-critical concerns are minor or nit.
- **The reviewer reports; the orchestrator decides.** Whether a FAIL leads to another round, an advance or an escalation is decided by the orchestrator using the iteration rule in the guide, not by the reviewer.

## Review Checklist

The reviewer MUST check each of these against the spec:

### 1. Acceptance Criteria Coverage
- [ ] Every acceptance criterion in the spec has corresponding code
- [ ] No criterion is partially implemented or stubbed out

### 2. Functional Correctness
- [ ] Logic handles the stated requirements
- [ ] Edge cases mentioned in the spec are handled
- [ ] Error paths produce reasonable behavior (not crashes or silent failures)

### 3. Test Coverage
- [ ] Tests exist for the new/changed functionality
- [ ] Tests actually assert the acceptance criteria (not just smoke tests)
- [ ] Tests would fail if the implementation were removed (not tautological)

### 4. Scope Discipline
- [ ] Changes are limited to what the spec requires (no gold-plating)
- [ ] No unrelated refactoring or formatting changes
- [ ] No new dependencies added without justification in the spec

### 5. Security (BLOCKING if violated)
- [ ] No hardcoded secrets, credentials, or API keys
- [ ] No command injection, SQL injection, or XSS vectors
- [ ] No unsafe file operations (path traversal, world-writable files)

## Evidence Requirements

Every finding, whatever its severity, MUST include the six contract fields:
- **title**: a short label (about 80 characters or fewer) naming the finding
- **description**: 1-3 sentences on what is wrong and why it matters
- **severity**: critical | major | minor | nit
- **protects**: the acceptance criterion (quoted), explicit requirement or credible user scenario it protects; required for critical/major
- **evidence**: file and line reference (`src/auth/login.ts:42`) and what is wrong, as expected-vs-found
- **blocker**: yes | no (yes only for critical/major with `protects`)

Signal fields: **theme** on every finding; on each blocker also **needs_user** (yes | no), **origin** (implementation | requirement | assumption) and, for an assumption, **assumption** (a ledger id such as A3, or a quoted decision).

## Output Format

The reviewer should produce output in this format:

```markdown
## Cross-Model Review: [task-id]

### Verdict: PASS | FAIL

### Acceptance Criteria Verification
| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | [criterion text] | PASS/FAIL | [file:line reference] |

FAIL only if at least one finding below has `blocker: yes`.

### Findings
1. - title: <short label, ≤ ~80 chars>
   - description: <1-3 sentences: what is wrong and why it matters>
   - severity: critical | major | minor | nit
   - protects: "[quoted criterion]" (required for critical/major)
   - evidence: `file:line` — expected [X], found [Y]
   - blocker: yes | no
   - theme: <short label>
   - needs_user: yes | no   (blockers only)
   - origin: implementation | requirement | assumption   (blockers only)
   - assumption: <ledger id such as A3, or a quoted decision>   (when origin is assumption)
```
