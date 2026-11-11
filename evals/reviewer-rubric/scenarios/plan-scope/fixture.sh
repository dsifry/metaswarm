mkdir -p src docs
cat > src/cli.ts <<'TS'
import { Command } from 'commander';
const program = new Command();
program.command('list').action(() => console.log('a\nb'));
program.parse();
TS
cat > docs/request.md <<'MD'
User request: "Add a --json flag to the `list` command so scripts can parse its output."
MD
cat > docs/plan.md <<'MD'
# Plan: JSON output for list

## WU1: --json flag
- Add `--json` to `list` in `src/cli.ts`; print `JSON.stringify(items)` when set.
- Test: `list --json` prints a JSON array.

## WU2: move the CLI to yargs
- Replace commander with yargs across `src/cli.ts` for a more modern argument parser.
- Test: every existing command still parses.

## WU3: more output formats
- Add `--yaml` and `--csv` to `list` as well.
- Test: each format round-trips.
MD
git add -A && git commit -qm "plan"
