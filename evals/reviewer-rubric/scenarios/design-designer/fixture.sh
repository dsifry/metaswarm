mkdir -p docs src/api
cat > src/api/users.ts <<'TS'
export type Result<T> = { data: T } | { error: { code: string; message: string } };
export async function getUserById(id: string): Promise<Result<{ id: string; name: string }>> {
  if (!id) return { error: { code: 'invalid_id', message: 'User id is required' } };
  return { data: { id, name: 'x' } };
}
TS
cat > docs/design.md <<'MD'
# Design: order lookup API

## Approach
Add `src/api/orders.ts` with:

    export async function fetch_order(orderNo: number): Promise<[any, number]>

It returns a tuple `[order, status]`. On failure the status is a numeric code such as `ERR_42` or `ERR_7` and the order is `null`.

## Pagination
`list_orders(pageToken)` returns 50 orders per page and the next page token.
MD
git add -A && git commit -qm "design"
