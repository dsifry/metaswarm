# Architecture Rubric

**Used By**: Architect Agent
**Purpose**: Ensure implementation plans follow codebase architecture and patterns
**Version**: 1.0

---

## Overview

This rubric evaluates implementation plans for architectural fit. It ensures new code follows established patterns, uses correct service layers, and maintains codebase consistency.

---

## Key Reference Documents

| Document                                | Purpose                                 |
| --------------------------------------- | --------------------------------------- |
| `CLAUDE.md`                             | Architecture overview, coding standards |
| `.claude/guides/testing-patterns.md`    | Testing philosophy, mock factories, TDD |
| `.claude/test-quality-anti-patterns.md` | Common testing mistakes to avoid        |
| `docs/SERVICE_INVENTORY.md`             | Existing services & factory catalog     |
| `.claude/guides/typescript-patterns.md` | Type safety patterns                    |

---

## Evaluation Categories

### 1. Service Layer Placement

| Layer                     | Purpose                         | Location                             |
| ------------------------- | ------------------------------- | ------------------------------------ |
| **API Routes**            | HTTP handling only              | `src/api/routes/`                    |
| **Pure Services**         | Business logic, no side effects | `src/lib/services/pure-*.ts`         |
| **Persistence Services**  | Database operations             | `src/lib/services/*-persistence.ts`  |
| **Orchestrator Services** | Coordinate multiple services    | `src/lib/services/*-orchestrator.ts` |
| **Adapters**              | External API wrappers           | `src/lib/services/*-adapter.ts`      |

**Check**: Is the proposed code in the correct layer?

```typescript
// WRONG - Business logic in API route
export async function POST(req) {
  const data = await req.json();
  // Complex business logic here...
  await prisma.user.create({ ... });
}

// RIGHT - API route delegates to service
export async function POST(req) {
  const data = await req.json();
  const result = await userService.createUser(data);
  return c.json(result);
}
```

---

### 2. Dependency Injection

| Criterion                    | Pass                | Fail                         |
| ---------------------------- | ------------------- | ---------------------------- |
| Dependencies via constructor | All deps injected   | Direct imports of singletons |
| Interfaces for external deps | Abstract boundaries | Concrete implementations     |
| No hidden dependencies       | All deps visible    | Global state, implicit deps  |

**Check**: Are dependencies properly injected?

```typescript
// WRONG - Hidden dependency
export class UserService {
  async getUser(id: string) {
    const user = await prisma.user.findUnique({ where: { id } }); // prisma is global!
  }
}

// RIGHT - Injected dependency
export class UserService {
  constructor(private readonly prisma: PrismaClient) {}

  async getUser(id: string) {
    return this.prisma.user.findUnique({ where: { id } });
  }
}
```

---

### 3. Pattern Consistency

| Pattern             | When to Use                    | Example                          |
| ------------------- | ------------------------------ | -------------------------------- |
| **Strategy**        | Multiple algorithms            | AI providers, payment processors |
| **Template Method** | Common workflow, varying steps | Pipeline processing              |
| **Factory**         | Complex object creation        | Mock factories                   |
| **Repository**      | Data access abstraction        | Database operations              |
| **Adapter**         | External API integration       | Gmail, Stripe, PostHog           |

**Check**: Does the plan use patterns consistent with similar features?

---

### 4. Naming Conventions

| Type          | Convention                       | Example                          |
| ------------- | -------------------------------- | -------------------------------- |
| Pure services | `pure-*.service.ts`              | `pure-scoring.service.ts`        |
| Persistence   | `*-persistence.service.ts`       | `contact-persistence.service.ts` |
| Orchestrators | `*-orchestrator.service.ts`      | `draft-orchestrator.service.ts`  |
| Adapters      | `*-adapter.ts` or `*.adapter.ts` | `gmail-adapter.ts`               |
| Types         | `*.types.ts` or in `types.ts`    | `contact.types.ts`               |
| Schemas       | `src/lib/schemas/[domain]/`      | `src/lib/schemas/beads/`         |

**Check**: Do file and class names follow conventions?

---

### 5. Data Flow

| Principle        | Description                                    |
| ---------------- | ---------------------------------------------- |
| Unidirectional   | Data flows one direction through layers        |
| No circular deps | Services don't depend on each other circularly |
| Clear boundaries | Each layer has defined responsibilities        |

```
API Route → Orchestrator → Pure Service → Persistence → Database
                ↓
            Adapter → External API
```

**Check**: Does data flow correctly through layers?

---

### 6. Error Handling Strategy

| Layer         | Error Handling                       |
| ------------- | ------------------------------------ |
| API Routes    | Catch, log, return HTTP status       |
| Orchestrators | Coordinate error handling, may retry |
| Pure Services | Throw typed errors, no side effects  |
| Persistence   | Wrap database errors                 |
| Adapters      | Wrap external API errors             |

**Check**: Is error handling appropriate for each layer?

---

### 7. Database Considerations

| Check          | Requirement               |
| -------------- | ------------------------- |
| Schema changes | Migration required?       |
| Indexes        | New queries need indexes? |
| Relations      | Foreign keys correct?     |
| Soft deletes   | Using deletedAt pattern?  |
| Multi-tenancy  | userId on all user data?  |

**Check**: Are database operations properly planned?

---

## Review Checklist

```markdown
### Service Placement

- [ ] Code is in correct layer (API/Service/Persistence)
- [ ] No business logic in API routes
- [ ] No HTTP concerns in services

### Dependency Injection

- [ ] All dependencies via constructor
- [ ] No global singletons imported
- [ ] Testable with mock injection

### Pattern Consistency

- [ ] Uses same patterns as similar features
- [ ] No unnecessary new patterns
- [ ] Patterns match complexity level

### Naming Conventions

- [ ] File names follow conventions
- [ ] Class/function names are descriptive
- [ ] Matches existing codebase style

### Data Flow

- [ ] Clear layer separation
- [ ] No circular dependencies
- [ ] Appropriate abstraction levels

### Error Handling

- [ ] Errors handled at correct layer
- [ ] Typed errors used
- [ ] User-facing errors are clear

### Database

- [ ] Migrations planned if needed
- [ ] Indexes for new queries
- [ ] userId filter on user data
```

---

## Output Format

```markdown
## Architecture Review: <task-id>

### Verdict: APPROVED | NEEDS REVISION

### Summary

<Brief assessment of architectural fit>

---

### Service Placement

**Status**: Correct | Needs Adjustment

<Analysis of where code should live>

### Dependency Injection

**Status**: Correct | Needs Adjustment

<Analysis of DI usage>

### Pattern Consistency

**Status**: Consistent | Deviation Noted

<Analysis of patterns used>

### Naming Conventions

**Status**: Follows Conventions | Needs Adjustment

<Analysis of naming>

### Data Flow

**Status**: Correct | Needs Adjustment

<Analysis of data flow>

---

### Recommendations

1. <Specific recommendation>
2. <Specific recommendation>

### Reference Examples

Similar features to reference:

- `src/lib/services/trial.service.ts` - Service with constructor DI
- `src/lib/services/plan-limits.service.ts` - Business logic service
- `src/lib/services/invitation.service.ts` - CRUD service pattern
```

---

## Common Issues

### 1. Business Logic in API Routes

Move to service layer.

### 2. Persistence Logic in Pure Services

Pure services should be side-effect free; move DB calls to persistence service.

### 3. Missing Orchestrator

When multiple services need coordination, use an orchestrator.

### 4. Over-Engineering

Single-use abstractions, premature optimization, excessive indirection.

### 5. Under-Engineering

God classes, mixed responsibilities, no separation of concerns.
