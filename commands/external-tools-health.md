# External Tools Health Check

Check the status of external AI tools (Codex CLI, Gemini CLI, OpenCode) and their configuration.

## Usage

```text
/external-tools-health
```

## Steps

1. **Check CLI availability**:
   ```bash
   command -v codex    >/dev/null 2>&1 && echo "codex: available"    || echo "codex: not found"
   command -v gemini   >/dev/null 2>&1 && echo "gemini: available"   || echo "gemini: not found"
   command -v opencode >/dev/null 2>&1 && echo "opencode: available" || echo "opencode: not found"
   ```

2. **Check configuration**: Read `.metaswarm/external-tools.yaml` if it exists. Report which adapters are enabled/disabled.

3. **Run per-adapter health checks** (each emits a JSON envelope with `status: ready|degraded|unavailable`):
   ```bash
   bash skills/external-tools/adapters/codex.sh    health
   bash skills/external-tools/adapters/gemini.sh   health
   bash skills/external-tools/adapters/opencode.sh health
   ```

4. **Report status**: Summary table showing each tool's install status, version, auth validity, configured model, and configuration.

## Related

- `skills/external-tools/SKILL.md` — the external tools delegation skill
- `skills/external-tools/adapters/{codex,gemini,opencode}.sh` — per-adapter scripts
- `.metaswarm/external-tools.yaml` — configuration file
