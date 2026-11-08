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

1. Copy `templates/ci-coverage-job.yml` into your `.github/workflows/ci.yml`
2. Add `coverage` to the `needs:` array of your merge-gating job

The CI job reads the command dynamically — if you change `enforcement.command`, CI picks it up automatically with no workflow edits.

### Gate 2: Pre-Push Hook (Husky)

A git hook that runs before every `git push`. Runs lint, typecheck, format checks, and coverage enforcement.

**Setup:**

1. Run `npx metaswarm init --with-husky` (initializes Husky if needed, copies the hook, and copies coverage thresholds)
2. Or manually: `npx husky init && cp templates/pre-push .husky/pre-push && chmod +x .husky/pre-push`

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

The easiest way to set up all three enforcement gates:

```bash
npx metaswarm init --with-husky --with-ci
```

This initializes Husky (if needed), copies the pre-push hook, copies coverage thresholds, and creates the CI workflow — all in one command.

If you already have Husky but no pre-push hook, `metaswarm init` (without flags) will copy the template automatically. If you already have a pre-push hook, it won't be overwritten — merge the coverage enforcement section manually.
