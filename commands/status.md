# Status

Show tribunal diagnostic information.

## Usage

```text
/status
```

## Behavior

Invokes the `tribunal:status` skill, which reports:

- Installed plugin version
- Project setup state
- Command shims status
- Legacy install detection
- BEADS plugin status
- External tools configuration
- Coverage threshold configuration
- Node.js availability

Use this to troubleshoot installation or configuration issues.

## Related

- `/tribunal:setup` — configure tribunal for a project
- `/tribunal:migrate` — migrate from npm-installed tribunal
