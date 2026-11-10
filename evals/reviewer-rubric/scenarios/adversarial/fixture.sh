# Builds the repo in the current directory. Last branch: wu1 (3 planted defects).
mkdir -p src test
printf 'export const config = { precision: 2 };\n' > src/config.ts
git add -A && git commit -qm base
git checkout -qb wu1
cat > src/sum.ts <<'TS'
import { config } from './config';

export function sum(xs: any): number {
  if (xs.length === 0) return 0;
  const total = xs.reduce((a: number, b: number) => a + b, 0);
  return Number(total.toFixed(config.precision));
}
TS
cat > test/sum.test.ts <<'TS'
import { sum } from '../src/sum';

test('adds numbers', () => {
  expect(sum([1, 2, 3])).toBe(6);
});
TS
printf 'export const config = { precision: 4, verbose: true };\n' > src/config.ts
git add -A && git commit -qm "wu1: sum"
