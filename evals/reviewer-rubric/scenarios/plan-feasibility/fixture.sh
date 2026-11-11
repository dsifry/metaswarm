mkdir -p src/services docs
printf '{ "name": "app", "scripts": { "test": "vitest run" } }\n' > package.json
cat > src/services/email.ts <<'TS'
export async function sendEmail(to: string, body: string): Promise<void> { void to; void body; }
TS
cat > docs/request.md <<'MD'
User request: "Retry failed welcome emails up to 3 times."
MD
cat > docs/plan.md <<'MD'
# Plan: retry welcome emails

## WU1: retry wrapper
- Add `withRetry(fn, attempts)` to `src/services/mailer.ts`, next to the existing `sendMail()`.
- Retry with exponential backoff: 1s, 2s, 4s.
- Test: a send that fails twice then succeeds is called 3 times.

## WU2: use it for welcome emails
- Wrap the welcome-email call in `withRetry(..., 3)`.

## Verify
Run `npm run test:unit`.
MD
git add -A && git commit -qm "plan"
