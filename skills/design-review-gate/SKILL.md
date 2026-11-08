---
name: design-review-gate
description: Automatic review gate that runs when brainstorming commits a project-sized design doc - spawns PM, Architect, Designer, Security, UX Reviewer and CTO agents in parallel, iterates under the severity rule until all approve or it escalates
auto_activate: true
triggers:
  - "project-sized design doc committed (docs/plans/*-design.md or docs/superpowers/specs/*-design.md)"
---

# Design Review Gate

## Purpose

This skill automatically activates when brainstorming writes and commits a project-sized design doc (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md)). It ensures complex features receive proper review before implementation begins by spawning six specialist reviewers:

1. **Product Manager Agent** - Use case validation and user benefit review
2. **Architect Agent** - Technical architecture review
3. **Designer Agent** - UX/API design quality review
4. **Security Design Agent** - Security threat modeling and protection review
5. **UX Reviewer Agent** - User flows, UI states (empty, loading, error) and integration wiring review
6. **CTO Agent** - Codebase alignment and TDD readiness review

All six must approve before proceeding to implementation.

---

## Coordination Mode Note

This skill supports both coordination modes:

- **Task Mode** (default): Spawn 6 parallel `Task()` subagents for each review round, each with role type `roleType("design-reviewer")`. Fresh instances per round. Role types are resolved per [Role type resolution](./guides/agent-coordination.md#role-type-resolution).
- **Team Mode**: `TeamCreate("review-{design-doc-name}")`, spawn 6 reviewers as named teammates (`pm`, `architect`, `designer`, `security`, `ux`, `cto`), each using the `roleType("design-reviewer")` type with the role in its prompt. Reviewers retain context through revision cycles — saves 6 cold starts per re-review round. After approval, send `shutdown_request` to all, then `TeamDelete`.

In either mode, the review criteria, the severity rule (see Phase 3), and escalation rules are identical. See `./guides/agent-coordination.md` for mode detection.

---

## Activation Triggers

This skill auto-activates when:

1. A project-sized design doc is committed to `docs/plans/*-design.md` or `docs/superpowers/specs/*-design.md` (see [`./guides/workflow-enforcement.md`](./guides/workflow-enforcement.md))
2. User explicitly requests: `/review-design <path-to-design.md>`

---

## Workflow

### Phase 1: Spawn Review Agents (Parallel)

```typescript
// Spawn all six agents in parallel for efficiency.
// Every reviewer uses the design-reviewer role type; the role (PM, Architect, ...) lives in the prompt.
const [pmResult, architectResult, designerResult, securityResult, uxResult, ctoResult] = await Promise.all([
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "PM review",
    prompt: pmReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "Architect review",
    prompt: architectReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "Designer review",
    prompt: designerReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "Security design review",
    prompt: securityDesignReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "UX review",
    prompt: uxReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: roleType("design-reviewer"),
    description: "CTO review",
    prompt: ctoReviewPrompt(designDocPath),
  }),
]);
```

### Phase 2: Aggregate Results

Each agent returns a structured review. Every finding uses the 6-field contract from [`./guides/delivery-scope.md`](./guides/delivery-scope.md):

```typescript
interface Finding {
  title: string; // short label, ≤ ~80 chars
  description: string; // 1-3 sentences: what is wrong and why it matters
  severity: "critical" | "major" | "minor" | "nit";
  protects: string; // credible user scenario | explicit requirement | DoD item; required for critical/major
  evidence: string; // design doc section, file:line, or expected-vs-found
  blocker: "yes" | "no"; // yes only if severity ∈ {critical, major} AND protects is non-empty
}

interface ReviewResult {
  agent: "product-manager" | "architect" | "designer" | "security-design" | "ux-reviewer" | "cto";
  verdict: "APPROVED" | "NEEDS_REVISION"; // NEEDS_REVISION only with at least one blocker: "yes" finding
  findings: Finding[]; // every finding, any severity
  suggestions: string[]; // Non-finding notes
  questions: string[]; // Clarifications needed
  use_case_analysis?: {
    // PM agent only
    total_use_cases: number;
    clear: number;
    needs_work: number;
    missing_scenarios: string[];
  };
  threat_model?: {
    // Security agent only
    high_risk: string[];
    medium_risk: string[];
    mitigations_required: string[];
  };
}
```

A NEEDS_REVISION without any `blocker: yes` finding is read as APPROVED, and its findings become follow-ups. A NEEDS_REVISION whose findings lack the 6 fields is re-requested once in the contract format, then escalated with the raw output. It is never treated as APPROVED.

### Phase 3: Check Gate

The orchestrator, not the reviewers, decides what happens after each round. It applies the severity rule from [`./guides/delivery-scope.md`](./guides/delivery-scope.md): `SAFETY_CAP` = 10 rounds per gate occurrence, and the first line that matches wins. "Re-validate" here means revising the design document; "FRESH review" means re-running all six reviewers.

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

- **PASS, advance**: all six agents are APPROVED (no `blocker: yes` finding). Proceed to implementation and create the epic with the approved design. Line 5's downgrade-and-advance counts the same, with the downgraded items listed as follow-ups.
- **Iterate**: consolidate the blockers, present them to the user, revise the design, and re-run the gate.
- **Overengineering check (line 5).** Signals include repeated review/fix cycles without a new user-visible risk, and blockers that protect only theoretical states. Restate the design's goals and DoD, re-classify each open blocker, and escalate only if one still names a credible scenario.
- **Rounds.** Every re-review is one round. In Team Mode the persistent reviewers re-review, and that still counts as a round.

**Follow-ups.** Minor/nit findings never block. When `bd` is available, file each as a BEADS task (`bd create --type task`), linked to the epic if one exists. Otherwise, or if `bd create` fails, list them under a `### Follow-ups` heading in the gate output.

### Phase 4: Human Escalation

When the severity rule says escalate (line 2, 3 or 5), present the escalation report in [Escalation](#escalation) and ask the human to decide: revise, narrow scope, defer or cancel. Escalation never approves (see `./guides/delivery-scope.md`): a revised or narrowed design gets a fresh review round and passes only by that round.

---

## Agent Prompts

### Shared Finding Rules (inserted into every prompt)

Every persona prompt below contains `${sharedFindingRules}`, which the orchestrator replaces with this block:

````markdown
## Findings

Use your persona checklist for criteria only. Report every finding with the 6 fields defined in `./guides/delivery-scope.md`:

- title: <short label, ≤ ~80 chars>
- description: <1-3 sentences: what is wrong and why it matters>
- severity: critical | major | minor | nit
- protects: <credible user scenario | explicit requirement | DoD item>   # required for critical/major
- evidence: <file:line or expected-vs-found>
- blocker: yes | no      # yes only if severity ∈ {critical, major} AND protects is non-empty

Rules:

- `protects:` is required for critical and major findings. A critical or major finding without `protects` is advisory (`blocker: no`).
- Verdict: NEEDS_REVISION only if at least one finding has `blocker: yes`; otherwise APPROVED.
- Minor/nit findings are recorded as follow-ups, not blockers. Put notes that are not findings in `suggestions` and `questions`.
````

### Product Manager Agent Prompt

````markdown
You are the PRODUCT MANAGER AGENT reviewing a design document.

## Your Task

Review this design for use case clarity and user benefit validation.

## Design Document

<path>: {designDocPath}

## Review Criteria

### 1. Use Case Validation

- [ ] Each use case follows WHO/WANTS/SO THAT/WHEN format
- [ ] User personas are clearly defined
- [ ] Use cases are realistic and based on user needs
- [ ] Edge cases and error scenarios considered from user perspective

### 2. User Benefit Review

- [ ] Value proposition clearly articulated
- [ ] Benefits are measurable (time saved, success rate, etc.)
- [ ] User journey impact understood
- [ ] Improvement is significant enough to build

### 3. Scope Assessment

- [ ] MVP clearly defined (must have vs nice to have)
- [ ] No feature creep detected
- [ ] Scope matches user needs, not technical possibilities
- [ ] "Solution looking for problem" anti-pattern avoided

### 4. Success Criteria

- [ ] Success metrics are user-focused (not just technical)
- [ ] Metrics are measurable and have thresholds
- [ ] Evaluation timeline defined
- [ ] Failure criteria also defined

${sharedFindingRules}

## Output Format

Return JSON:

```json
{
  "agent": "product-manager",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "use_case_analysis": {
    "total_use_cases": <number>,
    "clear": <number>,
    "needs_work": <number>,
    "missing_scenarios": ["list of gaps"]
  },
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["notes that are not findings"],
  "questions": ["clarifications needed"]
}
```
````

### Architect Agent Prompt

````markdown
You are the ARCHITECT AGENT reviewing a design document.

## Your Task
Review this design for technical architecture soundness.

## Design Document
<path>: {designDocPath}

## Review Criteria

### 1. Service Architecture
- [ ] Follows existing codebase patterns
- [ ] Service placement is correct
- [ ] Dependencies flow correctly (no circular deps)
- [ ] Naming conventions followed

### 2. Technical Correctness
- [ ] API contracts well-defined
- [ ] Database operations are correct (if applicable)
- [ ] Error handling is complete
- [ ] Performance considerations addressed

### 3. Integration Points
- [ ] Integrates cleanly with existing services
- [ ] No duplicate functionality (check docs/SERVICE_INVENTORY.md)
- [ ] Proper abstraction boundaries

${sharedFindingRules}

## Output Format

Return JSON:
```json
{
  "agent": "architect",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["notes that are not findings"],
  "questions": ["clarifications needed"]
}
```
````

### Designer Agent Prompt

````markdown
You are the DESIGNER AGENT reviewing a design document.

## Your Task
Review this design for UX, API design, and developer experience.

## Design Document
<path>: {designDocPath}

## Review Criteria

### 1. API/Interface Design
- [ ] APIs are intuitive and consistent with existing patterns
- [ ] Parameter names are clear and predictable
- [ ] Return types are well-structured
- [ ] Error responses are helpful (not cryptic)

### 2. User Experience (if applicable)
- [ ] User flows are logical and efficient
- [ ] Edge cases handled gracefully
- [ ] Error states provide actionable guidance
- [ ] Loading/progress states considered

### 3. Developer Experience
- [ ] Types are well-designed and reusable
- [ ] Interfaces are easy to implement against
- [ ] Mocking is straightforward
- [ ] Documentation is complete

### 4. Consistency
- [ ] Follows existing codebase conventions
- [ ] Similar to how other features work
- [ ] Naming is consistent with codebase

${sharedFindingRules}

## Output Format

Return JSON:
```json
{
  "agent": "designer",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["notes that are not findings"],
  "questions": ["clarifications needed"]
}
```
````

### Security Design Agent Prompt

````markdown
You are the SECURITY DESIGN AGENT reviewing a design document.

## Your Task
Review this design for security vulnerabilities BEFORE code is written.

## Design Document
<path>: {designDocPath}

## Review Criteria

### 1. Authentication & Authorization
- [ ] User identity verified at every entry point
- [ ] Authorization checked for each resource access
- [ ] No user can access other users' data
- [ ] Session management is secure

### 2. Data Protection
- [ ] Sensitive data identified and protected
- [ ] PII encrypted at rest and in transit
- [ ] No secrets in logs or error messages
- [ ] Data leakage vectors closed

### 3. Input Validation
- [ ] ALL inputs validated server-side
- [ ] No SQL injection vectors
- [ ] No XSS vectors
- [ ] Safe file upload handling (if applicable)

### 4. API Security
- [ ] Rate limits defined
- [ ] Brute force protection
- [ ] Error messages don't leak information
- [ ] No IDOR (Insecure Direct Object Reference) risks

### 5. OWASP Top 10 Check
- [ ] A01: Broken Access Control
- [ ] A02: Cryptographic Failures
- [ ] A03: Injection
- [ ] A04: Insecure Design
- [ ] A07: Auth Failures

## Required Context
BEFORE reviewing, consider:
- docs/ARCHITECTURE_CURRENT.md (security patterns)
- Existing auth flows in codebase
- OWASP guidelines

${sharedFindingRules}

## Output Format

Return JSON:
```json
{
  "agent": "security-design",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "threat_model": {
    "high_risk": ["components with critical risk"],
    "medium_risk": ["components with moderate risk"],
    "mitigations_required": ["security controls needed"]
  },
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["security notes that are not findings"],
  "questions": ["security clarifications needed"]
}
```
````

### UX Reviewer Agent Prompt

````markdown
You are the UX REVIEWER AGENT reviewing a design document.

## Your Task
Review this design for user flow completeness and integration: can a user actually do what the design describes once every work unit is built?

Read and follow `./rubrics/ux-review-rubric.md`: it is the single source of the UX criteria and their BLOCKING/WARNING levels. Your persona brief is `agents/ux-reviewer-agent.md` in the metaswarm plugin. The checklist below summarises the rubric.

**Backend-only designs:** if the design has no user-facing UI (no screens, pages, views or interactive components), return APPROVED with no findings and the suggestion "No user-facing UI in this design; UX review not applicable." Do not block backend-only designs.

## Design Document
<path>: {designDocPath}

## Review Criteria

### 1. User Flows
- [ ] Every user flow has a clear trigger (what the user does) and a visible outcome (what the user sees change)
- [ ] The design has a UI-FLOWS section with text wireframes (see the metaswarm plugin's `templates/UI-FLOWS.md`)

### 2. Screens and Components
- [ ] Every screen is described with a component hierarchy (what renders what, where)

### 3. UI States
- [ ] Empty, loading and error states are defined for each view
- [ ] Error states tell the user what happened and what to do next

### 4. Integration
- [ ] There is an explicit integration work unit that wires the components into the app shell (routes, layout, data/state hooks), not only component work units
- [ ] Each user flow can be traced from the app shell to the components and data it uses

### 5. Accessibility Basics
- [ ] Interactive elements are keyboard reachable, inputs are labelled, state is not conveyed by color alone (minor unless the design names an accessibility requirement)

${sharedFindingRules}

## Output Format

Return JSON:
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
````

### CTO Agent Prompt

````markdown
You are the CTO AGENT reviewing a design document.

## Your Task
Review this design for TDD readiness and codebase alignment.

## Design Document
<path>: {designDocPath}

## Review Criteria

### 1. TDD Readiness (CRITICAL)
- [ ] Test specifications are present
- [ ] RED-GREEN-REFACTOR cycles documented
- [ ] Edge cases enumerated per method
- [ ] Mock infrastructure specified
- [ ] Integration test helpers defined

### 2. Codebase Alignment
- [ ] Follows CLAUDE.md guidelines
- [ ] Aligns with docs/ARCHITECTURE_CURRENT.md
- [ ] No conflicts with existing services
- [ ] Security considerations addressed

### 3. Completeness
- [ ] All requirements addressed
- [ ] Success criteria are measurable
- [ ] Implementation phases are clear
- [ ] Acceptance criteria defined

### 4. Risk Assessment
- [ ] Risks identified with mitigations
- [ ] Dependencies documented
- [ ] Breaking changes flagged (if any)

## Required Context Files
BEFORE reviewing, read:
- docs/BACKEND_SERVICE_GUIDE.md
- docs/TESTING_GUIDE.md
- templates/task-completion-checklist.md

${sharedFindingRules}

## Output Format

Return JSON:
```json
{
  "agent": "cto",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "findings": [
    { "title": "<short label, ≤ ~80 chars>", "description": "<1-3 sentences: what is wrong and why it matters>", "severity": "critical|major|minor|nit", "protects": "<credible user scenario | explicit requirement | DoD item>", "evidence": "<design doc section: expected-vs-found>", "blocker": "yes|no" }
  ],
  "suggestions": ["notes that are not findings"],
  "questions": ["clarifications needed"]
}
```
````

---

## Iteration Protocol

### Round 1: Initial Review

1. Spawn all six agents in parallel (role type `roleType("design-reviewer")`)
2. Wait for all results
3. Apply the severity rule (Phase 3): if no agent reports a `blocker: yes` finding → proceed
4. If any `blocker: yes` finding → consolidate (see [Needs Revision](#needs-revision)) and present

### Later Rounds: Revision Cycles

1. Present consolidated blockers to the human
2. Human revises the design document
3. Re-run all six agents on the updated doc (a new round)
4. Apply the severity rule again: advance, iterate, or escalate

### Escalation

When the severity rule says escalate (cap hit, a recurring or disputed blocker, or a blocker that survives the overengineering check):

```markdown
## Review Escalation: Design Review Gate — <design doc>

**Rule line**: <2 cap hit | 3 recurring/disputed | 5 overengineering signal>

### Remaining findings
- **Critical**: [Security Design] <title>: <description> — protects: <...> — evidence: <...>
- **Major**: [Architect] <title>: <description> — protects: <...> — evidence: <...>
- **Major**: [CTO] <title>: <description> — protects: <...> — evidence: <...>
- **Minor**: [Designer] <title> (follow-up filed)
- **Nit**: [CTO] <title> (follow-up filed)

### Round history
| Round | Verdicts (APPROVED / NEEDS_REVISION) | Blockers (critical/major) | Fixed this round | Rule decision |
|-------|--------------------------------------|---------------------------|------------------|---------------|
| 1     | 3 / 3                                | 1 / 4                     | —                | 4: iterate    |
| 2     | 5 / 1                                | 0 / 2                     | 1 / 2            | 4: iterate    |
| 3     | 5 / 1                                | 0 / 2                     | 0 / 0            | 3: escalate   |

### Follow-ups
- <minor/nit findings, or the BEADS task IDs filed for them>

### Options
1. **Revise** — fix the remaining blockers (or the requirement they protect), then run a fresh review round
2. **Narrow scope** — move the contentious items to a new issue, then run a fresh review round on what remains
3. **Defer** — shelve this work for later; nothing advances
4. **Cancel** — abandon this work

**Recommendation**: <revise|narrow scope|defer|cancel> — <reason from the rule>
```

---

## Integration with Task Tracking

When design is approved:

```bash
# Create epic linked to design doc
# Use your project's task tracking system to create an epic and implementation phase tasks
# Example:
# task-cli create "<feature-name>" --type epic
# task-cli create "Phase 1: Infrastructure" --type task --parent <epic-id>
# task-cli create "Phase 2: Backend" --type task --parent <epic-id>
# task-cli create "Phase 3: Frontend" --type task --parent <epic-id>
# task-cli create "Phase 4: Polish" --type task --parent <epic-id>
```

---

## Output Format

### Approved Design

```markdown
## Design Review Gate: APPROVED

All six reviewers have approved the design.

| Agent           | Verdict  | Blockers | Minor/Nit | Suggestions |
| --------------- | -------- | -------- | --------- | ----------- |
| Product Manager | APPROVED | 0        | 0         | 1           |
| Architect       | APPROVED | 0        | 1         | 2           |
| Designer        | APPROVED | 0        | 0         | 1           |
| Security Design | APPROVED | 0        | 1         | 2           |
| UX Reviewer     | APPROVED | 0        | 0         | 1           |
| CTO             | APPROVED | 0        | 0         | 3           |

### Threat Model Summary (Security Agent)

- **High Risk**: None identified
- **Medium Risk**: AI-generated content could be manipulated
- **Mitigations**: Defense in depth already designed

### Suggestions (Non-Blocking)

1. [Architect] Consider adding caching layer for frequent queries
2. [Designer] Add loading skeleton to improve perceived performance
3. [Security] Add audit logging for all assistant actions
4. [Security] Consider anomaly detection for unusual query patterns
5. [CTO] Document rate limit headers in API response

### Follow-ups

- [Architect] minor: <title> (bd-123)
- [Security Design] minor: <title> (bd-124)

### Next Steps

1. Create epic for implementation
2. Set up worktree with `superpowers:using-git-worktrees`
3. Begin Phase 1 implementation

Ready to proceed with implementation? [Yes/No]
```

### Needs Revision

```markdown
## Design Review Gate: NEEDS REVISION (round 1)

One or more reviewers reported a `blocker: yes` finding.

| Agent           | Verdict        | Blockers (critical/major) | Minor/Nit |
| --------------- | -------------- | ------------------------- | --------- |
| Product Manager | APPROVED       | 0 / 0                     | 1         |
| Architect       | APPROVED       | 0 / 0                     | 2         |
| Designer        | NEEDS_REVISION | 0 / 2                     | 1         |
| Security Design | NEEDS_REVISION | 1 / 1                     | 1         |
| UX Reviewer     | APPROVED       | 0 / 0                     | 0         |
| CTO             | NEEDS_REVISION | 0 / 2                     | 1         |

### Blockers (MUST FIX)

#### Critical

1. [Security Design] **userId trust boundary** - Design shows userId passed to tools, but userId MUST come from server session only. Model could be jailbroken to output arbitrary userIds. — protects: no user can access other users' data — evidence: design §Tools passes `userId` from model output

#### Major

1. [Designer] **Missing error states** - The design doesn't specify what happens when search returns 0 results — protects: the search happy path's empty result — evidence: §Search has no empty state
2. [Designer] **Inconsistent API naming** - `get_contact_details` uses underscore but existing APIs use camelCase — protects: requirement "match existing API conventions" — evidence: §API vs. existing `getContact`
3. [Security Design] **Missing rate limits** - AI endpoints are expensive and must have rate limiting to prevent abuse — protects: credible abuse of a paid endpoint in normal use — evidence: §API has no rate limit
4. [CTO] **Missing TDD specs** - No RED-GREEN-REFACTOR cycles documented — protects: DoD "TDD specs present" — evidence: no Test Plan section
5. [CTO] **Missing edge cases** - Need systematic enumeration per method — protects: DoD "edge cases enumerated" — evidence: §Methods

### Follow-ups

- [Architect] minor: <title> (bd-125)
- [Designer] nit: <title> (bd-126)
- [Security Design] minor: <title> (bd-127)
- [CTO] minor: **Missing mock infrastructure** - No beforeEach/afterEach setup specified (bd-128)

### Threat Model (Security Agent)

- **High Risk**: User can potentially access other users' contacts via prompt injection
- **Medium Risk**: Rate limiting not defined for AI endpoints
- **Mitigations Required**: userId from session only, add rate limiting

### Questions Requiring Clarification

1. [CTO] What's the max conversation history size?
2. [Designer] What happens when user clicks "View More"?
3. [Security Design] How will location data be protected? Is it PII?

---

**Round**: 1 (cap 10)
**Rule decision**: 4: iterate — ≥2 independent reviewers reported blockers
**Action Required**: Please revise the design document to address every blocker above.
```

---

## Success Criteria

The design review gate succeeds when:

- [ ] All six agents return APPROVED verdict (or rule line 5 downgraded every remaining blocker to a follow-up)
- [ ] Every `blocker: yes` finding is resolved; minor/nit findings are filed as follow-ups
- [ ] All clarifying questions are answered
- [ ] Design document is updated with revisions
- [ ] Security threat model reviewed and mitigations in place
- [ ] Epic is created (or ready to create)

---

## Related Skills

- `superpowers:brainstorming` - Triggers this gate when it commits a project-sized design doc
- `superpowers:writing-plans` - Used after gate approval for detailed implementation plan

---

## Agent Definitions

See detailed agent definitions in your project's agent definition files (e.g., product-manager-agent.md, architect-agent.md, designer-agent.md, security-design-agent.md, ux-reviewer-agent.md, cto-agent.md). The UX Reviewer's persona is ux-reviewer-agent.md, and its criteria live in `./rubrics/ux-review-rubric.md`.
