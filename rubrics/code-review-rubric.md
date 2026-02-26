# Code Review Rubric

**Used By**: Code Review Agent
**Purpose**: Evaluate code changes before PR creation
**Version**: 1.0

---

## Overview

This rubric ensures code changes meet quality standards before being submitted as a PR. The internal code review catches issues early, before external reviewers (humans, CodeRabbit) see the code.

---

## Severity Levels

| Level        | Description                                               | Action                                  |
| ------------ | --------------------------------------------------------- | --------------------------------------- |
| **CRITICAL** | Security vulnerability, data loss risk, breaks production | MUST fix before PR                      |
| **HIGH**     | Bug, incorrect behavior, significant performance issue    | MUST fix before PR                      |
| **MEDIUM**   | Code smell, maintainability issue, minor bug              | SHOULD fix, discuss if time-constrained |
| **LOW**      | Style, nitpick, suggestion                                | OPTIONAL, note for future               |

---

## Reference Standards

| Document                                | Purpose                                  |
| --------------------------------------- | ---------------------------------------- |
| `.claude/guides/coding-standards.md`    | Coding standards (source of truth)       |
| `CLAUDE.md`                             | Architecture, coding standards, key locs |
| `.claude/guides/testing-patterns.md`    | Testing philosophy, mock factories, TDD  |
| `.claude/test-quality-anti-patterns.md` | Common testing mistakes to avoid         |
| TypeScript strict mode                  | Follow conventions from tsconfig.json and ESLint configuration |
| `docs/SERVICE_INVENTORY.md`             | Service catalog & factory inventory      |
| `.claude/task-completion-checklist.md`  | Pre-completion validation steps          |

---

## Evaluation Categories

### 1. Correctness (CRITICAL/HIGH)

| Criterion                          | Severity | Check                         |
| ---------------------------------- | -------- | ----------------------------- |
| Code does what it's supposed to do | CRITICAL | Manual trace through logic    |
| Edge cases handled                 | HIGH     | Null, empty, boundary values  |
| Error paths correct                | HIGH     | Exceptions caught and handled |
| No logic errors                    | CRITICAL | Conditions, loops, recursion  |
| State mutations are intentional    | HIGH     | No accidental side effects    |

**Questions**:

- Does this actually solve the problem?
- What happens with unexpected input?
- Are there race conditions?

---

### 2. Security (CRITICAL)

| Criterion                 | Severity | Check                       |
| ------------------------- | -------- | --------------------------- |
| No SQL/NoSQL injection    | CRITICAL | Parameterized queries only  |
| No XSS vulnerabilities    | CRITICAL | Output encoding, CSP        |
| Auth/authz enforced       | CRITICAL | userId checks, role checks  |
| Input validation present  | CRITICAL | Zod schemas on all inputs   |
| No secrets in code        | CRITICAL | No hardcoded keys/passwords |
| No sensitive data in logs | HIGH     | PII, tokens, passwords      |

**OWASP Top 10 Checklist**:

- [ ] A01: Broken Access Control
- [ ] A02: Cryptographic Failures
- [ ] A03: Injection
- [ ] A07: Cross-Site Scripting (XSS)

---

### 3. TypeScript Quality (HIGH/MEDIUM)

| Criterion                                  | Severity | Check                                 |
| ------------------------------------------ | -------- | ------------------------------------- |
| No `any` types                             | HIGH     | Explicit types everywhere             |
| No `as` type assertions (except safe ones) | MEDIUM   | Prefer type guards                    |
| Proper null handling                       | HIGH     | Optional chaining, nullish coalescing |
| Types match runtime behavior               | HIGH     | No lying types                        |
| Generics used appropriately                | MEDIUM   | Not over-engineered                   |

**Type Cast Checklist**:

- [ ] No `as any` (NEVER allowed)
- [ ] No `as unknown as` in test DI wiring (use `as never` instead)
- [ ] No `as unknown as` in production code without explanatory comment
- [ ] All Prisma model mocks use shared factories from `src/test-utils/factories/`
- [ ] No local factory wrapper functions that add no logic over shared factories

**Patterns to Flag**:

```typescript
// BAD
const data = response as any;
const user = getUser() as User; // Unsafe assertion
const svc = new MyService(mock as unknown as ConstructorParameters<typeof MyService>[0]); // Verbose

// GOOD
const data: ApiResponse = await fetchData();
const user = isUser(result) ? result : null; // Type guard
const svc = new MyService(deps as never); // Test DI wiring
```

---

### 4. Testing (HIGH)

| Criterion                          | Severity | Check                                            |
| ---------------------------------- | -------- | ------------------------------------------------ |
| Tests exist for new code           | HIGH     | 100% coverage required                           |
| Tests verify results, not presence | HIGH     | No `toBeDefined()` or `toHaveBeenCalled()` alone |
| Mock factories used                | HIGH     | `@/test-utils/factories`, never inline mocks     |
| No real API calls                  | HIGH     | All external calls mocked via constructor DI     |
| Edge cases tested                  | HIGH     | Every branch, error handler, fallback            |
| TDD followed                       | MEDIUM   | Tests written before implementation              |

**Test Quality Checks** (see `.claude/guides/testing-patterns.md`):

- [ ] Every assertion tests a **result**, not just presence
- [ ] Mock factories from `src/test-utils/factories/` used (never inline objects)
- [ ] `beforeEach` recreates fresh mocks (no shared mutable state)
- [ ] No `.skip()`, `.todo()`, or commented-out assertions
- [ ] No `as any` in tests
- [ ] Test DI wiring uses `as never` (not `as unknown as ConstructorParameters<...>`)
- [ ] No `as unknown as` without comment explaining why
- [ ] No tests removed to fix type errors

---

### 5. Performance (MEDIUM/HIGH)

| Criterion                 | Severity | Check                            |
| ------------------------- | -------- | -------------------------------- |
| No N+1 queries            | HIGH     | Batch/include relations          |
| No unnecessary re-renders | MEDIUM   | React memo, useMemo, useCallback |
| Efficient algorithms      | MEDIUM   | Appropriate data structures      |
| No memory leaks           | HIGH     | Cleanup effects, listeners       |
| Bundle size considered    | MEDIUM   | No huge imports                  |

**Database Query Checks**:

```typescript
// BAD - N+1
const users = await prisma.user.findMany();
for (const user of users) {
  const posts = await prisma.post.findMany({ where: { userId: user.id } });
}

// GOOD - Single query
const users = await prisma.user.findMany({
  include: { posts: true },
});
```

---

### 6. Maintainability (MEDIUM)

| Criterion                  | Severity | Check                        |
| -------------------------- | -------- | ---------------------------- |
| Functions are focused      | MEDIUM   | Single responsibility        |
| Names are descriptive      | MEDIUM   | Clear intent                 |
| Complex logic is commented | MEDIUM   | Non-obvious code explained   |
| No dead code               | LOW      | Remove unused code           |
| Consistent style           | LOW      | Matches codebase conventions |
| DRY principle followed     | MEDIUM   | No copy-paste code           |

**Complexity Thresholds**:

- Function > 30 lines: Consider splitting
- Nesting > 3 levels: Refactor
- Parameters > 5: Use options object

---

### 7. API Design (MEDIUM)

| Criterion                  | Severity | Check                             |
| -------------------------- | -------- | --------------------------------- |
| RESTful conventions        | MEDIUM   | Proper HTTP methods, status codes |
| Request/response schemas   | HIGH     | Zod validation                    |
| Error responses consistent | MEDIUM   | Standard error format             |
| Versioning considered      | LOW      | Breaking changes managed          |

---

## Review Output Format

````markdown
## Code Review: <files or PR description>

### Verdict: APPROVED | CHANGES REQUIRED

### Summary

<Brief description of what the code does and overall quality assessment>

---

### Critical Issues (Must Fix)

#### 1. SQL Injection Vulnerability

**File**: `src/lib/services/user.service.ts:45`
**Severity**: CRITICAL
**Issue**: Raw user input in query string
**Fix**: Use parameterized query

```typescript
// Current (vulnerable)
const query = `SELECT * FROM users WHERE name = '${userName}'`;

// Fixed
const users = await prisma.user.findMany({ where: { name: userName } });
```
````

---

### High Priority Issues (Must Fix)

#### 2. Missing Error Handling

**File**: `src/api/routes/webhooks/clerk.ts:23`
**Severity**: HIGH
**Issue**: API call can throw but isn't caught
**Fix**: Add try-catch with proper error response

---

### Medium Priority Issues (Should Fix)

#### 3. N+1 Query Pattern

**File**: `src/lib/services/email.service.ts:78`
**Severity**: MEDIUM
**Issue**: Fetching threads in a loop
**Suggestion**: Use `include` or batch query

---

### Low Priority / Suggestions

1. Consider renaming `data` to `contactData` for clarity (line 34)
2. This function could be simplified using optional chaining

---

### Checklist

#### Correctness

- [x] Code does what it should
- [x] Edge cases handled
- [ ] Error paths correct - **Missing try-catch**

#### Security

- [ ] No injection vulnerabilities - **SQL injection found**
- [x] Auth enforced
- [x] Input validated

#### TypeScript

- [x] No `any` types
- [x] Proper null handling

#### Testing

- [x] Tests exist
- [x] Tests are meaningful
- [x] Mocks appropriate

#### Performance

- [ ] No N+1 queries - **Found in email service**

#### Maintainability

- [x] Functions focused
- [x] Names descriptive

````

---

## Approval Criteria

**APPROVED** when:
- Zero CRITICAL issues
- Zero HIGH issues (or explicitly accepted with justification)
- MEDIUM issues documented (fix now or create follow-up task)

**CHANGES REQUIRED** when:
- Any CRITICAL issues exist
- Any HIGH issues without justification

---

## Iteration Protocol

### First Review
- Full review against all categories
- Prioritized list of issues

### Subsequent Reviews
- Focus on previously identified issues
- Verify fixes don't introduce new issues
- Quick scan for regression

### Maximum Iterations: 3
After 3 rounds, escalate to human if issues persist.

---

## Common Patterns to Flag

### Anti-Patterns

```typescript
// 1. any usage
const data: any = await fetch(); // MEDIUM

// 2. Unsafe type assertion
const user = data as User; // MEDIUM - use type guard

// 3. Missing await
async function save() {
  prisma.user.create({}); // HIGH - missing await
}

// 4. Swallowing errors
try { ... } catch (e) { } // HIGH - silent failure

// 5. Direct console.log in production code
console.log(data); // LOW - use logger

// 6. Hardcoded values
const API_URL = "https://api.example.com"; // MEDIUM - use env
````

### Good Patterns to Encourage

```typescript
// 1. Proper error handling
try {
  await service.process();
} catch (error) {
  logger.error({ error }, "Processing failed");
  throw new ServiceError("Processing failed", { cause: error });
}

// 2. Type guards
function isUser(obj: unknown): obj is User {
  return typeof obj === "object" && obj !== null && "id" in obj;
}

// 3. Zod validation
const schema = z.object({ email: z.string().email() });
const validated = schema.parse(input);
```

---

## Knowledge Integration

Before reviewing, check knowledge base for:

- Known issues with the files being changed
- Patterns that have caused problems before
- Team-specific conventions
