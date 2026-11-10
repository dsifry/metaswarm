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
