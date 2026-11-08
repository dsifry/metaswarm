---
name: migrate
description: Migrate from npm-installed metaswarm to the marketplace plugin — removes redundant files with safety checks
---

# Migration Skill

Migrate a project from npm-installed metaswarm (`npx metaswarm init`) to the marketplace plugin. Removes redundant embedded files with a safety protocol that prevents data loss.

**When to use**: The SessionStart hook detects `.claude/plugins/metaswarm/.claude-plugin/plugin.json` (legacy embedded plugin) and recommends running this skill.

---

## IMPORTANT: Safety & Messaging Guidelines

**The user MUST understand this before any file list is shown:**

Before presenting any migration preview or file list, ALWAYS lead with this framing:

> **What this migration does**: The marketplace plugin now provides all the skills, commands, rubrics, and guides that were previously copied into your project directory. This migration simply removes those redundant copies — the originals now live in the plugin itself.
>
> **Nothing is lost**: Your project-specific files (CLAUDE.md, .coverage-thresholds.json, .beads/, bin/, scripts/) are NEVER touched. Only duplicate metaswarm framework files are removed.
>
> **Reversible**: Removals of git-tracked files are staged with `git rm` (not permanently deleted). Untracked copies, which git can't restore, are moved to `.metaswarm/migrate-backup-<timestamp>/` instead of being deleted. Before you commit:
> - Undo the removals: see [Rollback](#rollback-nothing-is-permanent) (it restores only the files this migration removed, not other changes)
> - After committing: `git revert HEAD`
>
> **No commit is made automatically** — you review and commit when you're satisfied.

**Tone**: Be reassuring, not alarming. Say "cleaning up XX redundant copies" not "deleting XX files". Say "these files now live in the plugin" not "these files will be removed". Frame the migration as housekeeping, not destruction.

**When showing file counts**: If there are many files (e.g., 40+), explain that the large count is because the old npm installer copied the entire plugin framework into `.claude/plugins/metaswarm/` — that one directory accounts for most of the count, and it's all framework code that's now served directly by the plugin.

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

Display the complete migration plan before any changes. **Lead with the safety framing from the guidelines above**, then show the preview:

```
## Migration Preview

These are redundant copies of framework files that are now provided by the plugin.
All removals are staged (not committed) — you can undo everything before committing.

### Redundant framework files to clean up (XX files)
These are unmodified copies that the plugin now provides directly:
- .claude/plugins/metaswarm/ (embedded plugin copy — XX files, now served by marketplace plugin)
- .claude/rubrics/<each matching file> (now in plugin's rubrics/)
- .claude/guides/<each matching file> (now in plugin's guides/)
- .claude/commands/metaswarm-setup.md (replaced by plugin command)
- .claude/commands/metaswarm-update-version.md (replaced by plugin command)

### Files you've customized (require your decision)
- .claude/rubrics/code-review-rubric.md (MODIFIED — your changes are preserved until you decide)

### Your project files (NEVER touched)
- CLAUDE.md, .coverage-thresholds.json, .metaswarm/, .beads/, bin/, scripts/

### What gets added
- 6 command shims in .claude/commands/ (thin wrappers that route to plugin commands)
- .metaswarm/project-profile.json updated with "distribution": "plugin"

### Untracked copies (moved, not deleted)
- <each confirmed untracked file> → .metaswarm/migrate-backup-<timestamp>/

### How to undo (before committing)
git diff --cached --name-only -z --diff-filter=D -- .claude/plugins/metaswarm .claude/rubrics .claude/guides .claude/commands/metaswarm-setup.md .claude/commands/metaswarm-update-version.md | xargs -0 git restore --staged --worktree --
```

---

## Step 5: User Confirmation

Use `AskUserQuestion`:
- Remind the user: "This stages the cleanup — nothing is committed yet. You can undo just these removals before committing (see the Rollback section)."
- Ask: "Ready to clean up the redundant framework files?" (not "Ready to delete files?")
- For each user-modified file, ask individually: keep, remove, or show diff
- If the user chooses "diff", display the difference between their version and the plugin's, then re-ask

---

## Step 6: Git Safety

Before executing removals:
1. Run `git status` to check for uncommitted changes
2. If uncommitted changes exist, warn: "Recommended to commit or stash before migrating so changes are in their own commit. Continue anyway?"
3. If the user declines, exit

---

## Step 7: Cleanup

**Announce what you're doing**: Before running any commands, say:
> "Staging the redundant files for removal. These are all framework copies — your project files are untouched. Nothing is committed yet."

**Git-tracked files** -- use `git rm` (staged, reversible via `git checkout`):
```bash
git rm -rf .claude/plugins/metaswarm/
git rm .claude/rubrics/<each confirmed file>
git rm .claude/guides/<each confirmed file>
git rm .claude/commands/metaswarm-setup.md
git rm .claude/commands/metaswarm-update-version.md
```

**After running**: Reassure: "Done — XX files staged for removal. These are only staged, not committed. Run `git status` to see the staged changes; the Rollback section below shows how to undo just these removals."

**Untracked files** -- move them to a timestamped backup folder, not `rm` (unlikely, but git can't restore them). List the confirmed untracked files in `UNTRACKED` (find them with `git ls-files --others -- .claude/plugins/metaswarm .claude/rubrics .claude/guides .claude/commands`, then keep only the confirmed ones; skip this step when there are none):
```bash
UNTRACKED=(<each confirmed untracked file>)
BACKUP=".metaswarm/migrate-backup-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
printf '*\n' > "$BACKUP/.gitignore"   # keeps the backup out of commits
for f in "${UNTRACKED[@]}"; do
  mkdir -p "$BACKUP/$(dirname "$f")"
  mv -- "$f" "$BACKUP/$f"
done
echo "Moved ${#UNTRACKED[@]} untracked file(s) to $BACKUP/"
```

The backup keeps each file at its original path inside the folder, and its own `.gitignore` keeps git from listing or committing it. Delete the folder once you're happy with the migration. Name it in the Step 10 summary.

**Empty directories** -- remove `.claude/rubrics/` and `.claude/guides/` if empty after cleanup. Do NOT remove `.claude/commands/` (shims remain).

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

Cleaned up XX redundant framework files that are now provided by the marketplace plugin.
Your project files (CLAUDE.md, .coverage-thresholds.json, .beads/, etc.) were not touched.

### What changed
- Removed XX redundant framework copies (now served by plugin)
- Moved N untracked copies to .metaswarm/migrate-backup-<timestamp>/ (git ignores it; delete it once you're satisfied)
- Added 6 command shims to .claude/commands/
- Updated project profile to "distribution": "plugin"

### Next steps
1. Review staged changes: `git diff --cached --stat`
2. Commit when satisfied: `git commit -m "chore: migrate metaswarm from npm to marketplace plugin"`
3. Verify everything works: try `/start-task`

### If anything seems wrong
- Undo before committing: `git diff --cached --name-only -z --diff-filter=D -- .claude/plugins/metaswarm .claude/rubrics .claude/guides .claude/commands/metaswarm-setup.md .claude/commands/metaswarm-update-version.md | xargs -0 git restore --staged --worktree --` restores only deletions under the legacy paths Step 7 removes from, leaving your other changes (including other staged deletions) alone
- Undo after committing: `git revert HEAD`
- Bring the old files back: undoing as above restores the git-tracked ones. Untracked ones are in .metaswarm/migrate-backup-<timestamp>/; the Rollback section shows how to copy them back. There is no command that re-creates the old npm-copied layout: today `npx metaswarm init` installs the marketplace plugin, and `npx metaswarm setup` writes only the project's instruction files and `.coverage-thresholds.json`
```

---

## Generated agent files

`/setup` and `/update` generate `.claude/agents/metaswarm-<role>.md` from `.metaswarm/models.yaml`. These are separate from the legacy files above, and removing them is also how to uninstall metaswarm's phase agents.

1. List them for the user as removable: `ls .claude/agents/metaswarm-*.md`
2. Run `MA="$(command -v metaswarm-agents.sh || echo "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/bin/metaswarm-agents.sh")"; "$MA" clean` (uses `command -v metaswarm-agents.sh`). It removes only files carrying the `generated-by: metaswarm` header, so user-authored agents (including a same-named file without the header) are left alone.
3. `.metaswarm/models.yaml` is yours to keep or delete. After cleaning, the plugin's own phase agents (`metaswarm:<role>`) still apply with their default models.

---

## Rollback (Nothing Is Permanent)

Removals of tracked files use `git rm`, which only stages changes — files are NOT deleted from git history. Untracked files are moved to a backup folder, not deleted. The migration never auto-commits, so the user always has a chance to review and undo:

- **Before committing** (undo the migration only): `git diff --cached --name-only -z --diff-filter=D -- .claude/plugins/metaswarm .claude/rubrics .claude/guides .claude/commands/metaswarm-setup.md .claude/commands/metaswarm-update-version.md | xargs -0 git restore --staged --worktree --`. It restores only staged deletions under the legacy paths Step 7 removes from, so unrelated work, including other staged deletions, is kept. The shims and profile changes from Steps 8 and 9 stay; delete or `git restore -- <path>` them by path
- **After committing** (full undo): `git revert HEAD`
- **Single file recovery**: `git checkout HEAD~1 -- <path>`
- **Untracked files** moved to the backup folder in Step 7 aren't in git, so the commands above don't bring them back. Restore them from the folder:

**Restore untracked files** (use the folder Step 7 printed):
```bash
BACKUP=".metaswarm/migrate-backup-<timestamp>"
# Copies each file (and symbolic link, as a link) back to its original path. A
# path that exists again is skipped and reported, never overwritten; one that
# can't be restored is reported, and the backup is kept. Its .gitignore stays put.
if find "$BACKUP" \( -type f -o -type l \) ! -path "$BACKUP/.gitignore" -exec sh -c '
  b=$1; shift; rc=0
  for src; do
    dst=${src#"$b"/}
    if [ -e "$dst" ] || [ -L "$dst" ]; then echo "skipped (already exists): $dst"
    elif ! { mkdir -p "$(dirname "$dst")" && cp -RPp "$src" "$dst"; }; then
      echo "NOT restored: $dst" >&2; rc=1
    fi
  done
  exit $rc' sh "$BACKUP" {} +; then
  echo "Restored the files in $BACKUP; delete the folder once you've checked them"
else
  echo "Some files were NOT restored (see above). Keep $BACKUP until they are." >&2
fi
```
- **Old npm-copied layout**: restore its git-tracked files with the commands above. No current command re-creates it: `npx metaswarm init` now installs the marketplace plugin, and `npx metaswarm setup` writes only the project's instruction files and `.coverage-thresholds.json`

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
| Using `rm -f` on untracked files | Move them to `.metaswarm/migrate-backup-<timestamp>/` (git can't restore them) |
| Skipping dry run preview | Always show full preview |
| Removing project-local files | Never touch CLAUDE.md, .beads/, bin/, scripts/ |
| Saying "deleting XX files" or "removing XX files" | Say "cleaning up XX redundant copies" |
| Showing file list without safety context | Always lead with the safety framing |
| Jumping straight to `git rm` commands | Explain what you're doing and why it's safe first |
