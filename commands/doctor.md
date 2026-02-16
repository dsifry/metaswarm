# Doctor

Post-install and post-upgrade health check. Verifies the full metaswarm stack is working and reports actionable diagnostics.

## Usage

```text
/project:doctor
```

Run this after `metaswarm install`, after upgrading, or whenever something feels off.

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
- Check that the test command lines (`Test command:`, `Coverage command:`) don't contain placeholder values like `npm test` if the project uses a different runner (cross-reference with `.metaswarm/project-profile.json` commands)
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

Check `.metaswarm/project-profile.json` → `choices.git_hooks`:

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
  - Run via Bash: `.claude/plugins/metaswarm/skills/external-tools/adapters/codex.sh status <worktree>` (ignore errors for non-codex worktrees)
  - Run via Bash: `git -C <worktree> log --oneline -3 2>/dev/null || echo "no commits"`
  - Check for `.agent-state.json` in the worktree — if present, read and report issue number and status
  - Classify worktree as:
    - **Running**: Codex/adapter PID is alive
    - **Completed**: Has commits but no running process
    - **Abandoned**: No commits and no running process
  - Report summary table:

```
Active Worktrees:
  /tmp/worktree-abc123   Running    Issue #42   codex PID 12345
  /tmp/worktree-def456   Completed  Issue #18   3 commits, no running process
  /tmp/worktree-ghi789   Abandoned  Unknown     No commits, no process — safe to clean up
```

- If abandoned worktrees found: suggest cleanup command for each: `codex.sh cleanup <path>`

### 8. Summary

Print a final checklist with pass/warn/fail per section:

```
metaswarm doctor results:

  [PASS] Project Profile         — v0.7.0, all fields present
  [PASS] CLAUDE.md               — No TODO markers remaining
  [PASS] Coverage Config         — 100% thresholds, enforcement command set
  [PASS] External Tools: Codex   — ready (gpt-5.3-codex)
  [WARN] External Tools: Gemini  — not installed
  [PASS] Git Hooks               — .husky/pre-push executable
  [SKIP] BEADS                   — Not configured
  [SKIP] Active Agents           — No worktrees found

  Result: 5 passed, 1 warning, 0 failed

  Action items:
  - Install Gemini CLI: npm i -g @google/gemini-cli
```

If everything passes: "All checks passed! Your metaswarm installation is healthy."

If there are failures: "Some checks failed. Address the issues above, then re-run `/project:doctor`."

If there are only warnings: "All critical checks passed. Warnings above are optional improvements."
