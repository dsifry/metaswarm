---
name: migrate
description: Migrate from npm-installed metaswarm to the marketplace plugin — removes redundant files with safety checks
---

# Migration Skill

Migrate a project from npm-installed metaswarm (`npx metaswarm init`) to the marketplace plugin. Removes redundant embedded files with a safety protocol that prevents data loss.

**When to use**: The SessionStart hook detects `.claude/plugins/metaswarm/.claude-plugin/plugin.json` (legacy embedded plugin) and recommends running this skill.

---

## Step 1: Pre-flight Check

1. Confirm this skill is running from the marketplace plugin (if this skill loaded, the plugin is active)
2. Read `.metaswarm/project-profile.json` -- if `"distribution": "plugin"` is already set, inform the user migration was already completed and exit
3. Verify `.claude/plugins/metaswarm/.claude-plugin/plugin.json` exists -- if not, there is nothing to migrate; inform the user and exit

If the plugin is not loaded, the user needs to install it first: `/plugin marketplace add dsifry/metaswarm-marketplace`

---

## Step 2: Inventory Legacy Files

Scan for files installed by `npx metaswarm init` that are now provided by the marketplace plugin.

**Candidates for removal:**

| Category | Path pattern |
|---|---|
| Embedded plugin | `.claude/plugins/metaswarm/` (entire directory) |
| Rubrics | `.claude/rubrics/*.md` |
| Guides | `.claude/guides/*.md` |
| Old commands | `.claude/commands/metaswarm-setup.md`, `.claude/commands/metaswarm-update-version.md` |

**NEVER removed** (project-local files): `CLAUDE.md`, `.coverage-thresholds.json`, `.metaswarm/project-profile.json`, `.beads/`, `bin/`, `scripts/`, `.github/workflows/`, `.claude/commands/` shims.

---

## Step 3: Content Verification

For each removal candidate, verify it is an unmodified metaswarm file using SHA-256 hash comparison.

**Hash protocol:**
1. Read file content
2. Normalize line endings to LF (`\r\n` -> `\n`, `\r` -> `\n`)
3. Strip trailing whitespace from each line
4. Strip trailing newlines
5. Compute SHA-256 of normalized content
6. Compare against hash of the corresponding file from the marketplace plugin's own directories (rubrics/, guides/, etc.)

Computing hashes from the plugin's live files ensures the hash list stays current -- no hardcoded hashes that drift.

**Classification:**

| Result | Action |
|---|---|
| Hash matches | **Unmodified** -- add to deletion list |
| Hash differs | **User-modified** -- flag for user decision, never auto-delete |
| Not in hash list | **Unknown file** -- skip entirely |

---

## Step 4: Dry Run Preview

Display the complete migration plan before any changes:

```
## Migration Preview

### Files to remove (unmodified)
- .claude/plugins/metaswarm/ (entire directory, XX files)
- .claude/rubrics/<each matching file>
- .claude/guides/<each matching file>
- .claude/commands/metaswarm-setup.md
- .claude/commands/metaswarm-update-version.md

### User-modified files (require your decision)
- .claude/rubrics/code-review-rubric.md (MODIFIED)

### Files NOT touched
- CLAUDE.md, .coverage-thresholds.json, .metaswarm/, .beads/, bin/, scripts/

### Additional changes
- 6 command shims written to .claude/commands/
- .metaswarm/project-profile.json updated with "distribution": "plugin"
```

---

## Step 5: User Confirmation

Use `AskUserQuestion`:
- Present the deletion list and require explicit "yes" to proceed
- For each user-modified file, ask individually: keep, remove, or show diff
- If the user chooses "diff", display the difference between their version and the plugin's, then re-ask

---

## Step 6: Git Safety

Before executing removals:
1. Run `git status` to check for uncommitted changes
2. If uncommitted changes exist, warn: "Recommended to commit or stash before migrating so changes are in their own commit. Continue anyway?"
3. If the user declines, exit

---

## Step 7: Removal

**Git-tracked files** -- use `git rm` (staged, reversible via `git checkout`):
```bash
git rm -rf .claude/plugins/metaswarm/
git rm .claude/rubrics/<each confirmed file>
git rm .claude/guides/<each confirmed file>
git rm .claude/commands/metaswarm-setup.md
git rm .claude/commands/metaswarm-update-version.md
```

**Untracked files** -- use `rm -f` (unlikely but handle gracefully).

**Empty directories** -- remove `.claude/rubrics/` and `.claude/guides/` if empty after deletion. Do NOT remove `.claude/commands/` (shims remain).

---

## Step 8: Command Shim Creation

Write 6 shims to `.claude/commands/` (same as setup skill):

| Shim | Routes to |
|---|---|
| `start-task.md` | `/metaswarm:start-task` |
| `prime.md` | `/metaswarm:prime` |
| `review-design.md` | `/metaswarm:review-design` |
| `self-reflect.md` | `/metaswarm:self-reflect` |
| `pr-shepherd.md` | `/metaswarm:pr-shepherd` |
| `brainstorm.md` | `/metaswarm:brainstorm` |

Each shim:
```markdown
<!-- Created by metaswarm setup. Routes to the metaswarm plugin. Safe to delete if you uninstall metaswarm. -->
Invoke the `/metaswarm:<command-name>` skill with any arguments the user provided.
```

If a shim already exists with different content, ask before overwriting.

---

## Step 9: Profile Update

Merge these fields into `.metaswarm/project-profile.json` (preserve existing fields):
```json
{
  "distribution": "plugin",
  "migrated_at": "<ISO 8601 timestamp>",
  "migrated_from": "npm"
}
```

---

## Step 10: Post-Migration Summary

Display what was done and next steps:
```
## Migration Complete
- Removed XX legacy plugin files, XX rubrics, XX guides, 2 old commands
- Wrote 6 command shims
- Updated project profile to "distribution": "plugin"

### Next steps
1. Review staged changes: `git diff --cached`
2. Commit: `git commit -m "chore: migrate metaswarm from npm to marketplace plugin"`
3. Verify: try `/start-task`
```

---

## Rollback

All removals use `git rm`, so changes are staged and reversible:

- **Before committing**: `git restore --staged . && git checkout -- .`
- **After committing**: `git revert HEAD`
- **Full re-install**: `npx metaswarm install` (npm v0.9.0 remains published)
- **Single file**: `git checkout HEAD~1 -- <path>`

---

## Error Handling

| Error | Action |
|---|---|
| `.metaswarm/project-profile.json` missing | Create with minimal fields, proceed |
| `git rm` fails on a file | Log error, skip file, continue |
| Permission denied | Warn user, skip file, continue |
| Plugin not loaded | Exit with install instructions |
| `metaswarm_version < 0.8.0` | Warn manual intervention may be needed |

---

## Anti-Patterns

| Anti-Pattern | Do Instead |
|---|---|
| Auto-deleting modified files | Flag and ask explicitly |
| Deleting before confirming plugin works | Pre-flight check first |
| Using `rm -rf` on tracked files | Use `git rm` (reversible) |
| Skipping dry run preview | Always show full preview |
| Removing project-local files | Never touch CLAUDE.md, .beads/, bin/, scripts/ |
