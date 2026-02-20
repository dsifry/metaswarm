# Update Metaswarm

Update metaswarm to the latest version, refresh component files, and re-detect project context.

## Usage

```text
/metaswarm-update-version
```

## Steps

### 1. Check Current Version

- Read `.metaswarm/project-profile.json` and extract `metaswarm_version`
- If the file doesn't exist, stop and tell the user:
  > No project profile found. Run `/metaswarm-setup` first to initialize metaswarm.
- Display the current version to the user

### 2. Fetch Latest Version

- Run `npm view metaswarm version` to get the latest published version
- Compare current vs. latest:
  - **If current == latest**: tell the user they're already up to date and stop
  - **If current < latest**: continue to the next step

### 3. Show What's New

- Run `npx metaswarm@latest changelog --from <current-version>` to show changes between versions
- If that fails, try `npx metaswarm@latest changelog` and filter entries after the current version
- Highlight any **BREAKING CHANGES** prominently if present
- Show a summary of new features, fixes, and new components

### 4. Update Files

- Run `npx metaswarm@latest install` to refresh all component files
- This uses skip-if-exists semantics — user customizations in CLAUDE.md, agents, etc. are preserved
- New files (new skills, commands, agents, guides) will be added
- Existing metaswarm-shipped files will be refreshed to latest versions

### 5. Re-detect Project Context

- Re-run project detection from the setup flow:
  - Language, framework, test runner, linter, formatter, package manager, type checker, CI, git hooks
- Compare new detection results against `detection` in the existing project profile
- If changes are detected (e.g., project switched from Jest to Vitest):
  - Show what changed
  - Ask user if they want to re-customize affected files (e.g., update coverage commands in CLAUDE.md)
  - If yes, apply the same customization logic from `/metaswarm-setup`

### 6. Update Project Profile

- Update `.metaswarm/project-profile.json`:
  - `metaswarm_version` → set to new version
  - `updated_at` → set to current ISO 8601 timestamp
  - `detection` → refresh if project context changed (preserve if unchanged)
- Preserve all other fields (`installed_at`, `choices`, `commands`, etc.)

### 7. Summary

- Print what was updated:
  - Version change (e.g., `0.6.0 → 0.7.0`)
  - Number of files refreshed or added
  - Any new skills, commands, or agents that were added
  - Any project detection changes
- If there were breaking changes, remind the user to review them
- Suggest reviewing the changelog for new features to take advantage of
