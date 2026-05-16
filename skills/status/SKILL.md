---
name: status
description: Diagnostic status report — shows metaswarm installation state, project setup, and potential issues
---

# Status Skill

Generate a diagnostic report of the metaswarm installation, project configuration, and potential issues across Claude Code, Codex, and Gemini. Useful for troubleshooting and verifying setup or migration.

---

## Checks

Run each check below and present results in a single formatted report. Detect the active platform first:

- Codex: `PLUGIN_ROOT` or `CODEX_HOME` is present, `.codex-plugin/plugin.json` is the active manifest, or the user invoked `$status`
- Claude Code: `CLAUDE_PLUGIN_ROOT` is present, `.claude-plugin/plugin.json` is the active manifest, or the user invoked `$status`
- Gemini: `extensionPath` is present, `gemini-extension.json` is the active manifest, or the user invoked `$status`

### 1. Plugin Version

- Codex: read `.codex-plugin/plugin.json` from the plugin root and report `version`
- Claude Code: read `.claude-plugin/plugin.json` from the plugin root and report `version`
- Gemini: read `gemini-extension.json` from the plugin root and report `version`
- Fallback: read `package.json` at plugin root for `version`
- If neither found: `Plugin version: UNKNOWN`

### 2. Project Setup State

- Check if `.metaswarm/project-profile.json` exists in the working directory
- If present, report key fields: `distribution`, `metaswarm_version`, `language`, `framework`, `test_runner`
- If absent, report the platform-specific setup command:
  - Codex: `Project setup: NOT CONFIGURED -- run $setup`
  - Claude Code: `Project setup: NOT CONFIGURED -- run $setup`
  - Gemini: `Project setup: NOT CONFIGURED -- run $setup`

### 3. Platform Install State

**Codex**
- Check `.codex-plugin/plugin.json` exists in the plugin root
- Check `~/.codex/config.toml` for an enabled `metaswarm@...` plugin entry when accessible
- Scan `~/.codex/plugins/cache/` for `.codex-plugin/plugin.json` with `"name": "metaswarm"`
- If installed from a local marketplace, report cache version as `local`

**Claude Code**
- Check `.claude-plugin/plugin.json` exists in the plugin root
- Scan `~/.claude/plugins/cache/` for `.claude-plugin/plugin.json` with `"name": "metaswarm"`
- Report marketplace/plugin cache status when accessible

**Gemini**
- Check `gemini-extension.json` exists in the plugin root
- Report extension status when discoverable from the local Gemini config

### 4. Claude Command Shims

When checking a Claude project, check these files in `.claude/commands/`:

| Shim | Expected |
|---|---|
| `start-task.md` | Routes to `/metaswarm:start-task` |
| `prime.md` | Routes to `/metaswarm:prime` |
| `review-design.md` | Routes to `/metaswarm:review-design` |
| `self-reflect.md` | Routes to `/metaswarm:self-reflect` |
| `pr-shepherd.md` | Routes to `/metaswarm:pr-shepherd` |
| `brainstorm.md` | Routes to `/metaswarm:brainstorm` |

For each: report Present/Missing. If the file exists but does not contain "metaswarm" routing, flag as `present (non-metaswarm content)`.

When checking a Codex project, report `not applicable (Codex uses $skill-name invocation)` instead of treating missing `.claude/commands/` files as errors.

### 5. Legacy Embedded Plugin

- Check for `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
- If found: `DETECTED -- run $migrate`
- If found alongside the marketplace plugin, flag prominently as a conflict

### 6. BEADS Plugin

- Scan `~/.claude/plugins/cache/` and `~/.codex/plugins/cache/` for a directory containing `.claude-plugin/plugin.json` or `.codex-plugin/plugin.json` with `"name": "beads"`
- If found: `installed (standalone)` -- metaswarm defers priming to BEADS
- If not found: `not separately installed`

### 7. `bd` CLI

```bash
command -v bd && bd --version 2>/dev/null
```

- If found: report path and version
- If not found: `not installed -- knowledge priming and self-reflect require bd. Core orchestration works without it.`

### 8. `gtg` CLI

```bash
command -v gtg && gtg --help >/dev/null 2>&1
```

- If found: report path
- If not found: `not installed -- pr-shepherd will fall back to manual gh checks.`

### 9. External Tools

- Read `.metaswarm/external-tools.yaml` -- if absent: `not configured (optional)`
- If present, check each enabled adapter's availability:

```bash
command -v codex    # Codex CLI
command -v gemini   # Gemini CLI
```

Report per-tool: enabled (yes/no), status (available/not installed).

### 10. Coverage Thresholds

- Read `.coverage-thresholds.json` -- if absent: `not configured`
- If present, report threshold values (lines, branches, functions, statements) and enforcement command

### 11. Node.js

```bash
node --version 2>/dev/null
```

- If found: report version
- If not found: `not installed -- scripts/beads-*.ts require Node.js. Core orchestration works without it.`

---

## Output Format

```markdown
## Metaswarm Status Report

| Component | Status |
|---|---|
| Active platform | Codex |
| Plugin version | 0.11.0 |
| Project setup | Configured (distribution: plugin) |
| Platform install | Codex plugin installed and enabled |
| Command shims | Not applicable (Codex uses $skill-name) |
| Legacy embedded plugin | Not detected |
| BEADS plugin | Not separately installed |
| bd CLI | Available (v0.5.2) |
| gtg CLI | Available |
| External tools | Codex: available, Gemini: not installed |
| Coverage thresholds | 100% (all categories) |
| Node.js | Available (v22.4.0) |

### Issues Found
- None

### Recommendations
- None
```

When issues are found:

```markdown
### Issues Found
1. Legacy embedded plugin detected alongside marketplace plugin -- run `$migrate`
2. Codex plugin not installed from a marketplace -- install from `/plugins` after adding the marketplace

### Recommendations
1. Install `bd` CLI for knowledge priming and self-reflect
2. Install `gtg` for the fastest `$pr-shepherd` readiness checks
3. Configure external tools for cross-model review (`.metaswarm/external-tools.yaml`)
```

---

## Error Handling

This skill is diagnostic-only and never fails fatally. If any individual check errors, report the failure for that check (for example, `Plugin version: ERROR -- could not read plugin.json`) and continue with remaining checks.
