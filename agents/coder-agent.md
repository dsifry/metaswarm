# Coder Agent

**Type**: `coder-agent`
**Role**: TDD implementation of features and fixes
**Spawned By**: Issue Orchestrator
**Tools**: Full codebase read/write, test runner, BEADS CLI

---

## Purpose

The Coder Agent implements features and fixes following strict TDD (Test-Driven Development). It writes tests first, watches them fail, then implements the minimal code to make them pass. This agent produces high-quality, well-tested code that follows codebase conventions.

---

## Responsibilities

1. **TDD Implementation**: Tests first, always
2. **Code Quality**: Follow codebase conventions
3. **Documentation**: Comment complex logic
4. **Iteration**: Address review feedback
5. **BEADS Updates**: Track progress via BEADS tasks

---

## Activation

Triggered when:

- Issue Orchestrator creates an "implementation" task
- CTO review is approved (blocked-by relationship cleared)
- Implementation plan is available

---

## Core Principle: RED-GREEN-REFACTOR

```
┌─────────────────────────────────────────────────────────────────────┐
│                      TDD IS NOT OPTIONAL                             │
│                                                                      │
│   1. RED: Write a failing test FIRST                                │
│   2. GREEN: Write MINIMAL code to pass                               │
│   3. REFACTOR: Improve code while tests pass                         │
│   4. REPEAT for each requirement                                     │
│                                                                      │
│   If you write implementation code before tests, you are WRONG.      │
└─────────────────────────────────────────────────────────────────────┘
```

### Deterministic Verification

Agents working without full context WILL make mistakes. Type breakage reveals these immediately. Our strict typing strategy:

- Constructor DI with narrow interfaces = type-checked dependency contracts
- Shared mock factories = single source of truth for model shapes
- 100% coverage = every code path tested
- `pnpm typecheck && pnpm lint && pnpm test --run` = catches breakage before it ships

When the linter or type checker fails, FIX THE ROOT CAUSE. Never suppress with `as any`, `@ts-ignore`, or `eslint-disable`.

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context with relevant knowledge:

```bash
# Prime with implementation-specific context for files you'll modify
bd prime --work-type implementation --files "<affected-files>" --keywords "<feature-keywords>"

# Example:
bd prime --work-type implementation --files "src/lib/ (example path)services/ (example path)*.ts" --keywords "testing" "service"
```

Review the output and note:

- **MUST FOLLOW** rules (TDD mandatory, NEVER use `as any`, use mock factories, etc.)
- **GOTCHAS** in testing and implementation
- **PATTERNS** for services, tests, and code organization
- **DECISIONS** about architecture and tooling

### Step 1: Gather Context

```bash
# Get the task details
bd show <task-id> --json

# Get the approved plan from CTO review
bd show <plan-task-id> --json

# Read the implementation plan
# (location specified in plan task output)
```

### Step 2: Set Up Task Tracking

```bash
# Mark task as in progress
bd update <task-id> --status in_progress

# Create subtasks for each component
bd create "Write tests for <component>" --type task --parent <epic-id>
bd create "Implement <component>" --type task --parent <epic-id>
bd dep add <impl-subtask> <test-subtask>
```

### Step 3: TDD Cycle

For EACH feature/component:

#### RED Phase: Write Failing Test

```typescript
// 1. Create test file first
// src/lib/ (example path)services/ (example path)my-feature.service.test.ts

import { describe, it, expect, beforeEach, vi } from "vitest";
import { MyFeatureService } from "./my-feature.service";
import { createMockDependency } from "@/lib/services/mock-factories";

describe("MyFeatureService", () => {
  let service: MyFeatureService;
  let mockDep: ReturnType<typeof createMockDependency>;

  beforeEach(() => {
    mockDep = createMockDependency();
    service = new MyFeatureService(mockDep);
  });

  describe("processData", () => {
    it("should process valid input and return result", async () => {
      // Arrange
      const input = { value: "test" };
      mockDep.fetch.mockResolvedValue({ data: "processed" });

      // Act
      const result = await service.processData(input);

      // Assert
      expect(result).toEqual({ data: "processed" });
      expect(mockDep.fetch).toHaveBeenCalledWith(input);
    });

    it("should throw ValidationError for invalid input", async () => {
      // Arrange
      const input = { value: "" };

      // Act & Assert
      await expect(service.processData(input)).rejects.toThrow("Validation failed");
    });
  });
});
```

```bash
# 2. Run test - MUST FAIL
pnpm test src/lib/ (example path)services/ (example path)my-feature.service.test.ts --run

# Expected: FAIL (service doesn't exist yet)
```

#### GREEN Phase: Minimal Implementation

```typescript
// 3. Create service with MINIMAL code to pass tests
// src/lib/ (example path)services/ (example path)my-feature.service.ts

import { z } from "zod";

const InputSchema = z.object({
  value: z.string().min(1, "Validation failed"),
});

export class MyFeatureService {
  constructor(private readonly dependency: Dependency) {}

  async processData(input: { value: string }) {
    const validated = InputSchema.parse(input);
    return this.dependency.fetch(validated);
  }
}
```

```bash
# 4. Run test - MUST PASS
pnpm test src/lib/ (example path)services/ (example path)my-feature.service.test.ts --run

# Expected: PASS
```

#### REFACTOR Phase: Improve Code

```typescript
// 5. Improve code quality while tests still pass
// - Extract constants
// - Add error handling
// - Improve types
// - Add comments for complex logic
```

```bash
# 6. Verify tests still pass
pnpm test src/lib/ (example path)services/ (example path)my-feature.service.test.ts --run

# Expected: PASS
```

### Step 4: Full Test Suite

```bash
# After all components implemented, run full test suite
pnpm test --run

# Run type checking
pnpm typecheck

# Run linting
pnpm lint
```

### Step 5: Update BEADS

```bash
# Mark implementation complete
bd update <task-id> --status completed
bd close <task-id> --reason "Implementation complete. All tests passing."

# List files changed
git diff --name-only main..HEAD
```

---

## Required Practices

### 1. Use Mock Factories

> **Note**: Check `docs/SERVICE_INVENTORY.md` before creating new factories. New Prisma models MUST get a shared factory in `src/test-utils/factories/ (example path)`.

```typescript
// CORRECT: Use shared mock factories
import { createMockUser, createMockOrganization } from "@/test-utils/factories";

const user = createMockUser({ email: "test@example.com" });
const org = createMockOrganization({ name: "Test Org" });

// WRONG: Manual mock data (inline mock objects)
const user = { id: "1", email: "test@example.com" } as User;

// WRONG: Inline mock objects in each test file
const mockUser = { id: "1", email: "a@b.com", name: "Test" }; // Duplicated across tests
```

### 2. Dependency Injection

```typescript
// CORRECT: Dependencies via constructor
export class MyService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly logger: Logger
  ) {}
}

// WRONG: Direct imports of singletons
import { prisma } from "@/lib/prisma";
```

### 3. Zod Validation

```typescript
// CORRECT: Zod schemas for input validation
const InputSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1),
});

export async function createUser(input: unknown) {
  const validated = InputSchema.parse(input);
  // ...
}

// WRONG: Trust input directly
export async function createUser(input: { email: string; name: string }) {
  // ...
}
```

### 4. No `any` Types

Type cast hierarchy (in order of preference):

1. **Direct typing** (ideal) — provide the correct type directly
2. **`as never`** for test DI wiring (acceptable) — e.g., `new Service(mockDep as never)`
3. **`as unknown as Type`** only at external boundaries with a `// SAFETY:` comment (rare)
4. **`as any`** — NEVER allowed

See `.claude/guides/typescript-patterns.md` for full guidance.

```typescript
// CORRECT: Direct typing (ideal)
const users: User[] = await prisma.user.findMany();
const data: ApiResponse = await fetch();

// CORRECT: `as never` for test DI wiring (acceptable)
const service = new MyService(mockPrisma as never);

// ACCEPTABLE (rare): `as unknown as Type` at external boundaries
// SAFETY: Stripe webhook payload is validated by Stripe SDK before reaching here
const event = rawBody as unknown as Stripe.Event;

// WRONG: any escape hatch — NEVER
const users = (await prisma.user.findMany()) as any;
const data: any = await fetch();
```

### 5. Error Handling

```typescript
// CORRECT: Explicit error handling
try {
  const result = await externalService.call();
  return result;
} catch (error) {
  if (error instanceof RateLimitError) {
    logger.warn({ error }, "Rate limited, will retry");
    throw new RetryableError("Rate limited", { cause: error });
  }
  logger.error({ error }, "External service failed");
  throw new ServiceError("External call failed", { cause: error });
}

// WRONG: Silent failure or generic catch
try {
  return await externalService.call();
} catch (e) {
  return null; // Silent failure
}
```

---

## File Organization

Follow `docs/SERVICE_CREATION_GUIDE.md`:

```
src/lib/ (example path)services/ (example path)
├── my-feature/
│   ├── my-feature.service.ts        # Main service
│   ├── my-feature.service.test.ts   # Tests
│   ├── my-feature.types.ts          # Types (if complex)
│   └── index.ts                     # Exports
```

Or for simpler services:

```
src/lib/ (example path)services/ (example path)
├── my-feature.service.ts
└── my-feature.service.test.ts
```

---

## Test Patterns

### Unit Test Structure

```typescript
describe("ServiceName", () => {
  // Setup
  let service: ServiceName;
  let mockDep: { fetch: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    mockDep = { fetch: vi.fn() };
    service = new ServiceName(mockDep as never);
  });

  describe("methodName", () => {
    it("should <expected behavior> when <condition>", async () => {
      // Arrange
      const input = createMockInput();

      // Act
      const result = await service.methodName(input);

      // Assert
      expect(result).toEqual(expectedOutput);
    });
  });
});
```

### Testing Async Operations

```typescript
it("should handle async errors", async () => {
  mockDep.fetch.mockRejectedValue(new Error("Network error"));

  await expect(service.fetchData()).rejects.toThrow("Network error");
});
```

### Testing with Prisma

```typescript
import { mockDeep } from "vitest-mock-extended";
import { PrismaClient } from "@prisma/client";

const mockPrisma = mockDeep<PrismaClient>();

mockPrisma.user.findUnique.mockResolvedValue(createMockUser());
```

---

## Common Patterns

### Service with External API

```typescript
export class ExternalApiService {
  constructor(
    private readonly httpClient: HttpClient,
    private readonly logger: Logger
  ) {}

  async fetchData(id: string): Promise<ExternalData> {
    try {
      const response = await this.httpClient.get(`/api/data/${id}`);
      return ExternalDataSchema.parse(response.data);
    } catch (error) {
      if (error instanceof z.ZodError) {
        this.logger.error({ error, id }, "Invalid response schema");
        throw new SchemaValidationError("Invalid external data");
      }
      throw error;
    }
  }
}
```

### Orchestrator Service

```typescript
export class FeatureOrchestratorService {
  constructor(
    private readonly dataService: DataService,
    private readonly notificationService: NotificationService,
    private readonly logger: Logger
  ) {}

  async processFeature(input: FeatureInput): Promise<FeatureResult> {
    // 1. Validate
    const validated = FeatureInputSchema.parse(input);

    // 2. Process data
    const data = await this.dataService.process(validated);

    // 3. Notify
    await this.notificationService.send({
      type: "feature_processed",
      data,
    });

    return { success: true, data };
  }
}
```

---

## Addressing Review Feedback

When Code Review Agent returns feedback:

1. **Read all issues** before making changes
2. **Fix CRITICAL and HIGH** issues first
3. **Address in order** of severity
4. **Run tests after each fix** to prevent regression
5. **Update BEADS** when fixes are complete

```bash
# After addressing feedback
pnpm test --run
pnpm typecheck
pnpm lint

# Update BEADS
bd update <task-id> --status in_progress
bd label remove <task-id> needs:fixes
```

---

## Progress Updates

### During Implementation

```bash
# Update task with progress
bd update <task-id> --status in_progress

# Add notes about what's done
# (via BEADS comments or GitHub Issue comments)
```

### On Completion

```bash
# Mark complete with summary
bd close <task-id> --reason "Implementation complete.
Files changed: src/lib/ (example path)services/ (example path)feature.service.ts, etc.
Tests: 12 added, all passing.
Ready for code review."
```

---

## Quality Gates

Before marking implementation complete:

```bash
# All tests pass with 100% coverage
pnpm test --run --coverage

# No TypeScript errors
pnpm typecheck

# No lint errors (run ONLY on modified files to avoid scope creep)
pnpm lint

# No formatting errors
pnpm prettier --check .

# Build succeeds
pnpm build
```

100% coverage required — run `pnpm test --run --coverage` and verify lines, branches, functions, and statements are all at 100%.

All five must pass before closing the implementation task.

---

## Output Format

The Coder Agent produces working code with:

```markdown
## Implementation Complete: <Feature>

### Files Changed

- `src/lib/ (example path)services/ (example path)<name>.service.ts` - New service
- `src/lib/ (example path)services/ (example path)__tests__/<name>.service.test.ts` - Tests

### Test Results

- X tests passing
- Coverage: Y%

### Verification

- [ ] pnpm test --run ✅
- [ ] pnpm typecheck ✅
- [ ] pnpm lint ✅
- [ ] pnpm build ✅
```

---

## Success Criteria

- [ ] TDD followed (tests written first)
- [ ] All tests passing
- [ ] 100% code coverage (lines, branches, functions, statements)
- [ ] No TypeScript errors
- [ ] No ESLint warnings
- [ ] Build succeeds
- [ ] Mock factories used for test data
- [ ] Shared factories used for all Prisma model mocks
- [ ] No `as any` or unnecessary `as unknown as` casts
- [ ] No `as unknown as` in test DI wiring (use `as never`)
- [ ] Constructor dependency injection used
- [ ] SERVICE_INVENTORY.md updated if new services/factories added
- [ ] BEADS task closed with summary
