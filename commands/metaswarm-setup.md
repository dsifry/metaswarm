# Metaswarm Guided Setup

Interactive, Claude-guided setup for metaswarm in your project. Detects your stack, asks targeted questions, and customizes everything automatically.

## Usage

```text
/project:metaswarm-setup
```

---

## Phase 1: Bootstrap Check

Before anything else, verify that metaswarm components are installed.

### Step 1.1 — Check for plugin directory

Use the Glob tool to check if `.claude/plugins/metaswarm/` exists:

```
Glob: .claude/plugins/metaswarm/**/*
```

- If files are found, metaswarm components are installed. Proceed to Step 1.2.
- If NO files are found, tell the user: "Metaswarm components aren't installed yet. Let me install them now." Then run via Bash:

```bash
npx metaswarm install
```

Wait for the command to complete. If it fails, tell the user to check their Node.js installation and try `npm install -g metaswarm` manually.

### Step 1.2 — Check for existing project profile

Use the Glob tool to check if `.metaswarm/project-profile.json` exists.

- If it exists, read it and present the current configuration summary to the user. Use AskUserQuestion to ask:
  - "You already have a metaswarm project profile. What would you like to do?"
  - Options: "Re-run setup (Recommended)" / "Skip setup"
  - If user chooses "Skip setup", stop here with: "Setup skipped. Your existing configuration is unchanged."
  - If user chooses "Re-run setup", continue to Phase 2.
- If it does NOT exist, continue to Phase 2.

---

## Phase 2: Project Detection

You MUST detect all of the following automatically by scanning the project directory. Use the Glob and Read tools — do NOT ask the user for any of this information. Detect everything silently, then present the results.

### 2.1 — Language Detection

Check for these marker files using Glob at the project root:

| Marker File | Language |
|---|---|
| `package.json` | Node.js / JavaScript |
| `tsconfig.json` | TypeScript (refines Node.js to TypeScript) |
| `pyproject.toml` OR `setup.py` OR `requirements.txt` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` OR `build.gradle` OR `build.gradle.kts` | Java |
| `Gemfile` | Ruby |

If multiple languages are detected, note all of them but use the primary one (the one with the most infrastructure) for command generation.

If `tsconfig.json` exists alongside `package.json`, the language is "TypeScript" (not just "Node.js").

### 2.2 — Framework Detection

If `package.json` exists, Read it and check `dependencies` and `devDependencies` for:

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

If `pyproject.toml` or `requirements.txt` exists, check for:

| Dependency | Framework |
|---|---|
| `fastapi` | FastAPI |
| `django` | Django |
| `flask` | Flask |

If `go.mod` exists, Read it and check for:

| Module | Framework |
|---|---|
| `github.com/gin-gonic/gin` | Gin |
| `github.com/labstack/echo` | Echo |
| `github.com/gofiber/fiber` | Fiber |

If no framework is detected, set framework to `null`.

### 2.3 — Package Manager Detection (Node.js only)

If the language is Node.js or TypeScript, check for lock files:

| Lock File | Package Manager |
|---|---|
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `bun.lockb` | bun |
| `package-lock.json` | npm |

If no lock file is found, default to `npm`.

For non-Node.js languages, set package_manager to `null`.

### 2.4 — Test Runner Detection

Check in this order (first match wins per ecosystem):

**Node.js / TypeScript:**
1. Glob for `vitest.config.*` — if found, test runner is `vitest`
2. Read `package.json` → if `vitest` in `devDependencies`, test runner is `vitest`
3. Glob for `jest.config.*` — if found, test runner is `jest`
4. Read `package.json` → if `jest` in `devDependencies`, test runner is `jest`
5. Read `package.json` → if `mocha` in `devDependencies`, test runner is `mocha`

**Python:**
1. Read `pyproject.toml` → if `[tool.pytest]` section exists, test runner is `pytest`
2. Check Python dependencies for `pytest` → test runner is `pytest`
3. Default: `pytest` (standard for Python)

**Go:**
- If `go.mod` exists → test runner is `go test` (built-in)

**Rust:**
- If `Cargo.toml` exists → test runner is `cargo test` (built-in)

**Java:**
- If `pom.xml` exists → test runner is `maven` (mvn test)
- If `build.gradle` exists → test runner is `gradle` (gradle test)

### 2.5 — Linter Detection

| Marker | Linter |
|---|---|
| `.eslintrc*` OR `eslint.config.*` files exist, OR `eslint` in devDependencies | eslint |
| `biome.json` OR `@biomejs/biome` in devDependencies | biome |
| `[tool.ruff]` section in `pyproject.toml` OR `ruff.toml` exists | ruff |
| `.golangci.yml` OR `.golangci.yaml` exists | golangci-lint |
| `clippy` section in Cargo.toml or `.clippy.toml` exists | clippy |

### 2.6 — Formatter Detection

| Marker | Formatter |
|---|---|
| `.prettierrc*` files exist OR `prettier` in devDependencies | prettier |
| `biome.json` exists (biome also formats) | biome |
| `black` in Python dependencies | black |
| `[tool.ruff.format]` section in `pyproject.toml` | ruff format |
| `rustfmt.toml` OR `.rustfmt.toml` exists | rustfmt |

Note: If biome is detected as both linter and formatter, report it once as "Biome (lint + format)".

### 2.7 — Type Checker Detection

| Marker | Type Checker |
|---|---|
| `tsconfig.json` exists | tsc |
| `mypy` in Python deps OR `[tool.mypy]` in `pyproject.toml` | mypy |
| `pyright` in Python deps OR `pyrightconfig.json` exists | pyright |

For Go (`go vet`) and Rust (`cargo check`), type checking is built-in — note this but don't list as a separate tool.

### 2.8 — CI Detection

| Marker | CI System |
|---|---|
| `.github/workflows/` directory exists (with .yml files inside) | GitHub Actions |
| `.gitlab-ci.yml` exists | GitLab CI |
| `Jenkinsfile` exists | Jenkins |
| `.circleci/config.yml` exists | CircleCI |

### 2.9 — Git Hooks Detection

| Marker | Hook System |
|---|---|
| `.husky/` directory exists | Husky |
| `.pre-commit-config.yaml` exists | pre-commit |
| `.lefthook.yml` exists | Lefthook |

### 2.10 — Present Detection Results

After completing all detection, present findings to the user in a clear, formatted summary:

```
I detected the following about your project:

  Language:        TypeScript (Node.js)
  Framework:       Next.js
  Package manager: pnpm
  Test runner:     Vitest
  Linter:          ESLint
  Formatter:       Prettier
  Type checker:    tsc
  CI:              GitHub Actions
  Git hooks:       Husky
```

For items that were not detected, show "None detected" — these will inform which questions to ask in Phase 3.

If a language could not be detected at all, use AskUserQuestion to ask the user what language/stack they're using before proceeding.

---

## Phase 3: Targeted Questions

Use the AskUserQuestion tool to ask ONLY the questions that are relevant based on detection results. Do NOT ask about things that were auto-detected. Ask 3-5 questions maximum in a single AskUserQuestion call.

### Question Selection Logic

**Always ask:**

1. **Coverage threshold** — "What test coverage threshold do you want to enforce?"
   - Options: "100% (Recommended)", "80%", "60%", "Custom"
   - Header: "Coverage"

**Ask only if relevant:**

2. **External AI tools** — Ask ONLY if the project would benefit from it (non-trivial project):
   - "Set up external AI tools (Codex/Gemini) for cost savings on implementation tasks?"
   - Options: "Yes (Recommended)", "No"
   - Header: "AI Tools"

3. **Visual review** — Ask ONLY if a web framework was detected (Next.js, Nuxt, React, Vue, Angular, SvelteKit, Django with templates, Flask with templates):
   - "Enable visual screenshot review for UI changes?"
   - Options: "Yes", "No"
   - Header: "Visual"

4. **CI pipeline** — Ask ONLY if NO CI system was detected:
   - "Create a GitHub Actions CI pipeline for automated testing?"
   - Options: "Yes (Recommended)", "No"
   - Header: "CI"

5. **Git hooks** — Ask ONLY if NO git hooks were detected:
   - "Set up git hooks for pre-push quality checks?"
   - Options: "Yes (Recommended)", "No"
   - Header: "Hooks"

6. **BEADS task tracking** — Ask ONLY if the `bd` CLI is available (check via `which bd` or `command -v bd` in Bash):
   - "Set up BEADS task tracking for knowledge management?"
   - Options: "Yes", "No"
   - Header: "BEADS"

---

## Phase 4: Customize Installed Files

Based on detection results and user answers, customize the following files. Read each file first, then use Edit to modify it.

### 4.1 — Customize CLAUDE.md

Read the project's `CLAUDE.md` file. Find and update the TODO sections.

**Test commands section** — Find the lines:
```
<!-- TODO: Update these commands for your project's test runner -->
- Test command: `npm test`
- Coverage command: `npm run test:coverage`
```

Replace with the correct commands based on detected test runner and package manager:

| Test Runner | Package Manager | Test Command | Coverage Command |
|---|---|---|---|
| vitest | pnpm | `pnpm vitest run` | `pnpm vitest run --coverage` |
| vitest | npm | `npx vitest run` | `npx vitest run --coverage` |
| vitest | yarn | `yarn vitest run` | `yarn vitest run --coverage` |
| vitest | bun | `bun vitest run` | `bun vitest run --coverage` |
| jest | pnpm | `pnpm jest` | `pnpm jest --coverage` |
| jest | npm | `npx jest` | `npx jest --coverage` |
| jest | yarn | `yarn jest` | `yarn jest --coverage` |
| mocha | any | `npx mocha` | `npx nyc mocha` |
| pytest | — | `pytest` | `pytest --cov --cov-fail-under={threshold}` |
| go test | — | `go test ./...` | `go test -coverprofile=coverage.out ./...` |
| cargo test | — | `cargo test` | `cargo tarpaulin` |
| maven | — | `mvn test` | `mvn test jacoco:report` |
| gradle | — | `gradle test` | `gradle test jacocoTestReport` |

Remove the TODO comment after replacing. The updated section should look like:
```
- Test command: `pnpm vitest run`
- Coverage command: `pnpm vitest run --coverage`
```

**Code quality section** — Find the lines:
```
<!-- TODO: Update these for your project's language and tools -->
- TypeScript strict mode, no `any` types
- ESLint + Prettier
```

Replace with language-appropriate descriptions:

| Language | Code Quality Line 1 | Code Quality Line 2 |
|---|---|---|
| TypeScript | `TypeScript strict mode, no \`any\` types` | `{linter} + {formatter}` |
| JavaScript | `Modern ES modules, strict mode` | `{linter} + {formatter}` |
| Python | `Type hints required (PEP 484), no \`Any\` escape hatches` | `{linter} + {formatter}` |
| Go | `Go idioms, \`go vet\` clean, exported types documented` | `{linter}` |
| Rust | `Clippy clean (\`#![deny(clippy::all)]\`), no \`unsafe\` without comment` | `{formatter}` |
| Java | `Null-safe patterns, no raw types` | `{linter} + {formatter}` |
| Ruby | `Rubocop clean, frozen string literals` | `RuboCop` |

Replace `{linter}` and `{formatter}` with the actual detected tools. If none detected, omit that part.

Remove the TODO comment after replacing.

### 4.2 — Customize .coverage-thresholds.json

Read `.coverage-thresholds.json`. Update:

**Threshold values** — If user chose something other than 100%:
```json
"thresholds": {
  "lines": {chosen_value},
  "branches": {chosen_value},
  "functions": {chosen_value},
  "statements": {chosen_value}
}
```

**Enforcement command** — Map to the correct coverage command:

| Test Runner | Package Manager | Enforcement Command |
|---|---|---|
| vitest | pnpm | `pnpm vitest run --coverage` |
| vitest | npm | `npx vitest run --coverage` |
| vitest | yarn | `yarn vitest run --coverage` |
| jest | pnpm | `pnpm jest --coverage` |
| jest | npm | `npx jest --coverage` |
| jest | yarn | `yarn jest --coverage` |
| pytest | — | `pytest --cov --cov-fail-under={threshold}` |
| go test | — | `go test -coverprofile=coverage.out ./...` |
| cargo test | — | `cargo tarpaulin --fail-under {threshold}` |
| maven | — | `mvn test jacoco:report` |
| gradle | — | `gradle test jacocoTestReport` |

### 4.3 — Update .gitignore

Read the project's `.gitignore` file (it may be the template or the user's own). Append any missing language-specific entries. Do NOT duplicate entries that already exist.

**Node.js / TypeScript — ensure these are present:**
```
node_modules/
dist/
.next/
.nuxt/
.env
.env.local
.env.*.local
coverage/
```

**Python — ensure these are present:**
```
__pycache__/
*.pyc
.venv/
venv/
*.egg-info/
.env
dist/
coverage/
.mypy_cache/
.pytest_cache/
```

**Go — ensure these are present:**
```
vendor/
.env
coverage.out
```

**Rust — ensure these are present:**
```
target/
.env
```

**Java — ensure these are present:**
```
build/
.gradle/
target/
.env
*.class
```

**Always ensure these are present regardless of language:**
```
.DS_Store
*.log
.env
```

### 4.4 — External Tools Setup

If the user chose YES for external AI tools:

1. Check if Codex CLI is installed: run `which codex` via Bash
2. Check if Gemini CLI is installed: run `which gemini` via Bash
3. For any tool NOT installed, tell the user:
   - Codex: "Codex CLI is not installed. Install it with: `npm i -g @openai/codex`"
   - Gemini: "Gemini CLI is not installed. Install it with: `npm i -g @google/gemini-cli`"
   - Ask if the user wants you to install them now. If yes, run the install commands via Bash.
4. For installed tools, verify they're authenticated:
   - Codex: run `codex --version` — if it works, it's likely configured
   - Gemini: run `gemini --version` — if it works, it's likely configured
5. Ensure `.metaswarm/` directory exists (create via Bash `mkdir -p .metaswarm` if needed)
6. Copy or create `.metaswarm/external-tools.yaml` with both tools configured:
   - Set `enabled: true` for installed tools
   - Set `enabled: false` for tools that aren't installed
7. Tell the user about any auth steps needed (e.g., "Run `codex login` to authenticate with OpenAI")

### 4.5 — Visual Review Setup

If the user chose YES for visual review:

1. Check if Playwright is available: run `npx playwright --version` via Bash
2. If not available or Chromium not installed, tell the user: "Installing Playwright Chromium for screenshot capabilities..."
3. Run `npx playwright install chromium` via Bash
4. Confirm success

### 4.6 — Git Hooks Setup

If the user chose YES for git hooks and no hooks were detected:

**For Node.js / TypeScript projects:**
1. Tell the user: "Setting up Husky for git hooks..."
2. Check if husky is in devDependencies. If not, install it:
   - pnpm: `pnpm add -D husky`
   - npm: `npm install -D husky`
   - yarn: `yarn add -D husky`
3. Run `npx husky init` via Bash
4. Copy the pre-push hook template: read `templates/pre-push` and write it to `.husky/pre-push`
5. Make it executable: `chmod +x .husky/pre-push`

**For Python projects:**
1. Tell the user: "Consider setting up pre-commit hooks. Install with: `pip install pre-commit`"
2. Offer to create a basic `.pre-commit-config.yaml` with ruff/black/mypy hooks

**For other languages:**
1. Suggest appropriate hook tools for their ecosystem

### 4.7 — BEADS Setup

If the user chose YES for BEADS and `bd` is available:

1. Run `bd init` via Bash
2. Confirm success
3. Tell the user: "BEADS initialized. Use `/project:prime` to load knowledge before starting tasks."

---

## Phase 5: Write Project Profile

Create the `.metaswarm/` directory if it doesn't exist:
```bash
mkdir -p .metaswarm
```

Write `.metaswarm/project-profile.json` with the following structure. Use the Write tool.

```json
{
  "metaswarm_version": "0.7.0",
  "installed_at": "{current ISO 8601 timestamp}",
  "updated_at": "{current ISO 8601 timestamp}",
  "detection": {
    "language": "{detected language, e.g., 'typescript'}",
    "framework": "{detected framework or null}",
    "test_runner": "{detected test runner, e.g., 'vitest'}",
    "linter": "{detected linter or null}",
    "formatter": "{detected formatter or null}",
    "package_manager": "{detected package manager or null}",
    "type_checker": "{detected type checker or null}",
    "ci": "{detected CI system or null}",
    "git_hooks": "{detected hook system or null}"
  },
  "choices": {
    "coverage_threshold": {chosen threshold number, e.g., 100},
    "external_tools": {true or false},
    "visual_review": {true or false},
    "ci_pipeline": {true or false, only if CI question was asked},
    "git_hooks": {true or false, only if hooks question was asked},
    "beads": {true or false, only if BEADS question was asked}
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

Fill in ALL values based on detection results and user answers. Use `null` for anything not detected or not applicable.

For the `commands` section, derive the correct commands:

| Tool | Command |
|---|---|
| eslint (pnpm) | `pnpm eslint .` |
| eslint (npm) | `npx eslint .` |
| biome (pnpm) | `pnpm biome check .` |
| ruff | `ruff check .` |
| golangci-lint | `golangci-lint run` |
| tsc (pnpm) | `pnpm tsc --noEmit` |
| tsc (npm) | `npx tsc --noEmit` |
| mypy | `mypy .` |
| pyright | `pyright` |
| prettier (pnpm) | `pnpm prettier --check .` |
| prettier (npm) | `npx prettier --check .` |
| biome format | `pnpm biome check --formatter-enabled=true .` |
| black | `black --check .` |
| ruff format | `ruff format --check .` |

---

## Phase 6: Verify & Summary

### 6.1 — Health Checks

If external tools were enabled, run health checks for each enabled tool:

```bash
# For Codex
codex --version 2>/dev/null && echo "Codex: OK" || echo "Codex: NOT AVAILABLE"

# For Gemini
gemini --version 2>/dev/null && echo "Gemini: OK" || echo "Gemini: NOT AVAILABLE"
```

Report any tools that failed health checks and suggest remediation.

### 6.2 — Final Summary

Present a comprehensive summary to the user:

```
Setup complete! Here's what was configured:

  Project:         {project name from package.json or directory name}
  Language:        {language}
  Framework:       {framework or "None"}
  Test runner:     {test_runner} → `{test command}`
  Coverage:        {threshold}% → `{coverage command}`
  Linter:          {linter or "None"}
  Formatter:       {formatter or "None"}
  Type checker:    {type_checker or "None"}
  CI:              {ci or "None"}
  Git hooks:       {hooks or "None"}
  External tools:  {Enabled/Disabled}
  Visual review:   {Enabled/Disabled}
  BEADS:           {Enabled/Disabled}

Files modified:
  - CLAUDE.md (test commands, code quality section)
  - .coverage-thresholds.json (enforcement command, thresholds)
  - .gitignore (language-specific entries)
  - .metaswarm/project-profile.json (created)
  {list any other files modified}

You're all set! Try `/project:start-task` on a small task to see metaswarm in action.
```

### 6.3 — Post-Setup Tips

Based on what was configured, offer 1-2 relevant tips:

- If external tools enabled: "Use `/project:external-tools-health` to check tool status anytime."
- If BEADS enabled: "Use `/project:prime` before starting work to load relevant knowledge."
- If no CI was set up: "Consider adding CI later — metaswarm includes a GitHub Actions template in `templates/ci.yml`."
- If visual review enabled: "The visual review skill can screenshot your app during development. Agents will use it automatically."

---

## Error Handling

Throughout the setup process:

- If any Bash command fails, report the error clearly and offer to skip that step or retry
- If a file can't be read (permissions, missing), note it and continue with other detection
- If AskUserQuestion times out or is dismissed, use sensible defaults (100% coverage, no external tools, no visual review)
- Never leave the project in a half-configured state — if setup is interrupted, the user should be able to re-run `/project:metaswarm-setup` to pick up where they left off (the Phase 1 re-setup check handles this)
