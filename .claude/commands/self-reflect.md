---
description: Extract learnings from recent PR reviews, conversations, and session patterns to update the knowledge base
---

# BEADS Self-Reflect

You are performing a self-reflection for the BEADS agent swarm. Your job is to analyze PR review comments, conversation history, and session patterns to extract high-quality, reusable learnings.

**Philosophy**: Be judicious. Quality over quantity. Each learning should make future development measurably better.

## Phase A: PR Comment Analysis

### Step 1: Fetch PR Comments

```bash
GITHUB_TOKEN=$(gh auth token) npx tsx scripts/beads-fetch-pr-comments.ts --days 7
```

This outputs PR comments to `.beads/temp/pr-comments.json`.

### Step 2: Extract CodeRabbit's Structured Learnings

```bash
cat .beads/temp/pr-comments.json | jq -r '.comments[].body' | grep -A5 "^Learnt from:" | grep "^Learning:" | sed 's/^Learning: //' | sort -u
```

### Evaluate Each CodeRabbit Learning

**NOT all CodeRabbit learnings are equal.** Evaluate each one:

#### ACCEPT (High Value)

- **Applies to patterns**: `Applies to **/*.test.ts: ...` - Actionable file-scoped rules
- **NEVER/ALWAYS rules**: Clear, enforceable constraints
- **Security/Performance**: Critical quality gates
- **Gotchas with context**: Explains WHY something is problematic

#### REJECT or DEFER (Low Value)

- **PR-specific context**: "In PR #X, someone did Y" - Too specific unless the pattern generalizes
- **Personality observations**: "Developer provides detailed updates" - Not actionable
- **Process descriptions**: Meta, not code
- **Duplicate with slight rewording**: Check if we already have this fact
- **Obvious/trivial**: Things any developer should know

#### TRANSFORM (Medium Value -> Make High Value)

- **Before**: "In PR #593, developer explains optional AIProvider methods support backward compatibility"
- **After**: "Optional interface methods (generateWithTools?, generateObject?) follow Interface Segregation Principle - add runtime guards before use"

### Quality Filter Questions

For each potential learning, ask:

1. **Would this prevent a bug?** If yes, high priority.
2. **Would this save review cycles?** If yes, add it.
3. **Is this codebase-specific or universal?** Tag accordingly.
4. **Do we already have this?** Check for semantic duplicates.
5. **Can an agent act on this?** If not actionable, skip it.
6. **Would this confuse a naive agent?** If a future agent without context wouldn't benefit, skip it.

## Phase B: Conversation History Mining

Extract learnings from Claude Code session history stored in `~/.claude/projects/`.

### Step 1: Fetch Conversation History

```bash
npx tsx scripts/beads-fetch-conversation-history.ts --days 7
```

This parses session JSONL files and outputs learning triggers to `.beads/temp/conversation-history.json`.

### Step 2: Review Learning Triggers

The script automatically detects these trigger types:

| Trigger Type    | What It Captures                         | Example Patterns                           |
| --------------- | ---------------------------------------- | ------------------------------------------ |
| `correction`    | User correcting Claude's understanding   | "No, actually...", "That's wrong"          |
| `disagreement`  | User pushing back on suggestions         | "I disagree", "I'd prefer", "But what about" |
| `clarification` | User clarifying their intent             | "What I meant is...", "To clarify..."      |
| `discovery`     | Debugging insights and realizations      | "It turns out...", "The problem was..."    |
| `decision`      | Architectural/design choices made        | "Let's go with...", "We'll use..."         |
| `misconception` | Claude had wrong mental model            | Corrections after Claude's confident answer |

### Step 3: Analyze Triggers

```bash
cat .beads/temp/conversation-history.json | jq -r '.triggers[] | "\(.type): \(.userMessage | .[0:100])..."' | head -20
```

For each trigger, evaluate:

1. **Is this a pattern?** Same correction across multiple sessions → High value
2. **Is this codebase-specific?** Generic advice vs. this project's quirks
3. **Would future Claude benefit?** Add to knowledge base if yes
4. **Is there a root cause?** Why did Claude get it wrong? Document that

### High-Value Trigger Patterns

**ACCEPT these triggers:**
- User corrections about project architecture ("No, we use X not Y")
- Clarifications about domain terminology
- Corrections about API behavior or library quirks
- Design decisions with rationale ("We chose X because Y")

**REJECT these triggers:**
- Typo corrections or simple misunderstandings
- One-off preferences that won't generalize
- Corrections about information outside the codebase
- Clarifications that were just poor phrasing

### Current Context Analysis

Also analyze the current context window for implicit insights:

**Strategic patterns to look for:**

| Pattern                       | Usually indicates          | Value     |
| ----------------------------- | -------------------------- | --------- |
| "The problem was..."          | Debugging insight          | High      |
| "It turns out..."             | Discovery moment           | High      |
| "We decided to..."            | Architectural decision     | Very High |
| "The reason we..."            | Rationale worth preserving | Very High |
| "Unlike what you'd expect..." | Non-obvious behavior       | High      |
| "Never do X because..."       | Gotcha/pitfall             | High      |

**Filter**: Only capture insights that are codebase-specific, non-obvious, actionable, and durable.

## Phase C: Config Reflection (Optional)

Review Claude instructions and config for improvement opportunities:

- `.claude/commands/*` - Are commands still accurate?
- `CLAUDE.md` - Any outdated guidance?
- `.claude/settings.json` - Missing permissions or tools?

Present findings interactively: explain issue -> propose change -> get feedback -> implement.

## Step 3: Analyze Comment Patterns

Beyond CodeRabbit's structured learnings, look for **recurring patterns** in review comments:

```bash
cat .beads/temp/pr-comments.json | jq -r '.comments[] | select(.reviewerType == "coderabbit") | .body' | grep -i "nitpick\|issue\|suggestion\|consider\|should\|must\|avoid" | head -50
```

### Pattern Detection Checklist

Look for these patterns across multiple PRs:

1. **Repeated corrections**: Same issue flagged in multiple PRs -> Create a learning
2. **Architectural feedback**: Comments about service design, dependencies -> Capture the principle
3. **Testing feedback**: Mock patterns, test structure issues -> Document the pattern
4. **Type safety issues**: Repeated type casting problems -> Create a gotcha
5. **Performance concerns**: N+1 queries, memory issues -> Document with context

## Step 4: Present Candidates for Approval

Present learnings as a numbered list for user selection:

```markdown
## Candidate Learnings

1. **<Brief title>** - <One sentence description>

2. **<Brief title>** - <One sentence description>

3. **<Brief title>** - <One sentence description>

---

Which numbers do you want to capture? (all / 1,2,3 / none)
```

**After user selects**, classify each approved learning interactively:

```text
**Fact**: [extracted core insight]
**Type**: [pattern|gotcha|decision|api_behavior|security|performance]
**Applies to**: [file patterns or components]
**Confidence**: [high|medium|low]

Does this look right? (yes / edit)
```

### Conflict Resolution

When a new learning conflicts with an existing one:

| Situation                              | Action                                |
| -------------------------------------- | ------------------------------------- |
| New learning is more specific/accurate | New supersedes old                    |
| Both capture different valid aspects   | Keep both, add distinguishing context |
| New learning contradicts old           | Ask user which is correct             |
| Old learning is a subset of new        | Merge into comprehensive learning     |

**The key question**: Would having both learnings confuse a naive agent, or complement each other?

## Step 5: Categorize and Store

For each validated learning, add it to the appropriate knowledge base JSONL file following the schema in `.beads/knowledge/README.md`.

### Type Guide

| Type           | When to Use                  | Example                                                 |
| -------------- | ---------------------------- | ------------------------------------------------------- |
| `pattern`      | Reusable code patterns       | "Use mock factories for test data"                      |
| `gotcha`       | Common mistakes/pitfalls     | "Truthy check fails for explicit zero values"           |
| `security`     | Security-sensitive patterns  | "Always validate JWT server-side"                       |
| `performance`  | Performance implications     | "Use database indexes for frequent queries"             |
| `decision`     | Team/architectural decisions | "Prefer Strategy over Template Method for AI providers" |
| `api_behavior` | External API quirks          | "Prisma findMany returns [] not null"                   |
| `code_quirk`   | Codebase-specific oddities   | "Thread model is for drafts only, not email threads"    |
| `correction`   | User-corrected misconception | "Services dir is for business logic, not API handlers"  |

### Canonicalization Rules

1. **Remove PR references**: "In PR #593..." -> Remove, keep the principle
2. **Remove names when not relevant**: Keep only if it's a team decision
3. **Generalize file paths**: `src/lib/services/foo.ts` -> `src/lib/services/**/*.ts`
4. **Use imperative mood**: "Consider using..." -> "Use..."
5. **Include the WHY**: "Use X" -> "Use X because Y"
6. **Keep under 200 chars** when possible

### Confidence Assessment

| Level    | Criteria                                                                       |
| -------- | ------------------------------------------------------------------------------ |
| `high`   | Explicit rules (NEVER/ALWAYS), security issues, repeated pattern across 3+ PRs |
| `medium` | Single PR observation, team preference, architectural guidance                 |
| `low`    | Speculative, context-dependent, might not always apply                         |

## Step 6: Deduplication Check

Before adding, check for semantic duplicates in existing knowledge files.

## Step 7: Generate Report

```markdown
## Self-Reflection Results

### Summary

- PRs Analyzed: X
- Comments Reviewed: Y
- CodeRabbit Learnings Evaluated: Z
  - Accepted: A
  - Rejected (low value): B
  - Transformed: C
- Conversation History Triggers: T
  - Corrections: C1
  - Disagreements: C2
  - Discoveries: C3
  - Decisions: C4
- Total New Facts Added: N

### Learnings Added

#### High-Value Learnings

1. **[type]** <description>
   - Why accepted: <reason>

#### Rejected/Deferred

1. "<learning>" - <reason for rejection>

### Knowledge Base Statistics

- Total facts: N
- By type: pattern (X), decision (Y), gotcha (Z)...
- Quality: high (A), medium (B), low (C)
```

## Anti-Patterns to Avoid

1. **Quantity over quality**: Don't add 100 mediocre facts; add 10 great ones
2. **Blindly trusting CodeRabbit**: Evaluate each learning critically
3. **Ignoring duplicates**: Check before adding
4. **Missing the WHY**: Facts without reasoning are less useful
5. **Over-specificity**: "Use X in file Y" -> "Use X in files matching pattern"
6. **Under-specificity**: "Write good tests" -> Not actionable, skip it
