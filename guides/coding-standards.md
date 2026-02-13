# Coding Standards

When reviewing or writing code in a metaswarm-managed project, enforce the following standards. Flag violations clearly and suggest specific fixes. Be direct and specific.

---

## TypeScript Discipline

Use TypeScript's type inference wherever it produces clear, unambiguous types. Do not annotate what the compiler already knows.

Explicitly annotate function signatures (parameters and return types), exported interfaces, and public API boundaries -- these are contracts, not suggestions.

Never use `any`. If you are reaching for `any`, you have not understood the data shape yet. Use `unknown` and narrow, or define the type properly.

Prefer `interface` for object shapes and `type` for unions, intersections, and computed types. Do not mix them randomly.

Use discriminated unions instead of optional fields and type guards instead of type assertions (`as`).

Generics should clarify, not obscure. If a generic makes the code harder to read, you have over-abstracted.

### Strict Mode

All projects must use `"strict": true` in `tsconfig.json`. This enables:

- `strictNullChecks` -- no implicit null/undefined
- `noImplicitAny` -- no inferred `any`
- `strictFunctionTypes` -- correct variance checking
- `strictPropertyInitialization` -- class fields must be initialized

### Type Cast Hierarchy

When you must cast (e.g., in tests), use the least permissive option:

1. **Type narrowing** (best) -- `if ('field' in obj)`, `typeof`, `instanceof`
2. **Generic constraints** -- `function process<T extends Base>(item: T)`
3. **`as Type`** -- only when narrowing is not possible and you can prove correctness
4. **`as never`** -- test DI wiring only
5. **`as unknown as Type`** -- rare, for genuinely incompatible types
6. **`as any`** -- NEVER. Not in production code. Not in tests. Not in config.

---

## SOLID Principles (Non-Negotiable)

**Single Responsibility**: Every module, class, and function does one thing. If you need the word "and" to describe what it does, split it.

**Open/Closed**: Extend behavior through composition, strategy, or decoration -- not by modifying existing code. New features should not require editing working code.

**Liskov Substitution**: Subtypes must be substitutable for their base types without breaking callers. If your subclass throws where the parent does not, or ignores parent behavior, it is broken.

**Interface Segregation**: Do not force consumers to depend on methods they do not use. Prefer small, focused interfaces over fat ones.

**Dependency Inversion**: Depend on abstractions (interfaces), not concretions. High-level modules should never import low-level implementation details directly.

---

## Dependency Injection

Inject dependencies through constructors or factory functions. Never instantiate dependencies inline (e.g., `new EmailService()` inside a handler).

Use DI for anything with side effects: database access, HTTP clients, email/notification services, file system, logging, time/clock.

This is not optional -- it is the foundation of testable code. If a module cannot be tested without hitting a real database or API, the architecture is wrong.

```typescript
// GOOD -- dependencies are explicit and injectable
class OrderService {
  constructor(
    private readonly db: DatabaseClient,
    private readonly paymentGateway: PaymentGateway,
    private readonly logger: Logger
  ) {}
}

// BAD -- hidden, untestable dependencies
class OrderService {
  private db = new DatabaseClient(process.env.DB_URL!);
  private gateway = new PaymentClient(process.env.PAYMENT_KEY!);
}
```

---

## Design Patterns (Use When They Solve Real Problems)

Apply patterns where they reduce complexity. Do not use them to show off.

**Strategy**: When behavior varies by context. Replace conditional chains (`if/else`, `switch`) that select between algorithms with injectable strategy objects.

**Factory / Abstract Factory**: When object creation logic is complex or context-dependent. Centralize creation, keep business logic clean.

**Observer / Event Emitter**: When components need to react to changes without tight coupling. Prefer typed event systems.

**Decorator**: When you need to layer behavior (logging, caching, retry, auth) without modifying the underlying implementation. Middleware stacks are decorators.

**Adapter**: When integrating external APIs or legacy code whose interface does not match yours. Wrap it, do not leak it.

**Command**: When operations need to be queued, undone, logged, or retried. Encapsulate the operation as an object.

**Repository**: Separate data access from business logic. Business logic never writes raw queries.

**Avoid Singleton** unless absolutely necessary (and it almost never is). If you think you need one, you probably need DI with a shared instance instead.

---

## Error Handling

Use typed, domain-specific error classes -- not raw `throw new Error("something broke")`.

```typescript
// GOOD -- typed errors with context
class OrderNotFoundError extends Error {
  constructor(public readonly orderId: string) {
    super(`Order not found: ${orderId}`);
    this.name = "OrderNotFoundError";
  }
}

// GOOD -- Result type for expected failures
type Result<T, E = Error> =
  | { success: true; data: T }
  | { success: false; error: E };
```

Rules:

- Never swallow errors silently. If you catch, either handle it meaningfully, transform it, or rethrow with context.
- Prefer result types (`{ success, data } | { success, error }`) for expected failure cases. Reserve exceptions for truly exceptional situations.
- Every error should be traceable. Include enough context (what operation, what input, what state) to debug without reproducing.
- Never `catch (e: any)`. Narrow your catch, type your errors.

---

## Naming Conventions

### Files

- Services: `order.service.ts`
- Utilities: `string-utils.ts`
- Types/interfaces: `order.types.ts`
- Constants: `config.ts` or `constants.ts`
- Tests: `order.service.test.ts` (in `__tests__/` directory)
- Use kebab-case for file names

### Classes, Interfaces, Types

- PascalCase: `OrderService`, `PaymentGateway`, `CreateOrderInput`
- Prefix interfaces with intent, not `I`: `PaymentGateway` not `IPaymentGateway`

### Functions and Variables

- camelCase: `calculateDiscount`, `orderTotal`
- Boolean: `isValid`, `hasPermission`, `shouldRetry` -- not `valid`, `check`, `flag`
- Descriptive: `normalizeAddresses()` not `processData()`
- No abbreviations unless universally understood (`id`, `url`, `config` are fine; `usr`, `mgr`, `proc` are not)

### Constants

- UPPER_SNAKE_CASE for true constants: `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT_MS`

---

## Import Organization

Organize imports in consistent groups, separated by blank lines:

```typescript
// 1. Node built-ins
import { readFile } from "node:fs/promises";
import path from "node:path";

// 2. External packages
import { z } from "zod";

// 3. Internal aliases (@/ or ~/)
import { OrderService } from "@/services/order.service";
import { Logger } from "@/lib/logger";

// 4. Relative imports
import { validateInput } from "./validators";
import type { OrderInput } from "./types";
```

Rules:

- Use `import type` for type-only imports
- No circular dependencies -- if A imports B and B imports A, extract shared code to C
- No barrel file abuse -- only use `index.ts` re-exports when the module boundary is intentional

---

## Function and Module Design

Functions should be short and do one thing. If it is over 30 lines, it probably does too much.

Max 3-4 parameters. If you need more, use an options/config object.

Prefer pure functions where possible. Side effects should be pushed to the edges of the system.

Never mutate function arguments. Return new values.

Avoid deeply nested code. Early returns, guard clauses, and extraction into helper functions keep nesting flat.

No magic numbers or strings. Use named constants or enums.

---

## Code Organization

Organize by feature/domain, not by technical layer. `users/user.service.ts` not `services/user-service.ts`.

Keep related code close together. If you always change two files in tandem, they should be in the same module.

Explicit exports. Do not use barrel files (`index.ts` re-exporting everything) unless the module boundary is intentional and well-defined.

Circular dependencies are architecture bugs. If A depends on B and B depends on A, extract the shared concept into C.

---

## Async and Concurrency

Never fire-and-forget a Promise. Every promise must be awaited, returned, or explicitly handled with `.catch()`.

Use `Promise.all` / `Promise.allSettled` for parallel work. Sequential `await` in a loop is usually a performance bug.

Handle race conditions explicitly. If two operations can interleave, the code must account for it.

Timeouts on all external calls. No unbounded waits.

---

## Security and Data Handling

Validate and sanitize all external input at the boundary. Never trust user input, API responses, or file contents.

Never log sensitive data (tokens, passwords, PII). Redact before logging.

Use parameterized queries. No string concatenation for SQL or any query language.

Secrets come from environment variables or a secrets manager, never from code or config files committed to the repo.

---

## Performance Awareness

Do not optimize prematurely, but do not be negligent either. N+1 queries, unbounded list operations, and missing indexes are bugs, not optimization tasks.

Pagination for any list endpoint. No unbounded queries.

Cache intentionally with clear invalidation strategies. Ad-hoc caching creates stale data bugs.

Be conscious of memory: do not load entire datasets into memory when you can stream or paginate.

---

## See Also

- [Testing Patterns Guide](./testing-patterns.md) -- Test quality and coverage standards
- [Build Validation Guide](./build-validation.md) -- Validation workflows
- [Git Workflow Guide](./git-workflow.md) -- Commit and PR conventions
