---
name: project-bootstrap
description: Auto-scaffold metaswarm into any project on first session — fully automatic on Claude Code (SessionStart hook), skill-invoked on Codex
auto_activate: true
triggers:
  - "bootstrap project"
  - "setup metaswarm"
  - "scaffold metaswarm"
  - "initialize metaswarm"
---

# Project Bootstrap

**Core principle**: Metaswarm should be available in every project without manual setup — the framework bootstraps itself on first contact.

This skill ensures that when you open a session in a new project, metaswarm's full scaffolding (agents, guides, rubrics, templates, knowledge base) is installed automatically. On Claude Code this happens via a `SessionStart` hook with zero user intervention. On Codex and other platforms, the agent invokes this skill at session start to check and scaffold if needed.

---

## Coordination Mode Note

This skill operates identically in both Task Mode and Team Mode. It runs before any other skill and has no dependencies.

---

## When to Activate

Activate this skill when **ALL** of these conditions are true:

- A session is starting in a project directory
- The project is a git repository
- `.claude/plugins/metaswarm/.claude-plugin/plugin.json` does **not** exist

**Do NOT activate when:**

- `plugin.json` already exists (metaswarm is already scaffolded)
- The working directory is not a git repository
- The directory is `$HOME` itself (avoid polluting the home directory)

---

## Announce at Start

> "Metaswarm isn't set up in this project yet — bootstrapping now."

---

## 1. Detection

Check for the metaswarm marker file:

```bash
if [ -f ".claude/plugins/metaswarm/.claude-plugin/plugin.json" ]; then
  # Already installed — exit silently
  exit 0
fi
```

If it exists, do nothing. The check must be fast (single `stat` call) so it adds no latency to sessions where metaswarm is already present.

---

## 2. Bootstrap

Run the non-interactive install:

```bash
echo "Y" | npx metaswarm install
```

The `echo "Y"` auto-accepts the CLAUDE.md append prompt. The installer:
- Never overwrites existing files (skips with `·` marker)
- Creates the full scaffolding: agents, guides, rubrics, templates, knowledge base
- Generates `plugin.json` with the current metaswarm version
- Initializes beads if `.beads/` doesn't exist

---

## 3. Verification

After install, confirm the marker exists:

```bash
cat .claude/plugins/metaswarm/.claude-plugin/plugin.json
```

Expected output includes `"name": "metaswarm"` and a valid `"version"` field.

---

## Platform Setup

### Claude Code — Fully Automatic (SessionStart Hook)

Add the bootstrap script to the global Claude Code hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "metaswarm-bootstrap"
          }
        ]
      }
    ]
  }
}
```

The `metaswarm-bootstrap` script (see `scripts/metaswarm-bootstrap` in this skill directory) runs on every session start. It exits immediately if metaswarm is already present, so there is no latency penalty for existing projects.

**Installation:**

```bash
# Copy the bootstrap script to a location on PATH
cp skills/project-bootstrap/scripts/metaswarm-bootstrap ~/.local/bin/
chmod +x ~/.local/bin/metaswarm-bootstrap

# Or use the full path in the hook if ~/.local/bin is not on PATH
```

### Codex — Skill-Invoked

Codex does not have session hooks. Instead, the agent should invoke this skill at the start of every session. The skill is loaded globally from `~/.agents/skills/metaswarm/` and instructs the agent to run the bootstrap check.

**Installation:**

```bash
# Clone or copy metaswarm to Codex home
cp -r "$(npm root -g)/metaswarm" ~/.codex/metaswarm 2>/dev/null || \
  cp -r "$(dirname "$(which metaswarm)")/../lib/node_modules/metaswarm" ~/.codex/metaswarm

# Symlink skills into the global Codex skills directory
mkdir -p ~/.agents/skills
ln -sf ~/.codex/metaswarm/skills ~/.agents/skills/metaswarm
```

### Other Platforms

Any platform that supports agent skills can use this skill. The core logic is:

1. Check for `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
2. If missing, run `echo "Y" | npx metaswarm install`
3. Verify the install succeeded

---

## Anti-Patterns

| # | Anti-Pattern | Why It's Wrong | What to Do Instead |
|---|---|---|---|
| 1 | **Running install every session** — always calling `npx metaswarm install` without checking first | Wastes 5-10 seconds on npx resolution every session start | Check for `plugin.json` first; only install if missing |
| 2 | **Installing in non-git directories** — running bootstrap in `/tmp` or home directory | Scaffolds agents, rubrics, and knowledge files into directories that aren't projects | Guard with `git rev-parse --is-inside-work-tree` before installing |
| 3 | **Interactive install in hooks** — running `npx metaswarm install` without piping `Y` | The CLAUDE.md prompt blocks the hook, hanging the session start | Always pipe `echo "Y"` to make the install non-interactive |
| 4 | **Overwriting existing plugin.json** — deleting and recreating on every run | Loses the version that was intentionally installed; may downgrade | Only install when the marker file is completely absent |

---

## Verification Checklist

Before considering bootstrap complete:

- [ ] `plugin.json` exists at `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
- [ ] Plugin version in `plugin.json` matches the installed metaswarm version
- [ ] Agent definitions exist in `.claude/plugins/metaswarm/skills/beads/agents/`
- [ ] Guides exist in `.claude/guides/`
- [ ] Rubrics exist in `.claude/rubrics/`
- [ ] CLAUDE.md contains the metaswarm section
- [ ] Session start latency is under 100ms for already-bootstrapped projects

---

## Related Skills

- `orchestrated-execution` — The 4-phase execution loop that this skill enables
- `plan-review-gate` — Adversarial plan review that requires agents to be scaffolded
- `external-tools` — External tool delegation that depends on project-level configuration
