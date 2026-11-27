# Security Implementation Rubric

**Used By**:
- the Security Coder, as its checklist before hand-back;
- the Adversarial Reviewer, on any work unit built by the `security-coder` tier or that touches a security boundary.

**Purpose**: Catch the defects that security-critical code actually ships with: the ones tests at 100% coverage still miss.
**Version**: 1.0

---

## How to use it

**This rubric adds to the existing rubrics; it replaces none of them.**
- The reviewer still applies `adversarial-review-rubric.md` in full.
- `security-review-rubric.md`, which follows the OWASP Top 10, still covers web and API surface issues.
- This rubric covers how the security mechanism itself is built.

**Every section gets a verdict:**
- **PASS**: give file:line evidence.
- **N/A**: give one line saying why the section does not apply.
- **FAIL**: report it as a finding under the contract in `guides/delivery-scope.md`.

**Severity:**
- A finding that lets an unverified, unauthorized or replayed input be accepted is **critical**.
- A finding that exposes a secret value is **critical**.
- Neither is ever downgraded to minor without the user's decision.
- Everything else follows the normal severity rules.

**Delivery scope still applies.** A blocker must name the credible scenario it protects. Theoretical hardening with no credible path becomes a follow-up, not a blocker (see `guides/delivery-scope.md`).

---

## S1. Trust anchor

| Check | What to look for |
|---|---|
| Where the key comes from | The key, certificate or allowed identity used to verify must come only from an already-trusted store, such as a verified record or pinned config. It must never come from the message being verified, or from anything that message names. A message identifier (such as a key ID) may only choose among entries that already exist in the trusted store; it must not add, replace or define a key, certificate or allowed identity. |
| Who can write the anchor | Name every writer of the trust store. Can any of them be driven by an unverified input, another tenant or another fleet? |
| Bootstrap | The first key a system trusts (trust on first use, or a first status) must be explicit, narrow, and impossible to reach again after bootstrap. |
| Version skew | An old release that lacks the new key or field must fail with a clear message that names the cause. It must never fall back to "unverified is fine". A new release that adds a signer must not break an older verifier's recovery path without a stated decision. |

## S2. Binding and replay

| Check | What to look for |
|---|---|
| Every field bound | A signed answer must bind who sent it, who it is for, which request, which step, which sequence or nonce, and the result code. List each field and the line that checks it. |
| Zero and empty values | A zero sequence, an empty nonce, an empty request id or an empty key is refused outright. It is never treated as "not set, so skip the check". |
| Replay | Resending an earlier valid answer, or one from another session, fleet or tenant, is refused. Prove it with a test. |
| Partial binding | An answer that leaves out an optional binding field must not pass a check that the field was meant to pin. |

## S3. Fail closed

| Check | What to look for |
|---|---|
| Unknown inputs | An unknown target, verb, service, version or field causes a refusal before anything is sent or decoded. |
| Pending or unwired paths | A feature that is not built yet ends in an error that names its owner. It must never produce a pass, a zero or an empty success, and no caller may read that error as success. |
| Error paths | Every error return after a partial effect leaves the system in a state that is safe to retry. Look for a lock held, a token half issued, or a file half written. |
| Defaults | No security setting defaults to open. A missing config means refuse, not allow. |

## S4. One path through verification

| Check | What to look for |
|---|---|
| No bypass | Every way an answer or credential enters the program goes through the one verify function. Walk run, send, batch steps, resume, retry, paging, export, health, logs and any adapter. |
| Structural guard | A test fails when someone adds a new decode path that skips verification. It must parse the code (an AST check, or a type that only verify can build), not match a string, because a local alias defeats a string match. |
| Guard proven | The guard has been shown to fail on a deliberately added bypass. |

## S5. Secrets

| Check | What to look for |
|---|---|
| Where values go | A secret value goes only to the process that consumes it, ideally on stdin. Never in argv, an inherited environment, a temp file, a log line, an error message, a test name or a fixture committed to the repo. |
| Printing | Output shows at most a short fingerprint or prefix of a key, never the key or any secret. |
| Test material | Tests use keys generated during the test, or committed public halves only. Real or copied secrets never appear in tests. |
| Lifetime | Every secret issued has a revoke or expiry path, and that path is tested. |

## S6. Inverses and recovery

| Check | What to look for |
|---|---|
| Every effect has its inverse | For each grant, issue, enable, write or lock, there is a revoke, withdraw, disable, roll back or release path, and a test of it. |
| Recovery keeps security | Rollback, restore, resume after a crash, and the final pass all verify exactly as strictly as the normal path. No recovery mode skips a check "because it is an emergency". |
| Dry runs | A dry run runs every check the real run would. Only the writes are skipped. |

## S7. Errors and inputs from the other side

| Check | What to look for |
|---|---|
| No echo | A refusal never echoes text from the untrusted side, such as a remote error string or a field value, into logs or the user's screen without bounding and escaping it. |
| Bounded reads | Untrusted input is size-limited and time-limited before it is parsed. |
| Parsing matches the writer | The parser accepts exactly what the real writer emits, and refuses what the real reader refuses: blank lines, trailing whitespace, duplicate keys. A verifier that accepts more than its consumer moves the failure somewhere else. |

## S8. Tests that prove the mechanism

| Check | What to look for |
|---|---|
| A rejection test per attack | There is a separate test for each of: wrong key, each wrong binding field, replay, unsigned, malformed, and unknown target. A single "invalid answer fails" test does not count. |
| Real counterparties | At least one test runs against the real other side, in process: the real gate, signer or service, not only a fake. |
| Tests first | The hand-back shows each test of the new defense or the fixed defect failing before the code existed, and the mutation runs. Any other new test (for example a positive test of existing valid behaviour) needs only a stated reason in the hand-back. |
| Nothing weakened | No structural test, allow-list, pinned string or existing assertion was loosened. Any change to one is justified in the hand-back. |

---

## Reviewer output

Append this to the normal adversarial review:

```text
### Security implementation rubric
S1 Trust anchor: PASS | FAIL | N/A, then evidence or reason
S2 Binding and replay: ...
S3 Fail closed: ...
S4 One path through verification: ...
S5 Secrets: ...
S6 Inverses and recovery: ...
S7 Errors and inputs from the other side: ...
S8 Tests that prove the mechanism: ...
```
