# Testing Patterns Guide

This is the canonical guide for how and why we write tests in projects using the metaswarm framework. It covers philosophy, practical patterns, infrastructure, and anti-patterns. Every agent and developer writing tests should read this document.

---

## Table of Contents

- [Philosophy](#philosophy)
  - [Why 100% Coverage?](#why-100-coverage)
  - [Why TDD?](#why-tdd)
  - [Tests Must Test Results, Not Presence](#tests-must-test-results-not-presence)
  - [Never Lobotomize a Test](#never-lobotomize-a-test)
  - [Dependency Injection Is Non-Negotiable](#dependency-injection-is-non-negotiable)
  - [No Live Services in Tests](#no-live-services-in-tests)
- [Practical Patterns](#practical-patterns)
  - [Test File Location and Naming](#test-file-location-and-naming)
  - [Mock Infrastructure](#mock-infrastructure)
  - [Service Testing Pattern](#service-testing-pattern)
  - [Route/Handler Testing Pattern](#routehandler-testing-pattern)
  - [Testing Error Paths](#testing-error-paths)
  - [Testing Time-Dependent Code](#testing-time-dependent-code)
  - [Testing Compound Boolean Logic (MC/DC)](#testing-compound-boolean-logic-mcdc)
  - [Using and Creating Mock Factories](#using-and-creating-mock-factories)
- [Test Boundaries](#test-boundaries)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
  - [End-to-End Tests](#end-to-end-tests)
- [Type Safety in Tests](#type-safety-in-tests)
- [Coverage Configuration](#coverage-configuration)
- [Anti-Patterns](#anti-patterns)
- [CI Integration](#ci-integration)
- [Checklist: Before Submitting Tests](#checklist-before-submitting-tests)
- [Commands](#commands)

---

## Philosophy

### Why 100% Coverage?

We enforce 100% statement, branch, function, and line coverage. Thresholds are defined in `.coverage-thresholds.json` at the repo root (portable across projects). Orchestrator agents **must** read that file and run `npm run test:coverage` before marking any task complete. Here is why:

1. **Coverage is a floor, not a ceiling.** 100% coverage does not mean the code is correct -- but anything less than 100% _guarantees_ untested code paths. Untested code is code we do not understand.

2. **It forces design decisions.** If code is hard to test, it is usually hard to maintain. The coverage requirement pushes toward constructor DI, pure functions, and clean separation of concerns. Code that is easy to test is easy to reason about.

3. **It eliminates the "that line doesn't matter" excuse.** Every `if` branch, every error handler, every fallback exists because someone thought it was necessary. If it is worth writing, it is worth testing. If it is not worth testing, delete it.

4. **It catches regressions in edge cases.** The bugs that reach production live in the code paths nobody thought to test -- the error handler that silently swallows, the fallback that returns stale data, the branch that was "obvious."

Files that are genuinely untestable in isolation (generated code, server bootstrap, UI primitives) should be excluded in your test configuration. Everything else gets covered.

### Why TDD?

We require Test-Driven Development (Red-Green-Refactor) for all new services:

1. **RED**: Write a failing test that describes desired behavior.
2. **GREEN**: Write the minimum code to make it pass.
3. **REFACTOR**: Improve code while keeping tests green.

TDD is not bureaucracy -- it is a design tool. Writing the test first forces you to think about the interface before the implementation. It ensures every line of code exists to satisfy a requirement, not a guess.

### Tests Must Test Results, Not Presence

The most important rule: **every assertion must verify that the code produces the correct result, not merely that something exists or was called.**

```typescript
// BAD -- tests presence, not correctness
expect(result).toBeDefined();
expect(mockFn).toHaveBeenCalled();
expect(output.length).toBeGreaterThan(0);

// GOOD -- tests actual results
expect(result).toEqual({ id: "item_123", status: "active" });
expect(mockFn).toHaveBeenCalledWith({
  id: "item_123",
  amount: 500,
  type: "GRANT",
});
expect(output).toEqual(["item_abc", "item_def"]);
```

A test that passes when the code returns the wrong value is worse than no test at all -- it gives false confidence.

### Never Lobotomize a Test

When a test fails, the fix is **never** to weaken the assertion. Fix the code or fix the mock infrastructure. The short version:

- Never replace specific matchers with `expect.any()`
- Never comment out or remove assertions
- Never use `.skip()` or `.todo()` to silence failures
- Never reduce assertion specificity to make a test pass

If fixing one test breaks another, you are removing functionality, not fixing a bug. Stop and investigate the root cause.

### Dependency Injection Is Non-Negotiable

Every service takes its dependencies through the constructor. This is not just for testability -- it is for clarity. When you read a constructor, you see exactly what the service depends on. When you write a test, you control exactly what it receives.

```typescript
// Production
const service = new OrderService(database, paymentClient, logger);

// Test
const service = new OrderService(mockDatabase, mockPaymentClient, mockLogger);
```

No global imports, no module-level singletons, no hidden dependencies. If a service needs something, it asks for it in the constructor.

### No Live Services in Tests

Unit and integration tests must **never** make real API calls. All external services (databases, third-party APIs, message queues, caches) are mocked. This ensures tests are:

- **Fast**: Milliseconds, not seconds
- **Deterministic**: Same input produces same output, every time
- **Free**: No API costs from test runs
- **Independent**: No network, no credentials, no external state

---

## Practical Patterns

### Test File Location and Naming

```text
src/services/order.service.ts
src/services/__tests__/order.service.test.ts

src/api/routes/webhooks/payment.ts
src/api/routes/webhooks/__tests__/payment.test.ts

scripts/process-queue.ts
scripts/__tests__/process-queue.test.ts
```

Conventions:

- Test files use `.test.ts` (or `.test.tsx` for components) and live in a `__tests__/` directory adjacent to the code they test.
- Mirror the source file name: `foo.service.ts` -> `foo.service.test.ts`
- One test file per source file as a baseline; split into multiple files only when a single test file exceeds ~300 lines.

### Mock Infrastructure

#### Database Mock

```typescript
import { createMockDatabaseClient } from "@/test-utils/mocks/database";

const mockDb = createMockDatabaseClient();
// Provides mock stubs for all models/tables your ORM exposes
```

#### ID Factories

```typescript
import { testId } from "@/test-utils/factories/ids";

const orderId = testId("order", "abc"); // "order_test_abc"
const userId = testId("user", "def"); // "user_test_def"
```

#### Finding Existing Mocks

Before creating a new mock, check:

1. `src/test-utils/mocks/` -- Shared mock factories
2. `src/test-utils/factories/` -- Shared data factories
3. Existing `__tests__/` directories near the code you are testing -- look for local mock patterns
4. Your project's service inventory documentation

### Service Testing Pattern

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createMockDatabaseClient } from "@/test-utils/mocks/database";
import { OrderService } from "../order.service";

describe("OrderService", () => {
  let service: OrderService;
  let mockDb: ReturnType<typeof createMockDatabaseClient>;
  let mockPaymentClient: {
    charge: ReturnType<typeof vi.fn>;
    refund: ReturnType<typeof vi.fn>;
  };
  let mockLogger: {
    info: ReturnType<typeof vi.fn>;
    warn: ReturnType<typeof vi.fn>;
    error: ReturnType<typeof vi.fn>;
  };

  beforeEach(() => {
    mockDb = createMockDatabaseClient();
    mockPaymentClient = {
      charge: vi.fn().mockResolvedValue({}),
      refund: vi.fn().mockResolvedValue({}),
    };
    mockLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

    service = new OrderService({
      db: mockDb,
      paymentClient: mockPaymentClient,
      logger: mockLogger,
    } as never);
  });

  it("creates an order with correct total", async () => {
    mockDb.order.create.mockResolvedValue({
      id: "order_123",
      total: 2500,
      status: "PENDING",
    });

    const result = await service.createOrder({
      items: [{ productId: "prod_1", quantity: 2, unitPrice: 1250 }],
    });

    expect(result.total).toBe(2500);
    expect(result.status).toBe("PENDING");
    expect(mockDb.order.create).toHaveBeenCalledWith(
      expect.objectContaining({ total: 2500 })
    );
  });
});
```

Key points:

- `beforeEach` creates fresh mocks (no state leaks between tests)
- Constructor DI injects all dependencies
- Assertions verify **specific values**, not just "was called"

### Route/Handler Testing Pattern

```typescript
function buildApp(mockService: MockOrderService) {
  // Build your application/router with mock dependencies injected
  const app = createApp();
  app.route("/api/orders", createOrderRoutes(mockService));
  return app;
}

it("returns 201 on successful order creation", async () => {
  const app = buildApp(mockService);
  const res = await app.request("/api/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ items: [{ productId: "prod_1", quantity: 1 }] }),
  });

  expect(res.status).toBe(201);
  const body = await res.json();
  expect(body).toEqual(
    expect.objectContaining({ id: expect.any(String), status: "PENDING" })
  );
});
```

### Testing Error Paths

Every `if` branch and `catch` block needs a test. Error paths are where production bugs hide.

```typescript
it("throws NotFoundError when order does not exist", async () => {
  mockDb.order.findUnique.mockResolvedValue(null);

  await expect(service.getOrder("order_nonexistent")).rejects.toThrow(
    NotFoundError
  );
});

it("returns failed entry when single payment charge fails", async () => {
  mockPaymentClient.charge.mockRejectedValue(new Error("Gateway timeout"));

  const result = await service.processPayments(["order_123"]);

  expect(result.failed).toEqual([
    { orderId: "order_123", error: "Gateway timeout" },
  ]);
});
```

### Testing Time-Dependent Code

```typescript
import { vi, beforeEach, afterEach } from "vitest";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2025-01-15T00:00:00Z"));
});

afterEach(() => {
  vi.useRealTimers();
});

it("calculates days remaining correctly", async () => {
  mockDb.subscription.findUnique.mockResolvedValue({
    expiresAt: new Date("2025-01-25T00:00:00Z"),
    status: "ACTIVE",
  });

  const status = await service.getSubscriptionStatus("sub_123");

  expect(status.daysRemaining).toBe(10);
  expect(status.isActive).toBe(true);
});
```

### Testing Compound Boolean Logic (MC/DC)

When a function contains a compound boolean expression (2+ conditions joined by `&&` or `||`), standard branch coverage only requires two tests: one where the whole expression is true, one where it is false. This means individual conditions can be wrong, missing, or using the wrong operator without any test noticing.

**MC/DC (Modified Condition/Decision Coverage)** requires that each condition is proven to independently affect the outcome. For `n` conditions, you need `n + 1` tests minimum.

#### When to Apply MC/DC

Apply MC/DC to compound boolean expressions in:

- **Authorization/RBAC guards** -- conditions that gate access to operations
- **Eligibility/business rules** -- status checks, feature flags, tier checks
- **Validation logic** -- multi-field input validation
- **State machine transitions** -- compound conditions that determine next state

Do **not** apply MC/DC to simple single-condition checks. Branch coverage is sufficient for those.

#### The Pattern: Baseline + Toggle Each Condition

```typescript
describe("canPerformAction -- MC/DC", () => {
  // Baseline: all conditions true -> allowed
  it("allows when all conditions met", () => {
    const result = canPerformAction(
      createMockUser({ role: "ADMIN" }),
      createMockOrganization({ tier: "PRO", suspended: false })
    );
    expect(result).toBe(true);
  });

  // Toggle role alone -> denied
  it("denies when non-admin (other conditions true)", () => {
    const result = canPerformAction(
      createMockUser({ role: "MEMBER" }),
      createMockOrganization({ tier: "PRO", suspended: false })
    );
    expect(result).toBe(false);
  });

  // Toggle tier alone -> denied
  it("denies when free tier (other conditions true)", () => {
    const result = canPerformAction(
      createMockUser({ role: "ADMIN" }),
      createMockOrganization({ tier: "FREE", suspended: false })
    );
    expect(result).toBe(false);
  });

  // Toggle suspended alone -> denied
  it("denies when suspended (other conditions true)", () => {
    const result = canPerformAction(
      createMockUser({ role: "ADMIN" }),
      createMockOrganization({ tier: "PRO", suspended: true })
    );
    expect(result).toBe(false);
  });
});
```

What MC/DC catches that branch coverage misses:

- Wrong operator: `&&` where `||` was intended (or vice versa)
- Missing condition: a guard deleted but branch coverage still passes
- Dead condition: a condition that can never be false due to upstream logic
- Masked condition: short-circuit evaluation prevents a condition from being evaluated

### Using and Creating Mock Factories

Check your project's existing factory infrastructure before creating new ones. Do not duplicate factories that already exist.

```typescript
// GOOD -- import the shared factory
import { createMockOrganization } from "@/test-utils/factories";
const org = createMockOrganization({ tier: "ENTERPRISE" });

// BAD -- re-creating a factory that already exists
function makeOrg(overrides = {}) {
  return { id: "org_1", ...overrides };
}

// BAD -- inline object with incomplete fields
const org = { id: "org_1", name: "Test" }; // missing tier, status, dates, etc.
```

**When to create a local helper**: Only for test-specific _combinations_ of shared factories:

```typescript
// GOOD -- composes shared factory, does not replace it
function createTrialOrg() {
  return createMockOrganization({ tier: "FREE", trialEndsAt: futureDate });
}
```

**When to create a new shared factory**: When you add a new model/entity. Add the factory to `src/test-utils/factories/`, export it from `index.ts`, and update your service inventory.

Never construct mock objects inline with incomplete fields. Never duplicate a factory or record type that already exists.

---

## Test Boundaries

### Unit Tests

**Scope**: Single function, class, or module in isolation.

**Characteristics**:
- All dependencies are mocked
- No I/O (no database, no network, no filesystem)
- Run in milliseconds
- Deterministic -- no randomness, no real clocks

**When to use**: Business logic, utility functions, transformations, validations, domain objects.

```typescript
describe("calculateDiscount", () => {
  it("applies 10% discount for orders over $100", () => {
    expect(calculateDiscount(15000)).toBe(1500); // cents
  });

  it("applies no discount for orders under $100", () => {
    expect(calculateDiscount(9999)).toBe(0);
  });
});
```

### Integration Tests

**Scope**: Multiple components working together, typically at an I/O boundary.

**Characteristics**:
- Test real interactions between components
- May use test doubles for external services (test containers, in-memory databases)
- Run in seconds
- Test the contract between your code and external systems

**When to use**: Database queries, API routes, middleware chains, service compositions.

```typescript
describe("OrderAPI (integration)", () => {
  let app: Application;
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
    app = buildApp({ db: testDb.client });
  });

  afterAll(async () => {
    await testDb.cleanup();
  });

  it("creates order and persists to database", async () => {
    const res = await app.request("/api/orders", {
      method: "POST",
      body: JSON.stringify({ items: [{ productId: "prod_1", quantity: 1 }] }),
    });

    expect(res.status).toBe(201);

    const order = await testDb.client.order.findFirst();
    expect(order).not.toBeNull();
    expect(order!.status).toBe("PENDING");
  });
});
```

### End-to-End Tests

**Scope**: The entire system from external input to external output.

**Characteristics**:
- Test the system as a user would interact with it
- Use real (or near-real) infrastructure
- Run in seconds to minutes
- Validate complete user workflows

**When to use**: Critical user journeys, smoke tests, deployment verification.

**Guidelines**:
- Keep the E2E suite small and focused on high-value paths
- Use dedicated test environments
- Accept slightly lower reliability (network, timing) in exchange for higher confidence
- Never use E2E tests as a substitute for unit/integration tests

---

## Type Safety in Tests

### Mock DI Wiring: Use `as never`

When injecting mock deps into service constructors, use `as never`:

```typescript
// CORRECT -- concise, honest about the cast
const service = new MyService(deps as never);

// WRONG -- verbose, no additional safety over `as never`
const service = new MyService(
  mockDb as unknown as ConstructorParameters<typeof MyService>[0],
  mockClient as unknown as ConstructorParameters<typeof MyService>[1]
);

// WRONG -- disables all type checking
const service = new MyService(deps as any);
```

Why `as never` over `as unknown as X`: both bypass the type checker at the cast point. `as never` is honest -- it says "trust me, this is test wiring." The verbose form gives a false impression of safety while being equally unchecked.

### Other Type Patterns

- Use `ReturnType<typeof vi.fn>` for mock function types
- Use `Partial<Type>` for partial mock objects
- **Never** use `as any` in tests (or anywhere else)

---

## Coverage Configuration

Coverage thresholds are defined in `.coverage-thresholds.json` at the repository root:

```json
{
  "statements": 100,
  "branches": 100,
  "functions": 100,
  "lines": 100
}
```

### Configuring Your Test Runner

#### Vitest Example

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import thresholds from "./.coverage-thresholds.json";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      thresholds: {
        statements: thresholds.statements,
        branches: thresholds.branches,
        functions: thresholds.functions,
        lines: thresholds.lines,
      },
      exclude: [
        "**/*.config.*",
        "**/test-utils/**",
        "**/generated/**",
        "**/node_modules/**",
      ],
    },
  },
});
```

#### Jest Example

```javascript
// jest.config.js
const thresholds = require("./.coverage-thresholds.json");

module.exports = {
  coverageThreshold: {
    global: {
      statements: thresholds.statements,
      branches: thresholds.branches,
      functions: thresholds.functions,
      lines: thresholds.lines,
    },
  },
  collectCoverageFrom: [
    "src/**/*.{ts,tsx}",
    "!src/**/*.config.*",
    "!src/test-utils/**",
    "!src/generated/**",
  ],
};
```

### Exclusion Policy

Files excluded from coverage MUST be genuinely untestable in isolation:

- Generated code (ORM clients, GraphQL types, route manifests)
- Server bootstrap/entry points
- Configuration files
- UI primitive re-exports (barrel files)
- Type-only files (`.d.ts`)

Everything else gets covered. If you find yourself wanting to exclude a file, ask: "Can I refactor this to be testable?" The answer is almost always yes.

---

## Anti-Patterns

### 1. Over-Mocking

```typescript
// BAD -- mocks everything, tests nothing
it("processes order", async () => {
  mockService.processOrder.mockResolvedValue({ success: true });
  const result = await controller.handleOrder(mockRequest);
  expect(mockService.processOrder).toHaveBeenCalled();
});
```

This test verifies that your mock was called. It does not verify that your code works. If you deleted the implementation, this test would still pass.

### 2. Testing Implementation Details

```typescript
// BAD -- tests internal method call order
expect(service.validate).toHaveBeenCalledBefore(service.save);

// GOOD -- tests the observable result
expect(result.status).toBe("SAVED");
expect(result.validationErrors).toEqual([]);
```

Test the contract (inputs and outputs), not the internal execution path. Implementation details change during refactoring; contracts do not.

### 3. Shared Mutable State

```typescript
// BAD -- tests depend on order
let counter = 0;
it("first test", () => {
  counter++;
  expect(counter).toBe(1);
});
it("second test", () => {
  expect(counter).toBe(1); // Fails if first test doesn't run
});
```

Every test must set up its own world. Use `beforeEach` for fresh state. Never rely on test execution order.

### 4. Flaky Tests

Common causes:

- **Real timers**: Use `vi.useFakeTimers()` instead of `setTimeout`
- **Non-deterministic data**: Use factories with fixed seeds, not `Math.random()`
- **Race conditions**: Await all promises; do not fire-and-forget
- **External dependencies**: Mock all I/O; no real network calls in unit tests
- **Date sensitivity**: Mock `Date.now()` and `new Date()`

If a test fails intermittently, it is a bug. Fix it immediately -- do not re-run until it passes.

### 5. Assertion-Free Tests

```typescript
// BAD -- no assertion, test always passes
it("handles error", async () => {
  await service.handleError(new Error("boom"));
});
```

Every test MUST contain at least one assertion. A test without assertions is not a test.

### 6. Catch-and-Ignore in Tests

```typescript
// BAD -- swallows the error, test passes incorrectly
it("rejects invalid input", async () => {
  try {
    await service.process(invalidInput);
  } catch {
    // test passes
  }
});

// GOOD -- explicitly asserts the error
it("rejects invalid input", async () => {
  await expect(service.process(invalidInput)).rejects.toThrow(
    ValidationError
  );
});
```

### 7. Snapshot Abuse

Snapshots are for capturing complex output that is tedious to assert manually (rendered UI trees, serialized configs). They are NOT a substitute for specific assertions on business logic.

```typescript
// BAD -- snapshot on business logic
expect(calculateTotal(items)).toMatchSnapshot();

// GOOD -- specific assertion
expect(calculateTotal(items)).toBe(4250);
```

---

## CI Integration

### Coverage Gate in CI

Coverage must be enforced in CI as a required check. If coverage drops below threshold, the build fails.

```yaml
# Example GitHub Actions workflow
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - run: npm run test:coverage
      # Coverage thresholds enforced by test runner config
      # Build fails automatically if thresholds are not met
```

### Required CI Checks for PRs

A PR should not be mergeable until:

1. All tests pass
2. Coverage thresholds are met
3. Type checking passes
4. Linting passes with zero warnings

Configure branch protection rules to enforce these checks.

---

## Checklist: Before Submitting Tests

1. **Every assertion tests a result**, not just presence (`toBeDefined`, `toHaveBeenCalled` alone are insufficient)
2. **Every error path has a test** -- `catch` blocks, `if` guards, validation failures
3. **Every branch has a test** -- `if/else`, ternaries, `switch` cases, default values. For compound booleans: each condition independently tested via MC/DC
4. **Mock infrastructure is correct** -- mocks return the right shapes, not just `undefined`
5. **No weakened assertions** -- no `expect.any()` where specifics are possible
6. **No skipped tests** -- no `.skip()`, `.todo()`, or commented-out assertions
7. **Fresh state per test** -- `beforeEach` recreates mocks, no shared mutable state
8. **Tests run in isolation** -- order-independent, no reliance on prior test side effects
9. **Types are clean** -- no `as any`, proper use of `as never` for DI wiring
10. **Coverage is 100%** -- run `npm run test:coverage` and verify all thresholds

---

## Commands

Adapt these commands to your project's package manager and test runner:

| Command                            | Purpose                            |
| ---------------------------------- | ---------------------------------- |
| `npm test -- --run`                | Run all tests and exit             |
| `npm run test:coverage`            | Run with coverage enforcement      |
| `npx vitest run path/__tests__/`   | Run specific test directory        |
| `npx vitest run path/file.test.ts` | Run specific test file             |
| `npm test -- --watch`              | Watch mode during development      |

---

## See Also

- [Coding Standards Guide](./coding-standards.md) -- TypeScript discipline and design patterns
- [Build Validation Guide](./build-validation.md) -- Pre-commit validation and CI workflows
- [Git Workflow Guide](./git-workflow.md) -- Commit and PR conventions
