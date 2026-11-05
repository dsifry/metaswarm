# Plan: Phase-named subagent types with per-phase default models (Issue #53)

Spec: GitHub issue #53. This plan resolves the issue's open questions and splits the work into units.
Branch: `feat/53-phase-agent-types`. Target version: **0.13.0**. Deprecated names are removed in **0.14.0**.
Revision: 3 (after plan-review-gate iteration 2).
Requires Claude Code **v2.1.251 or later**. In earlier versions `CLAUDE_CODE_SUBAGENT_MODEL` overrode frontmatter. This minimum is documented in README and CHANGELOG, and `/status` warns when `claude --version` is older.

## Facts this design relies on (verified against code.claude.com/docs/en/sub-agents)

- How the model is chosen, highest priority first: per-call `model` param → agent frontmatter `model` → `CLAUDE_CODE_SUBAGENT_MODEL` (a default only) → session model. So frontmatter `model: opus` beats `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`, and a per-call `model` still wins (escalation keeps working).
- Plugin agents are namespaced `metaswarm:<name>` and have the lowest priority. Project agent names can't contain `:`, so a project file can never shadow `metaswarm:<name>`. The docs give no supported way to override a plugin agent's model per project.
- Frontmatter: `name` and `description` are required. `model` accepts `sonnet|opus|haiku|fable|inherit|<full id>`. `tools` is an allowlist and `disallowedTools` is a denylist. Unknown fields are ignored silently. The agents-directory watcher only covers directories that existed at session start, so a newly created `.claude/agents/` needs a session restart.

## Resolved open questions

1. **One `design-reviewer` with the role in the prompt, not five types.** Same for `plan-reviewer`. Spawn `description` already distinguishes roles ("PM review", …), and `metaswarm-usage` splits by description within a type. The persona files (`product-manager-agent.md`, `architect-agent.md`, `designer-agent.md`, `security-design-agent.md`, `cto-agent.md`) stay as role briefs that the reviewer reads.
2. **Config: new `.metaswarm/models.yaml`.** `external-tools.yaml` can't hold it, because that file existing is what turns external tools on, and model defaults must work without external tools. `adapters.*.model` is removed from `templates/external-tools.yaml` and from `templates/external-tools-setup.md` and folded into `roles.<role>.codex|gemini`. Adapters don't read any YAML today: `DEFAULT_MODEL` is hard-coded at `codex.sh:26` and `gemini.sh:24`. The new resolver reads `models.yaml` first. During the deprecation window it falls back to a legacy `adapters.<tool>.model` in `external-tools.yaml`, which prints a stderr warning. That fallback is removed in 0.14.0. After this change `models.yaml` is the only documented place that sets models.
3. **Project overrides, given that plugin agents can't be overridden.** The plugin ships `agents/<role>.md` with default `model:` frontmatter, which applies when `/setup` hasn't been run. `/setup` and `/update` generate `.claude/agents/metaswarm-<role>.md` (project scope, so no `:`) from `models.yaml`. Each skill resolves the type with one rule, defined once in `guides/agent-coordination.md` (synced to the 4 copies with `node lib/sync-resources.js --sync`):
   > **Role type resolution**: use `metaswarm-<role>` if `.claude/agents/metaswarm-<role>.md` exists, otherwise `metaswarm:<role>`.

   If the orchestrator misses this rule, the spawn falls back to the plugin default, which already has a correct reviewer model. So it degrades rather than breaks, and the "reviewers on Opus" AC still holds. `/setup` tells the user to restart the session if it had to create `.claude/agents/`.
4. **Old vs new names.** The new canonical types are `design-reviewer`, `plan-reviewer`, `researcher`, `planner`, `coder`, `adversarial-reviewer`, plus the existing `pr-shepherd-agent` and `knowledge-curator-agent`, which keep their names and only gain frontmatter.
   - Three old agents overlap with new ones: `coder-agent` → `coder`, `researcher-agent` → `researcher`, `code-review-agent` → `adversarial-reviewer`.
   - Their content moves to the new file. Each old file becomes a short stub with frontmatter that matches its successor, `description: "DEPRECATED (removed in 0.14.0) — use metaswarm:<new>"`, and a one-line body pointing to the successor.
   - Every repo reference to the old names is updated to the new ones in WU1. No permanent aliases.
   - All other persona agents keep their names and gain frontmatter.
5. **No `validator` type (departs from the issue's initial roster).** VALIDATE is run by the orchestrator by design. `orchestrated-execution/SKILL.md` says "The orchestrator independently runs quality gates… NOT via the coding subagent", and `external-tools/SKILL.md` says "Phase 2: VALIDATE (Always Orchestrator -- Unchanged)". Delegating it would weaken the trust model, and an unused type is cruft. The issue labels the roster "initial; to be refined", and this is the refinement.
6. **Escalation.** `models.yaml` has `escalation.coder: { after_failures: 2, claude: opus }`. Today orchestrated-execution has no model escalation: its retry section only retries, then escalates to a human. WU4 adds explicit text: after `after_failures` failed VALIDATE attempts, re-spawn the coder with a per-call `model: <escalation.coder.claude>`.
7. **Non-Claude hosts.** Research Codex agent roles and Gemini subagent model config, and document the mapping in the host reference files. Where a host has no per-role model, role names pass through to the host's generic spawn and the host's default model applies. Host-side generators become a follow-up issue only if research shows a mechanism exists.
8. **Gate quality alongside cost.** `metaswarm-usage --gates` reports rounds-to-pass per gate occurrence, measured as reviewer spawn batches per gate per session. Batches are identified by a time gap of 5 minutes or more between reviewer spawns in the same session. Before rollout, reviewers are classified by keyword. After rollout, they are classified exactly by type. Whether findings later proved real can't be derived from transcripts, so the PR adds a short manual-tally section to the PR template (`.github/pull_request_template.md` if present, otherwise the PR body) for the post-rollout comparison.

## Phase roster (plugin defaults)

| Type | Phase | model | disallowedTools |
|---|---|---|---|
| design-reviewer | design gate | opus | Write, Edit, NotebookEdit |
| plan-reviewer | plan gate | opus | Write, Edit, NotebookEdit |
| researcher | research | sonnet | Write, Edit, NotebookEdit |
| planner | plan / decompose | opus | — |
| coder | IMPLEMENT | sonnet | — |
| adversarial-reviewer | ADVERSARIAL REVIEW | opus | Write, Edit, NotebookEdit |
| pr-shepherd-agent | PR | sonnet | — |
| knowledge-curator-agent | reflect | sonnet | — |
| issue-orchestrator, swarm-coordinator-agent | orchestration | inherit | — |
| other persona agents | — | inherit | — |

No agent sets a `tools:` allowlist. Read-only is expressed only through `disallowedTools`, so Team Mode tools (`SendMessage`, `TaskUpdate`; see `guides/agent-coordination.md` verdict collection) stay available. The WU1 test asserts that no agent declares `tools:`.

## `.metaswarm/models.yaml` (template at `templates/models.yaml`, auto-synced to `skills/setup/templates/`)

```yaml
# metaswarm models v1 — one place to set each phase's model
roles:
  design-reviewer:
    claude: opus
    codex: gpt-5.3-codex
    gemini: pro
  plan-reviewer:
    claude: opus
    codex: gpt-5.3-codex
    gemini: pro
  researcher:
    claude: sonnet
  planner:
    claude: opus
  coder:
    claude: sonnet
    codex: gpt-5.3-codex
    gemini: flash
  adversarial-reviewer:
    claude: opus
    codex: gpt-5.3-codex
    gemini: pro
  pr-shepherd-agent:
    claude: sonnet
  knowledge-curator-agent:
    claude: sonnet
escalation:
  coder:
    after_failures: 2
    claude: opus
```

### Parsing and validation rules (shared bash reader in `bin/metaswarm-agents.sh`, also sourced by the adapter resolver; main dispatch is guarded by `[ "${BASH_SOURCE[0]}" = "$0" ]`)

- Block-style YAML only, with 2-space indentation and at most 3 levels (`roles` → role → host). `#` comments and blank lines are allowed.
- Errors exit 2 and print `models.yaml:<line>: <reason>`. Each of these is an error:
  - flow maps (`{`)
  - tabs
  - odd or deeper indentation
  - an unknown top-level key
  - an unknown role (not in the roster)
  - an unknown host key (not `claude`, `codex` or `gemini`)
  - a `claude:` value that isn't one of `sonnet|opus|haiku|fable|inherit` or doesn't match `^claude-[a-z0-9.-]+$`
  - a non-integer `after_failures`
- An empty file or a file with only comments means all defaults.
- The issue's sample `cross_model: true` is not a models.yaml key. Cross-model review routing stays in `external-tools.yaml` / the external-tools skill.
- A missing role, or a missing host key within a role, falls back to the plugin default. For claude that is the `agents/<role>.md` frontmatter. For codex/gemini it is the adapter's built-in default.

### How the scripts find things

- The plugin root is resolved by this chain, which extends the env-var convention in `skills/setup/SKILL.md` Pre-Flight:
  1. `$PLUGIN_ROOT`, `$CLAUDE_PLUGIN_ROOT` or `$extensionPath`
  2. walk up from the script's own directory looking for `agents/coder.md` (this works from `bin/` and from `skills/setup/bin/`)
  3. the newest `~/.claude/plugins/cache/*/metaswarm/*/` that contains `agents/coder.md`
  4. otherwise exit 3 with "cannot locate metaswarm plugin; set CLAUDE_PLUGIN_ROOT"

  Skills always invoke `${PLUGIN_ROOT}/bin/metaswarm-agents.sh`, never a project-local `bin/` copy. `/setup`'s bin copy step excludes `metaswarm-agents.sh` and `metaswarm-usage`.
- The plugin version comes from `<plugin root>/.claude-plugin/plugin.json`, read with `sed` because there is no jq dependency.
- Bash 3.2 compatible, for macOS: no associative arrays and no `mapfile`. The hash uses `shasum -a 256`, falling back to `sha256sum`.
- The project root is `git rev-parse --show-toplevel`, falling back to `$PWD`. The config is `<project>/.metaswarm/models.yaml`.

## Work units

TDD in every WU: write the test first, run it and watch it fail, then implement.

**VALIDATE command (every WU, and CI):**

```bash
bash -c 'shopt -s nullglob; for f in tests/*/test-*.sh; do echo "== $f"; bash "$f" || exit 1; done'
node lib/sync-resources.js --check
```

Each suite runs separately, and that covers every suite directory: agents, cli, codex, gemini, hooks, lib and templates. `bin/external-tools-verify.sh` is not part of VALIDATE (it needs real tools and jq), so WU4 runs it manually where those are available. WU6 replaces the per-file CI steps for these directories with this loop in `.github/workflows/ci.yml`.

Spawn sites are identified by their content (description string), not by line number, because WU1 frontmatter shifts lines.

### WU0: Version bump to 0.13.0 (first, so later WUs see the real version)
- Update `package.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` and `gemini-extension.json`.
- Set `.coverage-thresholds.json` `enforcement.command` to the VALIDATE loop (user decision).
- Add a CHANGELOG stub entry; WU6 fills it in.
- Verify: `node lib/sync-resources.js --check` (the manifest versions match) and `tests/gemini`/`tests/cli` in the VALIDATE loop.

### WU1: Agent frontmatter, new phase agents, rename references
- Test: `tests/agents/test-agent-frontmatter.sh` checks:
  - Every `agents/*.md` and `skills/start/agents/*.md` starts with `---` frontmatter containing `name`, `description` and `model`, and `name` equals the filename stem.
  - Both copies have identical frontmatter.
  - Every roster type has exactly the roster's `model` and `disallowedTools`. In particular, design-reviewer, plan-reviewer and adversarial-reviewer are `model: opus` (AC3, static half).
  - No agent declares `tools:`.
  - The deprecated stubs name their successor and `0.14.0`.
  - No tracked file references `coder-agent`, `researcher-agent` or `code-review-agent`, except:
    - the stubs
    - `CHANGELOG.md` and `docs/plans/`
    - `tests/`
    - `bin/metaswarm-usage` and its `skills/setup/bin/` copy, which map legacy agentTypes to phases for the baseline
  - The prose moved out of `code-review-agent.md` (for example "spawn a NEW Code Review Agent instance") is reworded for `adversarial-reviewer`.
- Files:
  - `agents/*.md`: 19 existing files get frontmatter. New files: `agents/{design-reviewer,plan-reviewer,researcher,planner,coder,adversarial-reviewer}.md`. Deprecation stubs: `coder-agent`, `researcher-agent`, `code-review-agent`.
  - `skills/start/agents/*.md`: the same changes, edited in parallel. This directory is not synced, so its `./`-relative paths are kept.
  - Old-name references:
    - `USAGE.md`
    - `INSTALL.md`
    - `skills/start/SKILL.md` (directory tree)
    - `agents/slack-coordinator-agent.md`, `agents/issue-orchestrator.md`, `agents/metrics-agent.md`, `agents/sre-agent.md`, and their `skills/start/agents/` copies
  - Agent counts: the current docs say 18 or 19 in places; the new count is 28 = 19 + 6 new + 3 stubs, written as "25 agents (+3 deprecated)":
    - `README.md`, `USAGE.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
    - `docs/index.html`, `gemini-extension.json`
    - `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
    - `templates/{CLAUDE,CLAUDE-append,AGENTS,AGENTS-append,GEMINI,GEMINI-append}.md`, auto-synced to `skills/setup/templates/` via `--sync`

### WU2: Switch spawn sites to role types
- Test: `tests/agents/test-no-general-purpose.sh` checks the following. Prose sites are matched by a per-file anchor phrase listed in the test.
  - Over `skills/**/*.md`, `agents/*.md`, `guides/*.md`, `commands/*.md`, `templates/*.md` and the root `CLAUDE.md`, `AGENTS.md` and `GEMINI.md`, every `Task({` block has a `subagent_type`, and none is `"general-purpose"` unless its file plus description is in the in-test allowlist (which starts empty).
  - Prose mentions of "fresh `Task()`" in orchestrated-execution, external-tools, swarm-coordinator, design-review-gate Team Mode and pr-shepherd are followed, in the same section, by the role type to use. So is the "spawn a fresh `Task()` reviewer" line in CLAUDE.md and its templates.
  - No skill tells the orchestrator to spawn the built-in `Plan` type for planning (`orchestrated-execution` Pre-Flight note).
  - `guides/agent-coordination.md` defines "Role type resolution" and the roster table.
- Sites, by content:
  - `skills/design-review-gate/SKILL.md`: 5 reviewers → `design-reviewer`
  - `skills/plan-review-gate/SKILL.md`: 3 reviewers → `plan-reviewer`
  - `skills/start/SKILL.md`: "Issue Orchestrator for #…" → `issue-orchestrator`; "Research for issue" → `researcher`; the architect/plan spawn → `planner`; "Code review for" and "Security audit for" → `adversarial-reviewer` with the role in the prompt; "Extract learnings from epic" → `knowledge-curator-agent`
  - `agents/issue-orchestrator.md` and `skills/start/agents/issue-orchestrator.md`: "Research for issue" → `researcher`
  - `guides/worktree-development.md`: "Implement feature X in worktree" → `coder`
  - `CLAUDE.md` and `templates/CLAUDE.md` (synced to `skills/setup/templates/`), "After Standalone TDD": "spawn a fresh `Task()` reviewer" → `adversarial-reviewer` (resolved by role type)
  - `skills/orchestrated-execution/SKILL.md`, Pre-Flight note "spawn an Architect as a Plan subagent": the Architect is now spawned as `planner`. That type can write `PLAN.md` itself, so the note about the read-only `Plan` type is replaced.
  - prose spawns in `skills/orchestrated-execution/SKILL.md` (IMPLEMENT → coder, ADVERSARIAL REVIEW → adversarial-reviewer; VALIDATE stays orchestrator-run, so no change), `skills/external-tools/SKILL.md` (the Claude fallback path uses coder / adversarial-reviewer), `skills/start/agents/swarm-coordinator-agent.md` and `agents/swarm-coordinator-agent.md`, and `skills/pr-shepherd/SKILL.md` (pr-shepherd-agent)
  - `guides/agent-coordination.md`: the resolution rule and roster. Team Mode teammates use the same role types (`TeamCreate` member type = role type). Then run `node lib/sync-resources.js --sync`.

### WU3: models.yaml, generator, /setup, /update, /status, migrate wiring
- Test: `tests/agents/test-generate-agents.sh` runs against fixture `tests/agents/fixtures/models.yaml` in a `mktemp -d` git repo. Its cases:
  - `bin/metaswarm-agents.sh generate` writes `.claude/agents/metaswarm-<role>.md`. Each file has `name: metaswarm-<role>`, the configured `model`, the plugin `description`/`disallowedTools`, the plugin body, and a first body line `<!-- generated-by: metaswarm v<version> sha256:<hash-of-rest> — edit .metaswarm/models.yaml, not this file -->`. `<version>` comes from the plugin's `plugin.json`, and the test asserts it matches that file's version rather than a literal.
  - A second run produces byte-identical output.
  - A role missing from the fixture gets the plugin default model.
  - A reviewer role set to `opus` in the fixture comes out with `model: opus` (AC3, generated half).
  - Each parse error listed above exits 2 with a line number (one case per rule), and nothing is written on error.
  - An empty `models.yaml` produces all defaults.
  - With no `.metaswarm/models.yaml`, `generate` prints "no models.yaml — using plugin defaults; run /setup to customize", writes nothing and exits 0. If no generated files exist, the plugin types apply.
  - `check` exits 1 and lists a file if any of these hold:
    - it was hand-edited (hash mismatch)
    - it is stale (version or config mismatch)
    - it is an orphan (a generated file for a role not in the roster)
    - it is missing (a role in `models.yaml` with no file)

    It exits 0 when everything is clean.
  - `generate` deletes orphans, but only files with the `generated-by: metaswarm` header.
  - A hand-edited file is overwritten only with `--force`. Otherwise it exits 1 naming the file.
  - A same-named `.claude/agents/metaswarm-<role>.md` without the header (user-authored) is never overwritten. `generate` exits 1 naming it.
  - `clean` removes only files with the header, and leaves `.claude/agents/my-own.md` untouched.
- Files:
  - new `bin/metaswarm-agents.sh` (auto-synced to `skills/setup/bin/`)
  - new `templates/models.yaml` (auto-synced)
  - `skills/setup/SKILL.md` and `commands/metaswarm-setup.md`: Phase 3 copies `models.yaml` if absent and runs `generate`; Phase 6 tells the user to restart if `.claude/agents/` was new
  - `commands/update.md` and `commands/metaswarm-update-version.md`: run `generate` after an update
  - `skills/status/SKILL.md` and `commands/status.md`: run `check`, report drift
  - `hooks/session-start.sh`: if any `.claude/agents/metaswarm-*.md` header version differs from the plugin version (for example after a marketplace auto-update), add one line, "metaswarm agents are stale — run /update", to the hook's JSON `additionalContext` (not raw stdout). Tested in `tests/hooks/test-session-start.sh`. Version comparison only; no hashing at session start.
  - `skills/migrate/SKILL.md`: a new "Generated agent files" section that runs `clean`, lists `.claude/agents/metaswarm-*.md` as removable, and serves as the uninstall instructions
- Generated files are committed, not gitignored, so teammates share them. The header carries the version.

### WU4: Escalation override and adapter role models
- Test: `tests/agents/test-escalation.sh` checks that the orchestrated-execution retry section contains a per-call `model` on coder re-spawn and references `escalation.coder` in models.yaml.
- Test: `tests/agents/test-adapter-models.sh`, using fixtures in a temp project. It checks that:
  - `codex.sh health --role coder` reports the role's codex model.
  - A role without a codex key reports the built-in default.
  - `health` with no `--role` is unchanged: same JSON keys including `model`, so `bin/external-tools-verify.sh` keeps passing.
  - A legacy `adapters.codex.model` in `external-tools.yaml`, with no models.yaml, is used and prints a deprecation warning on stderr.
  - models.yaml beats legacy.
  - The same cases pass for `gemini.sh`.
- Files:
  - `skills/orchestrated-execution/SKILL.md`
  - `skills/external-tools/adapters/{_common.sh,codex.sh,gemini.sh}`: add `resolve_model <tool> <role>` and a `--role` flag; the resolved value replaces `DEFAULT_MODEL` at each use
  - `skills/external-tools/SKILL.md`
  - `templates/external-tools.yaml` and `templates/external-tools-setup.md`: remove `model:`, point to models.yaml, auto-synced
  - `commands/external-tools-health.md`
  - `bin/external-tools-verify.sh`: no change expected; its test runs in VALIDATE

### WU5: `metaswarm-usage` report
- Test: `tests/lib/test-usage-report.sh`, the path named in the issue. It uses fixture transcripts in `tests/lib/fixtures/usage/<proj>/<session>/subagents/` (`*.jsonl` + `*.meta.json`). The fixtures include:
  - a duplicated message id
  - an agent missing its meta file (counted under `unknown`)
  - a malformed JSONL line (skipped with a count)
  - an empty directory (prints a "no transcripts" message and exits 0)

  It asserts exact per-type, per-model and per-phase totals for input, cache write, cache read and output. Per-phase uses the role type when it is a metaswarm role, and otherwise falls back to keyword classification of the description. It also asserts:
  - `--gates` rounds-to-pass on a fixture with 2 batches of plan reviewers
  - `--pricing <json>` adds cost columns
  - the `--json` output parses
- Files: new `bin/metaswarm-usage` (Node, no dependencies; Node is already required by `cli/metaswarm.js`), auto-synced to `skills/setup/bin/`. It takes a default root of `~/.claude/projects`, a `--root` flag (used by the tests) and `--project <glob>`.
- Baseline: run on the author's history and paste token and gate tables into the PR body. The post-rollout comparison needs real post-merge usage, so it is listed in the PR as an explicit follow-up checklist item. This departs from the AC's "attached to the PR", and the departure is stated in the PR.

### WU6: Host docs, CI, CHANGELOG
- Research: Codex CLI agent roles and per-role model config, and Gemini CLI subagent model config. Write the findings to:
  - `skills/start/references/codex-tools.md`, `opencode-tools.md`, `cursor-tools.md`, and `platform-adaptation.md`
  - `GEMINI.md`

  The format is a role → host mechanism table, with a pass-through fallback.
- Test: extend `tests/codex/test-codex-skills.sh` so that each host reference file mentions every roster role.
- CI: replace the per-file test steps in `.github/workflows/ci.yml` with the VALIDATE loop.
- Fill in the CHANGELOG entry: the new types, models.yaml, no validator (and why), the deprecations removed in 0.14.0, the restart note, and the minimum Claude Code v2.1.251.

## Dependencies
WU0 → WU1 → WU2 → WU3 → WU4. WU5 depends only on WU0 and can run in parallel with WU1. WU6 comes after WU2.

## Out of scope
- Post-rollout usage comparison (needs time to pass; posted after merge as a follow-up checklist item).
- Generators for Codex/Gemini host config, unless research shows a mechanism exists (that becomes a new issue).
- Actually removing the deprecated names (0.14.0).

## Coverage gate (DECIDED 2026-11-05: use the test loop)
`.coverage-thresholds.json` enforces `pnpm test:coverage`, but `package.json` has no scripts and the tests are bash suites. Recommendation: set `enforcement.command` to the VALIDATE loop above, so the CLAUDE.md gate runs something real. Line coverage isn't measurable for the bash and markdown changes. For the one Node file, `bin/metaswarm-usage`, WU5 also runs `node --test --experimental-test-coverage` on a small `tests/lib/metaswarm-usage.test.mjs` and requires 100% of that file. The user approved this. It is applied in WU0.

## Human checkpoints
1. After WU1+WU2: confirm the roster and names.
2. Before the PR, a live AC3 check. In a scratch project, set `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` and run `/review-design` and the plan gate once each. Then confirm with `metaswarm-usage --project '*<scratch-dir-name>*' --json` (default root `~/.claude/projects`; `--project` is a glob on the encoded project dir name) that design-reviewer and plan-reviewer ran on Opus and the coder ran on Sonnet. Paste the output into the PR.
3. Before the PR: review the baseline usage report.
