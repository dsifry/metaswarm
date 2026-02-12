# Changelog

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
