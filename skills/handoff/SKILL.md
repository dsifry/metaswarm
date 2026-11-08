---
name: handoff
description: Analyze the current session and write a self-contained handoff document so a fresh agent can resume the work with full context — outputs a single "Read XXX.md and do YYY." sentence
---

# Handoff Skill

Capture everything a **fresh agent with zero prior context** needs to resume the current work, write it to a single self-contained markdown document, and hand it off with one unambiguous sentence:

> **Read `docs/handoffs/<file>.md` and do `<the next concrete action>`.**

Use this when a session is ending, when context is about to be compacted, when you are switching machines or sessions, or when the user explicitly asks for a handoff. The goal is **zero context loss**: the receiving agent should be able to act correctly after reading exactly one file.

---

## Output Contract

This skill produces exactly two things:

1. **A handoff document** at `docs/handoffs/handoff-<YYYY-MM-DD-HHmm>.md` (created if the directory does not exist). It is comprehensive, self-contained, and links to — or quotes — every artifact the next agent must read.
2. **A single closing sentence**, and nothing else after the document is written, of the exact form:

   ```text
   Read docs/handoffs/handoff-2026-06-17-1432.md and do <YYY>.
   ```

   Where `<YYY>` is one concrete, actionable next step (an imperative, not a vague theme). Good: "implement the `parseConfig` validation in `src/config.ts:84` and make `tests/config.test.ts` pass". Bad: "continue the work" / "look into the config stuff".

The sentence is the deliverable the user hands to the next agent. The document is what makes that sentence safe to follow.

---

## Method

### Step 1 — Reconstruct what we are working on

Review the session to date and answer, concretely:

- **Objective**: What is the user actually trying to accomplish? State it in one or two sentences.
- **Definition of Done**: What does "finished" look like? Enumerate verifiable acceptance criteria if any exist.
- **Why**: The motivation/problem behind the task, so the next agent does not re-litigate settled decisions.

Pull from: the user's original request, any GitHub Issue (`gh issue view <n>`), the design/plan docs, and the arc of the conversation.

### Step 2 — Load any persisted metaswarm state

If this project uses metaswarm's context persistence, read and fold in whatever exists — do **not** duplicate it blindly, summarize and link:

```bash
ls .beads/plans/active-plan.md            # the approved plan (if mid-execution)
ls .beads/context/project-context.md      # completed work units, patterns, tooling
ls .beads/context/execution-state.md      # current work unit, phase, VALIDATE attempts, review round
```

Recovery order for the next agent: if bd is installed, `bd prime` (bd context); then read `.beads/plans/active-plan.md` and `.beads/context/*.md`; then `/prime` for knowledge.

If an active plan exists, the handoff must point to it explicitly and state which work unit/phase is in progress.

### Step 3 — Establish current status

Be honest and specific about state. Distinguish clearly between:

- **Done & verified** — with evidence (tests passing, build green, commit SHAs).
- **Done but unverified** — written but not yet tested/run.
- **In progress** — the exact thing being worked on right now, and where it stopped.
- **Not started** — remaining work.

Capture the working tree reality so the next agent is not surprised:

```bash
git branch --show-current
git status --short
git log --oneline -10
git diff --stat
```

Note uncommitted changes, stashes, and whether the branch is pushed.

### Step 4 — Identify required reading

List every artifact the next agent must read **before acting**, and for each one say *why* and *what to look for*. Categories to sweep:

- **Specs / Issues** — the requirements source of truth (GitHub Issue, spec section, DoD).
- **Design docs** — `docs/plans/*-design.md`, `docs/superpowers/specs/*-design.md`, and any approved design.
- **Plans** — `.beads/plans/active-plan.md`, `docs/plans/*-plan.md`.
- **Code** — the specific files and `file:line` anchors that are the focus of the work, plus any pattern files to imitate.
- **Tests** — the tests that define correctness (failing tests are the spec under TDD).
- **Config / gates** — `.coverage-thresholds.json`, CLAUDE.md rules, CI config that the change must satisfy.

Prefer precise pointers (`src/foo.ts:120-145`) over whole-file references. If something is short and load-bearing, quote it directly into the handoff so the next agent does not have to hunt.

### Step 5 — Decide the single next action (`YYY`)

Pick the one most important, concrete next step. It must be:

- **Actionable** — an imperative the agent can start immediately.
- **Specific** — names files, functions, or DoD items.
- **Bounded** — the immediate next move, not the entire remaining roadmap (the rest goes in the document's "Remaining work" section).

### Step 6 — Write the document

Create `docs/handoffs/handoff-<YYYY-MM-DD-HHmm>.md` using the template below. Fill every section; write "None" where a section genuinely does not apply rather than deleting it.

### Step 7 — Emit the handoff sentence

After writing the file, verify it (Step 8), then output the single sentence — exactly one line, the literal file path, and the concrete action. Do not add commentary after it.

### Step 8 — Self-check before handing off

Confirm, as if you were the receiving agent who knows nothing:

- [ ] Could I start work from this document alone, without the prior conversation?
- [ ] Are all referenced files/paths/issues real and correct (spot-check with `ls`/`git`)?
- [ ] Is the next action unambiguous and immediately startable?
- [ ] Are decisions and their rationale captured so I won't undo them?
- [ ] Are the quality gates (tests, coverage, lint, build commands) stated?
- [ ] Does the closing sentence name the exact file and a concrete action?

---

## Handoff Document Template

````markdown
# Handoff: <short title of the work>

**Date**: <YYYY-MM-DD HH:mm> · **Branch**: `<branch>` · **Author session**: <model/agent>

## 1. Objective
<1–2 sentences: what we are trying to accomplish and why.>

## 2. Definition of Done
- [ ] <verifiable acceptance criterion>
- [ ] <…>

## 3. Current Status
**Done & verified:**
- <item> (evidence: <tests/commit>)

**Done, not yet verified:**
- <item>

**In progress (stopped here):**
- <the exact thing being worked on, and where/why it paused>

**Not started:**
- <remaining item>

### Working tree
- Branch `<branch>`, <pushed/not pushed>
- Uncommitted changes: <git status --short summary, or "clean">
- Recent commits:
  - `<sha>` <subject>

## 4. Required Reading (read these before acting)
| # | Path / reference | Why it matters | What to look for |
|---|---|---|---|
| 1 | `<path-or-issue>` | <reason> | <specific thing> |
| 2 | `<path:line>` | <reason> | <specific thing> |

## 5. Key Decisions & Rationale
- **<decision>** — <why; what alternatives were rejected and why>. Do not undo without reason.

## 6. Code Map
- `<file:line>` — <what lives here / its role in this task>
- Pattern to imitate: `<file>` — <why>

## 7. How to Verify
```bash
<test command>           # e.g., npm test
<coverage command>       # reads .coverage-thresholds.json
<lint/build command>
```
Expected: <what green looks like>.

## 8. Open Questions / Blockers
- <question needing the user, or external dependency>  — or "None"

## 9. Next Action
<The single concrete next step — the YYY — expanded with any detail the one-liner can't hold.>

## 10. Remaining Work (after the next action)
1. <subsequent step>
2. <…>
````

---

## Anti-Patterns

1. **Vague next action** — "continue where we left off" is useless. Name the file and the change.
2. **Assuming shared memory** — the next agent has none. If it matters and isn't in the doc, it's lost.
3. **Dumping the transcript** — synthesize. A 40-line oriented summary beats a 4,000-line paste.
4. **Stale pointers** — verify paths and line numbers exist before citing them; code may have moved.
5. **Hiding uncommitted state** — always disclose dirty working tree, stashes, and unpushed commits.
6. **Multiple "final" sentences** — emit exactly one `Read <file> and do <action>.` line.
7. **Silent decision loss** — if a choice was made and settled, record it with rationale so it isn't reopened.

---

## Relationship to Other Metaswarm Pieces

- Complements `/prime` (which loads knowledge **into** a session) by serializing context **out of** a session for the next one.
- For mid-execution work, this skill should reference `.beads/plans/active-plan.md` and `.beads/context/execution-state.md` rather than restating them, so the next agent can follow the recovery order (if bd is installed, `bd prime` for bd context; then read those files; then `/prime` for knowledge) and then read the handoff for the human-readable narrative.
- Run `/self-reflect` separately to capture durable *learnings* into the knowledge base; `/handoff` captures *this task's* transient state to resume it.
