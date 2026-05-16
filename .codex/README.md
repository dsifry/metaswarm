# metaswarm for Codex CLI

Install metaswarm's orchestration skills as a [Codex CLI](https://github.com/openai/codex) plugin.

## Install

### Plugin marketplace install

```bash
codex plugin marketplace add dsifry/metaswarm-marketplace
codex
# In Codex, open /plugins, select the metaswarm marketplace, and install metaswarm.
```

### Local checkout install

From a metaswarm checkout:

```bash
codex plugin marketplace add /path/to/metaswarm
codex
# In Codex, open /plugins, select "metaswarm", and install metaswarm.
```

The repo-local marketplace points at the public metaswarm repository root. For testing an unmerged branch, use a temporary marketplace whose plugin source URL is a `file://` URL or a pushed branch ref.

### Legacy manual install

Use this only if your Codex build does not support plugins:

```bash
git clone https://github.com/dsifry/metaswarm.git ~/.codex/metaswarm
mkdir -p ~/.agents/skills
for d in ~/.codex/metaswarm/skills/*/; do
  ln -sf "$d" ~/.agents/skills/metaswarm-$(basename "$d")
done
```

### Via npm (cross-platform installer)

```bash
npx metaswarm init --codex
```

## Project Setup

In your project directory, invoke the setup skill:

```text
$setup
```

This detects your project's language, framework, test runner, and tools, then creates `AGENTS.md` and `.coverage-thresholds.json`.

## How Codex Finds Skills

Codex uses the `name` field from each skill's `SKILL.md` frontmatter — not the directory name. The directory prefix `metaswarm-` is for organization only. You invoke skills using `$name` syntax matching the SKILL.md `name` field.

## Available Skills

| Invoke with | SKILL.md name | Purpose |
|---|---|---|
| `$start` | `start` | Begin tracked work on a task |
| `$setup` | `setup` | Interactive guided setup |
| `$brainstorming-extension` | `brainstorming-extension` | Refine an idea with design review gate |
| `$design-review-gate` | `design-review-gate` | 5-reviewer design review |
| `$plan-review-gate` | `plan-review-gate` | 3-reviewer adversarial plan review |
| `$orchestrated-execution` | `orchestrated-execution` | 4-phase execution loop |
| `$pr-shepherd` | `pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | `handling-pr-comments` | Handle PR review comments |
| `$create-issue` | `create-issue` | Create a well-structured GitHub Issue |
| `$external-tools` | `external-tools` | Check/use external AI tools |
| `$status` | `status` | Run diagnostic checks |
| `$migrate` | `migrate` | Migrate from npm installation |
| `$visual-review` | `visual-review` | Playwright screenshot capture |

## Execution Model

Codex supports skills and subagents, but the exact orchestration surface is not identical to Claude Code. metaswarm skills should follow `skills/start/references/codex-tools.md` for tool mapping.

- Use `$setup`, `$start`, `$status`, and `$pr-shepherd` in Codex.
- Do not use Claude slash-command shims in Codex.
- Plugin hooks are optional in Codex and require the `plugin_hooks` feature. Core metaswarm workflows do not depend on hooks.

The quality gates and rubric criteria are identical across platforms. The difference is invocation and tool mapping, not review standards.

## Updating

Use Codex's plugin marketplace update flow for plugin installs. For legacy manual installs, re-run `.codex/install.sh` or pull the clone under `~/.codex/metaswarm`.

## Uninstall

Use Codex's `/plugins` UI to uninstall plugin installs.

For legacy manual installs:

```bash
# Remove skill symlinks
for link in ~/.agents/skills/metaswarm-*; do rm -f "$link"; done
# Remove installation
rm -rf ~/.codex/metaswarm
```
