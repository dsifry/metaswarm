# Test Coverage Rubric

**Used By**: Test Automator Agent
**Purpose**: Ensure adequate test coverage and test quality
**Version**: 1.0

---

## Overview

This rubric evaluates test quality beyond just coverage percentages. Good tests catch bugs, document behavior, and enable safe refactoring.

---

## Reference Standards

| Document                                | Purpose                                                        |
| --------------------------------------- | -------------------------------------------------------------- |
| `./guides/testing-patterns.md`    | Canonical test writing guide (philosophy, patterns, checklist) |
| `test-quality-anti-patterns.md (project-specific)` | Cascading failures, mock factory anti-patterns                 |
| `test-quality-anti-patterns.md (project-specific)` | Common testing mistakes to avoid                               |
| `docs/SERVICE_INVENTORY.md`             | Mock factory inventory & usage rules                           |
| `src/test-utils/factories/`             | Shared mock factories (single source of truth)                 |
| `src/test-utils/mocks/prisma.ts`        | Prisma mock client                                             |

---

## Coverage Targets

| Area     | Required |
| -------- | -------- |
| All code | 100%     |

This project enforces 100% statement, branch, function, and line coverage. See `./guides/testing-patterns.md` for the philosophy behind this requirement.

---

## Test Quality Criteria

### 1. Test Independence

| Criterion         | Pass                 | Fail                    |
| ----------------- | -------------------- | ----------------------- |
| No shared state   | Each test isolated   | Tests affect each other |
| Order independent | Can run in any order | Must run in sequence    |
| No external deps  | All mocked           | Calls real APIs/DB      |

### 2. Meaningful Assertions

| Criterion           | Pass                | Fail              |
| ------------------- | ------------------- | ----------------- |
| Tests behavior      | Validates outcomes  | Only checks calls |
| Specific assertions | Checks exact values | Uses toBeTruthy() |
| Error cases         | Tests failure paths | Only happy path   |

### 3. Mock Appropriateness

| Criterion        | Pass               | Fail                |
| ---------------- | ------------------ | ------------------- |
| Uses factories   | `createMockUser()` | Manual mock objects |
| Mocks boundaries | External APIs, DB  | Internal functions  |
| Realistic data   | Plausible values   | `"test"`, `"abc"`   |

### 4. Documentation Value

| Criterion          | Pass                     | Fail                   |
| ------------------ | ------------------------ | ---------------------- |
| Clear naming       | `should return X when Y` | `test1`, `works`       |
| Describes behavior | Readable specs           | Implementation details |
| Edge cases noted   | Documents boundaries     | Only obvious cases     |

---

## Test Patterns

### Good Test Structure

```typescript
describe("UserService", () => {
  let service: UserService;
  let mockPrisma: MockPrismaClient;

  beforeEach(() => {
    mockPrisma = createMockPrisma();
    service = new UserService(mockPrisma);
  });

  describe("createUser", () => {
    it("should create user with hashed password", async () => {
      // Arrange
      const input = { email: "test@example.com", password: "password123" };
      mockPrisma.user.create.mockResolvedValue(createMockUser(input));

      // Act
      const result = await service.createUser(input);

      // Assert
      expect(result.email).toBe(input.email);
      expect(result.passwordHash).not.toBe(input.password);
      expect(mockPrisma.user.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ email: input.email }),
      });
    });

    it("should throw ValidationError for invalid email", async () => {
      const input = { email: "invalid", password: "password123" };

      await expect(service.createUser(input)).rejects.toThrow(ValidationError);
    });
  });
});
```

### Anti-Patterns to Flag

```typescript
// BAD - Tests implementation, not behavior
it("should call prisma", async () => {
  await service.getUser("123");
  expect(mockPrisma.user.findUnique).toHaveBeenCalled();
  // Missing: what should the result be?
});

// BAD - No meaningful assertion
it("should work", async () => {
  const result = await service.process(data);
  expect(result).toBeTruthy(); // What is "truthy"?
});

// BAD - Manual mock data
const mockUser = { id: "1", email: "a@b.com" } as User;
// Should use: createMockUser({ email: "a@b.com" }) from @/test-utils/factories

// BAD - Real API call
it("should fetch data", async () => {
  const result = await service.fetchFromApi(); // Real HTTP!
});
```

---

## Test Categories

### Unit Tests

- Test single function/method
- All dependencies mocked
- Fast execution (<100ms)

### Integration Tests

- Test multiple components together
- Database may be real (test DB)
- External APIs mocked

### E2E Tests

- Full user flows
- Real browser/API calls
- Separate from CI (slow)

---

## Required Test Cases

### For Every Service Method

1. **Happy path** - Normal operation
2. **Invalid input** - Validation errors
3. **Not found** - Missing resources
4. **Permission denied** - Auth failures
5. **External failure** - API/DB errors

### For API Routes

1. **Valid request** - Success response
2. **Invalid body** - 400 Bad Request
3. **Unauthenticated** - 401 Unauthorized
4. **Forbidden** - 403 Forbidden
5. **Not found** - 404 Not Found
6. **Server error** - 500 handling

---

## Review Output Format

```markdown
## Test Review: <files>

### Coverage Summary

| File       | Statements | Branches | Functions | Lines |
| ---------- | ---------- | -------- | --------- | ----- |
| service.ts | 85%        | 72%      | 90%       | 84%   |

### Verdict: ADEQUATE | NEEDS IMPROVEMENT

---

### Missing Test Cases

#### 1. Error handling not tested

**File**: `service.test.ts`
**Method**: `processData()`
**Missing**: Test for when external API returns 500

#### 2. Edge case not covered

**File**: `service.test.ts`
**Method**: `calculateScore()`
**Missing**: Test for empty input array

---

### Test Quality Issues

#### 1. Weak assertion

**File**: `service.test.ts:45`
**Issue**: Uses `toBeTruthy()` instead of specific value
**Fix**: `expect(result.status).toBe('completed')`

#### 2. Missing mock factory

**File**: `service.test.ts:23`
**Issue**: Manual mock object creation
**Fix**: Use `createMockUser()` from mock-factories

---

### Recommendations

1. Add error path tests for `processData()`
2. Replace `toBeTruthy()` with specific assertions
3. Use mock factories consistently
```

---

## Mock Factory Requirements

All tests should use centralized mock factories:

```typescript
// From src/test-utils/factories/
import {
  createMockUser,
  createMockOrganization,
  createMockMembership,
} from "@/test-utils/factories";

// Usage
const user = createMockUser({ email: "specific@email.com" });
const org = createMockOrganization({ plan: "ENTERPRISE" });
```

### When to Create New Factories

Add to `src/test-utils/factories/` when:

1. Multiple tests need same mock structure
2. Object has complex default values
3. Type safety is important

```typescript
// Add new factory
export function createMockNewEntity(overrides: Partial<NewEntity> = {}): NewEntity {
  return createMock<NewEntity>({
    id: faker.string.uuid(),
    createdAt: new Date(),
    ...overrides,
  });
}
```
