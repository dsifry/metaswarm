# Contributing to metaswarm

Thank you for your interest in contributing to metaswarm.

## How to Contribute

### Reporting Issues

Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Your environment (Claude Code version, BEADS version, OS)

### Adding or Improving Agents

Agent definitions live in `agents/`. Each agent is a Markdown file with:

1. **Role** — What the agent specializes in
2. **Responsibilities** — What it does and produces
3. **Process** — Step-by-step workflow
4. **Output Format** — Expected deliverables
5. **Integration Points** — How it connects to other agents

When contributing a new agent:
- Place it in `agents/<name>-agent.md`
- Add it to the agent roster in `ORCHESTRATION.md`
- Document it in `USAGE.md`
- Keep it generic (no project-specific references)

### Adding Skills

Skills are orchestration behaviors in `skills/<name>/SKILL.md`. A skill coordinates multiple agents or provides a reusable workflow pattern.

### Improving Rubrics

Rubrics in `rubrics/` define quality standards for reviews. Contributions should:
- Be actionable (agents can follow them)
- Be measurable (clear pass/fail criteria)
- Not be project-specific

### Knowledge Base Templates

The `knowledge/` directory contains schema templates. Improvements to the schema, documentation, or example entries are welcome.

## Pull Request Process

1. Fork the repository
2. Create a branch (`feat/`, `fix/`, `docs/`)
3. Make your changes
4. Ensure all Markdown is well-formed
5. Submit a PR with a clear description

## Code of Conduct

Be respectful. Focus on the work. Assume good intent.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
