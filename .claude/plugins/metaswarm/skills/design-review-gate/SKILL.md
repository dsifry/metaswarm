---
name: design-review-gate
description: Automatic review gate that runs after brainstorming completes - spawns PM, Architect, Designer, Security, and CTO agents in parallel, iterates until all approve
auto_activate: true
triggers:
  - "design document created"
  - "docs/plans/*-design.md committed"
  - after:superpowers:brainstorming
---

# Design Review Gate

## Purpose

This skill automatically activates after a design document is created (typically via `superpowers:brainstorming`). It ensures complex features receive proper review before implementation begins by spawning five specialist agents:

1. **Product Manager Agent** - Use case validation and user benefit review
2. **Architect Agent** - Technical architecture review
3. **Designer Agent** - UX/API design quality review
4. **Security Design Agent** - Security threat modeling and protection review
5. **CTO Agent** - Codebase alignment and TDD readiness review

All five must approve before proceeding to implementation.

---

## Coordination Mode Note

This skill supports both coordination modes:

- **Task Mode** (default): Spawn 5 parallel `Task()` subagents for each review round. Fresh instances per round.
- **Team Mode**: `TeamCreate("review-{design-doc-name}")`, spawn 5 reviewers as named teammates (`pm`, `architect`, `designer`, `security`, `cto`). Reviewers retain context through revision cycles — saves 5 cold starts per re-review round. After approval, send `shutdown_request` to all, then `TeamDelete`.

In either mode, the review criteria, iteration protocol, and escalation rules are identical. See `guides/agent-coordination.md` for mode detection.

---

## Activation Triggers

This skill auto-activates when:

1. A design document is committed to `docs/plans/*-design.md`
2. The `superpowers:brainstorming` skill completes
3. User explicitly requests: `/project:review-design <path-to-design.md>`

---

## Workflow

### Phase 1: Spawn Review Agents (Parallel)

```typescript
// Spawn all five agents in parallel for efficiency
const [pmResult, architectResult, designerResult, securityResult, ctoResult] = await Promise.all([
  Task({
    subagent_type: "general-purpose",
    description: "PM review",
    prompt: pmReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Architect review",
    prompt: architectReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Designer review",
    prompt: designerReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "Security design review",
    prompt: securityDesignReviewPrompt(designDocPath),
  }),
  Task({
    subagent_type: "general-purpose",
    description: "CTO review",
    prompt: ctoReviewPrompt(designDocPath),
  }),
]);
```

### Phase 2: Aggregate Results

Each agent returns a structured review:

```typescript
interface ReviewResult {
  agent: "product-manager" | "architect" | "designer" | "security-design" | "cto";
  verdict: "APPROVED" | "NEEDS_REVISION";
  blockers: string[]; // MUST fix before implementation
  suggestions: string[]; // Nice to have
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

### Phase 3: Check Gate

```
IF all five agents return APPROVED:
  → Proceed to implementation
  → Create epic with approved design

ELSE:
  → Consolidate feedback
  → Present to user
  → Iterate on design
  → Re-run gate (max 3 iterations)
```

### Phase 4: Human Escalation

After 3 failed iterations:

1. Create summary of remaining blockers
2. Ask human to decide: override, defer, or cancel

---

## Agent Prompts

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
  "blockers": ["list of MUST fix issues"],
  "suggestions": ["nice to have improvements"],
  "questions": ["clarifications needed"]
}
```
````

````

### Architect Agent Prompt

```markdown
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

## Output Format

Return JSON:
```json
{
  "agent": "architect",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "blockers": ["list of MUST fix issues"],
  "suggestions": ["nice to have improvements"],
  "questions": ["clarifications needed"]
}
````

````

### Designer Agent Prompt

```markdown
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

## Output Format

Return JSON:
```json
{
  "agent": "designer",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "blockers": ["list of MUST fix issues"],
  "suggestions": ["nice to have improvements"],
  "questions": ["clarifications needed"]
}
````

````

### Security Design Agent Prompt

```markdown
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
  "blockers": ["MUST fix security issues"],
  "suggestions": ["nice to have security improvements"],
  "questions": ["security clarifications needed"]
}
````

````

### CTO Agent Prompt

```markdown
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
- .claude/task-completion-checklist.md

## Output Format

Return JSON:
```json
{
  "agent": "cto",
  "verdict": "APPROVED" | "NEEDS_REVISION",
  "blockers": ["list of MUST fix issues"],
  "suggestions": ["nice to have improvements"],
  "questions": ["clarifications needed"]
}
````

````

---

## Iteration Protocol

### Round 1: Initial Review

1. Spawn all five agents in parallel
2. Wait for all results
3. If all APPROVED → proceed
4. If any NEEDS_REVISION → consolidate and present

### Rounds 2-3: Revision Cycles

1. Present consolidated feedback to human
2. Human revises design document
3. Re-run all five agents on updated doc
4. Repeat until all approve

### Round 4: Escalation

If still not approved after 3 iterations:

```markdown
## Design Review Gate: Escalation Required

After 3 review cycles, the following blockers remain unresolved:

### Architect Agent
- [blocker 1]
- [blocker 2]

### Designer Agent
- [blocker 1]

### CTO Agent
- [blocker 1]
- [blocker 2]

### Options
1. **Override** - Proceed anyway (document technical debt)
2. **Defer** - Shelve this feature for later
3. **Revise** - Continue iterating on design
4. **Cancel** - Abandon this feature

Please choose an option or provide additional context.
````

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

All five reviewers have approved the design.

| Agent           | Verdict  | Blockers | Suggestions |
| --------------- | -------- | -------- | ----------- |
| Product Manager | APPROVED | 0        | 1           |
| Architect       | APPROVED | 0        | 2           |
| Designer        | APPROVED | 0        | 1           |
| Security Design | APPROVED | 0        | 2           |
| CTO             | APPROVED | 0        | 3           |

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

### Next Steps

1. Create epic for implementation
2. Set up worktree with `superpowers:using-git-worktrees`
3. Begin Phase 1 implementation

Ready to proceed with implementation? [Yes/No]
```

### Needs Revision

```markdown
## Design Review Gate: NEEDS REVISION

One or more reviewers found blocking issues.

| Agent           | Verdict        | Blockers | Suggestions |
| --------------- | -------------- | -------- | ----------- |
| Architect       | APPROVED       | 0        | 2           |
| Designer        | NEEDS_REVISION | 2        | 1           |
| Security Design | NEEDS_REVISION | 2        | 1           |
| CTO             | NEEDS_REVISION | 3        | 0           |

### Blocking Issues (MUST FIX)

#### Designer Agent

1. **Missing error states** - The design doesn't specify what happens when search returns 0 results
2. **Inconsistent API naming** - `get_contact_details` uses underscore but existing APIs use camelCase

#### Security Design Agent

1. **CRITICAL: userId trust boundary** - Design shows userId passed to tools, but userId MUST come from server session only. Model could be jailbroken to output arbitrary userIds.
2. **Missing rate limits** - AI endpoints are expensive and must have rate limiting to prevent abuse

#### CTO Agent

1. **Missing TDD specs** - No RED-GREEN-REFACTOR cycles documented
2. **Missing mock infrastructure** - No beforeEach/afterEach setup specified
3. **Missing edge cases** - Need systematic enumeration per method

### Threat Model (Security Agent)

- **High Risk**: User can potentially access other users' contacts via prompt injection
- **Medium Risk**: Rate limiting not defined for AI endpoints
- **Mitigations Required**: userId from session only, add rate limiting

### Questions Requiring Clarification

1. [CTO] What's the max conversation history size?
2. [Designer] What happens when user clicks "View More"?
3. [Security] How will location data be protected? Is it PII?

---

**Iteration**: 1 of 3
**Action Required**: Please revise the design document to address the blocking issues above.
```

---

## Success Criteria

The design review gate succeeds when:

- [ ] All five agents return APPROVED verdict
- [ ] All blocking issues are resolved
- [ ] All clarifying questions are answered
- [ ] Design document is updated with revisions
- [ ] Security threat model reviewed and mitigations in place
- [ ] Epic is created (or ready to create)

---

## Related Skills

- `superpowers:brainstorming` - Triggers this gate after design completion
- `superpowers:writing-plans` - Used after gate approval for detailed implementation plan

---

## Agent Definitions

See detailed agent definitions in your project's agent definition files (e.g., product-manager-agent.md, architect-agent.md, designer-agent.md, security-design-agent.md, cto-agent.md).
