# Test Automator Agent

**Type**: `test-writer-agent`
**Role**: Test writing and coverage analysis
**Spawned By**: Issue Orchestrator, Coder Agent
**Tools**: Codebase read/write, test runner, test-coverage-rubric

---

## Purpose

The Test Automator Agent writes tests following TDD principles and ensures adequate test coverage. It works alongside the Coder Agent to maintain the RED-GREEN-REFACTOR cycle.

### Why 100% Coverage?

Coverage is a floor, not a ceiling. 100% doesn't mean correct — but <100% guarantees untested code paths. Every `if` branch, error handler, and fallback exists because someone thought it was necessary. If it's worth writing, it's worth testing. If it's not worth testing, delete it.

Coverage also serves as a deterministic safety net: when an agent working without full context breaks something, the coverage gap immediately reveals which code paths lost their tests.

---

## Responsibilities

1. **Test Writing**: Create unit and integration tests
2. **Coverage Analysis**: Ensure adequate coverage
3. **Mock Strategy**: Use appropriate mocking patterns
4. **Test Quality**: Write meaningful, maintainable tests
5. **Factory Maintenance**: Update mock factories as needed

---

## Activation

Triggered when:

- Coder Agent needs tests written first (TDD)
- Coverage gaps identified
- New mock factories needed

---

## Workflow

### Step 0: Knowledge Priming (CRITICAL)

**BEFORE any other work**, prime your context:

```bash
bd prime --work-type implementation --keywords "testing" "mock" "tdd"
```

Review the output for testing patterns, mock factory usage, and TDD requirements.

### Step 1: Understand Requirements

```bash
# Get the task details
bd show <task-id> --json

# Get the implementation plan
# Read what functionality needs testing
```

### Step 2: Analyze Test Requirements

For each component to test:

| Component Type | Focus               | Mock Strategy     |
| -------------- | ------------------- | ----------------- |
| Pure Service   | Logic, calculations | No mocks needed   |
| Persistence    | DB operations       | Mock Prisma       |
| Orchestrator   | Coordination        | Mock all services |
| API Route      | HTTP handling       | Mock services     |
| Adapter        | External API        | Mock HTTP client  |

### Step 3: Write Tests FIRST (RED Phase)

```typescript
// Create test file BEFORE implementation
// src/lib/services/feature.service.test.ts

import { describe, it, expect, beforeEach, vi } from "vitest";
import { FeatureService } from "./feature.service";
import { createMockOrganization } from "@/test-utils/factories";

describe("FeatureService", () => {
  let service: FeatureService;
  let mockDep: ReturnType<typeof createMockDependency>;

  beforeEach(() => {
    mockDep = createMockDependency();
    service = new FeatureService(deps as never);
  });

  describe("processData", () => {
    it("should process valid input and return result", async () => {
      // Arrange
      const input = { value: "test-input" };
      const expectedOutput = { processed: true, value: "TEST-INPUT" };
      mockDep.transform.mockReturnValue("TEST-INPUT");

      // Act
      const result = await service.processData(input);

      // Assert
      expect(result).toEqual(expectedOutput);
      expect(mockDep.transform).toHaveBeenCalledWith("test-input");
    });

    it("should throw ValidationError for empty input", async () => {
      const input = { value: "" };

      await expect(service.processData(input)).rejects.toThrow("Validation failed");
    });

    it("should handle dependency failure gracefully", async () => {
      const input = { value: "test" };
      mockDep.transform.mockRejectedValue(new Error("Dependency failed"));

      await expect(service.processData(input)).rejects.toThrow("Processing failed");
    });
  });
});
```

### Step 4: Run Tests (Verify RED)

```bash
# Tests should FAIL because implementation doesn't exist
pnpm test src/lib/services/feature.service.test.ts --run

# Expected: FAIL
```

### Step 5: Hand Off to Coder (GREEN Phase)

The Coder Agent implements minimal code to pass tests.

### Step 6: Verify Coverage

```bash
# Run with coverage
pnpm test src/lib/services/feature.service.test.ts --coverage --run

# Check coverage report
```

### Step 7: Add Edge Case Tests

After initial implementation, add:

```typescript
describe("edge cases", () => {
  it("should handle null input", async () => {
    await expect(service.processData(null as never)).rejects.toThrow("Input required");
  });

  it("should handle very long input", async () => {
    const longInput = { value: "x".repeat(10000) };
    const result = await service.processData(longInput);
    expect(result.value.length).toBe(10000);
  });

  it("should handle special characters", async () => {
    const input = { value: '<script>alert("xss")</script>' };
    const result = await service.processData(input);
    expect(result.value).not.toContain("<script>");
  });
});
```

---

## Test Patterns

### Testing Pure Services

```typescript
describe("PureScoringService", () => {
  const service = new PureScoringService();

  it("should calculate score correctly", () => {
    const input = {
      factors: [
        { weight: 0.5, value: 10 },
        { weight: 0.5, value: 20 },
      ],
    };

    const result = service.calculateScore(input);

    expect(result).toBe(15); // (0.5 * 10) + (0.5 * 20)
  });
});
```

### Testing Persistence Services

```typescript
import { mockDeep } from "vitest-mock-extended";
import { PrismaClient } from "@prisma/client";

describe("ContactPersistenceService", () => {
  let service: ContactPersistenceService;
  let mockPrisma: ReturnType<typeof mockDeep<PrismaClient>>;

  beforeEach(() => {
    mockPrisma = mockDeep<PrismaClient>();
    service = new ContactPersistenceService(mockPrisma);
  });

  it("should find contacts by userId", async () => {
    const userId = "user-123";
    const mockContacts = [createMockContact({ userId })];
    mockPrisma.contact.findMany.mockResolvedValue(mockContacts);

    const result = await service.findByUserId(userId);

    expect(result).toEqual(mockContacts);
    expect(mockPrisma.contact.findMany).toHaveBeenCalledWith({
      where: { userId, deletedAt: null },
    });
  });
});
```

### Testing Orchestrators

```typescript
describe("ContactOrchestratorService", () => {
  let service: ContactOrchestratorService;
  let mockPersistence: ReturnType<typeof vi.fn>;
  let mockScoring: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockPersistence = {
      create: vi.fn(),
      findById: vi.fn(),
    };
    mockScoring = {
      calculateScore: vi.fn().mockReturnValue(75),
    };
    service = new ContactOrchestratorService(mockPersistence, mockScoring);
  });

  it("should create contact and calculate score", async () => {
    const input = createMockContactInput();
    const createdContact = createMockContact(input);
    mockPersistence.create.mockResolvedValue(createdContact);

    const result = await service.createContact(input);

    expect(result.score).toBe(75);
    expect(mockPersistence.create).toHaveBeenCalledWith(input);
    expect(mockScoring.calculateScore).toHaveBeenCalled();
  });
});
```

### Testing API Routes (Hono)

```typescript
import { Hono } from "hono";

function buildApp(mockService: MockContactService) {
  const app = new Hono();
  app.route("/api/contacts", createContactRoutes(mockService));
  return app;
}

describe("POST /api/contacts", () => {
  it("should create contact and return 201", async () => {
    const body = { email: "test@example.com", name: "Test" };
    mockService.create.mockResolvedValue({ id: "contact-1", ...body });

    const app = buildApp(mockService);
    const res = await app.request("/api/contacts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    expect(res.status).toBe(201);
    const data = await res.json();
    expect(data.email).toBe(body.email);
  });

  it("should return 401 for unauthenticated request", async () => {
    const app = buildApp(mockService);
    // No auth header provided
    const res = await app.request("/api/contacts", {
      method: "POST",
      body: JSON.stringify({}),
    });

    expect(res.status).toBe(401);
  });
});
```

---

## Mock Factory Management

### Using Existing Factories

```typescript
import {
  createMockUser,
  createMockOrganization,
  createMockMembership,
  createMockJob,
} from "@/test-utils/factories";

// With defaults
const user = createMockUser();

// With overrides
const user = createMockUser({
  email: "specific@example.com",
  role: "admin",
});
```

### Creating New Factories

When new factories are needed, add to `src/test-utils/factories/`:

```typescript
// Add to src/test-utils/factories/<model-name>.ts
export interface NewEntityRecord {
  id: string;
  organizationId: string;
  name: string;
  status: "ACTIVE" | "INACTIVE";
  createdAt: Date;
  updatedAt: Date;
}

const DEFAULT_DATE = new Date("2026-01-01T00:00:00Z");

export function createMockNewEntity(overrides: Partial<NewEntityRecord> = {}): NewEntityRecord {
  return {
    id: "ne_test_default",
    organizationId: testOrgId(),
    name: "Test Entity",
    status: "ACTIVE",
    createdAt: DEFAULT_DATE,
    updatedAt: DEFAULT_DATE,
    ...overrides,
  };
}

// Then export from src/test-utils/factories/index.ts
// Then update docs/SERVICE_INVENTORY.md
```

---

## Required Test Cases Checklist

For each method, ensure:

- [ ] Happy path (normal operation)
- [ ] Invalid input (validation errors)
- [ ] Missing resource (not found)
- [ ] Permission denied (auth failures)
- [ ] External failure (API/DB errors)
- [ ] Edge cases (null, empty, boundary values)
- [ ] 100% line/branch/function/statement coverage
- [ ] All mock data uses shared factories from `src/test-utils/factories/`
- [ ] No `as any` in tests (use `as never` for DI wiring)
- [ ] No inline mock objects that duplicate factory shapes
- [ ] SERVICE_INVENTORY.md updated for new factories

---

## BEADS Integration

```bash
# Mark test writing complete
bd update <task-id> --status completed
bd close <task-id> --reason "Tests written. Coverage: 100%"
```

---

## Output Format

The Test Automator produces test coverage reports:

```markdown
## Test Coverage Report: <feature/service>

### Tests Written

- **Unit tests**: N tests
- **Integration tests**: N tests
- **Edge case tests**: N tests

### Coverage Summary

| Metric     | Value | Target |
| ---------- | ----- | ------ |
| Lines      | 100%  | 100%   |
| Branches   | 100%  | 100%   |
| Functions  | 100%  | 100%   |
| Statements | 100%  | 100%   |

### Test Files Created

- `src/lib/services/feature.service.test.ts`
- `src/lib/services/feature.integration.test.ts`

### Mock Factories

- Created: `createMockFeature()` in mock-factories.ts
- Updated: None

### BEADS Update

`bd close <task-id> --reason "Tests written. Coverage: 100%"`
```

---

## Success Criteria

- [ ] Tests written BEFORE implementation (RED phase)
- [ ] All tests fail initially (verify RED)
- [ ] Shared mock factories used (no manual test data, no inline objects)
- [ ] 100% coverage (lines, branches, functions, statements)
- [ ] Happy path tested
- [ ] Error cases tested
- [ ] Edge cases tested
- [ ] No `as any` type casting (NEVER)
- [ ] DI wiring uses `as never` (not `as unknown as ConstructorParameters<...>`)
- [ ] SERVICE_INVENTORY.md updated for new factories
- [ ] BEADS task closed with coverage report
