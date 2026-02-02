# BEADS Knowledge Base

This directory contains curated learnings from the agent swarm. Knowledge is extracted from:

- CodeRabbit PR reviews
- Human code reviews
- Agent discoveries during implementation
- Production incidents and debugging
- External documentation

## Directory Structure

```text
knowledge/
  README.md                    # This file
  codebase-facts.jsonl        # Facts about how the code works
  api-behaviors.jsonl         # External API quirks and behaviors
  patterns.jsonl              # Reusable patterns and best practices
  anti-patterns.jsonl         # Things to avoid
  gotchas.jsonl               # Common pitfalls and surprises
  decisions.jsonl             # Architectural decisions with context
  provenance/                 # Raw inputs for audit trail
    coderabbit/               # Raw CodeRabbit comments
    reviews/                  # Raw human review comments
```

## Knowledge Fact Format

Each JSONL file contains one fact per line:

```json
{
  "id": "fact-abc123",
  "type": "api_behavior|code_quirk|pattern|gotcha|decision|dependency|performance|security",
  "fact": "Clear description of the knowledge",
  "recommendation": "What to do about it",
  "confidence": "high|medium|low",
  "provenance": [
    {
      "source": "coderabbit|human|agent|documentation|test|production",
      "reference": "PR #123",
      "date": "2026-01-09"
    }
  ],
  "tags": ["api", "rate-limiting"],
  "affectedFiles": ["src/lib/services/example.ts"],
  "affectedServices": ["ExampleService"],
  "createdAt": "2026-01-09T12:00:00Z",
  "updatedAt": "2026-01-09T12:00:00Z",
  "usageCount": 0,
  "helpfulCount": 0,
  "outdatedReports": 0
}
```

## Knowledge Types

| Type           | Description                       | Example                                        |
| -------------- | --------------------------------- | ---------------------------------------------- |
| `api_behavior` | How external APIs actually behave | "API returns 429 after ~100 req/min"           |
| `code_quirk`   | Unexpected behavior in our code   | "Thread model stores drafts only, not threads" |
| `pattern`      | Reusable approach                 | "Use exponential backoff for rate limits"      |
| `gotcha`       | Common mistake                    | "Don't forget userId filter on queries"        |
| `decision`     | Why we chose X over Y             | "Chose Zustand over Redux for simplicity"      |
| `dependency`   | External dependency behavior      | "PostHog batches events, 30s delay"            |
| `performance`  | Performance characteristics       | "Contact search is O(n) - needs index"         |
| `security`     | Security-related knowledge        | "Never log OAuth tokens"                       |

## Confidence Levels

| Level    | Meaning                  | When to Use                   |
| -------- | ------------------------ | ----------------------------- |
| `high`   | Verified multiple times  | CodeRabbit + human confirmed  |
| `medium` | Observed once reliably   | Single source, clear evidence |
| `low`    | Suspected but unverified | Inference, needs confirmation |

## Usage by Agents

Agents query knowledge before starting work:

```bash
# Find relevant facts
grep -l "<keyword>" .beads/knowledge/*.jsonl

# Query specific file patterns
cat .beads/knowledge/api-behaviors.jsonl | jq 'select(.affectedServices | contains(["ExampleService"]))'
```

## Contributing Knowledge

Knowledge is added by:

1. **Knowledge Curator Agent** - Automated extraction from PRs
2. **Human developers** - Manual additions
3. **Other agents** - Discoveries during work

To add knowledge manually:

```bash
# Append to appropriate file
echo '{"id": "...", ...}' >> .beads/knowledge/gotchas.jsonl
```

## Maintenance

- **Weekly**: Knowledge Curator reviews for staleness
- **On PR merge**: Extract learnings from CodeRabbit
- **On incident**: Add post-mortem learnings
