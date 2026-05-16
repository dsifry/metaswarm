# Codex CLI Integration

metaswarm supports Codex as a first-class plugin.

## Install from Marketplace

```bash
codex plugin marketplace add dsifry/metaswarm-marketplace
codex
```

Then open `/plugins`, select the metaswarm marketplace, and install metaswarm.

## Local Development Install

From a metaswarm checkout:

```bash
codex plugin marketplace add /path/to/metaswarm
codex
```

Then open `/plugins`, select `metaswarm`, and install metaswarm.

The repo-local marketplace points at the public metaswarm repository root. For testing an unmerged branch, use a temporary marketplace whose plugin source URL is a `file://` URL or a pushed branch ref.

## Invoke Skills

Codex invokes metaswarm by skill name:

| Command | Purpose |
|---|---|
| `$setup` | Configure the current project |
| `$start` | Begin tracked work |
| `$status` | Diagnose installation and project state |
| `$pr-shepherd` | Monitor a PR through readiness |

Claude slash-command shims are not used in Codex.

## Hooks

Codex plugin hooks are optional and require the `plugin_hooks` feature. Core metaswarm workflows are designed to work without hook context.
