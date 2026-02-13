# Build Validation Guide

This guide covers build processes, validation workflows, and systematic error resolution for projects using the metaswarm framework. It is framework-level guidance applicable to any TypeScript/JavaScript codebase.

---

## Table of Contents

- [Command Timeout Guidelines](#command-timeout-guidelines)
- [Build Process Overview](#build-process-overview)
- [TypeScript Checking Strategies](#typescript-checking-strategies)
- [Critical Validation Workflow](#critical-validation-workflow)
- [File Tracking for Targeted Validation](#file-tracking-for-targeted-validation)
- [Coverage Enforcement](#coverage-enforcement)
- [Build Error Resolution](#build-error-resolution)
- [CI/CD Pipeline Configuration](#cicd-pipeline-configuration)
- [Production vs Development Builds](#production-vs-development-builds)
- [Pre-Push Hooks](#pre-push-hooks)
- [Build Performance Optimization](#build-performance-optimization)
- [Container Build Patterns](#container-build-patterns)

---

## Command Timeout Guidelines

**IMPORTANT**: Claude Code has a default 2-minute timeout for Bash commands. For long-running commands, always specify extended timeouts using the `timeout` parameter in milliseconds.

### Recommended Timeouts

| Command                      | Timeout (ms) | Duration   | Usage                         |
| ---------------------------- | ------------ | ---------- | ----------------------------- |
| Full build                   | 300000       | 5 minutes  | Complete build with typechecking |
| Test suite                   | 240000       | 4 minutes  | Full test execution           |
| Test coverage                | 300000       | 5 minutes  | Tests + coverage report       |
| Type checking                | 120000       | 2 minutes  | TypeScript compilation check  |
| Linting                      | 120000       | 2 minutes  | Full ESLint pass              |
| Database migrations          | 180000       | 3 minutes  | Large schema changes          |
| Container builds             | 600000       | 10 minutes | Docker image builds           |
| Large file processing        | 300000       | 5 minutes  | Bulk data operations          |

**Note**: Maximum timeout is 600000ms (10 minutes). For operations longer than 10 minutes, break them into smaller steps.

---

## Build Process Overview

A standard build pipeline for a TypeScript project includes these stages, executed in order:

```text
1. Type Check     (tsc --noEmit)         -- Structural correctness
2. Lint           (eslint)                -- Style and correctness rules
3. Test           (vitest/jest --run)     -- Behavioral correctness
4. Coverage       (test:coverage)         -- Coverage threshold enforcement
5. Build          (bundler build)         -- Production artifact generation
```

### Validation Order (Fail Fast)

Always validate in this order to fail fast on the cheapest checks:

1. **Type check** -- catches structural errors in seconds
2. **Lint** -- catches style and correctness issues
3. **Test** -- catches behavioral regressions
4. **Coverage** -- ensures no untested code paths
5. **Build** -- generates production artifacts

If any step fails, stop and fix before proceeding. Do not skip steps.

---

## TypeScript Checking Strategies

### Quick Check Commands

| Approach            | Time     | Purpose                              |
| ------------------- | -------- | ------------------------------------ |
| `tsc --noEmit`      | 5-15s    | Check TypeScript errors only         |
| Watch mode          | Instant  | Continuous monitoring during dev     |
| Lint changed files  | 1-3s     | Lint only modified files             |
| Parallel check      | 15-20s   | Lint + typecheck + tests in parallel |
| Full build          | 1-5 min  | Complete production build            |

### When to Use Each

1. **During development**: Use watch mode for instant feedback
   ```bash
   npx tsc --noEmit --watch
   ```

2. **Before committing**: Quick typecheck + lint changed files
   ```bash
   npx tsc --noEmit && npx eslint $(git diff --name-only --diff-filter=ACM | grep -E '\.(ts|tsx)$')
   ```

3. **Before creating a PR**: Full validation suite
   ```bash
   npx tsc --noEmit && npm run lint && npm run test:coverage && npm run build
   ```

4. **Full production build**: Only when you need actual build artifacts
   ```bash
   npm run build  # Use 300000ms timeout
   ```

### Incremental Builds

For large projects, use TypeScript project references to enable incremental builds:

```json
// tsconfig.json
{
  "compilerOptions": {
    "composite": true,
    "incremental": true,
    "tsBuildInfoFile": "./dist/.tsbuildinfo"
  }
}
```

```bash
# Incremental build (only recompiles changed files)
npx tsc --build

# Clean incremental cache
npx tsc --build --clean
```

### Project References

For monorepos or large projects, split into sub-projects:

```json
// tsconfig.json (root)
{
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/api" },
    { "path": "./packages/web" }
  ]
}
```

```bash
# Build all projects in dependency order
npx tsc --build --verbose
```

---

## Critical Validation Workflow

**Before marking ANY task complete**, you MUST validate your changes.

### Incremental Checks (During Development)

```bash
# 1. TypeScript
npx tsc --noEmit

# 2. ESLint on modified files only
npx eslint $(git diff --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx)$')

# 3. Prettier on modified files
npx prettier --check $(git diff --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx)$')
```

### Full Validation (Before Completion)

**IMPORTANT**: While incremental checks on modified files are useful during development, you MUST run the full validation suite before declaring any task complete:

```bash
# MANDATORY before marking task complete:
npm run lint          # Full ESLint check -- must pass with 0 warnings
npx tsc --noEmit      # Full TypeScript check -- must pass with 0 errors
npm run test:coverage # Full test suite with coverage -- must meet thresholds
npm run build         # Full build -- must succeed with no errors
```

**Why**: Your changes may affect other files indirectly through imports, type definitions, or shared utilities. Only a full validation ensures the entire codebase remains healthy.

### Validation Sequence (Repeat Until ALL Pass)

1. Fix all TypeScript errors: `npx tsc --noEmit`
2. Fix all ESLint warnings: `npm run lint`
3. Run tests: `npm test -- --run`
4. Verify coverage: `npm run test:coverage`
5. Verify build: `npm run build`
6. If ANY step fails, return to step 1

**Error Continuation Rule**: If you encounter 10 errors, fix ALL 10, not just the first 3.

**Success Criteria**: Only mark task complete when all commands return exit code 0 with zero errors and zero warnings.

---

## File Tracking for Targeted Validation

Track all files you modify during a session for efficient validation:

```bash
# Before starting work, check clean state
git status

# During work, periodically check modifications
git status --porcelain

# Before validation, get list of modified files
MODIFIED_FILES=$(git diff --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx)$')

# Run validation only on your changes
if [ -n "$MODIFIED_FILES" ]; then
  echo "$MODIFIED_FILES" | xargs npx eslint --max-warnings 0
  echo "$MODIFIED_FILES" | xargs npx prettier --check
else
  echo "No modified JS/TS files detected -- skipping lint/format."
fi
```

**Why targeted validation matters**:

- Running linters on the entire codebase creates out-of-scope work
- Users expect changes only to files related to the task
- Targeted validation is faster and more focused
- Prevents introducing issues in unrelated code

---

## Coverage Enforcement

Coverage thresholds are defined in `.coverage-thresholds.json` at the repo root:

```json
{
  "statements": 100,
  "branches": 100,
  "functions": 100,
  "lines": 100
}
```

Orchestrator agents **must** read that file and run `npm run test:coverage` before marking any task complete. If any threshold is not met, the task fails.

For detailed coverage configuration, see the [Testing Patterns Guide](./testing-patterns.md#coverage-configuration).

---

## Build Error Resolution

### DO NOT Stop Prematurely

- If build errors exist, CONTINUE fixing them
- If tests are failing, CONTINUE debugging
- If ESLint has warnings, CONTINUE resolving them
- The task is NOT complete until ALL validation steps pass

### Systematic Error Fixing Process

1. **Identify ALL errors first**: Run full build and list every error
2. **Group errors by type**: TypeScript, ESLint, test failures
3. **Fix errors systematically**: Start with TypeScript (often cascading), then ESLint, then tests
4. **Verify each fix**: Re-run the relevant check after each batch of fixes
5. **Never skip errors**: Every single error must be resolved

### Common Error Patterns

When encountering build errors:

- **NEVER use `as any` or `@ts-ignore`** -- these mask problems instead of solving them
- Do not stop at the first error -- use `npx tsc --noEmit 2>&1 | head -100` to see all errors
- After fixing errors, always re-run the check to verify

Common TypeScript patterns to remember:

- Use proper null checks instead of non-null assertion (`!`)
- Extract nullable values before comparisons
- Create proper interfaces instead of using `any`
- Check property paths carefully in nested objects
- Use discriminated unions for complex type narrowing

### Build Failure Triage

| Error Type             | First Action                                    | Common Cause                         |
| ---------------------- | ----------------------------------------------- | ------------------------------------ |
| TypeScript errors      | `npx tsc --noEmit`                              | Type mismatches, missing properties  |
| ESLint errors          | `npx eslint <file> --max-warnings 0`            | Unused imports, style violations     |
| Test failures          | `npx vitest run <file>` (or jest)               | Logic bugs, stale mocks             |
| Coverage drops         | `npm run test:coverage`                         | Untested branches or new code        |
| Build/bundle errors    | `npm run build`                                 | Import resolution, missing exports   |
| Missing dependencies   | `npm install`                                   | Package not installed                |

---

## CI/CD Pipeline Configuration

### GitHub Actions Example

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Type check
        run: npx tsc --noEmit

      - name: Lint
        run: npm run lint

      - name: Test with coverage
        run: npm run test:coverage

      - name: Build
        run: npm run build
```

### Branch Protection Rules

Configure these as required status checks:

- Type checking must pass
- Linting must pass with zero warnings
- All tests must pass
- Coverage thresholds must be met
- Build must succeed

### Caching for Faster CI

```yaml
- uses: actions/cache@v4
  with:
    path: |
      node_modules
      ~/.npm
      dist/.tsbuildinfo
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

---

## Production vs Development Builds

### Overview

| Environment           | Type Checking | Optimization | Use Case                     |
| --------------------- | ------------- | ------------ | ---------------------------- |
| **Local Development** | Full          | None         | Active development           |
| **CI/CD**             | Full          | Full         | Pre-deployment validation    |
| **Production Deploy** | Skipped       | Full         | Fast deploys after CI passed |

### Why Skip Type Checking in Production?

Type checking in production builds is redundant when CI/CD has already validated types. Skipping it saves 30-60 seconds per deployment.

```bash
# Development/CI: full validation
npm run build

# Production: skip type checking (CI already validated)
SKIP_TYPE_CHECK=true npm run build
```

### When NOT to Skip Type Checking

- Local development builds
- CI/CD pipeline builds
- Before creating PRs
- When testing type changes

---

## Pre-Push Hooks

Use git hooks to prevent pushing broken code:

### Using Husky

```bash
npm install --save-dev husky
npx husky init
```

### Pre-Push Hook

```bash
#!/usr/bin/env bash
# .husky/pre-push

echo "Running pre-push validation..."

# Type check
npx tsc --noEmit || {
  echo "TypeScript check failed. Push aborted."
  exit 1
}

# Lint
npm run lint || {
  echo "Lint check failed. Push aborted."
  exit 1
}

# Tests
npm test -- --run || {
  echo "Tests failed. Push aborted."
  exit 1
}

echo "All checks passed. Pushing..."
```

### Pre-Commit Hook (Staged Files Only)

```bash
#!/usr/bin/env bash
# .husky/pre-commit

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx)$')

if [ -n "$STAGED_FILES" ]; then
  echo "$STAGED_FILES" | xargs npx eslint --max-warnings 0 || {
    echo "Lint errors in staged files. Commit aborted."
    exit 1
  }
fi
```

---

## Build Performance Optimization

### General Strategies

1. **Incremental TypeScript builds**: Use `--incremental` and project references
2. **Parallel execution**: Run independent checks in parallel
3. **Targeted validation**: Check only modified files during development
4. **Caching**: Use build caches (`.tsbuildinfo`, bundler caches, CI caches)
5. **Watch mode**: Use watch mode during active development instead of repeated full builds

### Parallel Validation Script

```bash
#!/usr/bin/env bash
# scripts/check-fast.sh -- Run validation checks in parallel

set -euo pipefail

echo "Starting parallel validation..."

# Run checks in parallel
npx tsc --noEmit &
PID_TSC=$!

npm run lint &
PID_LINT=$!

npm test -- --run &
PID_TEST=$!

# Wait for all and capture exit codes
FAIL=0
wait $PID_TSC || { echo "TypeScript check FAILED"; FAIL=1; }
wait $PID_LINT || { echo "Lint check FAILED"; FAIL=1; }
wait $PID_TEST || { echo "Tests FAILED"; FAIL=1; }

if [ $FAIL -ne 0 ]; then
  echo "Validation FAILED"
  exit 1
fi

echo "All checks passed."
```

### Large Project Strategies

For projects with slow builds:

- **Split into packages**: Use workspaces/project references so only changed packages rebuild
- **Use `swc` or `esbuild`**: Faster transpilation for development builds (keep `tsc` for type checking)
- **Prune test suites**: Run only tests related to changed files during development
  ```bash
  npx vitest --changed  # Run tests related to uncommitted changes
  ```
- **Parallelize CI**: Split test suites across multiple CI runners

---

## Container Build Patterns

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production=false

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Production image
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./

USER node
CMD ["node", "dist/index.js"]
```

### Build Cache Optimization

```dockerfile
# Copy package files first (rarely change) for better layer caching
COPY package.json package-lock.json ./
RUN npm ci

# Then copy source (frequently changes)
COPY . .
RUN npm run build
```

### Health Checks

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:${PORT}/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1); })"
```

---

## See Also

- [Testing Patterns Guide](./testing-patterns.md) -- Coverage configuration and test quality
- [Git Workflow Guide](./git-workflow.md) -- Pre-commit verification and PR workflows
- [Coding Standards Guide](./coding-standards.md) -- TypeScript discipline and error handling
- [Worktree Development Guide](./worktree-development.md) -- Parallel development validation
