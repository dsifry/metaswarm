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
