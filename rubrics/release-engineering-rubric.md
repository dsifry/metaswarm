# Release Engineering Rubric

**Used By**: Release Engineer Agent
**Purpose**: Evaluate release readiness and execution quality at every gate from merge through production verification
**Version**: 1.0

---

## Overview

This rubric ensures every release passes through rigorous verification at each stage. The Release Engineer Agent uses this rubric to evaluate readiness before proceeding through each gate. Unlike code review (which evaluates code quality), this rubric evaluates **operational safety** — can we ship this without breaking production?

---

## Severity Levels

| Level | Description | Action |
|-------|-------------|--------|
| **BLOCKING** | Will cause production incident, data loss, or service outage | HALT — do not proceed until resolved |
| **HIGH** | Significant risk to production stability or user experience | MUST resolve before proceeding |
| **MEDIUM** | Elevated risk, may cause issues under specific conditions | SHOULD resolve; document and proceed with monitoring if time-constrained |
| **LOW** | Minor process gap, no immediate production risk | Note for improvement, proceed |

---

## Gate 1: Pre-Merge Readiness

### 1.1 Approval Chain (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| PM product review approved | BLOCKING | `gh pr view --json reviews` shows PM APPROVED |
| QA review approved | BLOCKING | `gh pr view --json reviews` shows QA APPROVED |
| Technical review(s) approved (if required) | BLOCKING | All required reviewers APPROVED |
| All review threads resolved | BLOCKING | Zero unresolved threads |
| No blocking defect issues open | BLOCKING | No open issues with `blocking` label referencing this PR |

### 1.2 CI & Quality Gates (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| All CI checks passing | BLOCKING | `gh pr checks` shows all green |
| Coverage thresholds met | BLOCKING | `.coverage-thresholds.json` thresholds satisfied |
| No merge conflicts | BLOCKING | `gh pr view --json mergeable` is `MERGEABLE` |
| Branch is up-to-date with base | HIGH | No commits on main since branch was last rebased |

### 1.3 Scope Verification (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Changes match approved spec scope | HIGH | Diff doesn't include files outside declared scope |
| No unauthorized CI/CD config changes | BLOCKING | `.github/`, `vercel.json`, deploy hooks unchanged unless spec-approved |
| No dependency changes without review | HIGH | `package.json`, `go.mod` changes were reviewed |
| Database migrations reviewed | BLOCKING | Any migration files have explicit PM/COO sign-off |

---

## Gate 2: Merge Execution Quality

### 2.1 Commit Hygiene (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Squash-merge used (not merge commit) | HIGH | Single commit on main for the PR |
| Commit message uses `refs #<issue>` | HIGH | NOT `closes #<issue>` or `fixes #<issue>` |
| Commit message follows conventional format | MEDIUM | `<type>(<scope>): <description>` |
| Commit message includes reviewer attribution | LOW | `Reviewed-by:` and `Tested-by:` lines |

### 2.2 Post-Merge Cleanup (MEDIUM)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Feature branch deleted | MEDIUM | Branch no longer exists on remote |
| Lifecycle label updated | MEDIUM | Issue has `lifecycle:merge` label |
| Merge freeze activated | BLOCKING | `merge-freeze:active` label applied |

---

## Gate 3: CI on Main

### 3.1 Pipeline Health (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| CI pipeline started | BLOCKING | `gh run list --branch main` shows new run |
| All test suites pass | BLOCKING | Unit, integration, E2E all green |
| Build artifacts generated | HIGH | Build step completed successfully |
| No new warnings introduced | LOW | Warning count stable or decreased |

### 3.2 Failure Response (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Failure classified within 5 minutes | BLOCKING | Flaky vs. real failure determined |
| Appropriate action taken | BLOCKING | Flaky: documented + proceed. Real: hotfix or revert |
| Stakeholders notified of failure | HIGH | Coder + PM aware of CI failure on main |

---

## Gate 4: Pre-Deploy Environment Health

### 4.1 Target Environment (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Production health endpoint responding | BLOCKING | `curl /api/health` returns 200 |
| Database accessible and healthy | BLOCKING | Connection pool OK, no stuck queries |
| External dependencies reachable | HIGH | Third-party APIs responding |
| Deploy credentials valid | BLOCKING | Token/key not expired |
| No active incidents on platform | HIGH | Hosting platform status page green |

### 4.2 Rollback Plan (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Previous known-good version identified | HIGH | Can name the version to rollback to |
| Rollback mechanism tested/verified | MEDIUM | Deploy platform supports instant rollback |
| Database migration reversibility assessed | BLOCKING | If migration included: can it be reversed? |

---

## Gate 5: Deployment Execution

### 5.1 Deploy Process (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Deployment triggered via official pipeline | BLOCKING | Not a manual file copy or ad-hoc process |
| Build phase completed | BLOCKING | No build errors |
| Deployment phase completed | BLOCKING | New version serving traffic |
| Health check passing on new version | BLOCKING | `/api/health` returns 200 from new version |
| Deployment completed within timeout (15m) | HIGH | If exceeded, treat as failure |

### 5.2 Deployment Monitoring (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Error rate monitored during rollout | HIGH | Dashboard or logs observed |
| Latency monitored during rollout | HIGH | No immediate spike |
| Resource utilization checked | MEDIUM | CPU/memory within bounds |

---

## Gate 6: Post-Deploy Verification

### 6.1 Smoke Tests (BLOCKING)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Core user flows working | BLOCKING | Login, primary features, data access |
| Targeted tests for this change pass | BLOCKING | Acceptance criteria verified in production |
| Health endpoint stable | BLOCKING | Consistent 200 responses |

### 6.2 Soak Period (15 minutes minimum) (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Error rate stable (< 5% increase) | BLOCKING | Compare to pre-deploy baseline |
| p95 latency stable (< 20% increase) | HIGH | Compare to pre-deploy baseline |
| Memory/CPU stable | HIGH | No upward trend during soak |
| No new error types in logs | HIGH | Log analysis shows no novel exceptions |
| No user-reported issues | MEDIUM | Support channels quiet |
| External API success rates stable | MEDIUM | No degradation in outbound calls |

### 6.3 Customer-Reported Issue Verification (when applicable)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Original bug no longer reproducible | BLOCKING | QA verified the specific scenario |
| PM notified of verification results | HIGH | PM can instruct customer-support |
| Customer notification queued | HIGH | Resolution email prepared |

---

## Gate 7: Release Completion

### 7.1 Cleanup & Communication (HIGH)

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Merge freeze lifted | HIGH | `merge-freeze:active` label removed |
| Queued PRs notified | MEDIUM | Next PR in queue knows they can proceed |
| Issue closed | HIGH | GitHub Issue closed by CoS/PM |
| BEADS task closed | MEDIUM | `bd close <task-id>` executed |
| Release report generated | MEDIUM | Timeline, metrics, artifacts documented |
| Stakeholders notified | HIGH | PM, CoS, team aware of release |

---

## Emergency Rollback Rubric

When a rollback is triggered, evaluate:

| Criterion | Severity | Verification |
|-----------|----------|-------------|
| Rollback initiated within 5 minutes of detection | BLOCKING | Time from anomaly detection to rollback start |
| Stakeholders notified before rollback | HIGH | CoS, COO, PM, Coder aware |
| Previous version restored and verified | BLOCKING | Health check passing on previous version |
| P1 issue created for root cause | HIGH | Issue filed with context |
| Merge freeze maintained until stable | BLOCKING | No other merges during recovery |
| Post-incident review scheduled | MEDIUM | Within 24 hours of incident |

---

## Scoring Summary

For each release, the Release Engineer tracks gate passage:

```markdown
## Release Scorecard: PR #<number>

| Gate | Status | Issues Found | Time |
|------|--------|-------------|------|
| Pre-Merge Readiness | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| Merge Execution | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| CI on Main | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| Pre-Deploy Health | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| Deployment | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| Post-Deploy Verification | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |
| Release Completion | PASS/FAIL | 0 BLOCKING, 0 HIGH | HH:MM |

**Overall: RELEASED / ROLLED_BACK / BLOCKED**
**Total time: X minutes**
**Issues found: N (B blocking, H high, M medium, L low)**
```

---

## Approval Criteria

**PROCEED** to next gate when:
- Zero BLOCKING issues at current gate
- Zero HIGH issues (or explicitly accepted with PM/COO justification)
- MEDIUM issues documented

**HALT** when:
- Any BLOCKING issue exists
- Any HIGH issue without justification

**ROLLBACK** when:
- Any BLOCKING issue detected at Gate 5 or Gate 6
- Error rate exceeds 5% increase
- Production health endpoint failing
- Any data integrity concern

---

## Anti-Patterns to Flag

| Anti-Pattern | Why It's Dangerous | What to Do Instead |
|-------------|-------------------|-------------------|
| "YOLO deploy" — skip pre-deploy checks | Deploys to unhealthy environment | Always run Gate 4 |
| "It's just a small change" — skip soak | Small changes can have big blast radius | Always soak 15 minutes minimum |
| Deploy on Friday afternoon | Reduced staffing for incident response | Deploy early in the work week |
| Skip merge freeze for "quick" PRs | Concurrent deploys mask which change broke things | One merge → one deploy → one verification |
| Rollback hesitation | "Let me debug it in prod" wastes time | Rollback first, debug second |
| Manual deploy | Bypasses CI, monitoring, audit trail | Always use the official pipeline |
| Deploying during active incident | Adds variables to an already complex situation | Wait for incident resolution |

---

## Knowledge Integration

Before each release, check knowledge base for:

- Known deployment gotchas for this service/component
- Recent incidents that might affect this release
- Platform-specific deployment quirks (cold start times, cache invalidation)
- Environment-specific configuration that needs verification
