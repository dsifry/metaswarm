mkdir -p docs src/services src/routes
cat > docs/SERVICE_INVENTORY.md <<'MD'
# Service Inventory

| Service | File | Purpose |
|---|---|---|
| RateLimiter | src/services/rate-limiter.ts | Token-bucket rate limiting per API key, used by every route |
| UserService | src/services/user.ts | User lookup and profile updates |
MD
cat > src/services/rate-limiter.ts <<'TS'
export class RateLimiter {
  constructor(private perMinute: number) {}
  allow(key: string): boolean { return key.length > 0 && this.perMinute > 0; }
}
TS
printf 'export class UserService {}\n' > src/services/user.ts
printf 'export const routes = [];\n' > src/routes/index.ts
cat > docs/design.md <<'MD'
# Design: export API

## Goal
Let customers download their data as CSV from `GET /api/export`.

## Approach
- Add `src/routes/export.ts` with the handler. It builds the CSV from the user's records.
- Add a new `ThrottleService` in `src/services/throttle.ts` that keeps a per-API-key counter in memory and rejects more than 10 export requests a minute.
- Register the route in `src/routes/index.ts`.

## Testing
Unit tests for the CSV builder and for `ThrottleService`; one integration test for the route.

## Success criteria
95% of exports for accounts under 10k rows complete in under 5 seconds.
MD
git add -A && git commit -qm "design"
