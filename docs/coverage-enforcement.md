# Deterministic Coverage Enforcement

## Why Procedural Enforcement Fails

Telling agents "check coverage before pushing" in a checklist is not enforcement — it's a suggestion. Agents skip steps, misread thresholds, or run the wrong command. The warmstart-tng project shipped multiple PRs with coverage regressions because the only gate was a checklist item that agents occasionally ignored.

Deterministic enforcement means the system blocks bad code automatically, regardless of whether an agent follows instructions.

## The Three Enforcement Gates

All three gates read from the same file: `.coverage-thresholds.json` in your project root.

```json
{
  "thresholds": {
    "lines": 100,
    "branches": 100,
    "functions": 100,
    "statements": 100
  },
  "enforcement": {
    "command": "pnpm test:coverage",
    "blockPRCreation": true,
    "blockTaskCompletion": true
  }
}
```

### Gate 1: CI Job (GitHub Actions)

A CI job that reads `enforcement.command` from the JSON file and runs it. Fails the workflow on non-zero exit.

**Setup:**

- **No CI yet (Node.js/npm projects):** run `/setup` and answer Yes to "Create a GitHub Actions CI pipeline?". It writes `.github/workflows/ci.yml` from the plugin's `templates/ci.yml`, whose test step runs `enforcement.command`. `/setup` only asks when it detects no CI. The template is npm-based (`setup-node`, `npm ci`, `npm run lint`), so for Python, Go, Rust or pnpm-only projects add a CI job for your stack that runs `enforcement.command` instead (see `templates/ci-coverage-job.yml`).
- **Existing CI:** copy one of the jobs in `templates/ci-coverage-job.yml` (from the metaswarm plugin's `templates/`) under `jobs:` in your workflow, for example `.github/workflows/ci.yml`. Then add that job's key (`coverage-simple` or `coverage-merge`) to the `needs:` array of your merge-gating job.

The CI job reads the command dynamically — if you change `enforcement.command`, CI picks it up automatically with no workflow edits.

### Gate 2: Pre-Push Hook (Husky)

A git hook that runs before every `git push`. Runs lint, typecheck, format checks, and coverage enforcement.

**Setup:**

- **No git hooks yet (Node.js project):** run `/setup` and answer Yes to "Set up git hooks for pre-push quality checks?". It installs Husky, runs `npx husky init` and writes `.husky/pre-push` from the plugin's `templates/pre-push`. `/setup` only asks when it detects no hooks.
- **Manually:** if the project has no `.coverage-thresholds.json` yet, copy `templates/coverage-thresholds.json` from the metaswarm plugin to the project root and set `enforcement.command` (without the file the hook skips coverage and the push succeeds). Then run `npm install --save-dev husky`, then `npx husky init` (it adds a `prepare` script and a sample `.husky/pre-commit` that runs `npm test`; delete or edit that file if you don't want it), copy `templates/pre-push` from the metaswarm plugin's `templates/` to `.husky/pre-push`, then `chmod +x .husky/pre-push`. If you already have a `.husky/pre-push`, merge its coverage enforcement section into yours instead of overwriting it.

The hook uses `jq` if available, falls back to a Node one-liner to read the command from `.coverage-thresholds.json`.

### Gate 3: Agent Completion Check

The task-completion-checklist instructs agents to read `enforcement.command` from `.coverage-thresholds.json` and run it before pushing or creating a PR. This is the weakest gate (agents can still skip it), but combined with CI and pre-push hooks, coverage regressions are caught.

## How `.coverage-thresholds.json` Drives All Three

```
.coverage-thresholds.json
    ├── CI job reads enforcement.command → runs it → blocks merge on failure
    ├── pre-push hook reads enforcement.command → runs it → blocks push on failure
    └── agent checklist reads enforcement.command → runs it → blocks PR creation on failure
```

One file. One command. Three enforcement points.

## Customizing the Enforcement Command

Set `enforcement.command` to whatever your project uses:

| Language | Example Command |
|---|---|
| TypeScript (Vitest) | `pnpm test:coverage` |
| TypeScript (Jest) | `npx jest --coverage` |
| Python (pytest) | `pytest --cov --cov-fail-under=100` |
| Rust | `cargo tarpaulin --fail-under 100` |
| Go | `go test -cover ./...` |

## Reading Thresholds in Your Test Config

To avoid duplicating thresholds in both `.coverage-thresholds.json` and your test config, read from the JSON file directly.

### Vitest

```typescript
import fs from "node:fs";
import path from "node:path";

const coverageConfig = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, ".coverage-thresholds.json"), "utf-8"),
);

export default defineConfig({
  test: {
    coverage: {
      thresholds: coverageConfig.thresholds,
    },
  },
});
```

### Jest

```javascript
const fs = require("fs");
const path = require("path");

const coverageConfig = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, ".coverage-thresholds.json"), "utf-8"),
);

module.exports = {
  coverageThreshold: {
    global: {
      lines: coverageConfig.thresholds.lines,
      branches: coverageConfig.thresholds.branches,
      functions: coverageConfig.thresholds.functions,
      statements: coverageConfig.thresholds.statements,
    },
  },
};
```

## Husky Installation

The easiest way to set up all three enforcement gates is `/setup`. It always writes `.coverage-thresholds.json`, and it offers the CI pipeline and the pre-push hook when your project has no CI or no git hooks yet (see Gate 1 and Gate 2 above).

`npx metaswarm init` has no Husky or CI options. To add the hook by hand in a Node.js project, run these from your project root, where `$METASWARM` is the metaswarm plugin root, the directory that holds `templates/` (`$CLAUDE_PLUGIN_ROOT` in a Claude Code session, or `dirname "$(dirname "$(command -v metaswarm-agents.sh)")"`):

```bash
METASWARM="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(command -v metaswarm-agents.sh)")")}"
[ -f .coverage-thresholds.json ] || cp "$METASWARM/templates/coverage-thresholds.json" .   # then set enforcement.command
npm install --save-dev husky   # husky init adds "prepare": "husky", which needs the package
npx husky init                 # also writes a sample .husky/pre-commit (runs npm test)
cp "$METASWARM/templates/pre-push" .husky/pre-push
chmod +x .husky/pre-push
```

If you already have a pre-push hook, don't overwrite it: merge the coverage enforcement section of `templates/pre-push` into it. For CI, copy a job from `$METASWARM/templates/ci-coverage-job.yml` as described in Gate 1.
