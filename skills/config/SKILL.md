---
name: config
description: Layered configuration resolution for tribunal.yaml
auto_activate: false
triggers:
  - tribunal.yaml
  - config resolution
  - resolve config
  - configuration
---

# Config Skill — tribunal.yaml Resolution

## Purpose

Resolves layered configuration from `tribunal.yaml` by deep-merging a `common` block with CLI tool-specific overrides. Every Tribunal feature (debate, agent selection, coverage enforcement) reads its settings through this resolution system.

## Config File Structure

`tribunal.yaml` has a `common` block and optional tool-specific blocks:

```yaml
common:
  timeout_seconds: 300
  sandbox: docker
  coverage:
    lines: 100
    branches: 100

claude:
  timeout_seconds: 600

gemini:
  coverage:
    branches: 90
```

## Resolution Rules

The effective config for a tool is computed as:

```
effective_config = deep_merge(common, tool_specific[tool_name])
```

| Type    | Behavior                          |
|---------|-----------------------------------|
| Scalar  | Tool-specific value wins          |
| Object  | Recursively merged (keys combine) |
| Array   | Tool-specific replaces entirely   |
| Missing | Common value used as-is           |

If a tool has no block in the YAML, the common config is returned unchanged.

## Usage

### CLI

```bash
node lib/resolve-config.js <path-to-tribunal.yaml> <tool-name>
```

Outputs the resolved config as JSON to stdout.

### Programmatic

```javascript
const fs = require('fs');
const { resolveConfig, deepMerge, parseYaml } = require('./lib/resolve-config');

const yamlText = fs.readFileSync('tribunal.yaml', 'utf8');
const config = resolveConfig(yamlText, 'claude');
// config is the merged result
```

## Config Sections

| Section           | Description                                      |
|-------------------|--------------------------------------------------|
| `timeout_seconds` | Max execution time per task                      |
| `sandbox`         | Sandbox mode: `docker`, `platform`, or `none`    |
| `coverage`        | Code coverage thresholds (lines, branches, etc.) |
| `enforcement`     | Coverage enforcement rules and commands           |
| `debate`          | Brainstorming debate settings (rounds, agents)   |
| `agent_selection` | Agent priority and selection strategy             |
| `escalation`      | Retry and escalation limits                      |
| `health_check`    | Per-task health check toggle                     |

## Template

The default template is at `templates/tribunal.yaml`. Copy it to your project root and customize as needed.
