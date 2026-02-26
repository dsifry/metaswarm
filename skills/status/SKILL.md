---
name: status
description: Diagnostic status report — shows metaswarm installation state, project setup, and potential issues
---

# Status Skill

Generate a diagnostic report of the metaswarm installation, project configuration, and potential issues. Useful for troubleshooting and verifying setup or migration.

---

## Checks

Run each check below and present results in a single formatted report.

### 1. Plugin Version

- Read `.claude-plugin/plugin.json` from the plugin root -- report the `version` field
- Fallback: read `package.json` at plugin root for `version`
- If neither found: `Plugin version: UNKNOWN`

### 2. Project Setup State

- Check if `.metaswarm/project-profile.json` exists in the working directory
- If present, report key fields: `distribution`, `metaswarm_version`, `language`, `framework`, `test_runner`
- If absent: `Project setup: NOT CONFIGURED -- run /metaswarm:setup`

### 3. Command Shims

Check these 6 files in `.claude/commands/`:

| Shim | Expected |
|---|---|
| `start-task.md` | Routes to `/metaswarm:start-task` |
| `prime.md` | Routes to `/metaswarm:prime` |
| `review-design.md` | Routes to `/metaswarm:review-design` |
| `self-reflect.md` | Routes to `/metaswarm:self-reflect` |
| `pr-shepherd.md` | Routes to `/metaswarm:pr-shepherd` |
| `brainstorm.md` | Routes to `/metaswarm:brainstorm` |

For each: report Present/Missing. If the file exists but does not contain "metaswarm" routing, flag as `present (non-metaswarm content)`.

### 4. Legacy Embedded Plugin

- Check for `.claude/plugins/metaswarm/.claude-plugin/plugin.json`
- If found: `DETECTED -- run /metaswarm:migrate`
- If found alongside the marketplace plugin, flag prominently as a conflict

### 5. BEADS Plugin

- Scan `~/.claude/plugins/cache/` for a directory containing `.claude-plugin/plugin.json` with `"name": "beads"`
- If found: `installed (standalone)` -- metaswarm defers priming to BEADS
- If not found: `not separately installed`

### 6. `bd` CLI

```bash
command -v bd && bd --version 2>/dev/null
```

- If found: report path and version
- If not found: `not installed -- knowledge priming and self-reflect require bd. Core orchestration works without it.`

### 7. External Tools

- Read `.metaswarm/external-tools.yaml` -- if absent: `not configured (optional)`
- If present, check each enabled adapter's availability:

```bash
command -v codex    # Codex CLI
command -v gemini   # Gemini CLI
```

Report per-tool: enabled (yes/no), status (available/not installed).

### 8. Coverage Thresholds

- Read `.coverage-thresholds.json` -- if absent: `not configured`
- If present, report threshold values (lines, branches, functions, statements) and enforcement command

### 9. Node.js

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
| Plugin version | 1.0.0 |
| Project setup | Configured (distribution: plugin) |
| Command shims | 6/6 present |
| Legacy embedded plugin | Not detected |
| BEADS plugin | Not separately installed |
| bd CLI | Available (v0.5.2) |
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
1. Legacy embedded plugin detected alongside marketplace plugin -- run `/metaswarm:migrate`
2. Command shim `start-task.md` missing -- run `/metaswarm:setup`

### Recommendations
1. Install `bd` CLI for knowledge priming and self-reflect
2. Configure external tools for cross-model review (`.metaswarm/external-tools.yaml`)
```

---

## Error Handling

This skill is diagnostic-only and never fails fatally. If any individual check errors, report the failure for that check (e.g., `Plugin version: ERROR -- could not read plugin.json`) and continue with remaining checks.
