# Changelog

## [Unreleased]

### Added

- **Reviews now stop and ask when the requirement is the problem** (#103). The review iteration rule gains a Clarify line (line 2, after the clean pass). It fires on four signals:
  - C1: a blocker needs the user (`needs_user`) or rests on an unconfirmed assumption;
  - C2: blocker totals are not converging over three rounds, or reviewers diverge (the total did not fall, one reviewer dropped to no blockers and another rose; a falling total never counts);
  - C3: fixes keep causing new blockers;
  - C4: the same theme recurs across rounds.
  Instead of a plain escalation, the gate writes a Clarification report with a misunderstanding analysis and five options. There is no approve or override option. "Keep going" never defaults a `needs_user` question. The escalation lines (3-5) gain a "Clarify the requirement / re-brainstorm" option, and the rule lines are now numbered 1 to 7 (they ran 1 to 6).
- **A deterministic helper applies the rule** (#103). `lib/review-rule.js` reads a per-gate review-history file under `.beads/context/review-history/` and prints the rule line, action and signals, so the orchestrator no longer does the signal arithmetic by hand. In the metaswarm repo it runs the working copy, elsewhere the installed plugin's copy.
- **Reviewers report signal fields** (#103). Every finding carries `theme`. Blockers also carry `needs_user`, `origin` (implementation, requirement or assumption) and, when the blocker rests on an assumption, the ledger id. Only blockers feed the signals.
- **Brainstorming keeps an assumption ledger** (#103). `brainstorming-extension` loads at the start of every brainstorming session with an assumption ledger, a confirmation rule and a Common misreadings checklist. The no-superpowers `/brainstorm` fallback applies them too.
- **Misreadings are learned per project** (#103). A confirmed misunderstanding is stored in the project's knowledge base as a gotcha tagged `misunderstanding`, with an opt-in upstream issue.
- **Review history is recovered on resume** (#103). `/prime`, `/start-task`, `/start` and `/handoff` read `.beads/context/review-history/` so a clarify-pending gate re-asks its questions after compaction or in a new session, and the handoff names the open history files.

### Changed

- **The overengineering check now comes before the "two or more reviewers, so iterate" line** (#103). The rule is: pass, clarify, cap, recurring or disputed, overengineering, then iterate (line 6 for a fixed critical/major finding or two or more reviewers, line 7 otherwise). Before, a round with blockers from two or more reviewers iterated before the overengineering check could run. This is a behaviour change: a round flagged `overengineering` now gets the check first.

### Upgrading

`/setup` skips instruction files (CLAUDE.md, AGENTS.md, GEMINI.md) that already have a metaswarm section, and `/update` does not rewrite them. Re-running `/setup` will not do it either. Existing projects must update their instruction file by hand from the new templates (`templates/CLAUDE.md`, `templates/AGENTS.md` and `templates/GEMINI.md` in the metaswarm plugin):

1. Replace "Delivery Scope & Review Iteration": the new bullet order, with Clarify after the clean pass.
2. Add the new "During Brainstorming" section: it loads the brainstorming extension at the start of every session.
3. CLAUDE.md only: replace the Context Recovery line, which now names the review history and `clarify-pending`.

## 0.15.0

### Fixed

- **The Go coverage gate now fails below the threshold** (#78). `go test` has no threshold flag, so the `go test -coverprofile=coverage.out ./...` command that `/setup` wrote never failed. Setup now writes `.metaswarm/go-coverage-gate.go`, a standard-library Go program, and sets `enforcement.command` to `go run .metaswarm/go-coverage-gate.go`. It reads `.coverage-thresholds.json` on every run, compares exact statement counts (2,499 of 2,500 fails at 100%, though `go tool cover` shows 100.0%), enforces `lines` and `statements`, and reports `branches` and `functions` as not enforced. It passes the CI template's command guard. Existing Go projects: re-run `/setup`, which replaces the old `go test` command with the gate and writes the gate file, or set the command by hand (see `docs/coverage-enforcement.md`).
- **Re-running `/setup` with a new threshold updates `.coverage-thresholds.json`** (#79). With the new `--reconfigure` flag, which interactive `/setup` always passes, `lib/setup-mandatory-files.sh` updates an existing file's four thresholds and a `--cov-fail-under`/`--fail-under` value in `enforcement.command`, and keeps every other setting. This also applies the user's answers on a first `/setup` after `npx metaswarm setup` copied the template. It replaces the old bare `go test` command with the Go gate, keeping that command's own flags and packages, and warns when the command still embeds the old threshold in another form or names a different test runner than the one detected. The session hook's silent self-heal never changes an existing file. The script's JSON output gains a `warnings` array and escapes messages properly.
- **Test suites with an EXIT trap fail when they abort** (#75). On macOS bash 3.2 a `set -u` abort exited with the trap's status 0, so a crashed suite looked like a pass.
- **Gemini commands point at skills and files that exist** (#50). Eight generated `commands/metaswarm/*.toml` prompts told the agent to invoke a metaswarm skill that doesn't exist (`start-task`, `prime`, `review-design`, `self-reflect`, `brainstorm`, `update`, `handle-pr-comments`, `external-tools-health`). They now name the real skill (`design-review-gate`, `handling-pr-comments`) or tell the agent to follow the command's `commands/<name>.md` in the extension directory, with `PLUGIN_ROOT` set to it (for `/start-task` that is `commands/start-task.md`, the same flow Claude runs; Gemini's `/update` also names `gemini extensions update metaswarm`). A test checks every TOML target.
- **No more `npx metaswarm install`** (#74). The migrate skill's rollback notes named a command that doesn't exist. They now say to restore the old files from git, and what `npx metaswarm init` and `setup` actually do today. A test fails on any `metaswarm install` in tracked docs.
- **The two pipelines are stated, and every order statement matches** (#73). `guides/workflow-enforcement.md` now shows both: on the brainstorming path (`/start-task`, `/brainstorm`) the Design Review Gate reviews the design doc before writing-plans. In full orchestration it reviews the plan, after the Plan Review Gate. The CLAUDE/AGENTS/GEMINI templates, README, GETTING_STARTED, USAGE, the start and orchestrated-execution skills, the issue-orchestrator diagram and the landing page now name the Plan Review Gate and say which pipeline they describe. GETTING_STARTED's `/start-task` list had the gates in the wrong order. A line-level guard with self-test fixtures catches chains that skip the Plan Review Gate.
- **CI and hook templates fit the project** (#83).
  - `/setup` renders `.github/workflows/ci.yml` with the new `lib/render-ci.sh`. It keeps the toolchain steps for the detected stack (Node with npm, Python, Go or Rust) and drops the others. Other stacks (and pnpm, yarn, bun, Poetry, uv or Pipenv projects) are pointed at `templates/ci-coverage-job.yml`, and the required-check offer is skipped for them.
  - The workflow runs on pushes to the repo's default branch, read from `origin/HEAD` or `gh repo view`, instead of a hard-coded `main`. It checks pull requests into any branch.
  - After writing CI, `/setup` asks whether to make the `CI checks` job required on the default branch. On yes, `lib/require-ci-check.sh` adds a ruleset through `gh api`, leaving existing branch protection alone, and prints the manual steps if it can't.
  - The CI template and `templates/pre-push` run `lint` and `typecheck` only when `package.json` defines them. A failing script, or a `package.json` that can't be parsed, still fails the build or blocks the push. The hook now blocks on a failing typecheck, and uses pnpm when the project does.
  - The plan-review gate always runs for a plan that builds user-facing UI, whatever its size, so the check for a UI integration work unit isn't skipped.
- **PR skills no longer call scripts that don't exist** (#91). `handling-pr-comments` told the agent to run `bin/pr-comments-out-of-scope.sh`. Phase 2c now lists the out-of-scope comments itself: unresolved threads GitHub marks outdated or that no longer map to a diff line, and general PR discussion comments. `pr-shepherd`, the start skill and the issue-orchestrator offered `bin/create-pr-with-shepherd.sh`. They now say to run `gh pr create`, then `/pr-shepherd <pr-number>` (the orchestrator delegates it to a background shepherd). Phase 2c prints every comment in full, replies included. Neither script ever shipped. A test fails when a tracked doc, skill, command, agent or template references a `bin/` script that isn't in `bin/`.
- **Migrate backs up untracked legacy files instead of deleting them** (#90). Step 7 removed untracked copies with `rm -f`, which git can't undo. It now moves them to `.metaswarm/migrate-backup-<timestamp>/`, keeping their paths, and the summary names the folder. Rollback shows how to copy them back (symbolic links as links; a file already back counts as restored, a different file at the path is never overwritten, and a conflict or failed copy keeps the backup), Step 7 reports any file it couldn't move instead of counting it, and the "Reversible" note says so. A test runs the skill's own backup and restore snippets against a scratch repo.
- **The issue-orchestrator runs the Plan Review Gate** (#89). Phase 2 went Research → Plan → a lone CTO review, so neither the Plan Review Gate nor the 6-reviewer Design Review Gate ran, although its diagram showed both. Phase 2 now runs the `plan-review-gate` skill (3 adversarial reviewers), then the `design-review-gate` skill on the plan, both blocking, before work unit decomposition. The same change is made in `skills/start/agents/issue-orchestrator.md`. The order guard now splits each chain into steps, so it also catches emphasis (`**Design Review Gate**`), other arrows (`⇒`, `=>`), `/review-design`, an intermediate step (`Plan → Plan Validation → Design Review Gate`) and, on the brainstorming path, a Plan Review Gate before the Design Review Gate. The #73 regex still runs on every line, so nothing it caught is missed. Each variant has a self-test fixture.
- **The fallback CI job and the pre-push hook fit more projects** (#97).
  - `templates/ci-coverage-job.yml`, where `/setup` sends stacks it can't render a full workflow for, picks pnpm, yarn (classic or Berry), bun or npm from the lockfile instead of always running `npm ci`. Without a `package.json` it fails with a message to add the project's toolchain, and its header shows Poetry, uv, Pipenv and Java install lines.
  - `/setup` asks those stacks whether to add the coverage job, not whether to "create a CI pipeline" it won't write.
  - The pre-push hook stops the push when a project has a `package.json` but `node` isn't on PATH, instead of skipping lint and typecheck. Its format step uses pnpm only with a `pnpm-lock.yaml`, like lint and typecheck.
  - The rendered `ci.yml` passes actionlint with shellcheck (the coverage step's literal `$` pattern is annotated).
- **A plan revised in design review goes back through the Plan Review Gate** (#94). `guides/workflow-enforcement.md` and the design-review-gate skill now state what the issue-orchestrator already does: in full orchestration, a plan the Design Review Gate revises gets a fresh Plan Review Gate round, and a revision that fails it goes back through both gates. On the brainstorming path the Design Review Gate re-reviews a revised design doc in its usual fresh round, and the Plan Review Gate runs once, on the plan writing-plans writes. The order guard now treats a leading `/start-task` as the brainstorming path, splits chains on `➡`, `⮕`, `⟹`, `──►`, `─►`, plain `──` and a spaced ` > `, counts "Plans" as a plan step, and sees formatted gate names after an adjacent comma or semicolon. Prose with `;`, HTML, and `writing-plans` are not flagged. Each form has a self-test fixture.
- **Session start restores a missing Go coverage gate** (#87). When `.coverage-thresholds.json` runs `.metaswarm/go-coverage-gate.go` and the file is gone, the session hook's self-heal now writes it back from the plugin. When the gate is the only thing missing, it copies the file back without the full setup run, so customized command shims, the thresholds and the enforcement command are left as they are.

## 0.14.0

### Added

- **UX Reviewer is the 6th Design Review Gate reviewer** (#12). The gate now spawns PM, Architect, Designer, Security, UX Reviewer and CTO. The UX Reviewer has its own persona (`agents/ux-reviewer-agent.md`) and rubric (`rubrics/ux-review-rubric.md`). It checks that every user flow has a trigger and a visible outcome, that screens have a component hierarchy, that empty, loading and error states are defined, and that the design describes how the components are wired into the app shell. The integration work unit itself is checked at plan review (new Completeness row in `plan-review-rubric-adversarial.md`). A design with no user-facing UI is approved when the task needs none. Issue #12 had described this reviewer in the docs, but it was never added to the gate until now. There are now 23 agents and 10 rubrics, and a test ties the stated counts to the real files.

### Changed

- **Review findings carry `title` and `description`** (#58). Every finding uses six fields, `title`, `description`, `severity`, `protects`, `evidence` and `blocker`, and context recovery matches recurring findings by title and description.
- **Execution state splits "Retries" into VALIDATE attempts and review rounds** (#59). The VALIDATE counter counts consecutive failures and resets on PASS; review rounds follow the severity rule (cap 10). A pre-split state file's `Retries` value is read as VALIDATE attempts.
- **Escalation never approves** (#68). A review gate advances only when a fresh round has no `blocker: yes` finding, or when rule line 5's overengineering check downgrades every remaining blocker to a follow-up. Escalating to the human never approves: the options are Revise / Narrow scope / Defer / Cancel, and Override and `--force-override` are removed.
- **Workflow enforcement reconciled with superpowers >= 6.4.1** (#67). The canonical rules live in `guides/workflow-enforcement.md`; skills and the CLAUDE.md/AGENTS.md/GEMINI.md templates point to it.
- **Design Review Gate runs only for project-sized work** (#67). Quick tasks, chat-only designs and short design docs for small changes (superpowers 7.0.1+) skip it.
- **`docs/superpowers/specs/` is watched** (#67) alongside `docs/plans/`, and `/review-design --latest` searches both folders.
- **Plan Review Gate intercepts before writing-plans presents the plan** (#67), ahead of its own Execution Handoff.
- **Execution menu option 3 is now "Native inline execution"** (#67, `superpowers:executing-plans`), replacing "Parallel session"; the 3-option menu replaces writing-plans' 2-option handoff.
- **INSTALL.md lists all 9 referenced superpowers skills** (#67) and states the minimum version (superpowers >= 6.4.1, tested with 7.0.2).
- **The session hook surfaces metaswarm's knowledge base** (#70), with or without the beads plugin. At session start and compaction it inlines the MUST FOLLOW rules from `.beads/knowledge/` (capped at 10 rules or about 2 KB) and points to `/prime <topic>` for the rest. Without a working `jq` it adds only the pointer. Existing `bd prime` behaviour is unchanged.
- **Orphaned command mirrors are caught** (#64). `node lib/sync-resources.js --check` reports any `.claude/commands/*.md` that has no source in `commands/` and isn't on the exclusion list, and `--sync` removes it. Excluded names and non-`.md` files are never touched.
- **`/metaswarm-setup` and `/metaswarm-update-version` are now short deprecated aliases** for `/setup` and `/update` (#64). Their old npm-era bodies called CLI commands that don't exist (`install`, `changelog`), set the version even when agent regeneration failed, offered CI creation they never performed, and had a Go coverage gate that never failed.
- **`/external-tools-health` runs each adapter's `health` check** (#64) and reports `status`, `version`, `auth_valid` and `model`. It no longer relies on `command -v` and the repo's own self-test script.

### Fixed

- **`.claude/commands/` mirrors `commands/`** (#61), so this repo's unprefixed commands no longer serve stale copies. `node lib/sync-resources.js --check` blocks drift. `status.md` (it would shadow the built-in `/status`) and the two legacy commands are excluded.
- **bd/beads dependency drift** (#62). Removed `bd prime --work-type/--keywords/--files` flags (they never existed), `bd sync` (now `bd dolt push/pull`, only with a Dolt remote) and other nonexistent bd commands. The docs no longer claim `bd prime` loads metaswarm's knowledge base. Minimum versions are stated: bd ≥ 1.0.4 (tested with 1.3.4), and Dolt ≥ 2.4.0 only for server mode. `tests/deps/test-dependency-drift.sh` guards against regressions.
- **The plugin hook works when the plugin path contains a space.** `hooks/hooks.json` now quotes `${CLAUDE_PLUGIN_ROOT}`.
- **Every command has `description:` frontmatter**, so plugin installs list all 16 commands for the model, not only 4.
- **Documentation fixes from a pre-release review.**
  - `docs/coverage-enforcement.md` no longer documents the removed `init --with-husky --with-ci` flags.
  - INSTALL's superpowers command is now `claude plugin install superpowers@claude-plugins-official`.
  - The landing page and USAGE no longer list the removed Code Reviewer.
  - The skill, command, guide and rubric counts are corrected.
  - The templates use `/metaswarm:status` rather than the built-in `/status`.
  - The pr-shepherd agents name `metaswarm:pr-shepherd` instead of a `your-project:` placeholder.
  - The manual Husky steps install `husky` before `husky init`, and the CI coverage steps name the real job keys (`coverage-simple` / `coverage-merge`) in `templates/ci-coverage-job.yml` too.
  - CONTRIBUTING loads a local checkout with `claude --plugin-dir` (there is no `claude plugin add`).
  - The code-review and adversarial-review rubrics name the Adversarial Reviewer as their user.

### Removed

- **Deprecated agent stubs `coder-agent`, `researcher-agent` and `code-review-agent`** (deprecated in 0.13.0) are removed from `agents/` and `skills/start/agents/`. Use `metaswarm:coder`, `metaswarm:researcher` and `metaswarm:adversarial-reviewer`. `bin/metaswarm-usage` still recognises the old names in historical transcripts.
- **Legacy `adapters.<tool>.model` in `.metaswarm/external-tools.yaml`** (deprecated in 0.13.0) is no longer read. The adapters warn if it's still present; set `roles.<role>.codex|gemini` in `.metaswarm/models.yaml` instead.

### Upgrade note

Neither `/update` (marketplace plugin update) nor `npx metaswarm setup` (skips an instruction file that already mentions metaswarm) rewrites a project's own CLAUDE.md, AGENTS.md or GEMINI.md. Projects that already copied metaswarm's CLAUDE.md, AGENTS.md or GEMINI.md templates (or their `-append` variants) should refresh the "Workflow Enforcement" and "Quality Gates" sections from the new templates by hand.

## 0.13.0

### Added
- **Phase-named subagent types with per-phase default models** (#53): every phase now spawns a role type instead of `general-purpose`. Roster: `design-reviewer`, `plan-reviewer`, `adversarial-reviewer`, `planner` (opus); `researcher`, `coder`, `pr-shepherd-agent`, `knowledge-curator-agent` (sonnet); `issue-orchestrator`, `swarm-coordinator-agent` (inherit). Every `agents/*.md` and `skills/start/agents/*.md` now has frontmatter with `name`, `description`, `model` (22 agents, +3 deprecated).
- **`roleType("<role>")` and a resolution rule** (`guides/agent-coordination.md`, "Role type resolution"): spawn sites name a role, resolved as: use `metaswarm-<role>` if `.claude/agents/metaswarm-<role>.md` exists, otherwise `metaswarm:<role>` (the plugin default, which carries the same model), so an unconfigured project still works.
- **`.metaswarm/models.yaml`** (from `templates/models.yaml`) is the per-project override file. Setup, `/update`, `/status` and migrate generate and check `.claude/agents/metaswarm-<role>.md` from it via `bin/metaswarm-agents.sh`.
- **Per-call model for coder escalation**: coder retries can escalate to a stronger model by passing `model` on the spawn call, rather than via a different agent type.
- **`bin/metaswarm-usage`**: report of subagent cost by agent type, model, phase and type × model (which type actually ran on which model), plus review-gate rounds, from Claude Code transcripts; maps legacy agent types for a pre-rollout baseline.
- **Host docs**: "Role types on this host" tables for Codex, Gemini, OpenCode and Cursor in `skills/start/references/` and `GEMINI.md`, with research sources and what is unverified. Hosts without a per-role model get the role name passed through to their generic spawn, and the host default model applies.
- **README "Per-phase models"** section.
- **Delivery Scope and Overengineering policy** (#54, `guides/delivery-scope.md`): one source of truth for what may block delivery (a credible normal-usage failure, a missing or contradictory requirement, a broken key happy path, an important error or recovery-path failure), what must not expand a work unit, and the overengineering signals. Synced to the skills that need it; root and template `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` carry the core rule inline plus a reference to the guide.
- **Finding contract** (#54): every review finding carries `severity` (critical | major | minor | nit), `protects`, `evidence` and `blocker`. A finding blocks only if it is critical or major AND names what it protects; otherwise it is advisory. FAIL (or NEEDS_REVISION) requires at least one `blocker: yes` finding. Minor/nit findings become follow-ups (BEADS tasks, else a `### Follow-ups` list in the PR body). Rubrics, reviewer agents, gates and the issue-orchestrator's reviewer prompt use it.

### Changed
- **Severity-gated review iteration replaces the fixed 3-iteration cap** (#54): after each review round the orchestrator applies an ordered rule (PASS when no blockers; escalate at the 10-round `SAFETY_CAP`, or when a blocker recurs or reviewers disagree on it; otherwise fix and run a FRESH review, with an overengineering check that can downgrade blockers to follow-ups). Applies to orchestrated execution, the plan review gate, the design review gate, `/review-design`, `/start-task`, `start`, `brainstorming-extension` and the issue-orchestrator. Escalation reports group findings by severity and include round history and a recommendation; `/review-design --force-override` is offered on any escalation.
- **VALIDATE retries are scoped** (#54): the 3-attempt Recovery Protocol (and coder model escalation) now applies only to VALIDATE failures (tests, coverage, lint, typecheck); review FAILs follow the severity rule.
- **External-tool adapters** (#54): the Codex and Gemini review prompts ask for the 4 contract fields and return FAIL only on a `blocker: yes` finding (prompt text only; no parser change).
- **Design review gate result schema** (#54): `ReviewResult.blockers: string[]` and the gate's inline persona schemas' `"blockers"` arrays are replaced by `findings: Finding[]` (`{ severity, protects, evidence, blocker }`); `suggestions` and `questions` are kept. Verdict words (APPROVED/NEEDS_REVISION, PASS/FAIL) are unchanged.
- **Codex adapter passes the configured model**: `codex exec` now receives `-m <model>` when a model is configured for the role (`.metaswarm/models.yaml`) or via the legacy `adapters.codex.model`. Previously the configured model was reported but never passed. With nothing configured, no `-m` is passed and your `~/.codex/config.toml` model still applies.
- **No validator type, deliberately**: VALIDATE is always run by the orchestrator itself ("trust nothing, verify everything" — it never delegates quality gates to a subagent and never trusts a subagent's report), so a validator agent would never be spawned. The issue's initial roster listed one; the design refined it out.
- **Coverage gate**: `.coverage-thresholds.json` `enforcement.command` now runs the bash test suites (`tests/*/test-*.sh`), since the project has no `pnpm test:coverage`. The gate (and CI) also runs `node --test --experimental-test-coverage` for `bin/metaswarm-usage` with `--test-coverage-{lines,branches,functions}=100` (via `tests/lib/coverage-gate.sh`), so a coverage drop fails it. Developing metaswarm therefore needs Node.js >= 22.8 (the gate says so explicitly); the installer's Node 18+ runtime requirement is unchanged. The bash scripts are covered by behavioural suites; line coverage is not measured for shell (would need kcov/bashcov).
- **CI** runs every `tests/*/test-*.sh` suite in one step plus the usage tests with coverage.

### Deprecated
- `coder-agent`, `researcher-agent` and `code-review-agent` are stubs pointing at `coder`, `researcher` and `adversarial-reviewer`. They are removed in 0.14.0.
- `adapters.*.model` in the external-tools config is deprecated in favour of `roles.<role>.codex|gemini` in `.metaswarm/models.yaml`; the legacy key still works in 0.13.x with a stderr deprecation warning and is removed in 0.14.0.

### Upgrade notes
- **Restart Claude Code** after `.claude/agents/` is first created; agent types are loaded at session start.
- **Claude Code v2.1.251 or later is required** for the per-agent model frontmatter behavior.

## 0.12.0

### Added
- **`/handoff` command and `handoff` skill**: Analyzes the current session and writes a self-contained handoff document to `docs/handoffs/handoff-<YYYY-MM-DD-HHmm>.md` capturing the objective, current status, working-tree state, required reading (specs/designs/plans/code `file:line`/tests), and key decisions — so a fresh agent with zero prior context can resume the work. Emits a single closing sentence of the form `Read <file>.md and do <concrete next action>.` Wired across all platforms: Claude command (`commands/handoff.md`, `.claude/commands/handoff.md`), Gemini/Codex TOML (`commands/metaswarm/handoff.toml`, generated from `lib/sync-resources.js`), and skill definition (`skills/handoff/SKILL.md`)
- **First-class Codex CLI plugin support** (#44): Native `.codex-plugin/plugin.json` manifest and marketplace entry, platform-aware setup/status skills, and expanded session-start hook handling so Codex CLI is a first-class target alongside Claude Code and Gemini CLI

## 0.11.0

### Changed
- **Beads integration updated for standalone plugin (v0.63.3+)**: Metaswarm now defers to the standalone beads plugin (`/plugin install beads` from steveyegge/beads marketplace) for context priming, semantic summarization, and config management
- **Context recovery simplified**: `bd prime` now runs automatically via the beads plugin's SessionStart and PreCompact hooks — agents no longer need to call it manually
- **`/self-reflect` references `bd compact`**: Semantic summarization of closed issues now uses the beads plugin's native `bd compact` command instead of the former custom script
- **`bd decision` for persistent decision tracking**: Key Decisions sections in CLAUDE.md templates, orchestrated-execution, and worktree-development guide now reference `bd decision` for recording architectural decisions that survive compaction
- **Developer setup and README templates**: Updated to recommend standalone beads plugin installation from marketplace as the primary path

### Removed
- `scripts/beads-self-reflect.ts` — replaced by `bd compact` in the standalone beads plugin
- `templates/beads-config.yaml` — beads plugin manages its own configuration
- Setup copies of both files (`skills/setup/scripts/`, `skills/setup/templates/`)

### Added
- `tests/templates/test-beads-cleanup.sh` — 27-assertion regression test for beads integration cleanup
- 2 new test cases in `tests/hooks/test-session-start.sh` — verify dedup behavior (bd prime skipped when standalone beads detected, called when not)

## 0.10.0

### Added
- **Native Gemini CLI extension**: Install with `gemini extensions install https://github.com/dsifry/metaswarm.git`. Includes extension manifest (`gemini-extension.json`), context file (`GEMINI.md`), and 12 TOML commands in `commands/metaswarm/`
- **Native Codex CLI package**: Install with `curl -sSL .../install.sh | bash`. Clones repo and symlinks skills into `~/.agents/skills/`. Skills are invoked by their SKILL.md `name` field (e.g., `$start`, `$setup`). Includes install script (`.codex/install.sh`) and usage guide (`.codex/README.md`)
- **YAML frontmatter added** to 3 skills that lacked it: `create-issue`, `handling-pr-comments`, `pr-shepherd`. All 13 skills now have proper frontmatter for Codex discoverability
- **Cross-platform installer**: `npx metaswarm init` detects installed CLIs (claude, codex, gemini) and installs metaswarm for each. Supports `--claude`, `--codex`, `--gemini` flags for targeted install
- **Platform detection module** (`lib/platform-detect.js`): Detects installed CLIs, returns config paths and install methods for each platform
- **Platform adaptation reference** (`skills/start/references/platform-adaptation.md`): Documents tool equivalents, graceful degradation, and command syntax across all three platforms
- **Instruction file templates**: `templates/AGENTS.md`, `templates/AGENTS-append.md`, `templates/GEMINI.md`, `templates/GEMINI-append.md` for Codex and Gemini project setup
- **Multi-platform setup**: `lib/setup-mandatory-files.sh` now supports `--platform claude|codex|gemini|all` flag to write platform-appropriate instruction files
- **Platform-aware session-start hook**: `hooks/session-start.sh` self-locates its plugin root using `$CLAUDE_PLUGIN_ROOT`, `$extensionPath`, or script directory fallback
- **TOML command sync**: `lib/sync-resources.js` now generates and validates Gemini TOML commands, checks version sync across all manifests (package.json, plugin.json, gemini-extension.json)
- **Test suites**: `tests/gemini/`, `tests/codex/`, `tests/cli/` with validation for extension structure, skill symlinks, and installer behavior
- **`AGENTS.md` at repo root**: Codex CLI instruction file with metaswarm workflow, quality gates, and session completion rules
- **`GEMINI.md` at repo root**: Gemini CLI extension context with commands, quality gates, and platform notes

### Changed
- **npm package un-deprecated**: `package.json` no longer has `deprecated` field. The npm package is now the cross-platform installer
- **npm package description**: Updated to "Cross-platform installer for metaswarm"
- **CLI rewritten** (`cli/metaswarm.js`): Now supports `init`, `setup`, `detect` commands with platform flags. Replaces old deprecation-warning-only behavior
- **Version bumped to 0.10.0** across: `package.json`, `.claude-plugin/plugin.json`, `gemini-extension.json`
- README.md, INSTALL.md, GETTING_STARTED.md updated with Codex and Gemini installation paths
- `package.json` `files` array updated to include `lib/`, `.codex/`, `AGENTS.md`, `GEMINI.md`, `gemini-extension.json`
- `package.json` `keywords` updated to include `codex-cli` and `gemini-cli`

## 0.9.2

### Changed
- Updated plugin.json description with Gemini/Codex and accurate counts

## 0.9.1

### Fixed
- Corrected plugin install commands throughout docs

## 0.9.0

### Added
- **Claude Code marketplace plugin distribution**: metaswarm is now installed via `claude plugin marketplace add dsifry/metaswarm-marketplace && claude plugin install metaswarm`, replacing the npm `npx metaswarm init` method. The npm package is deprecated and prints a deprecation warning
- **Setup skill** (`skills/setup/`): Interactive guided project setup that replaces `npx metaswarm init`. Detects language, framework, test runner, linter, and CI, then configures everything automatically
- **Migrate skill** (`skills/migrate/`): Automated migration from npm installation to plugin. Detects old `.claude/plugins/metaswarm/` files, verifies content matches, removes stale copies, and creates project-local command shims
- **Status skill** (`skills/status/`): 9 diagnostic checks — plugin version, project setup, command shims, legacy install detection, BEADS plugin, bd CLI, external tools, coverage thresholds, and Node.js
- **Session-start hook** (`hooks/session-start.sh`): Context priming, legacy npm installation detection with migration prompt, BEADS dedup, and self-healing mandatory file writes
- **`/start` alias command**: Shorthand for `/start-task`
- **`/setup` command**: Routes to the setup skill (replaces `/metaswarm-setup`)
- **`/update` command**: Routes to plugin update (replaces `/metaswarm-update-version`)
- **`/status` command**: Routes to the status diagnostic skill
- **Shell script for mandatory files**: `hooks/session-start.sh` writes CLAUDE.md and other required files if the agent skips them, ensuring projects always have the correct configuration
- **Marketplace repository**: Created `dsifry/metaswarm-marketplace` for plugin distribution
- **Cross-CLI validation**: Setup and migration workflows validated across Claude Code, Gemini CLI, and Codex CLI

### Changed
- **Primary installation method**: Plugin marketplace (`claude plugin install metaswarm`) replaces npm (`npx metaswarm init`)
- **npm package deprecated**: `package.json` includes deprecation notice pointing to plugin marketplace
- **Command names simplified**: `/metaswarm-setup` → `/setup`, `/metaswarm-update-version` → `/update` (legacy aliases preserved)
- Updated counts: 13 skills (was 9), 15 commands (was 9), 8 rubrics

### Upgrade Instructions
- **From v0.7.x / v0.8.x**: Run `claude plugin marketplace add dsifry/metaswarm-marketplace && claude plugin install metaswarm`, then `/metaswarm:migrate` in Claude Code to clean up old npm-installed files. See [INSTALL.md](INSTALL.md#upgrading-to-v090) for details
- **From v0.6.x or earlier**: Same as above, then run `/setup` to get the interactive configuration
- **Already on plugin**: Run `/update` in Claude Code

## 0.8.0

### Added
- **Workflow enforcement rules** in CLAUDE.md templates: mandatory intercepts at every superpowers handoff point (brainstorming → writing-plans → executing-plans → finishing-a-branch) to ensure quality gates are never bypassed
- **Execution method choice**: agents now always ask the user whether to use metaswarm orchestrated execution (more thorough, more tokens) or superpowers execution skills (faster, lighter-weight) — no default, user decides
- **BEADS context persistence**: approved plans, project context, and execution state are written to `.beads/plans/` and `.beads/context/` so agents can recover after context compaction or session interruption
- **Context recovery protocol** (`bd prime --work-type recovery`): reloads approved plan, completed work, and current execution position from disk after context loss
- **Start-task recovery check**: detects interrupted executions at startup, asks user to resume or start fresh
- **Pre-PR self-reflect**: knowledge capture moved from post-merge to before PR creation; KB updates are committed as part of the PR so learnings land atomically with the code
- **Subagent discipline rules**: `--no-verify` prohibition, TDD enforcement, file scope rules, and no-self-certify rules added to coder-agent and orchestrated-execution spawn templates
- **EnterPlanMode intercept**: CLAUDE.md instructs agents to use `/start-task` instead of `EnterPlanMode` for tasks touching 3+ files (EnterPlanMode bypasses all quality gates)
- **Standalone TDD review**: after TDD sessions modifying 3+ files, agent asks user if they want adversarial review before committing
- **Coverage source of truth unification**: `.coverage-thresholds.json` is now explicitly the single source of truth across all skills including `verification-before-completion`
- **Plan persistence in plan-review-gate**: approved plans are written to `.beads/plans/active-plan.md` after gate approval + user approval
- **Execution state tracking**: `.beads/context/execution-state.md` tracks current work unit, phase, and retry count across phase transitions

### Changed
- **Command namespace simplified**: removed `/project:` prefix from 259 references across 52 files — commands now use `/start-task`, `/review-design`, `/self-reflect`, etc.
- **Brainstorming-extension rewritten**: replaced aspirational YAML triggers with documentation of the actual 3-layer enforcement mechanism (CLAUDE.md instructions, start-task command, skill documents)
- **Project Context Document now persisted to disk**: written to `.beads/context/project-context.md` and updated after each work unit commit
- **PR shepherd self-reflect timing**: post-merge knowledge capture is now a fallback only (primary capture happens pre-PR)
- **Cross-platform sed syntax**: cleanup commands use `OSTYPE` detection for macOS vs GNU/Linux compatibility
- **Gitignore template**: added `!.env.example` negation, BEADS runtime exclusions, and execution state exclusions
- **Code fence language specifiers**: added `text` language to all bare fenced code blocks for markdown lint compliance
- Updated counts: 9 skills (was 8), 9 commands, 8 rubrics

## 0.7.1

### Fixed
- `npx metaswarm init --full` crashed because npm strips `.gitignore` files from packages. Renamed template to `gitignore` (no dot) so it ships correctly.

## 0.7.0

### Added
- **Claude-guided installation** (`/metaswarm-setup`): Interactive setup that detects your project's language, framework, test runner, linter, formatter, package manager, CI system, and git hooks — then customizes everything automatically. Supports 7 languages (TypeScript, Python, Go, Rust, Java, Ruby, JavaScript), 15+ frameworks, and all major toolchains
- **Self-update command** (`/metaswarm-update-version`): Check for new metaswarm versions, show changelog, update files, re-detect project context, and refresh the project profile
- **Project profile** (`.metaswarm/project-profile.json`): Stores detection results, user choices, and derived commands for future reference and updates
- **`npx metaswarm install`** CLI command: Separate heavy file-copy operation that can be invoked by the setup skill or run directly

### Changed
- **`npx metaswarm init` is now a thin bootstrap**: Copies only 3 files (metaswarm-setup command, metaswarm-update-version command, minimal CLAUDE.md reference) instead of 60+ files. Points user to `/metaswarm-setup` for interactive guided setup
- **`npx metaswarm init --full`** preserves the legacy behavior (init + install in one step) for CI/scripting environments
- README.md install section rewritten around two-step guided flow
- INSTALL.md restructured: "Recommended: Claude-Guided Setup" as primary, "Manual / CI Installation" as fallback
- GETTING_STARTED.md quickstart updated to the new flow
- CLAUDE.md template updated with both new commands

## 0.6.0

### Added
- **External AI tool delegation** (`skills/external-tools/`): Delegate implementation and review tasks to OpenAI Codex CLI and Google Gemini CLI. Cross-model adversarial review ensures the writer is always reviewed by a different model. Availability-aware escalation chain: Model A (2 tries) → Model B (2 tries) → Claude (1 try) → user alert
- **Codex CLI adapter** (`skills/external-tools/adapters/codex.sh`): Shell adapter for OpenAI Codex CLI with health, implement, and review commands
- **Gemini CLI adapter** (`skills/external-tools/adapters/gemini.sh`): Shell adapter for Google Gemini CLI with health, implement, and review commands
- **Shared adapter helpers** (`skills/external-tools/adapters/_common.sh`): 14 shared helper functions including `safe_invoke()` with macOS-compatible timeout fallback, worktree management, cost extraction, structured JSON output, and error classification
- **Cross-model review rubric** (`rubrics/external-tool-review-rubric.md`): Binary PASS/FAIL rubric for cross-model adversarial review with file:line evidence requirements
- **External tools config template** (`templates/external-tools.yaml`): Per-project configuration for adapter settings, routing strategy, and budget limits
- **External tools setup guide** (`templates/external-tools-setup.md`): User-facing installation and authentication guide for Codex and Gemini CLI
- **`/external-tools-health` command** (`commands/external-tools-health.md`): Slash command to check external tool availability and authentication status
- **External tools verification script** (`bin/external-tools-verify.sh`): End-to-end verification with 15 checks covering shared helpers, both adapters, and file existence
- **External tools detection in start-task**: `/start-task` now auto-detects installed external tools and suggests enabling them
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
