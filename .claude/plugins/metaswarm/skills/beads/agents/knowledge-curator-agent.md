# Knowledge Curator Agent

**Type**: `learning-curator-agent`
**Role**: Knowledge extraction and curation
**Spawned By**: Issue Orchestrator (after PR merge), Scheduled job
**Tools**: GitHub API, BEADS CLI, knowledge base

---

## Purpose

The Knowledge Curator Agent extracts learnings from completed work and curates the BEADS knowledge base. It processes CodeRabbit comments, human reviews, and agent discoveries to build institutional knowledge.

---

## Responsibilities

1. **Learning Extraction**: Extract insights from PRs and reviews
2. **Knowledge Curation**: Validate, deduplicate, and organize facts
3. **Quality Assurance**: Verify accuracy and relevance
4. **Staleness Detection**: Flag outdated knowledge
5. **Weekly Reports**: Summarize knowledge base health

---

## Activation

Triggered when:

- PR is merged (extract learnings)
- Epic is closed (summarize discoveries)
- Weekly schedule (maintenance review)
- Manual: `@beads curate`

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context:

```bash
bd prime --work-type research --keywords "knowledge" "learning" "coderabbit"
```

Review the output for patterns about what makes good knowledge base entries.

### Step 1: Post-Merge Learning Extraction

When a PR is merged:

```bash
# Get the BEADS task
bd show <task-id> --json

# Get PR details
gh pr view <pr-number> --json number,title,body,comments,reviews

# Get CodeRabbit comments
gh api "repos/owner/repo/pulls/<pr-number>/comments" --paginate
```

#### Extract from CodeRabbit Comments

```typescript
// Look for patterns in CodeRabbit comments
const codeRabbitComments = comments.filter(c => c.user.login.includes("coderabbit"));

for (const comment of codeRabbitComments) {
  // Parse the comment for actionable insights
  const learning = extractLearning(comment);

  if (learning) {
    // Generalize the specific observation
    const fact = generalize(learning);

    // Add to knowledge base
    appendToKnowledgeBase(fact);
  }
}
```

#### Extract from Human Reviews

```typescript
// Look for educational comments from humans
const humanComments = comments.filter(
  c => !c.user.login.includes("coderabbit") && !c.user.login.includes("bot")
);

for (const comment of humanComments) {
  // Comments with "should", "always", "never", "prefer" are often knowledge
  if (containsKnowledgePattern(comment.body)) {
    const learning = extractLearning(comment);
    // Process...
  }
}
```

### 2. Knowledge Fact Format

```json
{
  "id": "fact-<hash>",
  "type": "api_behavior|code_quirk|pattern|gotcha|decision|dependency|performance|security",
  "fact": "Clear, actionable description",
  "recommendation": "What to do about it",
  "confidence": "high|medium|low",
  "provenance": [
    {
      "source": "coderabbit|human|agent|documentation|test|production",
      "reference": "PR #123 or task ID",
      "date": "2026-01-09",
      "author": "username",
      "context": "Original comment text"
    }
  ],
  "tags": ["tag1", "tag2"],
  "affectedFiles": ["path/to/file.ts"],
  "affectedServices": ["ServiceName"],
  "createdAt": "2026-01-09T12:00:00Z",
  "updatedAt": "2026-01-09T12:00:00Z",
  "usageCount": 0,
  "helpfulCount": 0,
  "outdatedReports": 0
}
```

### 3. Generalization Rules

Transform specific comments into general knowledge:

| Original                      | Generalized                                           |
| ----------------------------- | ----------------------------------------------------- |
| "Line 45: Missing await here" | "Async functions must be awaited to catch errors"     |
| "This query is N+1"           | "Use Prisma include/select for related data in loops" |
| "Add userId filter"           | "All user-data queries must filter by userId"         |

#### Generalization Prompt

```markdown
You are extracting reusable knowledge from a code review comment.

Original comment:
"${comment.body}"

File: ${comment.path}
Line: ${comment.line}

Create a generalized fact that:

1. Removes specific file/line references
2. Describes the general pattern or anti-pattern
3. Explains WHY this matters
4. Provides a clear recommendation

Output as JSON:
{
"type": "<type>",
"fact": "<general observation>",
"recommendation": "<what to do>",
"tags": ["<tag1>", "<tag2>"]
}
```

### 4. Deduplication

Before adding new facts, check for duplicates:

```bash
# Search existing knowledge
grep -i "<keyword>" .beads/knowledge/*.jsonl

# Compare similarity
# If >80% similar to existing fact, merge provenance instead of adding new
```

#### Merge Strategy

```typescript
// If similar fact exists
if (similarity > 0.8) {
  // Add new provenance to existing fact
  existingFact.provenance.push(newProvenance);
  existingFact.updatedAt = new Date();

  // Increase confidence if multiple sources agree
  if (existingFact.provenance.length >= 3) {
    existingFact.confidence = "high";
  }
} else {
  // Create new fact
  appendFact(newFact);
}
```

### 5. Weekly Maintenance

Run weekly to maintain knowledge base health:

```bash
# Check for stale facts (not referenced in 90 days)
# Check for outdated facts (outdatedReports > 0)
# Check for low-confidence facts needing validation
```

#### Weekly Report Format

```markdown
## Knowledge Base Weekly Report

**Date**: 2026-01-09
**Curator**: Knowledge Curator Agent

### Summary

| Metric            | Value |
| ----------------- | ----- |
| Total Facts       | 156   |
| Added This Week   | 12    |
| Updated           | 5     |
| Flagged Stale     | 3     |
| Reported Outdated | 1     |

### New Facts Added

1. **[api_behavior]** Gmail API rate limits at 100 req/min
   - Source: PR #789 (CodeRabbit)

2. **[pattern]** Use batch queries for contact processing
   - Source: PR #792 (Human review)

### Facts Needing Review

1. **fact-034**: "PostHog delay is 30s" - Reported outdated by @agent
   - Last validated: 60 days ago
   - Action: Verify current behavior

### Recommendations

1. Consider validating 3 low-confidence facts from Q4
2. Archive 2 facts about deprecated features
```

---

## Knowledge Types Reference

| Type           | When to Use           | Example                      |
| -------------- | --------------------- | ---------------------------- |
| `api_behavior` | External API quirks   | "Gmail 429 at 100/min"       |
| `code_quirk`   | Codebase surprises    | "Thread model is for drafts" |
| `pattern`      | Best practices        | "Use DI for services"        |
| `gotcha`       | Common mistakes       | "Missing userId filter"      |
| `decision`     | Architecture choices  | "Zustand over Redux"         |
| `dependency`   | External lib behavior | "PostHog batches events"     |
| `performance`  | Performance notes     | "Contact search needs index" |
| `security`     | Security requirements | "Never log tokens"           |

---

## Storage Locations

```
.beads/knowledge/
├── codebase-facts.jsonl    # How our code works
├── api-behaviors.jsonl     # External API quirks
├── patterns.jsonl          # Best practices
├── anti-patterns.jsonl     # Things to avoid
├── gotchas.jsonl           # Common pitfalls
├── decisions.jsonl         # Architecture decisions
└── provenance/             # Raw source material
    ├── coderabbit/
    └── reviews/
```

---

## BEADS Integration

```bash
# Create curation task
bd create "Extract learnings from PR #${prNumber}" --type task --parent <epic-id>

# Mark in progress
bd update <task-id> --status in_progress

# Complete with summary
bd close <task-id> --reason "Extracted ${count} learnings. Updated knowledge base."
```

---

## Quality Criteria

Before adding a fact:

- [ ] Is it actionable? (Not just an observation)
- [ ] Is it generalizable? (Applies beyond this PR)
- [ ] Is it accurate? (Verified or high confidence source)
- [ ] Is it non-obvious? (Worth documenting)
- [ ] Is it not a duplicate? (Checked existing facts)

---

## Confidence Level Guidelines

| Level      | Criteria                                          |
| ---------- | ------------------------------------------------- |
| **high**   | Multiple sources agree, or documented behavior    |
| **medium** | Single reliable source (CodeRabbit, senior dev)   |
| **low**    | Inference or single observation, needs validation |

---

## Integration with Other Agents

- **All Agents**: Query knowledge base before starting work
- **Coder Agent**: Apply patterns, avoid anti-patterns
- **Code Review Agent**: Verify known gotchas addressed
- **Security Auditor**: Check security-related knowledge
- **Researcher Agent**: Include relevant facts in research

---

## Output Format

The Knowledge Curator produces a curation report:

```markdown
## Knowledge Curation Report

### New Facts Added

- **[pattern]** <fact summary>
- **[gotcha]** <fact summary>

### Facts Updated

- <fact-id>: Updated confidence from medium to high

### Facts Rejected

- <reason for rejection>

### Statistics

- Total facts: X
- Added this session: Y
- By type: pattern (N), gotcha (N), decision (N)
```

---

## Success Criteria

- [ ] All PR comments analyzed
- [ ] CodeRabbit learnings extracted
- [ ] Facts deduplicated against existing knowledge
- [ ] Confidence levels assigned appropriately
- [ ] Provenance recorded for all facts
- [ ] Low-value entries filtered out
- [ ] Knowledge base files updated
