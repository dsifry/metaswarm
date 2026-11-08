#!/usr/bin/env bash
# tests/setup/test-require-ci-check.sh
# #83 item 2: lib/require-ci-check.sh makes the CI check required on the default
# branch by adding a repository ruleset. It never rewrites existing branch
# protection, does nothing if its ruleset already exists, and prints the manual
# steps when it can't. GitHub is replaced by a stub `gh` on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/lib/require-ci-check.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: logs each call; behaviour comes from STUB_* variables.
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "auth status") exit "${STUB_AUTH_RC:-0}" ;;
  "repo view") echo "acme/app"; exit 0 ;;
esac
if [ "$1" = api ]; then
  shift
  method=GET; input=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X|--method) method="$2"; shift 2 ;;
      --input) input="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ "$method" = POST ]; then
    [ -n "$input" ] && cat "$input" > "$STUB_PAYLOAD"
    [ "${STUB_POST_RC:-0}" -eq 0 ] && { echo '{"id":42}'; exit 0; }
    echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1
  fi
  printf '%s' "${STUB_EXISTING:-}"
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
export STUB_LOG="$TMP/gh.log" STUB_PAYLOAD="$TMP/payload.json"

run() { # sets RC and OUT
  : > "$STUB_LOG"; rm -f "$STUB_PAYLOAD"
  RC=0; OUT="$(PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$@" 2>&1)" || RC=$?
}

echo "Helper exists"
if [ -f "$SCRIPT" ]; then pass "lib/require-ci-check.sh exists"; else fail "lib/require-ci-check.sh is missing"; fi

if [ -f "$SCRIPT" ]; then
  echo "Adds a ruleset requiring the check on the default branch"
  run
  [ "$RC" -eq 0 ] && pass "succeeds" || fail "failed (rc=$RC): $OUT"
  grep -q 'repos/acme/app/rulesets' "$STUB_LOG" && pass "uses the rulesets API" || fail "did not call the rulesets API: $(tr '\n' ' ' < "$STUB_LOG")"
  if grep -qE 'branches/[^ ]+/protection' "$STUB_LOG"; then fail "touched branch protection: $(grep protection "$STUB_LOG")"; else pass "never touches existing branch protection"; fi
  if [ -f "$STUB_PAYLOAD" ] && node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf-8"));
    const rule = p.rules.find(r => r.type === "required_status_checks");
    const ok = p.target === "branch" && p.enforcement === "active"
      && p.conditions.ref_name.include.includes("~DEFAULT_BRANCH")
      && rule && rule.parameters.required_status_checks.some(c => c.context === "CI checks");
    process.exit(ok ? 0 : 1);' "$STUB_PAYLOAD"; then
    pass "payload: active branch ruleset on ~DEFAULT_BRANCH requiring \"CI checks\""
  else
    fail "payload is wrong: $(cat "$STUB_PAYLOAD" 2>/dev/null || echo none)"
  fi

  echo "Custom check name"
  run --check "Lint, Test & Coverage"
  node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf-8")); process.exit(p.rules[0].parameters.required_status_checks[0].context==="Lint, Test & Coverage"?0:1)' "$STUB_PAYLOAD" 2>/dev/null \
    && pass "--check sets the required context" || fail "--check ignored"
  run --check 'bad"name'
  [ "$RC" -ne 0 ] && [ ! -f "$STUB_PAYLOAD" ] && pass "rejects a check name that would break the JSON" || fail "accepted a JSON-breaking check name"

  echo "Idempotent"
  STUB_EXISTING="7" run
  [ "$RC" -eq 0 ] && [ ! -f "$STUB_PAYLOAD" ] && printf '%s' "$OUT" | grep -qi 'already' \
    && pass "an existing metaswarm ruleset means no second POST" || fail "re-created the ruleset (rc=$RC): $OUT"

  echo "Falls back to manual steps"
  STUB_POST_RC=1 run
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'Settings' && printf '%s' "$OUT" | grep -q 'CI checks' \
    && pass "a refused POST prints the manual steps and exits nonzero" || fail "refused POST (rc=$RC): $OUT"
  STUB_AUTH_RC=1 run
  [ "$RC" -ne 0 ] && [ ! -f "$STUB_PAYLOAD" ] && printf '%s' "$OUT" | grep -q 'Settings' \
    && pass "without gh auth it prints the manual steps" || fail "no-auth case (rc=$RC): $OUT"
  RC=0; OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPT" 2>&1)" || RC=$?
  if command -v gh >/dev/null 2>&1 && [ "$(command -v gh)" != "$TMP/bin/gh" ] && PATH="/usr/bin:/bin" command -v gh >/dev/null 2>&1; then
    echo "  SKIP: a real gh is on /usr/bin:/bin"
  else
    [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'Settings' && pass "without gh it prints the manual steps" || fail "no-gh case (rc=$RC): $OUT"
  fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
