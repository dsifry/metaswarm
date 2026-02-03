# Changelog

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
