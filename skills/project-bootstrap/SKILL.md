---
name: project-bootstrap
description: Auto-scaffold metaswarm into any project on first session and check for version updates — opt-in SessionStart hooks on Claude Code, skill-invoked on Codex
auto_activate: true
triggers:
  - "bootstrap project"
  - "setup metaswarm"
  - "scaffold metaswarm"
  - "initialize metaswarm"
  - "update metaswarm"
  - "check metaswarm version"
---

# Project Bootstrap

**Core principle**: Metaswarm should be available in every project without manual setup, and stay up to date without manual checking — the framework bootstraps itself on first contact and notifies you when updates are available.

This skill provides two SessionStart hooks:

1. **Auto-scaffold** — Installs metaswarm into any new project on first session
2. **Version check** — Compares installed version against npm and notifies if an update is available (cached for 24 hours to avoid repeated network calls)

On Claude Code both run automatically via `SessionStart` hooks after the user opts in during `metaswarm install` (or with `--install-global-hooks`). On Codex and other platforms, the agent invokes this skill at session start.

---

## Coordination Mode Note

This skill operates identically in both Task Mode and Team Mode. It runs before any other skill and has no dependencies.

---

## When to Activate

Activate this skill when **ANY** of these conditions are true:

- A session is starting in a project that lacks `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
- The user asks to update or check the metaswarm version
- The version-check hook reports a newer version is available

**Do NOT activate when:**

- `plugin.json` already exists and is current (metaswarm is already scaffolded and up to date)
- The working directory is not a git repository
- The directory is `$HOME` itself (avoid polluting the home directory)

---

## Announce at Start

> "Metaswarm isn't set up in this project yet — bootstrapping now."

Or, for version updates:

> "A newer version of metaswarm is available (X.Y.Z → A.B.C). Updating now."

---

## 1. Auto-Scaffold (metaswarm-bootstrap)

Check for the metaswarm marker file:

```bash
if [ -f ".claude/plugins/metaswarm/.claude-plugin/plugin.json" ]; then
  # Already installed — exit silently
  exit 0
fi
```

If missing, run the non-interactive install:

```bash
echo "Y" | npx metaswarm install
```

The `echo "Y"` auto-accepts the CLAUDE.md append prompt. The installer:
- Never overwrites existing files (skips with `·` marker)
- Creates the full scaffolding: agents, guides, rubrics, templates, knowledge base
- Generates `plugin.json` with the current metaswarm version
- Initializes beads if `.beads/` doesn't exist

---

## 2. Version Check (metaswarm-version-check)

Runs on every session start with a 24-hour cache to avoid redundant npm queries.

**Flow:**

```
Session Start
    │
    ▼
Cache fresh? ──yes──► Exit silently
    │
    no
    ▼
Read installed version from plugin.json
    │
    ▼
Query npm for latest version (5s timeout)
    │
    ▼
Compare versions
    │
    ├── Same ──► Write cache, exit silently
    │
    └── Different ──► Print update notice, write cache
```

**Cache file:** `~/.metaswarm/version-cache`
- Line 1: Unix timestamp of last check
- Line 2+: Cached update message from last network check (for diagnostics)

**Update notice format:**
```
metaswarm update available: 0.7.1 → 0.8.0. Run: npx metaswarm@0.8.0 install
```

This appears in the Claude Code session context via the hook output, so the agent sees it and can offer to update.

---

## 3. Applying Updates

When the version check reports an update, the agent should:

1. Show the user the available update
2. If the user approves, run:
   ```bash
   echo "Y" | npx metaswarm@<latest> install
   ```
3. Force-update changed files (the installer skips existing files, so for updates you need to remove the old versions first or use `npx metaswarm@<latest> install --force` if available)
4. Update `plugin.json` version to match

---

## Platform Setup

### Claude Code — Opt-In SessionStart Hooks

Both hooks are added to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/metaswarm-bootstrap"
          },
          {
            "type": "command",
            "command": "/path/to/metaswarm-version-check"
          }
        ]
      }
    ]
  }
}
```

**Installation (recommended):**

```bash
npx metaswarm install --install-global-hooks
```

Or run `npx metaswarm install` and answer prompts:
- Install global hooks/skills? `y` to enable SessionStart auto-bootstrap
- Enable session-start update checks? `y` to get update notices (optional)

The `metaswarm-bootstrap` script exits instantly if the project already has metaswarm. The `metaswarm-version-check` script exits instantly if it checked within 24 hours. Combined overhead for a warm session: ~2ms.

### Codex — Skill-Invoked

Codex does not have session hooks. Instead, the agent should invoke this skill at the start of every session. The skill is loaded globally from `~/.agents/skills/metaswarm/` and instructs the agent to:

1. Check if `.claude/plugins/metaswarm/.claude-plugin/plugin.json` exists — if not, run the bootstrap
2. Run `npm view metaswarm version` and compare against the installed version — if newer, notify the user

**Installation:**

```bash
# Copy metaswarm to Codex home
cp -r /path/to/metaswarm ~/.codex/metaswarm

# Symlink skills into the global Codex skills directory
mkdir -p ~/.agents/skills
ln -sf ~/.codex/metaswarm/skills ~/.agents/skills/metaswarm
```

### Other Platforms

Any platform that supports agent skills can use this skill. The core logic is:

1. Check for `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
2. If missing, run `echo "Y" | npx metaswarm install`
3. Compare `plugin.json` version against `npm view metaswarm version`
4. If newer version available, notify the user

---

## Anti-Patterns

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
|---|---|---|---|
| 1 | **Running install every session** — always calling `npx metaswarm install` without checking first | Wastes 5-10 seconds on npx resolution every session start | Check for `plugin.json` first; only install if missing |
| 2 | **Installing in non-git directories** — running bootstrap in `/tmp` or home directory | Scaffolds agents, rubrics, and knowledge files into directories that aren't projects | Guard with `git rev-parse --is-inside-work-tree` before installing |
| 3 | **Interactive install in hooks** — running `npx metaswarm install` without piping `Y` | The CLAUDE.md prompt blocks the hook, hanging the session start | Always pipe `echo "Y"` to make the install non-interactive |
| 4 | **Overwriting existing plugin.json** — deleting and recreating on every run | Loses the version that was intentionally installed; may downgrade | Only install when the marker file is completely absent |
| 5 | **Checking npm on every session** — no caching of version lookups | Adds 2-5 seconds of latency to every session start | Cache the result for 24 hours in `~/.metaswarm/version-cache` |
| 6 | **Auto-updating without user consent** — silently upgrading metaswarm | May break workflows mid-session or introduce unexpected changes | Only notify; let the user decide when to update |

---

## Scripts Reference

| Script | Purpose | Runs When |
|---|---|---|
| `scripts/metaswarm-bootstrap` | Scaffold metaswarm into a new project | Every session start (exits instantly if already installed) |
| `scripts/metaswarm-version-check` | Compare installed vs latest npm version | Every session start (cached for 24 hours) |

---

## Verification Checklist

Before considering setup complete:

- [ ] `plugin.json` exists at `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
- [ ] Plugin version in `plugin.json` matches the installed metaswarm version
- [ ] Agent definitions exist in `.claude/plugins/metaswarm/skills/beads/agents/`
- [ ] Guides exist in `.claude/guides/`
- [ ] Rubrics exist in `.claude/rubrics/`
- [ ] CLAUDE.md contains the metaswarm section
- [ ] Session start latency is under 100ms for already-bootstrapped projects
- [ ] Version check cache file exists at `~/.metaswarm/version-cache` after first session
- [ ] Version check correctly reports when a newer version is available

---

## Related Skills

- `orchestrated-execution` — The 4-phase execution loop that this skill enables
- `plan-review-gate` — Adversarial plan review that requires agents to be scaffolded
- `external-tools` — External tool delegation that depends on project-level configuration
