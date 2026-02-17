# Metaswarm Doctor

Health check and diagnostics. Verifies the full metaswarm stack is working and reports actionable findings. Run after setup, after upgrades, or to debug issues.

## Usage

```text
/project:metaswarm-doctor
```

## Steps

### 1. Project Profile

Read `.metaswarm/project-profile.json`:

- If missing: **FAIL** — "No project profile found. Run `/project:metaswarm-setup` to create one."
- If present: verify all required fields exist (`metaswarm_version`, `detection`, `choices`, `commands`)
- Check `metaswarm_version` — if it differs from the installed version in `package.json` (the metaswarm package), emit a **WARNING**: "Profile version {X} doesn't match installed version {Y}. Consider re-running `/project:metaswarm-setup`."
- Record result: PASS / WARN / FAIL

### 2. CLAUDE.md Customization

Read `CLAUDE.md`:

- Search for `<!-- TODO` markers (case-insensitive)
- If any TODO markers remain: **WARN** — "CLAUDE.md still has TODO placeholders that need customization: {list locations}"
- Cross-reference test commands with `.metaswarm/project-profile.json` `commands.test` and `commands.coverage` — warn only if they don't match the profile (don't flag `npm test` generically since it's valid for some projects)
- Record result: PASS / WARN

### 3. Coverage Configuration

Read `.coverage-thresholds.json`:

- If missing: **FAIL** — "No coverage thresholds file. Run `/project:metaswarm-setup`."
- If present:
  - Verify `enforcement_command` is set and is not empty or a placeholder
  - Verify `thresholds` object has `lines`, `branches`, `functions`, `statements` keys
  - Check that threshold values are numbers between 0 and 100
- Record result: PASS / FAIL

### 4. External Tools (if enabled)

Check if external tools are configured by reading `.metaswarm/external-tools.yaml`:

- If file doesn't exist: **SKIP** — "External tools not configured (optional)."
- If file exists:
  - For each adapter with `enabled: true`:
    - **Codex**: Run via Bash: `.claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh health`
      - Parse JSON output — check `status` field
      - If `status` is `"ready"`: PASS
      - If `status` is `"unavailable"`: WARN with reason (not installed / not authenticated)
    - **Gemini**: Run via Bash: `.claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh health`
      - Same check as Codex
  - Verify adapter scripts exist and are executable:
    - Glob for `.claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh`
    - Glob for `.claude/plugins/metaswarm/skills/external-tools/adapters/gemini.sh`
    - If missing: **FAIL** — "Adapter script not found. Re-run `npx metaswarm install`."
    - If not executable: **WARN** — "Adapter script not executable. Fix with: `chmod +x <path>`"
- Record results per tool: PASS / WARN / FAIL

### 5. Git Hooks (if configured)

Check `.metaswarm/project-profile.json` -> `choices.git_hooks`:

- If `false` or not set: **SKIP**
- If `true`:
  - Check if `.husky/pre-push` exists (or equivalent hook system detected in profile)
  - If exists and executable: PASS
  - If exists but not executable: **WARN** — "Hook exists but isn't executable. Fix with: `chmod +x .husky/pre-push`"
  - If missing: **WARN** — "Git hooks were enabled but no hook files found. Re-run setup or create manually."
- Record result: PASS / WARN / SKIP

### 6. BEADS (if configured)

Check if `.beads/` directory exists:

- If not present: **SKIP** — "BEADS not initialized (optional)."
- If present:
  - Check if `bd` command is available: run `command -v bd` via Bash
  - If available: run `bd status` via Bash and report the output summary
  - If not available: **WARN** — "`.beads/` directory exists but `bd` CLI not found in PATH."
- Record result: PASS / WARN / SKIP

### 7. Active Agents (Worktree Scan)

Scan for active or abandoned worktrees from external tool runs:

- Run via Bash: `ls -d /tmp/worktree-* 2>/dev/null || true`
- If no worktrees found: **SKIP** — "No active worktrees."
- For each worktree found:
  - **First**, read `.agent-state.json` to determine which adapter owns the worktree:
    - If `"agent": "codex-delegated"` -> use `codex.sh status`
    - If `"agent": "gemini-delegated"` -> use `gemini.sh status`
    - If no `.agent-state.json` exists -> try both adapters, use whichever finds PID files
  - Run the appropriate adapter's `status` command
  - Run via Bash: `git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"`
  - Classify worktree as:
    - **Running**: adapter/child PID is alive
    - **Completed**: Has commits but no running process
    - **Abandoned**: No commits and no running process
  - Report summary table:

```
Active Worktrees:
  /tmp/worktree-abc123   Running    Issue #42   codex PID 12345
  /tmp/worktree-def456   Completed  Issue #18   3 commits (gemini)
  /tmp/worktree-ghi789   Abandoned  Unknown     No commits, no process
```

- If abandoned worktrees found: suggest cleanup using the correct adapter:
  - Codex worktrees: `codex.sh cleanup <path>`
  - Gemini worktrees: `gemini.sh cleanup <path>`
  - Unknown: either adapter's `cleanup` works (both use `cleanup_worktree` from `_common.sh`)

### 8. Summary

Print a final checklist with pass/warn/fail per section:

```
metaswarm doctor results:

  [PASS] Project Profile         - v0.7.0, all fields present
  [PASS] CLAUDE.md               - No TODO markers remaining
  [PASS] Coverage Config         - 100% thresholds, enforcement command set
  [PASS] External Tools: Codex   - ready (gpt-5.3-codex)
  [WARN] External Tools: Gemini  - not installed
  [PASS] Git Hooks               - .husky/pre-push executable
  [SKIP] BEADS                   - Not configured
  [SKIP] Active Agents           - No worktrees found

  Result: 5 passed, 1 warning, 0 failed

  Action items:
  - Install Gemini CLI: npm i -g @google/gemini-cli
```

If everything passes: "All checks passed! Your metaswarm installation is healthy."

If there are failures: "Some checks failed. Address the issues above, then re-run `/project:metaswarm-doctor`."

If there are only warnings: "All critical checks passed. Warnings above are optional improvements."

**Tip:** If the session ended unexpectedly during a delegated run, running `/project:metaswarm-doctor` will discover orphaned worktrees and suggest cleanup commands.
