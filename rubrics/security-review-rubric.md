# Security Review Rubric

**Used By**: Security Auditor Agent
**Purpose**: Identify security vulnerabilities before code reaches production
**Version**: 1.0

---

## Overview

This rubric ensures code changes don't introduce security vulnerabilities. Based on OWASP Top 10 and security best practices. Any CRITICAL finding blocks the PR.

---

## Severity Levels

| Level        | Description                                    | Action                           |
| ------------ | ---------------------------------------------- | -------------------------------- |
| **CRITICAL** | Exploitable vulnerability, data breach risk    | MUST fix immediately, blocks PR  |
| **HIGH**     | Security weakness, defense-in-depth gap        | MUST fix before merge            |
| **MEDIUM**   | Hardening opportunity, best practice violation | SHOULD fix, document if deferred |
| **LOW**      | Minor improvement, future consideration        | OPTIONAL, note for backlog       |

---

## OWASP Top 10 Checklist

### A01:2021 - Broken Access Control

| Check                 | Severity | What to Look For                                     |
| --------------------- | -------- | ---------------------------------------------------- |
| Missing auth checks   | CRITICAL | Routes without auth middleware                       |
| Missing org scoping   | CRITICAL | Database queries without `where: { organizationId }` |
| IDOR vulnerabilities  | CRITICAL | User-supplied IDs used without ownership check       |
| Privilege escalation  | CRITICAL | Role checks missing or bypassable                    |
| CORS misconfiguration | HIGH     | Overly permissive origins                            |

**Code Patterns to Flag**:

```typescript
// CRITICAL - No auth check
app.get("/api/users", async c => {
  const users = await prisma.user.findMany(); // No auth middleware!
});

// CRITICAL - No org scoping (data leak)
const accounts = await prisma.emailAccount.findMany({
  where: { email: searchEmail }, // Missing organizationId!
});

// CRITICAL - IDOR vulnerability
const account = await prisma.emailAccount.findUnique({
  where: { id: params.accountId }, // No org ownership verification!
});
```

---

### A02:2021 - Cryptographic Failures

| Check           | Severity | What to Look For                      |
| --------------- | -------- | ------------------------------------- |
| Secrets in code | CRITICAL | API keys, passwords, tokens hardcoded |
| Secrets in logs | CRITICAL | Logging sensitive data                |
| Weak encryption | HIGH     | MD5, SHA1 for passwords               |
| Missing HTTPS   | HIGH     | HTTP URLs for APIs                    |
| Insecure random | MEDIUM   | Math.random() for security            |

**Code Patterns to Flag**:

```typescript
// CRITICAL - Hardcoded secret
const API_KEY = "sk_live_abc123...";

// CRITICAL - Secret in logs
logger.info({ apiKey, token }, "Making request");

// HIGH - Weak hashing
const hash = crypto.createHash("md5").update(password);
```

---

### A03:2021 - Injection

| Check             | Severity | What to Look For                |
| ----------------- | -------- | ------------------------------- |
| SQL injection     | CRITICAL | String concatenation in queries |
| NoSQL injection   | CRITICAL | Unvalidated objects in queries  |
| Command injection | CRITICAL | User input in shell commands    |
| LDAP injection    | CRITICAL | User input in LDAP queries      |
| XPath injection   | HIGH     | User input in XPath             |

**Code Patterns to Flag**:

```typescript
// CRITICAL - SQL injection
const query = `SELECT * FROM users WHERE name = '${userName}'`;

// CRITICAL - Command injection
exec(`convert ${userFilename} output.png`);

// CRITICAL - NoSQL injection
prisma.user.findMany({ where: JSON.parse(userInput) });
```

---

### A04:2021 - Insecure Design

| Check                             | Severity | What to Look For                |
| --------------------------------- | -------- | ------------------------------- |
| Missing rate limiting             | HIGH     | APIs without throttling         |
| No CAPTCHA on sensitive ops       | MEDIUM   | Registration, password reset    |
| Excessive data exposure           | HIGH     | Returning more data than needed |
| Missing business logic validation | HIGH     | Assuming client-side validation |

---

### A05:2021 - Security Misconfiguration

| Check                    | Severity | What to Look For             |
| ------------------------ | -------- | ---------------------------- |
| Debug mode in prod       | HIGH     | Development settings exposed |
| Default credentials      | CRITICAL | Unchanged passwords          |
| Unnecessary features     | MEDIUM   | Unused endpoints, features   |
| Missing security headers | MEDIUM   | CSP, X-Frame-Options, etc.   |
| Error details exposed    | HIGH     | Stack traces to users        |

---

### A06:2021 - Vulnerable Components

| Check                  | Severity      | What to Look For                |
| ---------------------- | ------------- | ------------------------------- |
| Known CVEs             | CRITICAL/HIGH | Outdated dependencies with CVEs |
| Unmaintained packages  | MEDIUM        | No updates in 2+ years          |
| Excessive dependencies | LOW           | Large attack surface            |

**Check Command**:

```bash
pnpm audit
```

---

### A07:2021 - Auth/Session Failures

| Check                    | Severity | What to Look For               |
| ------------------------ | -------- | ------------------------------ |
| Weak password policy     | MEDIUM   | No complexity requirements     |
| Session fixation         | HIGH     | Session ID not rotated on auth |
| Missing MFA              | MEDIUM   | Sensitive ops without 2FA      |
| Insecure session storage | HIGH     | Tokens in localStorage         |
| No session timeout       | MEDIUM   | Long-lived sessions            |

---

### A08:2021 - Software/Data Integrity

| Check                    | Severity | What to Look For                     |
| ------------------------ | -------- | ------------------------------------ |
| Unsigned updates         | HIGH     | CI/CD without verification           |
| Deserialization attacks  | CRITICAL | Unvalidated JSON.parse of user input |
| Missing integrity checks | MEDIUM   | External resources without SRI       |

---

### A09:2021 - Logging/Monitoring Failures

| Check              | Severity | What to Look For       |
| ------------------ | -------- | ---------------------- |
| Missing audit logs | MEDIUM   | Auth events not logged |
| PII in logs        | HIGH     | Logging personal data  |
| No alerting        | MEDIUM   | Failures not monitored |

---

### A10:2021 - SSRF

| Check                   | Severity | What to Look For                       |
| ----------------------- | -------- | -------------------------------------- |
| Unvalidated URLs        | CRITICAL | User-supplied URLs fetched server-side |
| Internal network access | CRITICAL | Fetching localhost, internal IPs       |
| Protocol bypass         | HIGH     | file://, gopher://, etc.               |

**Code Patterns to Flag**:

```typescript
// CRITICAL - SSRF vulnerability
const response = await fetch(userProvidedUrl); // No validation!

// CRITICAL - Internal network access
if (url.includes("localhost") || url.includes("127.0.0.1")) {
  // This check is bypassable!
}
```

---

## Reference Standards

| Document                                | Purpose                                 |
| --------------------------------------- | --------------------------------------- |
| `CLAUDE.md`                             | Architecture, auth patterns, guidelines |
| `./guides/testing-patterns.md`    | Testing philosophy, mock factories      |
| TypeScript strict mode                  | Follow conventions from tsconfig.json and ESLint configuration |
| `docs/SERVICE_INVENTORY.md`             | Service catalog                         |

---

## Project-Specific Checks

### Auth Security

| Check              | Severity | What to Look For                    |
| ------------------ | -------- | ----------------------------------- |
| JWT verification   | CRITICAL | All API routes use auth middleware  |
| Org scoping        | CRITICAL | All queries scoped to organization  |
| Webhook signatures | CRITICAL | Webhooks verified via signatures    |
| Role checks        | HIGH     | RBAC enforced for admin operations  |

### Payment Security

| Check             | Severity | What to Look For                        |
| ----------------- | -------- | --------------------------------------- |
| Webhook signature | CRITICAL | Always verify payment webhook signatures |
| PCI compliance    | HIGH     | Never log or store full card numbers    |
| Idempotency       | MEDIUM   | Use idempotency keys for payments       |

### Analytics

| Check         | Severity | What to Look For                    |
| ------------- | -------- | ----------------------------------- |
| PII in events | HIGH     | No email, names in analytics events |
| User consent  | MEDIUM   | Analytics respects user preferences |

---

## Review Output Format

```markdown
## Security Audit: <files or description>

### Verdict: APPROVED | BLOCKED

### Summary

<Brief security assessment>

---

### Critical Findings (Blocks PR)

#### 1. SQL Injection in User Search

**File**: `src/lib/services/user.service.ts:45`
**OWASP**: A03:2021 - Injection
**Issue**: User input directly concatenated into query string
**Impact**: Attacker can extract or modify database contents
**Fix**:
\`\`\`typescript
// Current (vulnerable)
const query = \`SELECT \* FROM users WHERE name = '\${name}'\`;

// Fixed
const users = await prisma.user.findMany({
where: { name: { contains: name } }
});
\`\`\`

---

### High Priority Findings

#### 2. Missing Auth Check on API Route

**File**: `src/api/routes/contacts/route.ts:12`
**OWASP**: A01:2021 - Broken Access Control
**Issue**: GET handler doesn't verify session
**Fix**: Add auth middleware check

---

### Medium Priority Findings

#### 3. Sensitive Data in Logs

**File**: `src/lib/services/gmail.service.ts:89`
**OWASP**: A02:2021 - Cryptographic Failures
**Issue**: Access token logged at debug level
**Fix**: Remove token from log context

---

### Low Priority / Notes

1. Consider adding rate limiting to /api/auth endpoints
2. CSP header could be more restrictive

---

### OWASP Coverage

- [x] A01: Broken Access Control - Checked
- [x] A02: Cryptographic Failures - Checked
- [x] A03: Injection - **FOUND ISSUE**
- [x] A04: Insecure Design - Checked
- [x] A05: Security Misconfiguration - Checked
- [x] A06: Vulnerable Components - Checked
- [x] A07: Auth Failures - **FOUND ISSUE**
- [x] A08: Integrity Failures - Checked
- [x] A09: Logging Failures - **FOUND ISSUE**
- [x] A10: SSRF - Checked
```

---

## Approval Criteria

**APPROVED** when:

- Zero CRITICAL findings
- Zero HIGH findings (or accepted with documented justification)
- All OWASP categories checked

**BLOCKED** when:

- Any CRITICAL finding exists
- Multiple HIGH findings without mitigation plan

---

## Common Vulnerability Patterns

### Authentication Bypass

```typescript
// WRONG - Trusting client-side check
if (req.headers['x-admin'] === 'true') { ... }

// RIGHT - Server-side auth via middleware
// Middleware verifies JWT and provides auth context
const { userId, orgId } = c.get("auth");
if (!userId) { throw new UnauthorizedError(); }
```

### Authorization Bypass

```typescript
// WRONG - No org scoping
const account = await prisma.emailAccount.findUnique({
  where: { id: accountId },
});

// RIGHT - Organization-scoped query
const account = await prisma.emailAccount.findUnique({
  where: { id: accountId, organizationId: auth.orgId },
});
```

### Input Validation

```typescript
// WRONG - Trusting user input
const data = JSON.parse(req.body);
await prisma.user.update({ where: { id: data.id }, data });

// RIGHT - Schema validation
const schema = z.object({
  id: z.string().uuid(),
  name: z.string().max(100),
});
const data = schema.parse(await req.json());
```
