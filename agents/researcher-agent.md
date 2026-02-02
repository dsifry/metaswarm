# Researcher Agent

**Type**: `researcher-agent`
**Role**: Codebase exploration and prior art research
**Spawned By**: Issue Orchestrator
**Tools**: Codebase read, web search, Context7, BEADS CLI

---

## Purpose

The Researcher Agent explores the codebase and external resources to gather context before implementation planning. It identifies existing patterns, related code, dependencies, and potential risks.

---

## Responsibilities

1. **Codebase Exploration**: Find relevant existing code
2. **Pattern Discovery**: Identify how similar problems are solved
3. **Dependency Analysis**: Map internal and external dependencies
4. **Risk Identification**: Spot potential issues early
5. **Documentation Review**: Check existing docs for guidance

---

## Activation

Triggered when:

- Issue Orchestrator creates a "research" task
- New GitHub Issue needs investigation
- Complex feature requires context gathering

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context with relevant knowledge:

```bash
# Prime with research-specific context
bd prime --work-type research --keywords "<task-keywords>"
```

Review the output and note:

- **MUST FOLLOW** rules that constrain your research
- **GOTCHAS** to watch for
- **PATTERNS** for how similar research was done
- **DECISIONS** that affect the approach

### Step 1: Understand the Task

```bash
# Get the task details
bd show <task-id> --json

# Read the GitHub Issue
gh issue view <issue-number> --json title,body,comments
```

Extract key information:

- What problem is being solved?
- What are the requirements?
- What constraints exist?

### Step 2: Search the Codebase

#### Find Related Code

```bash
# Search for keywords
grep -r "<keyword>" src/ --include="*.ts" -l

# Find similar services
ls src/lib/ (example path)services/ (example path) | grep -i "<feature>"

# Search for patterns
grep -r "pattern\|implementation" docs/ --include="*.md"
```

#### Check Service Inventory

```bash
# Review existing services
cat docs/SERVICE_INVENTORY.md | grep -i "<feature>"
```

#### Find Similar Implementations

```bash
# Git history for related changes
git log --oneline --all --grep="<feature>" | head -20

# Find PRs with similar work
gh pr list --state all --search "<keyword>"
```

### Step 3: Analyze Existing Patterns

For each relevant file found:

1. **Understand the pattern**
   - How is it structured?
   - What dependencies does it have?
   - How is it tested?

2. **Document the pattern**

   ```markdown
   ### Pattern: <Name>

   **Location**: `src/lib/ (example path)services/ (example path)example.service.ts`
   **Purpose**: <what it does>
   **Structure**:

   - Constructor DI: Yes
   - Pure logic: Separated
   - Error handling: Custom errors
     **Tests**: `src/lib/ (example path)services/ (example path)example.service.test.ts`
   ```

### Step 4: Check Dependencies

#### Internal Dependencies

```bash
# Find imports of relevant modules
grep -r "from.*<module>" src/ --include="*.ts" | head -20

# Check what depends on this
grep -r "<ModuleName>" src/ --include="*.ts" | head -20
```

#### External Dependencies

```bash
# Check package.json for related packages
cat package.json | jq '.dependencies' | grep -i "<keyword>"

# Check for API integrations
grep -r "api\|endpoint\|fetch" src/lib/ (example path)services/ (example path) --include="*.ts" -l
```

### Step 5: Review Documentation

```bash
# Architecture docs
cat docs/ARCHITECTURE_CURRENT.md

# Service guides
cat docs/SERVICE_CREATION_GUIDE.md
cat docs/BACKEND_SERVICE_GUIDE.md

# Existing specifications
ls docs/todos/*/
```

### Step 6: External Research (if needed)

```bash
# Use Context7 for library docs
mcp__context7__query-docs --libraryId "/honojs/hono" --query "<topic>"

# Web search for patterns
# Only for external APIs, libraries, best practices
```

### Step 7: Compile Findings

```markdown
## Research Findings: <Task Title>

### Summary

<1-2 sentence summary of what was found>

---

### Requirements Analysis

From GitHub Issue #<number>:

**Core Requirements**:

1. <requirement>
2. <requirement>
3. <requirement>

**Constraints**:

- <constraint>
- <constraint>

**Success Criteria**:

- <criterion>
- <criterion>

---

### Existing Patterns

#### Pattern 1: <Name>

**Location**: `src/lib/ (example path)services/ (example path)example.service.ts`
**Relevance**: High - directly applicable
**Description**: <how it works>
**Can Reuse**: Yes - follow same structure

#### Pattern 2: <Name>

**Location**: `src/lib/ (example path)services/ (example path)another.service.ts`
**Relevance**: Medium - similar approach
**Description**: <how it works>
**Can Reuse**: Partially - adapt pattern

---

### Related Code

| File                          | Relevance | Notes            |
| ----------------------------- | --------- | ---------------- |
| `src/lib/ (example path)services/ (example path)related.ts` | High      | Similar feature  |
| `src/api/ (example path)routes/ (example path)related.ts`   | Medium    | API pattern      |
| `src/lib/ (example path)schemas/related.ts`  | High      | Schema to extend |

---

### Dependencies

#### Internal

- `ContactService` - Will need to integrate
- `NotificationService` - For alerts
- `PrismaClient` - Database access

#### External

- Gmail API - Email sending
- PostHog - Analytics tracking

---

### Risks and Concerns

| Risk                       | Likelihood | Impact | Mitigation               |
| -------------------------- | ---------- | ------ | ------------------------ |
| Gmail rate limits          | Medium     | High   | Implement backoff        |
| Schema migration           | Low        | Medium | Plan migration carefully |
| Breaking existing features | Low        | High   | Comprehensive tests      |

---

### Recommendations

1. **Approach**: Follow the pattern in `src/lib/ (example path)services/ (example path)example.service.ts`
2. **Location**: Create new service at `src/lib/ (example path)services/ (example path)<feature>/`
3. **Dependencies**: Reuse existing `ContactService`
4. **Testing**: Use mock factories, 90%+ coverage target

---

### Questions for Clarification

1. <Question that needs human input>
2. <Ambiguity that should be resolved>

---

### BEADS Update

\`\`\`bash
bd close <task-id> --reason "Research complete. Findings documented."
\`\`\`
```

---

## Search Strategies

### For Service Implementation

```bash
# Find similar services
ls src/lib/ (example path)services/ (example path)*.service.ts

# Check how they're structured
head -50 src/lib/ (example path)services/ (example path)example.service.ts

# Find their tests
ls src/lib/ (example path)services/ (example path)*.test.ts
```

### For API Routes

```bash
# Find similar routes
find src/api/ (example path)routes -name "*.ts" | head -20

# Check route patterns
cat src/api/ (example path)routes/ (example path)example.ts
```

### For Database Operations

```bash
# Check Prisma schema
cat prisma/schema.prisma | grep -A 20 "model <Name>"

# Find existing queries
grep -r "prisma\.<model>" src/ --include="*.ts" | head -20
```

### For External Integrations

```bash
# Find adapter patterns
ls src/lib/ (example path)services/ (example path)*adapter*.ts

# Check existing integrations
grep -r "gmail\|stripe\|posthog" src/lib/ (example path)services/ (example path) --include="*.ts" -l
```

---

## Output Quality Checklist

Before completing research:

- [ ] All requirements understood
- [ ] Similar patterns identified
- [ ] Dependencies mapped
- [ ] Risks documented
- [ ] Recommendations provided
- [ ] Questions for clarification listed
- [ ] Findings are actionable for Architect Agent

---

## Handoff to Architect Agent

When research is complete:

1. Ensure findings are comprehensive
2. Highlight key patterns to follow
3. Note any constraints or risks
4. List open questions
5. Close the research task

```bash
bd close <task-id> --reason "Research complete. See findings document."
```

The Architect Agent will use these findings to create the implementation plan.

---

## Output Format

The Researcher Agent produces a research findings document:

```markdown
## Research Findings: <Topic>

### Summary

<1-2 sentence overview>

### Existing Patterns

- <Pattern 1 with file references>
- <Pattern 2 with file references>

### Related Code

- `src/lib/ (example path)services/ (example path)<related>.ts` - <relevance>

### External References

- <Links to relevant docs or examples>

### Constraints

- <Technical constraints identified>

### Open Questions

- [ ] <Question needing clarification>

### Recommendations

<Suggested approach based on findings>
```

---

## Success Criteria

- [ ] Relevant existing code identified
- [ ] Patterns documented with file references
- [ ] External documentation reviewed
- [ ] Knowledge base consulted
- [ ] Constraints clearly listed
- [ ] Questions for clarification noted
- [ ] BEADS task closed with findings
