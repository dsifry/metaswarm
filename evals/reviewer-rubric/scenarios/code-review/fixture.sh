# Last branch: feature (2 planted defects).
mkdir -p src test
printf '# app\n' > NOTES.md
git add -A && git commit -qm base
git checkout -qb feature
cat > src/parse.ts <<'TS'
export function parseQty(input: any): number {
  const n = parseInt(input, 10);
  return Number.isNaN(n) ? 0 : n;
}
TS
cat > test/parse.test.ts <<'TS'
import { parseQty } from '../src/parse';

test('parses a quantity', () => {
  expect(parseQty('3')).toBeDefined();
});
TS
git add -A && git commit -qm "feature: parseQty"
