---
description: Load relevant knowledge base facts into context before starting work
---

# BEADS Prime

**CRITICAL**: Run this command at the START of any investigation, planning, or implementation work to load relevant knowledge into your context.

## When to Use

- Starting work on a GitHub Issue
- Beginning investigation/research
- Before writing a plan
- Before implementing changes
- When switching to a new area of the codebase

## How It Works

This command queries the BEADS knowledge base for facts relevant to your current context and injects them into the conversation, ensuring you:

1. Follow established patterns and rules
2. Avoid known gotchas and pitfalls
3. Make decisions aligned with architectural choices
4. Don't repeat mistakes that have been learned from

## Usage

### Quick Prime (Most Common)

For general context with automatic detection:

```bash
bd prime
```

### Prime for Specific Files

When working on specific files:

```bash
bd prime --files "src/lib/services/**/*.ts" "src/api/routes/**/*.ts"
```

### Prime for Keywords

When working on a specific topic:

```bash
bd prime --keywords "authentication" "jwt" "security"
```

### Prime for Work Type

When doing a specific type of work:

```bash
bd prime --work-type planning
bd prime --work-type implementation
bd prime --work-type review
bd prime --work-type debugging
```

### Combined

```bash
bd prime \
  --files "src/lib/services/ai-*.ts" \
  --keywords "ai" "provider" "openai" \
  --work-type implementation
```

## What Gets Loaded

### 1. MUST FOLLOW (Critical Rules)

Non-negotiable rules containing NEVER/ALWAYS/MUST:

- "NEVER use `as any` type casting"
- "ALWAYS use centralized AI config"
- Security-critical patterns

### 2. GOTCHAS (Common Pitfalls)

Known issues to avoid:

- "Truthy check fails for explicit zero values - use !== undefined"
- API behavior quirks

### 3. PATTERNS (Best Practices)

Established patterns in this codebase:

- "Use mock factories from test utilities"
- "Services should follow TDD (Red-Green-Refactor)"

### 4. DECISIONS (Architectural Choices)

Team/architectural decisions:

- "State management uses Zustand + TanStack Query"
- "AI providers implement Strategy Pattern"

### 5. API BEHAVIORS

External API quirks:

- "Prisma findMany returns [] not null"

## Auto-Priming

The BEADS system should auto-prime in these scenarios:

1. **Session Start**: When `.beads/` directory is detected
2. **File Touch**: When reading/editing files that match knowledge patterns
3. **Keyword Detection**: When task description matches known topics

## Integration Points

### In Planning Phase

Before writing a plan, run:

```bash
bd prime --work-type planning --keywords "<task-keywords>"
```

### In Implementation Phase

Before writing code, run:

```bash
bd prime --files "<files-to-touch>" --work-type implementation
```

### In Review Phase

Before reviewing code, run:

```bash
bd prime --work-type review --files "<files-changed>"
```

## Manual Knowledge Check

If you need to check for specific knowledge:

```bash
# Search for specific topic
cat .beads/knowledge/*.jsonl | jq -r 'select(.fact | test("authentication"; "i")) | .fact'

# Get all gotchas
cat .beads/knowledge/gotchas.jsonl | jq -r '.fact'

# Get all patterns
cat .beads/knowledge/patterns.jsonl | jq -r '.fact'
```

## Output Format

The prime command outputs formatted knowledge that looks like:

```markdown
# Relevant Knowledge Base Facts

_25 facts loaded for this context_

## MUST FOLLOW (Critical Rules)

These are non-negotiable rules:

- **[pattern]** NEVER use `as any` type casting...
- **[security]** Always validate JWT tokens server-side...

## GOTCHAS (Common Pitfalls)

Avoid these known issues:

- **[gotcha]** Truthy check fails for explicit zero values...

## PATTERNS (Best Practices)

- **[pattern]** Use mock factories from test utilities...
```

## Verification

After priming, you should be able to answer:

1. What are the critical rules I must follow?
2. What gotchas should I watch out for?
3. What patterns should I apply?
4. What architectural decisions constrain my options?
