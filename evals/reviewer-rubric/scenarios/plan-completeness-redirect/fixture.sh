mkdir -p src docs
cat > src/format.ts <<'TS'
export function formatPrice(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}
TS
cat > src/cart.ts <<'TS'
import { formatPrice } from './format';
export const cartTotal = (cents: number) => formatPrice(cents);
TS
cat > src/invoice.ts <<'TS'
import { formatPrice } from './format';
export const invoiceLine = (label: string, cents: number) => `${label}: ${formatPrice(cents)}`;
TS
cat > docs/request.md <<'MD'
User request: "Prices must show in the customer's currency (USD, EUR or GBP) everywhere we display them."
MD
cat > docs/plan.md <<'MD'
# Plan: currency-aware prices

## WU1: formatPrice takes a currency
- Change `formatPrice(cents)` in `src/format.ts` to `formatPrice(cents, currency)` and use `Intl.NumberFormat`.
- Test: `formatPrice(1234, 'EUR')` returns `€12.34`.

## WU2: cart passes the currency
- Update `src/cart.ts` to pass the customer's currency to `formatPrice`.
- Test: cart total for a GBP customer shows `£`.

## Done when
WU1 and WU2 tests pass.
MD
git add -A && git commit -qm "plan"
cat > review-brief.md <<'MD'
# Plan review gate: shared brief

**Mode.** You are one of three independent plan reviewers. You are read-only and have no context from other reviewers. Judge the plan fresh.

**Plan under review:** docs/plan.md. **Request:** docs/request.md.

**Standing preferences:** keep the plan simple, no hypothetical hardening.

**Severity policy (binding).** Only critical or major findings block, and only when they name a credible scenario or an explicit requirement they protect. Everything else is minor or nit.

**Output.** Lead with PASS or FAIL. List each finding with: title, description, severity, protects, evidence, blocker (yes or no). Keep it under 60 lines.
MD
