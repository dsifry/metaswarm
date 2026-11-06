#!/usr/bin/env bash
# tests/agents/test-escalation.sh
# orchestrated-execution must describe model escalation of the coder after repeated VALIDATE failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$REPO_ROOT/skills/orchestrated-execution/SKILL.md"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# section <heading-regex>: prints from the matching heading to the next heading of the same or higher level
section() {
  awk -v re="$1" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$SKILL"
}

assert_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if ! printf '%s' "$text" | grep -qF -- "$s"; then fail "$label: missing '$s'"; return; fi
  done
  pass "$label"
}

RECOVERY="$(section '^## 9\. Recovery Protocol')"
RETRY="$(printf '%s\n' "$RECOVERY" | awk '/^### Step 3/{on=1} /^### Step 4/{on=0} on')"
ONFAIL="$(section '^### On FAIL: Mandatory Re-Review Protocol')"

[ -n "$RETRY" ] && pass "found Recovery Protocol Step 3" || fail "found Recovery Protocol Step 3"
[ -n "$ONFAIL" ] && pass "found On FAIL protocol" || fail "found On FAIL protocol"

for pair in "Recovery Step 3:$RETRY" "On FAIL:$ONFAIL"; do
  label="${pair%%:*}"; text="${pair#*:}"
  assert_in "$label names escalation.coder.after_failures and default 2" "$text" 'escalation.coder.after_failures' '(default 2'
  assert_in "$label re-spawns coder with roleType(\"coder\") and a per-call model" "$text" 'roleType("coder")' 'model'
  assert_in "$label uses escalation.coder.claude (default opus)" "$text" 'escalation.coder.claude' '`opus`'
  assert_in "$label reads .metaswarm/models.yaml" "$text" '.metaswarm/models.yaml'
  assert_in "$label says per-call model overrides the agent-file default" "$text" 'overrides the agent-file default'
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
