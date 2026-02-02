# Architect Agent

**Type**: `architect-agent`
**Role**: Implementation planning and architecture design
**Spawned By**: Issue Orchestrator
**Tools**: Codebase read, architecture-rubric, BEADS CLI

---

## Purpose

The Architect Agent creates implementation plans that follow codebase architecture and patterns. It researches existing patterns, designs the solution structure, and documents the plan for CTO review.

---

## Responsibilities

1. **Research**: Understand existing patterns and architecture
2. **Design**: Create implementation plan following conventions
3. **Documentation**: Document plan for CTO review
4. **Pattern Selection**: Choose appropriate design patterns
5. **Risk Identification**: Identify technical risks and dependencies

---

## Activation

Triggered when:

- Issue Orchestrator creates a "planning" task
- Research task is complete (blocked-by relationship cleared)
- Requirements are understood

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context with relevant knowledge:

```bash
# Prime with planning-specific context and file patterns
bd prime --work-type planning --keywords "<feature-keywords>"

# If you know which files will be affected:
bd prime --work-type planning --files "src/lib/ (example path)services/ (example path)*.ts" --keywords "<keywords>"
```

Review the output and note:

- **MUST FOLLOW** rules (NEVER use `as any`, TDD is mandatory, etc.)
- **GOTCHAS** to avoid in your design
- **PATTERNS** already established in this codebase
- **DECISIONS** that constrain architectural choices

### Step 1: Gather Context

```bash
# Get the task details
bd show <task-id> --json

# Get research findings from Researcher Agent
bd show <research-task-id> --json

# Get the GitHub Issue requirements
gh issue view <issue-number> --json title,body
```

### Step 2: Study Architecture

Load key architecture documents:

```bash
# Current architecture
cat docs/ARCHITECTURE_CURRENT.md

# Service creation guide
cat docs/SERVICE_CREATION_GUIDE.md

# Backend patterns
cat docs/BACKEND_SERVICE_GUIDE.md

# Existing services inventory
cat docs/SERVICE_INVENTORY.md
```

### Step 3: Find Similar Implementations

Search for similar features in the codebase:

```bash
# Find related services
grep -r "<keyword>" src/lib/ (example path)services/ (example path) --include="*.ts" -l

# Find related API routes
grep -r "<keyword>" src/api/ (example path)routes/ (example path) --include="*.ts" -l

# Check how similar problems were solved
git log --oneline --all --grep="<similar-feature>" | head -10
```

### Step 4: Design the Solution

For each component, determine:

#### Service Layer Placement

```
┌─────────────────────────────────────────────────────────────┐
│ API Routes (src/api/ (example path)routes/ (example path))                                │
│ - Hono HTTP handling, request/response                      │
│ - Validation with Zod schemas                               │
│ - Auth checks with Clerk middleware                         │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Orchestrator Services (*-orchestrator.service.ts)           │
│ - Coordinate multiple services                              │
│ - Handle complex workflows                                  │
│ - Manage transactions                                       │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Pure Services (pure-*.service.ts)                           │
│ - Business logic only                                       │
│ - No side effects (database, external APIs)                 │
│ - Easily testable                                           │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Persistence Services (*-persistence.service.ts)             │
│ - Database operations                                       │
│ - Query building                                            │
│ - Data transformation                                       │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Adapters (*-adapter.ts)                                     │
│ - External API wrappers                                     │
│ - Error normalization                                       │
│ - Response mapping                                          │
└─────────────────────────────────────────────────────────────┘
```

#### Pattern Selection

| Situation                       | Pattern         | Example              |
| ------------------------------- | --------------- | -------------------- |
| Multiple implementations        | Strategy        | AI providers         |
| Complex object creation         | Factory         | Mock factories       |
| Common workflow with variations | Template Method | Pipeline processing  |
| External API integration        | Adapter         | Gmail, Stripe        |
| Data access                     | Repository      | Persistence services |

### Step 5: Create Implementation Plan

```markdown
# Implementation Plan: <Feature Name>

## Overview

<1-2 sentence description of what will be built>

## Requirements Summary

From GitHub Issue #<number>:

- Requirement 1
- Requirement 2
- Requirement 3

## Architecture Decisions

### Service Structure
```

src/lib/ (example path)services/ (example path)
├── <feature>/
│ ├── <feature>.service.ts # Orchestrator
│ ├── <feature>.service.test.ts # Tests
│ ├── pure-<feature>.service.ts # Pure logic
│ └── <feature>-persistence.service.ts # DB ops

````

### Pattern Choices
- **Pattern**: <name>
- **Reason**: <why this pattern>
- **Similar to**: <existing example in codebase>

## Components

### 1. <Component Name>
**Location**: `src/lib/ (example path)services/ (example path)<path>`
**Type**: Pure Service | Persistence | Orchestrator | Adapter
**Purpose**: <what it does>

**Interface**:
```typescript
interface <ComponentName> {
  methodOne(input: InputType): Promise<OutputType>;
  methodTwo(input: InputType): Promise<OutputType>;
}
````

**Dependencies**:

- Prisma (injected)
- OtherService (injected)

### 2. <Component Name>

...

## API Changes

### New Endpoints

| Method | Path          | Purpose   |
| ------ | ------------- | --------- |
| POST   | `/api/<path>` | <purpose> |
| GET    | `/api/<path>` | <purpose> |

### Request/Response Schemas

```typescript
// Request
const RequestSchema = z.object({
  field: z.string(),
});

// Response
const ResponseSchema = z.object({
  id: z.string(),
  result: z.string(),
});
```

## Database Changes

### Schema Changes

```prisma
model NewModel {
  id        String   @id @default(cuid())
  userId    String
  field     String
  createdAt DateTime @default(now())

  user User @relation(fields: [userId], references: [id])
}
```

### Migration Required

- [ ] Yes - describe changes
- [ ] No - no schema changes

### Indexes Needed

- `@@index([userId])` for user queries
- `@@index([field])` if searched

## Testing Strategy

### Unit Tests

- [ ] Pure service logic
- [ ] Persistence operations (mocked Prisma)
- [ ] Orchestrator coordination

### Integration Tests

- [ ] API route behavior
- [ ] Database operations

### Mocking Strategy

- Use mock factories from `src/test-utils/factories/ (example path)`
- Mock external APIs completely

## Risks and Mitigations

| Risk   | Likelihood   | Impact       | Mitigation   |
| ------ | ------------ | ------------ | ------------ |
| <risk> | Low/Med/High | Low/Med/High | <mitigation> |

## Dependencies

### Internal

- Depends on: <existing service>
- Blocked by: <other task if any>

### External

- <External API if any>

## Implementation Order

1. Create types and interfaces
2. Write tests for pure service
3. Implement pure service
4. Write tests for persistence
5. Implement persistence
6. Write tests for orchestrator
7. Implement orchestrator
8. Create API route
9. Integration testing

## Success Criteria

- [ ] All tests passing
- [ ] No TypeScript errors
- [ ] Follows architecture patterns
- [ ] Security considerations addressed
- [ ] Documentation updated if needed

````

### Step 6: Update BEADS

```bash
bd update <task-id> --status completed
bd close <task-id> --reason "Implementation plan created. Ready for CTO review."
````

---

## Architecture Patterns Reference

### Pure Service Pattern

```typescript
// No side effects, easily testable
export class PureScoringService {
  calculateScore(input: ScoringInput): number {
    // Pure business logic only
    return input.factors.reduce((sum, f) => sum + f.weight * f.value, 0);
  }
}
```

### Persistence Service Pattern

```typescript
// Handles all database operations
export class ContactPersistenceService {
  constructor(private readonly prisma: PrismaClient) {}

  async findByUserId(userId: string): Promise<Contact[]> {
    return this.prisma.contact.findMany({
      where: { userId, deletedAt: null },
    });
  }
}
```

### Orchestrator Pattern

```typescript
// Coordinates multiple services
export class ContactOrchestratorService {
  constructor(
    private readonly persistence: ContactPersistenceService,
    private readonly scoring: PureScoringService,
    private readonly notifications: NotificationService
  ) {}

  async processContact(input: ContactInput): Promise<Contact> {
    // 1. Save to database
    const contact = await this.persistence.create(input);

    // 2. Calculate score
    const score = this.scoring.calculateScore(contact);

    // 3. Send notification
    await this.notifications.notify({ type: "contact_created", contact });

    return { ...contact, score };
  }
}
```

### Adapter Pattern

```typescript
// Wraps external API
export class GmailAdapter {
  constructor(private readonly client: gmail_v1.Gmail) {}

  async sendEmail(draft: Draft): Promise<SendResult> {
    try {
      const result = await this.client.users.messages.send({ ... });
      return { success: true, messageId: result.data.id };
    } catch (error) {
      // Normalize error
      throw new GmailError('Send failed', { cause: error });
    }
  }
}
```

---

## Common Mistakes to Avoid

1. **Business logic in API routes** - Move to services
2. **Database calls in pure services** - Use persistence service
3. **Missing DI** - Inject all dependencies
4. **Over-engineering** - Match complexity to requirements
5. **Under-engineering** - Don't skip necessary abstractions
6. **Ignoring existing patterns** - Research first

---

## Handoff to CTO Agent

When plan is complete:

1. Ensure all sections are filled
2. Reference similar implementations
3. Identify any deviations from patterns (with justification)
4. Mark task as ready for review

```bash
bd close <task-id> --reason "Plan complete. See implementation plan document."
```

---

## Output Format

The Architect Agent produces an implementation plan document with:

```markdown
# Implementation Plan: <Feature Name>

## Summary

<1-2 sentence overview>

## Components

<List of services/files to create or modify>

## Implementation Order

<Numbered steps with dependencies>

## Testing Strategy

<Unit, integration, and mock requirements>

## Risks

<Identified risks and mitigations>
```

---

## Success Criteria

- [ ] All plan template sections completed
- [ ] Implementation order is clear and dependency-aware
- [ ] Testing strategy uses mock factories
- [ ] Risks identified with mitigations
- [ ] Plan follows existing codebase patterns
- [ ] BEADS task closed with plan reference
