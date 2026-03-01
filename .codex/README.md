# metaswarm for Codex CLI

Install metaswarm's 13 orchestration skills for [Codex CLI](https://github.com/openai/codex).

## Install

### Quick install

```bash
curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.codex/install.sh | bash
```

### Manual install

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

## Limitations

Codex CLI does not have a `Task()` equivalent for spawning subagents. This means:

- **Design review** runs sequentially (each reviewer perspective one at a time) instead of in parallel
- **Adversarial review** uses rubrics as structured checklists rather than fresh isolated reviewers
- **Background tasks** are not available; all work runs in the current session

The quality gates and rubric criteria are identical — the same review standards apply regardless of platform. The difference is execution mode (sequential vs parallel), not review thoroughness.

## Updating

```bash
cd ~/.codex/metaswarm && git pull
```

Or re-run the install script — it detects existing installations and updates in-place.

## Uninstall

```bash
# Remove skill symlinks
for link in ~/.agents/skills/metaswarm-*; do rm -f "$link"; done
# Remove installation
rm -rf ~/.codex/metaswarm
```
