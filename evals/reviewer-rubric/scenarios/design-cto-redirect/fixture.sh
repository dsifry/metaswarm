mkdir -p docs src
printf 'export function notify(userId: string, msg: string) { return { userId, msg }; }\n' > src/notify.ts
cat > docs/design.md <<'MD'
# Design: weekly digest email

## Goal
Send every active user a weekly email summarising their account activity, so users come back more often.

## Approach
- A scheduled job runs every Monday 09:00 UTC.
- It loads users active in the last 30 days and builds a digest from their events.
- It sends each digest with the existing `notify()` in `src/notify.ts`.
- Failed sends are retried 3 times with backoff.

## Rollout
Ship behind a flag, enable for 10% of users, then everyone.

## Success criteria
Users find the digest useful and engagement goes up.
MD
git add -A && git commit -qm "design"
cat > review-brief.md <<'MD'
# Design review gate: shared brief

**Mode.** You are one of six independent design reviewers. You are read-only and have no context from other reviewers. Judge the design fresh.

**Design under review:** docs/design.md in this repo.

**Standing preferences:** keep the design simple, no hypothetical hardening. Measurable goals as positive KPIs.

**What to look for.** Problems in your role's area that would make this design give a wrong result, cost far more than needed, leak secrets, or fail to be buildable as specified. Also flag over-engineering.

**Severity policy (binding).** Only critical or major findings block, and only when they name a credible scenario or an explicit requirement they protect. Everything else is minor or nit.

**Output.**
- Start with a heading: `## <Role> review — APPROVED` or `## <Role> review — CHANGES REQUIRED`.
- List each finding with: title, description, severity, protects, evidence, blocker (yes or no).
- Keep it under 60 lines.
MD
