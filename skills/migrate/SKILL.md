---
name: migrate
description: Migrate from npm-installed tribunal to the marketplace plugin — removes redundant files with safety checks
---

# Migration Skill

Migrate a project from npm-installed tribunal (`npx tribunal init`) to the marketplace plugin. Removes redundant embedded files with a safety protocol that prevents data loss.

**When to use**: The SessionStart hook detects `.claude/plugins/tribunal/.claude-plugin/plugin.json` (legacy embedded plugin) and recommends running this skill.

---

## IMPORTANT: Safety & Messaging Guidelines

**The user MUST understand this before any file list is shown:**

Before presenting any migration preview or file list, ALWAYS lead with this framing:

> **What this migration does**: The marketplace plugin now provides all the skills, commands, rubrics, and guides that were previously copied into your project directory. This migration simply removes those redundant copies — the originals now live in the plugin itself.
>
> **Nothing is lost**: Your project-specific files (CLAUDE.md, .coverage-thresholds.json, .beads/, bin/, scripts/) are NEVER touched. Only duplicate tribunal framework files are removed.
>
> **Fully reversible**: All removals are staged with `git rm` (not permanently deleted). Before you commit:
> - Undo everything: `git restore --staged . && git checkout -- .`
> - After committing: `git revert HEAD`
>
> **No commit is made automatically** — you review and commit when you're satisfied.

**Tone**: Be reassuring, not alarming. Say "cleaning up XX redundant copies" not "deleting XX files". Say "these files now live in the plugin" not "these files will be removed". Frame the migration as housekeeping, not destruction.

**When showing file counts**: If there are many files (e.g., 40+), explain that the large count is because the old npm installer copied the entire plugin framework into `.claude/plugins/tribunal/` — that one directory accounts for most of the count, and it's all framework code that's now served directly by the plugin.

---

## Step 1: Pre-flight Check

1. Confirm this skill is running from the marketplace plugin (if this skill loaded, the plugin is active)
2. Read `.tribunal/project-profile.json` -- if `"distribution": "plugin"` is already set, inform the user migration was already completed and exit
3. Verify `.claude/plugins/tribunal/.claude-plugin/plugin.json` exists -- if not, there is nothing to migrate; inform the user and exit

If the plugin is not loaded, the user needs to install it first: `/plugin marketplace add jpeggdev/tribunal`

---

## Step 2: Inventory Legacy Files

Scan for files installed by `npx tribunal init` that are now provided by the marketplace plugin.

**Candidates for removal:**

| Category | Path pattern |
|---|---|
| Embedded plugin | `.claude/plugins/tribunal/` (entire directory) |
| Rubrics | `.claude/rubrics/*.md` |
| Guides | `.claude/guides/*.md` |
| Old commands | `.claude/commands/tribunal-setup.md`, `.claude/commands/tribunal-update-version.md` |

**NEVER removed** (project-local files): `CLAUDE.md`, `.coverage-thresholds.json`, `.tribunal/project-profile.json`, `.beads/`, `bin/`, `scripts/`, `.github/workflows/`, `.claude/commands/` shims.

---

## Step 3: Content Verification

For each removal candidate, verify it is an unmodified tribunal file using SHA-256 hash comparison.

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
- .claude/plugins/tribunal/ (embedded plugin copy — XX files, now served by marketplace plugin)
- .claude/rubrics/<each matching file> (now in plugin's rubrics/)
- .claude/guides/<each matching file> (now in plugin's guides/)
- .claude/commands/tribunal-setup.md (replaced by plugin command)
- .claude/commands/tribunal-update-version.md (replaced by plugin command)

### Files you've customized (require your decision)
- .claude/rubrics/code-review-rubric.md (MODIFIED — your changes are preserved until you decide)

### Your project files (NEVER touched)
- CLAUDE.md, .coverage-thresholds.json, .tribunal/, .beads/, bin/, scripts/

### What gets added
- 6 command shims in .claude/commands/ (thin wrappers that route to plugin commands)
- .tribunal/project-profile.json updated with "distribution": "plugin"

### How to undo (before committing)
git restore --staged . && git checkout -- .
```

---

## Step 5: User Confirmation

Use `AskUserQuestion`:
- Remind the user: "This stages the cleanup — nothing is committed yet. You can undo with `git restore --staged . && git checkout -- .`"
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
git rm -rf .claude/plugins/tribunal/
git rm .claude/rubrics/<each confirmed file>
git rm .claude/guides/<each confirmed file>
git rm .claude/commands/tribunal-setup.md
git rm .claude/commands/tribunal-update-version.md
```

**After running**: Reassure: "Done — XX files staged for removal. These are only staged, not committed. Run `git status` to see the staged changes, or `git restore --staged . && git checkout -- .` to undo."

**Untracked files** -- use `rm -f` (unlikely but handle gracefully).

**Empty directories** -- remove `.claude/rubrics/` and `.claude/guides/` if empty after cleanup. Do NOT remove `.claude/commands/` (shims remain).

---

## Step 8: Command Shim Creation

Write 6 shims to `.claude/commands/` (same as setup skill):

| Shim | Routes to |
|---|---|
| `start-task.md` | `/tribunal:start-task` |
| `prime.md` | `/tribunal:prime` |
| `review-design.md` | `/tribunal:review-design` |
| `self-reflect.md` | `/tribunal:self-reflect` |
| `pr-shepherd.md` | `/tribunal:pr-shepherd` |
| `brainstorm.md` | `/tribunal:brainstorm` |

Each shim:
```markdown
<!-- Created by tribunal setup. Routes to the tribunal plugin. Safe to delete if you uninstall tribunal. -->
Invoke the `/tribunal:<command-name>` skill with any arguments the user provided.
```

If a shim already exists with different content, ask before overwriting.

---

## Step 9: Profile Update

Merge these fields into `.tribunal/project-profile.json` (preserve existing fields):
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
- Added 6 command shims to .claude/commands/
- Updated project profile to "distribution": "plugin"

### Next steps
1. Review staged changes: `git diff --cached --stat`
2. Commit when satisfied: `git commit -m "chore: migrate tribunal from npm to marketplace plugin"`
3. Verify everything works: try `/start-task`

### If anything seems wrong
- Undo before committing: `git restore --staged . && git checkout -- .`
- Undo after committing: `git revert HEAD`
- Full re-install: `npx tribunal install` (npm package still available)
```

---

## Rollback (Nothing Is Permanent)

All removals use `git rm`, which only stages changes — files are NOT deleted from git history. The migration never auto-commits, so the user always has a chance to review and undo:

- **Before committing** (full undo): `git restore --staged . && git checkout -- .`
- **After committing** (full undo): `git revert HEAD`
- **Single file recovery**: `git checkout HEAD~1 -- <path>`
- **Full re-install of old approach**: `npx tribunal install` (npm package still published)

---

## Error Handling

| Error | Action |
|---|---|
| `.tribunal/project-profile.json` missing | Create with minimal fields, proceed |
| `git rm` fails on a file | Log error, skip file, continue |
| Permission denied | Warn user, skip file, continue |
| Plugin not loaded | Exit with install instructions |
| `tribunal_version < 0.8.0` | Warn manual intervention may be needed |

---

## Anti-Patterns

| Anti-Pattern | Do Instead |
|---|---|
| Auto-deleting modified files | Flag and ask explicitly |
| Deleting before confirming plugin works | Pre-flight check first |
| Using `rm -rf` on tracked files | Use `git rm` (reversible) |
| Skipping dry run preview | Always show full preview |
| Removing project-local files | Never touch CLAUDE.md, .beads/, bin/, scripts/ |
| Saying "deleting XX files" or "removing XX files" | Say "cleaning up XX redundant copies" |
| Showing file list without safety context | Always lead with the safety framing |
| Jumping straight to `git rm` commands | Explain what you're doing and why it's safe first |
