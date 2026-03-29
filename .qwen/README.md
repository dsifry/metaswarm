# metaswarm for Qwen Code CLI

Install metaswarm's orchestration skills for [Qwen Code CLI](https://github.com/QwenLM/qwen-code).

## Install

### Quick install

```bash
curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.qwen/install.sh | bash
```

### Manual install

```bash
git clone https://github.com/dsifry/metaswarm.git ~/.qwen/metaswarm
mkdir -p ~/.qwen/skills
for d in ~/.qwen/metaswarm/skills/*/; do
  ln -sf "$d" ~/.qwen/skills/metaswarm-$(basename "$d")
done
```

### Via npm (cross-platform installer)

```bash
npx metaswarm init --qwen
```

## Enable Skills

Qwen Code CLI skills are experimental. Enable with:

```bash
qwen --experimental-skills
```

Or edit `settings.json` to add a `skills` setting (may not take effect — CLI flag is recommended).

## Project Setup

In your project directory, invoke the setup skill:

```text
$setup
```

This detects your project's language, framework, test runner, and tools, then creates `QWEN.md` and `.coverage-thresholds.json`.

## How Qwen Finds Skills

Qwen uses the `name` field from each skill's `SKILL.md` frontmatter — not the directory name. The directory prefix `metaswarm-` is for organization only. You invoke skills using `$name` syntax matching the SKILL.md `name` field.

## Available Skills

| Invoke with | SKILL.md name | Purpose |
|---|---|---|
| `$start` | `start` | Begin tracked work on a task |
| `$setup` | `setup` | Interactive guided setup |
| `$brainstorming-extension` | `brainstorming-extension` | Refine an idea with design review gate |
| `$design-review-gate` | `design-review-gate` | Design review |
| `$plan-review-gate` | `plan-review-gate` | Adversarial plan review |
| `$orchestrated-execution` | `orchestrated-execution` | 4-phase execution loop |
| `$pr-shepherd` | `pr-shepherd` | Monitor a PR through to merge |
| `$handling-pr-comments` | `handling-pr-comments` | Handle PR review comments |
| `$create-issue` | `create-issue` | Create a well-structured GitHub Issue |
| `$status` | `status` | Run diagnostic checks |
| `$visual-review` | `visual-review` | Playwright screenshot capture |

## Skill Structure

Each skill is a directory with:

- **SKILL.md** — Required. Contains frontmatter with `name`, `description`, `triggers`, and the skill definition
- **Additional files** — Optional resources, scripts, or templates

Example structure:
```
~/.qwen/skills/metaswarm-start/
├── SKILL.md          # Required — skill definition
└── ...               # Optional resources
```

## Updating

```bash
cd ~/.qwen/metaswarm && git pull
```

Or re-run the install script — it detects existing installations and updates in-place.

## Uninstall

```bash
# Remove skill symlinks
for link in ~/.qwen/skills/metaswarm-*; do rm -f "$link"; done
# Remove installation
rm -rf ~/.qwen/metaswarm
```

## Limitations

Qwen Code CLI skills are experimental. Key considerations:

- **Skill discovery** — Skills must be placed in `~/.qwen/skills/` directory
- **Enable flag** — Must run with `--experimental-skills` flag or configure in settings
- **Subagent spawning** — Qwen may not have `Task()` equivalent for spawning subagents. Design reviews and adversarial reviews run sequentially instead of in parallel
- **Quality gates** — Rubric criteria remain identical; execution mode differs (sequential vs parallel)

## Troubleshooting

**Skills not loading:**
1. Verify skills are in `~/.qwen/skills/`
2. Ensure each skill has a `SKILL.md` file in its root
3. Run with `--experimental-skills` flag
4. Check Qwen Code CLI version supports skills

**Skill not found:**
- Invoke using `$name` syntax (e.g., `$start`, `$setup`)
- The name matches the `name` field in `SKILL.md` frontmatter
