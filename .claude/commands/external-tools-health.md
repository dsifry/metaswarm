# External Tools Health Check

Check the status of external AI tools (Codex CLI, Gemini CLI) and their configuration.

## Usage

```text
/external-tools-health
```

## Steps

1. **Locate the adapters.** The plugin's `bin/` is on PATH; `PLUGIN_ROOT`/`CLAUDE_PLUGIN_ROOT` often isn't set:
   ```bash
   MS_BIN="$(dirname "$(command -v metaswarm-agents.sh 2>/dev/null || echo "${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-.}}/bin/metaswarm-agents.sh")")"
   AD="$MS_BIN/../skills/external-tools/adapters"
   ```

2. **Run each adapter's health check.** Each prints one JSON object with `"tool"`, `"status"` (`ready` or `unavailable`), `"version"` (`not_installed` if the CLI is missing), `"auth_valid"` and `"model"`:
   ```bash
   bash "$AD/codex.sh" health || echo '{"tool":"codex","status":"error"}'
   bash "$AD/gemini.sh" health || echo '{"tool":"gemini","status":"error"}'
   ```
   To see the model for a specific role, add `--role <role>`. Models come from `.metaswarm/models.yaml` (`roles.<role>.codex|gemini`).

3. **Check configuration.** Read `.metaswarm/external-tools.yaml` if it exists, and report which adapters are enabled or disabled. Report a legacy `adapters.<tool>.model` in `external-tools.yaml` as deprecated.

4. **Report status.** Show a summary table with one row per tool: `status`, `version`, `auth_valid`, `model`, and whether it's enabled in the config. For each tool that isn't `ready`, give the fix: install the CLI, log in (`codex login`, or set `OPENAI_API_KEY` / the Gemini credentials), or enable it in `.metaswarm/external-tools.yaml`.

## Related

- `skills/external-tools/SKILL.md` — the external tools delegation skill
- `.metaswarm/external-tools.yaml` — configuration file
- `.metaswarm/models.yaml` — per-role models (`roles.<role>.codex|gemini`)
- `bin/external-tools-verify.sh`: the metaswarm repo's own adapter self-test (for developing metaswarm; not a health check)
