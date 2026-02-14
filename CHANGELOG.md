# Changelog

## 0.6.0

### Added
- **External AI tool delegation** (`skills/external-tools/`): Delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI. Cross-model adversarial review ensures the writer is always reviewed by a different model. Availability-aware escalation chain: Model A (2 tries) → Model B (2 tries) → Claude (1 try) → user alert
- **Codex CLI adapter** (`skills/external-tools/adapters/codex.sh`): Shell adapter for OpenAI Codex CLI with health, implement, and review commands
- **Gemini CLI adapter** (`skills/external-tools/adapters/gemini.sh`): Shell adapter for Google Gemini CLI with health, implement, and review commands
- **Shared adapter helpers** (`skills/external-tools/adapters/_common.sh`): 14 shared helper functions including `safe_invoke()` with macOS-compatible timeout fallback, worktree management, cost extraction, structured JSON output, and error classification
- **Cross-model review rubric** (`rubrics/external-tool-review-rubric.md`): Binary PASS/FAIL rubric for cross-model adversarial review with file:line evidence requirements
- **External tools config template** (`templates/external-tools.yaml`): Per-project configuration for adapter settings, routing strategy, and budget limits
- **External tools setup guide** (`templates/external-tools-setup.md`): User-facing installation and authentication guide for Codex and Gemini CLI
- **`/project:external-tools-health` command** (`commands/external-tools-health.md`): Slash command to check external tool availability and authentication status
- **External tools verification script** (`bin/external-tools-verify.sh`): End-to-end verification with 15 checks covering shared helpers, both adapters, and file existence
- **External tools detection in start-task**: `/project:start-task` now auto-detects installed external tools and suggests enabling them
- **External tools onboarding**: Added external tools sections to INSTALL.md, GETTING_STARTED.md, and CLAUDE.md template
- **`metaswarm init` copies external-tools.yaml**: Copies config template to `.metaswarm/` during project initialization (disabled by default)

### Changed
- Updated counts: 8 skills (was 7), 8 commands (was 8), 7 rubrics (was 7)
- CLAUDE.md template now includes external tools section
- Start-task command includes external tools availability check as step 0.5

## 0.5.1

### Added
- **Visual review skill** (`skills/visual-review/SKILL.md`): Playwright-based screenshot capture for reviewing web UIs, presentations (Reveal.js slides), and rendered pages. Supports local files, localhost servers, and deployed URLs with responsive viewport testing
- **Visual review remote support**: HTTP file server fallback for headless/remote environments where `open` command is unavailable

### Changed
- CLAUDE.md template now includes visual review reference

## 0.5.0

### Added
- **Team Mode** support with dual-mode coordination: uses `TeamCreate`/`SendMessage` when available, falls back to `Task` mode automatically
- **Plan Review Gate** (`skills/plan-review-gate/SKILL.md`): 3 adversarial reviewers (Feasibility, Completeness, Scope & Alignment) validate every implementation plan before execution begins
- **6 development guides** (`guides/`): agent-coordination, git-workflow, testing-patterns, coding-standards, worktree-development, build-validation
- **Adversarial plan review rubric** (`rubrics/plan-review-rubric.md`)
- Previously untracked framework files now included (commands, plugin copies, rubrics, templates, scripts)

### Fixed
- 132 "(example path)" rendering bugs across 19 agent files

### Changed
- Updated counts: 7 skills (was 6), 8 commands (was 7), 7 rubrics (was 6)
- CLI scaffolding updated with new templates and guides

## 0.4.1

### Changed
- Site updates for v0.4.0 process improvements

## 0.4.0

### Added
- **Plan validation pre-flight checklist**: Catches structural issues (architecture, dependencies, API contracts, security, UI/UX, external dependencies) before design review
- **UX Reviewer**: Added as 6th design review agent to verify user flows and integration work units
- **Project context document**: Maintained by orchestrator, passed to each coder subagent to prevent context loss
- **`SERVICE-INVENTORY.md` tracking**: Tracks services, factories, and shared modules across work units
- **External dependency detection**: Scans specs for API keys/credentials and prompts users before implementation
- **New templates**: `.gitignore`, `.env.example`, `SERVICE-INVENTORY.md`, `UI-FLOWS.md`, `CLAUDE.md`, `CLAUDE-append.md`, `ci.yml`

### Changed
- Quality gates converted from advisory recommendations to **blocking state transitions** with explicit state machine
- Coverage enforcement reads `.coverage-thresholds.json` as a blocking gate
- 12 anti-patterns documented (up from 8), including: skipping coverage, building UI in isolation, advisory quality gates, proceeding without external credentials

## 0.3.2

### Added
- "One-Shot Build" recipe in GETTING_STARTED.md: end-to-end example from empty repo to working app in one prompt
- "One Prompt. Full App." section on docs site with copyable setup and prompt
- Quick one-shot example in README.md install section
- Tips for writing effective one-shot specs (DoD items, tech stack, file scope, checkpoints)

## 0.3.1

### Changed
- Updated `docs/index.html` site to reflect v0.3.0 changes: 9-phase pipeline with orchestrated execution loop, "Trust Nothing, Verify Everything" section, dual-mode code reviewer, updated component counts (6 skills, 6 rubrics), proactive human checkpoints

## 0.3.0

### Added
- **Orchestrated Execution skill** (`skills/orchestrated-execution/SKILL.md`): 4-phase execution loop (IMPLEMENT → VALIDATE → ADVERSARIAL REVIEW → COMMIT) for rigorous, spec-driven implementation of complex tasks
- **Adversarial Review rubric** (`rubrics/adversarial-review-rubric.md`): Binary PASS/FAIL spec compliance verification with evidence requirements (file:line citations), distinct from collaborative code review
- **Dual-mode Code Review Agent**: Collaborative mode (existing, APPROVED/CHANGES REQUIRED) and Adversarial mode (new, PASS/FAIL against DoD contract with fresh reviewer rule)
- **Work Unit Decomposition** in Issue Orchestrator: Break implementation plans into discrete work units with DoD items, file scopes, and dependency graphs
- **Final Comprehensive Review** phase: Cross-unit integration check after all work units pass individually
- **Problem Definition Phase** in start-task command: Ensures clear scope, DoD items, file scope, and human checkpoints before implementation
- **"Choosing a Workflow" decision guide** in USAGE.md: Helps users pick the right level of process for their task
- **Recovery protocol**: Structured DIAGNOSE → CLASSIFY → RETRY (max 3) → ESCALATE with failure history

### Changed
- Issue Orchestrator workflow now uses 4-phase orchestrated execution loop instead of linear implementation flow (backward compatible — linear flow still works for tasks without DoD items)
- Workflow phases expanded from 8 to 9 (added Work Unit Decomposition, Orchestrated Execution, Final Review)
- README architecture diagram updated to show orchestrated execution loop
- Design principles updated: added "Trust Nothing, Verify Everything" and expanded "Human-in-the-Loop" to include proactive checkpoints
- GETTING_STARTED.md: added Step 4.5 explaining orchestrated execution with when-to-use and when-not-to-use guidance
- Updated counts: 6 skills (was 5), 6 rubrics (was 5)

## 0.2.0

### Added
- `--with-coverage` flag: copies `coverage-thresholds.json` to project root
- `--with-husky` flag: initializes Husky and installs pre-push coverage enforcement hook (implies `--with-coverage`)
- `--with-ci` flag: creates `.github/workflows/coverage.yml` for CI coverage gating (implies `--with-coverage`)
- Pre-publish check for `package.json` before attempting `npx husky init`
- `templates/pre-push`: Husky-compatible pre-push hook with lint, typecheck, format, and coverage checks
- `templates/ci-coverage-job.yml`: GitHub Actions workflow for coverage enforcement
- `docs/coverage-enforcement.md`: documentation for the three enforcement gates

### Changed
- `metaswarm init` without flags still works as before (no breaking changes)
- Husky recommendation message now suggests `metaswarm init --with-husky`
- Summary output reports only what was actually set up (not just what was requested)
- Updated `INSTALL.md`, `GETTING_STARTED.md`, and `docs/coverage-enforcement.md` with flag-based setup instructions

## 0.1.0

- Initial release
- CLI scaffolding via `metaswarm init`
- 18 agents, 5 skills, 7 commands, 5 rubrics
- BEADS knowledge base templates
- Auto-detection of `.husky/` for pre-push hook installation
