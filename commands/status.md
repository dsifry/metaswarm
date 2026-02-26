# Status

Show metaswarm diagnostic information.

## Usage

```text
/status
```

## Behavior

Invokes the `metaswarm:status` skill, which reports:

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

- `/metaswarm:setup` — configure metaswarm for a project
- `/metaswarm:migrate` — migrate from npm-installed metaswarm
