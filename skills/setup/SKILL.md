---
name: setup
description: Interactive project setup — detects your project, configures metaswarm, writes project-local files
---

# Setup

Interactive, Claude-guided setup for metaswarm. Detects your stack, asks targeted questions, writes project-local files, and creates command shims. Replaces both `npx metaswarm init` and the old `/metaswarm-setup` command.

<CRITICAL-REQUIREMENTS>
Setup MUST produce these 3 files. You CANNOT declare setup complete without them:

1. **CLAUDE.md with metaswarm section** — Append `./templates/CLAUDE-append.md` to existing CLAUDE.md, or write `./templates/CLAUDE.md` if none exists
2. **`.coverage-thresholds.json` at project root** — Read `./templates/coverage-thresholds.json`, customize thresholds and enforcement command, Write to project root
3. **6 shims in `.claude/commands/`** — Write `start-task.md`, `prime.md`, `review-design.md`, `self-reflect.md`, `pr-shepherd.md`, `brainstorm.md` to `.claude/commands/`

These are not optional. Do not invent alternative files or locations. Do not skip them because "the project already has commands" or "coverage is in the profile". These exact files in these exact locations are what the rest of the system reads.
</CRITICAL-REQUIREMENTS>

## Pre-Flight

### Existing Profile Check

Use Glob to check if `.metaswarm/project-profile.json` exists.

- **If it exists**: Read it, present the current configuration summary, and ask the user via AskUserQuestion: "You already have a metaswarm project profile. Re-run setup (overwrites choices) or skip?" Options: "Re-run setup" / "Skip". If the user skips, stop with: "Setup skipped. Existing configuration unchanged."
- **If it does not exist**: Continue to Project Detection.

---

## Phase 1: Project Detection

Scan the project directory silently using Glob and Read. Do NOT ask the user for any of this information. Detect everything, then present results.

### 1.1 Language

Check for marker files at the project root:

| Marker File | Language |
|---|---|
| `package.json` | Node.js / JavaScript |
| `tsconfig.json` | TypeScript (refines Node.js to TypeScript) |
| `pyproject.toml` OR `setup.py` OR `requirements.txt` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` OR `build.gradle` OR `build.gradle.kts` | Java |
| `Gemfile` | Ruby |
| `Makefile` (alone, no other markers) | Unknown (ask user) |

If `tsconfig.json` exists alongside `package.json`, the language is "TypeScript".

If multiple languages are detected, note all of them but use the primary one (most infrastructure) for command generation.

**If no language detected**: Use AskUserQuestion to ask the user what language/stack they are using before proceeding.

### 1.2 Framework

**Node.js/TypeScript** — Read `package.json` and check `dependencies` + `devDependencies`:

| Dependency | Framework |
|---|---|
| `next` | Next.js |
| `nuxt` OR `nuxt3` | Nuxt |
| `@angular/core` | Angular |
| `svelte` OR `@sveltejs/kit` | SvelteKit |
| `react` (without next/nuxt) | React |
| `vue` (without nuxt) | Vue |
| `express` | Express |
| `fastify` | Fastify |
| `hono` | Hono |
| `@nestjs/core` | NestJS |

**Python** — Check `pyproject.toml` or `requirements.txt` for: `fastapi`, `django`, `flask`.

**Go** — Read `go.mod` for: `github.com/gin-gonic/gin` (Gin), `github.com/labstack/echo` (Echo), `github.com/gofiber/fiber` (Fiber).

If no framework detected, set to `null`.

### 1.3 Package Manager (Node.js only)

| Lock File | Package Manager |
|---|---|
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `bun.lockb` | bun |
| `package-lock.json` | npm |

Default to `npm` if no lock file found. For non-Node.js, set to `null`.

### 1.4 Test Runner

**Node.js/TypeScript** (first match wins):
1. Glob for `vitest.config.*` or `vitest` in devDependencies -> `vitest`
2. Glob for `jest.config.*` or `jest` in devDependencies -> `jest`
3. `mocha` in devDependencies -> `mocha`

**Python**: Check for `[tool.pytest]` in `pyproject.toml` or `pytest` in dependencies -> `pytest` (default for Python).

**Go**: `go test` (built-in). **Rust**: `cargo test` (built-in). **Java/Maven**: `mvn test`. **Java/Gradle**: `gradle test`.

### 1.5 Linter

| Marker | Linter |
|---|---|
| `.eslintrc*` OR `eslint.config.*` OR `eslint` in devDependencies | eslint |
| `biome.json` OR `@biomejs/biome` in devDependencies | biome |
| `[tool.ruff]` in `pyproject.toml` OR `ruff.toml` | ruff |
| `.golangci.yml` OR `.golangci.yaml` | golangci-lint |
| `.clippy.toml` or clippy in Cargo.toml | clippy |

### 1.6 Formatter

| Marker | Formatter |
|---|---|
| `.prettierrc*` OR `prettier` in devDependencies | prettier |
| `biome.json` (also formats) | biome |
| `black` in Python deps | black |
| `[tool.ruff.format]` in `pyproject.toml` | ruff format |
| `rustfmt.toml` OR `.rustfmt.toml` | rustfmt |

If biome detected as both linter and formatter, report once as "Biome (lint + format)".

### 1.7 Type Checker

| Marker | Type Checker |
|---|---|
| `tsconfig.json` | tsc |
| `mypy` in Python deps OR `[tool.mypy]` in `pyproject.toml` | mypy |
| `pyright` in Python deps OR `pyrightconfig.json` | pyright |

Go (`go vet`) and Rust (`cargo check`) have built-in type checking — note but do not list separately.

### 1.8 CI Detection

| Marker | CI System |
|---|---|
| `.github/workflows/*.yml` | GitHub Actions |
| `.gitlab-ci.yml` | GitLab CI |
| `Jenkinsfile` | Jenkins |
| `.circleci/config.yml` | CircleCI |

### 1.9 Git Hooks Detection

| Marker | Hook System |
|---|---|
| `.husky/` | Husky |
| `.pre-commit-config.yaml` | pre-commit |
| `.lefthook.yml` | Lefthook |

### 1.10 Present Results

After all detection, present findings:

```
I detected the following about your project:

  Language:        {language}
  Framework:       {framework or "None detected"}
  Package manager: {package_manager or "N/A"}
  Test runner:     {test_runner or "None detected"}
  Linter:          {linter or "None detected"}
  Formatter:       {formatter or "None detected"}
  Type checker:    {type_checker or "None detected"}
  CI:              {ci or "None detected"}
  Git hooks:       {git_hooks or "None detected"}
```

---

## Phase 2: Interactive Questions

Use AskUserQuestion to ask ONLY questions relevant based on detection. 3-5 questions maximum.

**Always ask:**

1. **Coverage threshold** — "What test coverage threshold do you want to enforce?" Options: "100% (Recommended)" / "80%" / "60%" / "Custom"

**Ask only if relevant:**

2. **External AI tools** — Ask only for non-trivial projects: "Set up external AI tools (Codex/Gemini) for cost savings on implementation?" Options: "Yes" / "No"

3. **Visual review** — Ask only if a web framework was detected (Next.js, Nuxt, React, Vue, Angular, SvelteKit, Django, Flask): "Enable visual screenshot review for UI changes?" Options: "Yes" / "No"

4. **CI pipeline** — Ask only if NO CI detected: "Create a GitHub Actions CI pipeline?" Options: "Yes (Recommended)" / "No"

5. **Git hooks** — Ask only if NO hooks detected: "Set up git hooks for pre-push quality checks?" Options: "Yes (Recommended)" / "No"

---

## Phase 3: Write Required Files

After detection and questions are done, write files to the project. Read templates from `./` relative paths (co-located in this skill's directory).

**Do these 3 things FIRST, before anything else in Phase 3:**

### Step A: CLAUDE.md (do this NOW)

1. Use Grep to check if the project's `CLAUDE.md` already contains "metaswarm"
2. If YES → skip (already configured)
3. If NO and CLAUDE.md exists → Use AskUserQuestion: "Your CLAUDE.md exists but has no metaswarm section. Append metaswarm workflow instructions?" Options: "Yes (Recommended)" / "No"
   - If user says yes: Read `./templates/CLAUDE-append.md` with the Read tool, then use Edit to append its content to the project's `CLAUDE.md`
   - If user says no: warn them and continue
4. If NO CLAUDE.md exists → Read `./templates/CLAUDE.md`, customize the TODO sections (replace test/coverage commands and code quality tools with detected values), then Write to project root
5. **Verify**: Use Grep on the project's CLAUDE.md for "metaswarm". If not found, you skipped this step.

After writing or appending, also update TODO sections if present — replace `npm test`/`npm run test:coverage` with the detected test commands, and replace `TypeScript strict mode`/`ESLint + Prettier` with the detected language tools.

### Step B: .coverage-thresholds.json (do this NOW)

1. Read `./templates/coverage-thresholds.json` with the Read tool
2. Replace the threshold values with the user's chosen percentage (e.g., 100)
3. Replace the enforcement command with the correct one for the detected test runner:
   - pytest → `"pytest --cov --cov-fail-under={threshold}"`
   - vitest/pnpm → `"pnpm vitest run --coverage"`
   - jest/npm → `"npx jest --coverage"`
   - go → `"go test -coverprofile=coverage.out ./..."`
4. Write the result to `.coverage-thresholds.json` at the project root (NOT inside `.metaswarm/`)
5. **Verify**: Use Glob for `.coverage-thresholds.json`. If not found, you skipped this step.

### Step C: 6 command shims in .claude/commands/ (do this NOW)

Write each of these 6 files using the Write tool. Target directory is `.claude/commands/` — NOT `.metaswarm/shims/` or any other path.

For each shim, write this content (replacing `{command-name}` with the actual name):
```
<!-- Created by metaswarm setup. Routes to the metaswarm plugin. Safe to delete if you uninstall metaswarm. -->

Invoke the `/metaswarm:{command-name}` skill to handle this request. Pass along any arguments the user provided.
```

The 6 shims:
1. `.claude/commands/start-task.md` → routes to `/metaswarm:start-task`
2. `.claude/commands/prime.md` → routes to `/metaswarm:prime`
3. `.claude/commands/review-design.md` → routes to `/metaswarm:review-design`
4. `.claude/commands/self-reflect.md` → routes to `/metaswarm:self-reflect`
5. `.claude/commands/pr-shepherd.md` → routes to `/metaswarm:pr-shepherd`
6. `.claude/commands/brainstorm.md` → routes to `/metaswarm:brainstorm`

Skip any that already exist with the same content. If a shim exists with different content, overwrite it.

### Phase 3 Checkpoint

**STOP. Before continuing, verify all 3 are done:**
1. Grep CLAUDE.md for "metaswarm" → must match (unless user declined)
2. Glob for `.coverage-thresholds.json` → must exist
3. Glob for `.claude/commands/start-task.md` → must exist

**If any are missing, go back and do them now. Do NOT proceed to the next section.**

---

### Additional Files (after the 3 mandatory items above are done)

#### Knowledge Base

Read each file from `./knowledge/`:
- `patterns.jsonl`, `gotchas.jsonl`, `decisions.jsonl`, `api-behaviors.jsonl`, `codebase-facts.jsonl`, `anti-patterns.jsonl`, `facts.jsonl`

Write them to `.beads/knowledge/` in the project. Skip any that already exist.

#### Shell Utilities

Read each file from `./bin/`:
- `estimate-cost.sh`, `external-tools-verify.sh`, `pr-comments-check.sh`, `pr-comments-filter.sh`

Write them to `bin/` in the project. Make executable with `chmod +x`. Skip any that already exist.

#### TypeScript Scripts

Read each file from `./scripts/`:
- `beads-self-reflect.ts`, `beads-fetch-pr-comments.ts`, `beads-fetch-conversation-history.ts`

Write them to `scripts/` in the project. Skip any that already exist.

**Node.js dependency warning**: If Node.js was NOT detected as the project language, print:
> "Note: scripts/*.ts require Node.js (npx tsx) to run. Some advanced features (self-reflect, PR comment fetching) will work once Node.js is available. Core metaswarm functionality does not require Node.js."

#### Conditional Files

| Condition | Source | Destination |
|---|---|---|
| User chose YES for CI | `./templates/ci.yml` | `.github/workflows/ci.yml` |
| User chose YES for git hooks AND Husky detected or Node.js project | `./templates/pre-push` | `.husky/pre-push` (chmod +x) |
| User chose YES for external tools | `./templates/external-tools.yaml` | `.metaswarm/external-tools.yaml` |
| Always | `./templates/.env.example` | `.env.example` |
| Always | `./templates/SERVICE-INVENTORY.md` | `SERVICE-INVENTORY.md` |
| Always | `./templates/gitignore` | Merge into existing `.gitignore` (append missing entries, never duplicate) |

For `.gitignore`, read the existing file (if any), then append language-specific entries that are not already present. Always ensure `.env`, `.DS_Store`, and `*.log` are included.

---

## Phase 4: Profile Creation

Write `.metaswarm/project-profile.json` with all detection results and user choices:

```json
{
  "metaswarm_version": "1.0.0",
  "distribution": "plugin",
  "installed_at": "{current ISO 8601 timestamp}",
  "updated_at": "{current ISO 8601 timestamp}",
  "detection": {
    "language": "{detected language}",
    "framework": "{detected framework or null}",
    "test_runner": "{detected test runner}",
    "linter": "{detected linter or null}",
    "formatter": "{detected formatter or null}",
    "package_manager": "{detected package manager or null}",
    "type_checker": "{detected type checker or null}",
    "ci": "{detected CI system or null}",
    "git_hooks": "{detected hook system or null}"
  },
  "choices": {
    "coverage_threshold": 100,
    "external_tools": false,
    "visual_review": false,
    "ci_pipeline": false,
    "git_hooks": false
  },
  "commands": {
    "test": "{resolved test command}",
    "coverage": "{resolved coverage command}",
    "lint": "{resolved lint command or null}",
    "typecheck": "{resolved typecheck command or null}",
    "format_check": "{resolved format check command or null}"
  }
}
```

Fill all values from detection and user answers. Use `null` for anything not detected.

Command resolution reference:

| Test Runner | Pkg Mgr | Test Command | Coverage Command |
|---|---|---|---|
| vitest | pnpm | `pnpm vitest run` | `pnpm vitest run --coverage` |
| vitest | npm | `npx vitest run` | `npx vitest run --coverage` |
| vitest | yarn | `yarn vitest run` | `yarn vitest run --coverage` |
| jest | pnpm | `pnpm jest` | `pnpm jest --coverage` |
| jest | npm | `npx jest` | `npx jest --coverage` |
| jest | yarn | `yarn jest` | `yarn jest --coverage` |
| mocha | any | `npx mocha` | `npx nyc mocha` |
| pytest | -- | `pytest` | `pytest --cov --cov-fail-under={threshold}` |
| go test | -- | `go test ./...` | `go test -coverprofile=coverage.out ./...` |
| cargo test | -- | `cargo test` | `cargo tarpaulin --fail-under {threshold}` |
| mvn test | -- | `mvn test` | `mvn test jacoco:report` |
| gradle test | -- | `gradle test` | `gradle test jacocoTestReport` |

---

## Phase 5: Post-Setup Actions

### 5.1 External Tools (if enabled)

1. Check if Codex and Gemini CLIs are installed via Bash (`command -v codex`, `command -v gemini`)
2. For tools not installed, tell the user how to install them
3. For installed tools, verify with `--version`
4. Update `.metaswarm/external-tools.yaml` — set `enabled: true` for installed tools, `enabled: false` for missing ones

### 5.2 Visual Review (if enabled)

1. Run `npx playwright install chromium` via Bash
2. Report success or failure

### 5.3 Git Hooks (if enabled)

**Node.js/TypeScript**: Install Husky if not present, run `npx husky init`, write pre-push hook.
**Python**: Suggest `pip install pre-commit` and offer to create `.pre-commit-config.yaml`.
**Other**: Suggest appropriate hook tools for the ecosystem.

---

## Phase 6: Summary

Present a final summary:

```
Setup complete! Here's what was configured:

  Project:         {name}
  Language:        {language}
  Framework:       {framework or "None"}
  Test runner:     {test_runner} -> `{test command}`
  Coverage:        {threshold}% -> `{coverage command}`
  Linter:          {linter or "None"}
  Formatter:       {formatter or "None"}
  CI:              {ci or "None"}
  Git hooks:       {hooks or "None"}
  External tools:  {Enabled/Disabled}
  Visual review:   {Enabled/Disabled}

Mandatory files:
  ✔ CLAUDE.md          — {written new / appended metaswarm section / already had it}
  ✔ .coverage-thresholds.json — {threshold}% coverage, enforcement: `{command}`
  ✔ .claude/commands/   — 6 shims: start-task, prime, review-design, self-reflect, pr-shepherd, brainstorm

Other files written:
  {list every other file written or modified with its path}

You're all set! Run /start-task to begin working.
```

**Command naming**: When recommending commands to the user, always use the short shim names (`/start-task`, `/prime`, `/brainstorm`, etc.), NOT the namespaced plugin names (`/metaswarm:start-task`). The shims you just created in `.claude/commands/` make the short names work. The short names are easier to type and remember.

Offer 1-2 relevant tips based on configuration:
- If external tools enabled: "Use `/external-tools-health` to check tool status."
- If no CI set up: "Consider adding CI later -- metaswarm includes a template at `./templates/ci.yml`."
- If visual review enabled: "The visual review skill will screenshot your app during development."

---

## Missing Setup Auto-Detection

If `/start-task` is invoked and `.metaswarm/project-profile.json` does not exist, the start skill should auto-route here. This skill will run the full setup flow, then hand back to `/start-task` to continue with the user's original request.

---

## Error Handling

- If any Bash command fails, report the error and offer to skip that step or retry.
- If a file cannot be read, note it and continue with other detection.
- If AskUserQuestion is dismissed, use defaults: 100% coverage, no external tools, no visual review.
- Never leave the project half-configured. The pre-flight check allows re-running setup to completion.
- All template paths are hardcoded in this skill. Never construct file paths from user-provided input.

---

## Final Verification (run this before declaring setup complete)

Before saying "setup complete", actually verify these files exist by running these checks:

1. `Grep pattern="metaswarm" path="CLAUDE.md"` → must find matches
2. `Glob pattern=".coverage-thresholds.json"` → must find the file
3. `Glob pattern=".claude/commands/start-task.md"` → must find the file
4. `Glob pattern=".claude/commands/prime.md"` → must find the file
5. `Glob pattern=".claude/commands/brainstorm.md"` → must find the file

If ANY of these checks fail, go back to Phase 3 and create the missing files. Do NOT declare success without passing all 5 checks.
