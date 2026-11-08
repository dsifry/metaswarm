# UX Review Rubric

**Used By**: UX Reviewer Agent (Design Review Gate)
**Purpose**: Verify that a design describes user flows a user can actually complete, with every screen, UI state and integration step defined before work unit decomposition
**Version**: 1.0

---

## Overview

This rubric is the single source of the UX Reviewer's criteria. It catches the failure behind issue #12: components built and tested in isolation but never wired into the app, so nobody can actually use the feature. The question it asks is "once every work unit is built, can a user do what the design says?"

**No user-facing UI → APPROVED, if the task needs none.** First check the task or request the design implements. If the design has no user-facing UI and the task doesn't call for any (no screens, pages, views or interactive components; for example a backend service, library or data migration), return APPROVED with no findings and the suggestion "No user-facing UI in this design; UX review not applicable." If the task requires UI but the design omits it, report the missing UI design as a finding that protects the user flow the task asks for. Never block a backend-only design on this rubric.

---

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

- **`protects:` is required for critical and major findings.** It names the credible user scenario, explicit requirement or DoD item the finding protects, for example "a user can add a todo from the main screen".
- **Blocker definition.** A finding is a blocker (`blocker: yes`) only if its severity is critical or major AND `protects` is non-empty. Minor and nit findings are never blockers.
- **Unjustified findings are advisory.** A critical or major finding that cannot name what it protects is advisory, not a blocker. It becomes a follow-up and does not cause NEEDS_REVISION.
- **Mapping from the check tables below.** The tables keep their wording and are read as:
  - "BLOCKING if …" checks produce critical or major findings. They block only with `protects`.
  - "WARNING" checks produce minor findings.
- **Verdict.** NEEDS_REVISION only if at least one finding has `blocker: yes`; otherwise APPROVED.
- **The reviewer reports; the orchestrator decides.** Whether a NEEDS_REVISION leads to another round, an advance or an escalation is decided by the gate's severity rule, not by the reviewer.

---

## Key Reference Documents

| Document | Purpose |
| --- | --- |
| `templates/UI-FLOWS.md` (metaswarm plugin) | Template for screens, text wireframes, user flows and UI states |
| The design document under review | Flows, screens and work units to check |
| Existing app shell (routes, layout, providers) | Where new components must be mounted |

---

## Evaluation Categories

### 1. User Flows

| Check | Level | What to Look For |
| --- | --- | --- |
| Every flow has a trigger | BLOCKING if a described feature has no user action that starts it | "User clicks Add", "User opens /settings" |
| Every flow has a visible outcome | BLOCKING if the user cannot see that the action worked | "Todo appears at the top of the list" |
| Flows cover the stated use cases | BLOCKING if a use case in the design has no flow | Use case ↔ flow mapping |
| Steps name the component that handles them | WARNING | Step table with a Component column |

**Check**: Pick each use case and walk it as a user, trigger to outcome. Can you finish it from the design alone?

---

### 2. Screens and Component Hierarchy

| Check | Level | What to Look For |
| --- | --- | --- |
| Each screen has a component hierarchy or text wireframe | BLOCKING if a screen in a flow is not described | What renders what, and where |
| Each component has a parent on a screen | BLOCKING if a component is designed but never placed | Orphan components |
| Data source per screen is named | WARNING | Hooks, state, queries feeding the screen |

**Check**: For every component the design builds, can you point to the screen and parent that render it?

---

### 3. UI States (per view)

| Check | Level | What to Look For |
| --- | --- | --- |
| Empty state | BLOCKING if a list or data view has no defined empty state | "No todos yet — add one above" |
| Loading state | BLOCKING if a view waits on async data with no defined loading state | Spinner, skeleton, disabled input |
| Error state | BLOCKING if a failure the user can hit has no defined error state | Message plus what to do next |
| Error messages are actionable | WARNING | "Couldn't save. Retry" vs. "Error 500" |

**Check**: For each view, list the empty, loading and error states. Any missing one is a finding.

---

### 4. Integration Wiring

| Check | Level | What to Look For |
| --- | --- | --- |
| The design describes the integration wiring | BLOCKING if components are designed but nothing says how they are wired into the app shell | Routes, layout, providers, data hooks. The design gate runs before work-unit decomposition, so the integration work unit itself is checked at plan review (`plan-review-rubric-adversarial.md`, Completeness) |
| Each flow traces from the app shell to its data | BLOCKING if a flow's path from entry point to data is broken | Route → screen → component → hook → API |
| Placeholder content is replaced | WARNING | "Todo list will appear here" left in the shell |

**Check**: After the last work unit, does the running app show the feature, or only its tests?

---

### 5. UI-FLOWS Section

| Check | Level | What to Look For |
| --- | --- | --- |
| The design has a UI-FLOWS section (or references `templates/UI-FLOWS.md`) | BLOCKING if user-facing UI is designed with no flows section at all | Screens, flows and states in one place |
| Flows map to work units | WARNING | Each flow names the work units that deliver it |

---

### 6. Accessibility Basics

| Check | Level | What to Look For |
| --- | --- | --- |
| Interactive elements are keyboard reachable | WARNING | Tab order, Enter/Space activate |
| Inputs and icon buttons have labels | WARNING | Visible label or accessible name |
| State is not conveyed by color alone | WARNING | Error text, not only a red border |

Accessibility findings are minor unless the design names an accessibility requirement; then a gap that breaks it is BLOCKING with that requirement as `protects`.

---

## Review Checklist

- [ ] Design has user-facing UI (if not, and the task needs none: APPROVED with no findings, and say so in suggestions)
- [ ] Every user flow has a trigger and a visible outcome
- [ ] Every screen has a component hierarchy or text wireframe
- [ ] Empty, loading and error states are defined for each view
- [ ] The design describes the integration wiring into the app shell (the work unit is checked at plan review)
- [ ] A UI-FLOWS section exists
- [ ] Accessibility basics considered

---

## Output Format

Return the gate's JSON (`"agent": "ux-reviewer"`), with every finding in the contract above:

```json
{
  "agent": "ux-reviewer",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["notes that are not findings"],
  "questions": ["clarifications needed"]
}
```

---

## Common Issues

### 1. Components Without a Home
Every component has a work unit and tests, but no work unit mounts them. The app still shows placeholder text. Fix: add an integration work unit that wires them into the app shell.

### 2. Happy Path Only
The flow describes success but not the empty list on first launch, the spinner while loading, or the message when the save fails. Fix: define all three states per view.

### 3. Outcome the User Can't See
"The item is saved" with no visible change. Fix: say what the user sees (item appears, toast, counter updates).
