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

- **No CI yet (Node.js, Python, Go or Rust):** run `/setup` and answer Yes to "Create a GitHub Actions CI pipeline?". `/setup` only asks when it detects no CI. It renders `.github/workflows/ci.yml` from the plugin's `templates/ci.yml` with `lib/render-ci.sh`, which installs your stack's toolchain, and its test step runs `enforcement.command`. The workflow runs on pushes to your default branch and on every pull request. `/setup` then offers to make its `CI checks` job a required check (see below). For other stacks, Node projects on pnpm, yarn or bun, and Python projects managed by Poetry, uv or Pipenv, add a job that runs `enforcement.command` to your own CI (see `templates/ci-coverage-job.yml`). Its install step picks pnpm, yarn, bun or npm from the lockfile; for other stacks, replace that step with your toolchain's (the file's header has examples).
- **Existing CI:** copy one of the jobs in `templates/ci-coverage-job.yml` (from the metaswarm plugin's `templates/`) under `jobs:` in your workflow, for example `.github/workflows/ci.yml`. Then add that job's key (`coverage-simple` or `coverage-merge`) to the `needs:` array of your merge-gating job.

The CI job reads the command dynamically — if you change `enforcement.command`, CI picks it up automatically with no workflow edits.

**Before you rely on these gates:**

- For Node projects, `templates/ci.yml` and `templates/pre-push` run your `lint` and `typecheck` scripts when `package.json` defines them, and skip a missing one. A script that fails, or a `package.json` that can't be parsed, fails the build and blocks the push.
- A CI check blocks merges only if the branch requires it. When `/setup` writes the workflow, it offers to run `lib/require-ci-check.sh`, which adds a ruleset requiring `CI checks` on the default branch (admin rights needed; existing protection is left alone). Otherwise, add the coverage job (or the CI workflow's job) as a required status check in a branch protection rule or ruleset for your merge branch. If you merge into a branch other than the default, add it to the workflow's `push` filter too.

### Gate 2: Pre-Push Hook (Husky)

A git hook that runs before every `git push`. Runs lint, typecheck, format checks, and coverage enforcement.

**Setup:**

- **No git hooks yet (Node.js project):** run `/setup` and answer Yes to "Set up git hooks for pre-push quality checks?". It installs Husky, runs `npx husky init` and writes `.husky/pre-push` from the plugin's `templates/pre-push`. `/setup` only asks when it detects no hooks.
- **Manually:** if the project has no `.coverage-thresholds.json` yet, copy `templates/coverage-thresholds.json` from the metaswarm plugin to the project root and set `enforcement.command` (without the file the hook skips coverage and the push succeeds). Then run `npm install --save-dev husky` and, if the project has no Husky setup yet, `npx husky init` (skip it when `.husky/` already exists: it would overwrite your `prepare` script and `.husky/pre-commit`) (it adds a `prepare` script and a sample `.husky/pre-commit` that runs `npm test`; delete or edit that file if you don't want it), copy `templates/pre-push` from the metaswarm plugin's `templates/` to `.husky/pre-push`, then `chmod +x .husky/pre-push`. If you already have a `.husky/pre-push`, merge its coverage enforcement section into yours instead of overwriting it.

The hook uses `jq` if available, falls back to a Node one-liner to read the command from `.coverage-thresholds.json`. In a project with a `package.json`, it stops the push if `node` isn't on PATH, rather than skipping lint and typecheck. It runs the lint, typecheck and format scripts through pnpm only when the project has a `pnpm-lock.yaml`.

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
| Go | `go run .metaswarm/go-coverage-gate.go` |

Commands with a threshold flag (`--cov-fail-under`, `--fail-under`) repeat the threshold. Re-running `/setup` with a new threshold updates both the `thresholds` values and that flag. Without a re-run, keep the two in step by hand.

### Go

`go test` has no coverage-threshold flag, so `go test -cover ./...` reports coverage but never fails. For Go projects `/setup` writes `.metaswarm/go-coverage-gate.go`, a standard-library-only program, and sets `enforcement.command` to `go run .metaswarm/go-coverage-gate.go`. Commit the file so CI can run it. The gate:

- runs `go test` with a fresh cover profile and fails if the tests fail. Arguments, such as `-race` or a package list, are passed on to `go test`; when none of them is a package, `./...` is added. The gate sets `-coverprofile` itself and copies the profile to `coverage.out` afterwards
- reads `.coverage-thresholds.json` on every run, so editing the thresholds takes effect without re-running setup
- compares exact statement counts: `go tool cover -func` rounds to one decimal, so 2,499 of 2,500 statements would show as 100.0%
- enforces `lines` and `statements` against Go's statement coverage, and reports `branches` and `functions` as not enforced, because Go doesn't measure them

The gate runs from the project root, where `.coverage-thresholds.json` is, and expects the Go module there too. If the module lives in a subdirectory, set `enforcement.command` to a command that runs from that directory and fails below the threshold. If `.metaswarm/go-coverage-gate.go` goes missing, re-run `/setup` to write it again.

The leading dot in `.metaswarm` keeps the gate out of `go build ./...`, `go test ./...` and `go vet ./...`. The command starts with `go` and has no shell metacharacters, so it passes the command guard in the CI template.

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
[ -d .husky ] || npx husky init   # new setups only: writes "prepare" and a sample .husky/pre-commit (runs npm test)
cp "$METASWARM/templates/pre-push" .husky/pre-push
chmod +x .husky/pre-push
```

If you already have a pre-push hook, don't overwrite it: merge the coverage enforcement section of `templates/pre-push` into it. For CI, copy a job from `$METASWARM/templates/ci-coverage-job.yml` as described in Gate 1.
