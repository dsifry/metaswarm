#!/usr/bin/env bash
# tests/setup/test-go-coverage-gate.sh
# The Go coverage gate (#78): skills/setup/templates/go-coverage-gate.go, run as
# `go run .metaswarm/go-coverage-gate.go`, must fail below the thresholds in
# .coverage-thresholds.json and pass at or above them, against a real Go module.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE_SRC="$ROOT/skills/setup/templates/go-coverage-gate.go"
SETUP="$ROOT/lib/setup-mandatory-files.sh"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Go coverage gate (#78) ==="

[ -f "$GATE_SRC" ] && pass "gate template exists" || fail "gate template missing: $GATE_SRC"

if ! command -v go >/dev/null 2>&1; then
  # CI (ubuntu-latest) ships Go; a machine without it cannot run these checks.
  echo "  SKIP: go not installed; module checks not run"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  DONE=1
  [ "$FAIL" -eq 0 ]
  exit
fi
export GOFLAGS=-mod=mod GOCACHE="$TMP/gocache" GOPATH="$TMP/gopath" GOTOOLCHAIN=local

# new_module DIR N [U] — a module whose F has N+3+U statements; the test calls
# F(false), so the U statements inside `if b` (default 1) never run:
# N+3 of N+3+U covered.
new_module() {
  local dir="$1" n="$2" u="${3:-1}" i
  mkdir -p "$dir/.metaswarm"
  printf 'module example.com/m\n\ngo 1.21\n' > "$dir/go.mod"
  {
    printf 'package m\n\nfunc F(b bool) int {\n\tx := 0\n'
    i=0
    while [ "$i" -lt "$n" ]; do printf '\tx++\n'; i=$((i + 1)); done
    printf '\tif b {\n'
    i=0
    while [ "$i" -lt "$u" ]; do printf '\t\tx--\n'; i=$((i + 1)); done
    printf '\t}\n\treturn x\n}\n'
  } > "$dir/f.go"
  printf 'package m\n\nimport "testing"\n\nfunc TestF(t *testing.T) { F(false) }\n' > "$dir/f_test.go"
  cp "$GATE_SRC" "$dir/.metaswarm/go-coverage-gate.go"
}

# thresholds DIR LINES BRANCHES FUNCTIONS STATEMENTS
thresholds() {
  printf '{\n  "thresholds": { "lines": %s, "branches": %s, "functions": %s, "statements": %s },\n  "enforcement": { "command": "go run .metaswarm/go-coverage-gate.go" }\n}\n' \
    "$2" "$3" "$4" "$5" > "$1/.coverage-thresholds.json"
}

gate() { OUT="$(cd "$1" && go run .metaswarm/go-coverage-gate.go 2>&1)"; RC=$?; }

# --- 2,499 of 2,500 statements: `go tool cover -func` rounds this to 100.0% ---
BIG="$TMP/big"
new_module "$BIG" 2496
thresholds "$BIG" 100 100 100 100
gate "$BIG"
[ "$RC" -ne 0 ] && pass "2499/2500 fails at 100%" || fail "2499/2500 passed at 100% (rc=$RC): $OUT"
printf '%s' "$OUT" | grep -q "2499 of 2500 statements" && pass "reports exact statement counts" || fail "no exact counts in: $OUT"
printf '%s' "$OUT" | grep -q "99.96%" && pass "shows 99.96%, not a rounded 100.0%" || fail "percentage not shown unrounded: $OUT"
printf '%s' "$OUT" | grep -q "cover 1 more statement" && pass "says how many statements are missing" || fail "no missing-statement count: $OUT"
ROUNDED="$(cd "$BIG" && go tool cover -func=coverage.out | tail -1)"
printf '%s' "$ROUNDED" | grep -q "100.0%" && pass "precondition: go tool cover -func rounds it to 100.0%" || fail "precondition changed, go tool cover says: $ROUNDED"
thresholds "$BIG" 99.9 99.9 99.9 99.9
gate "$BIG"
[ "$RC" -eq 0 ] && pass "2499/2500 passes at 99.9%" || fail "2499/2500 failed at 99.9% (rc=$RC): $OUT"

# --- 3 of 4 statements (75%): boundary at, above and below ---
SMALL="$TMP/small"
new_module "$SMALL" 0
thresholds "$SMALL" 75 75 75 75
gate "$SMALL"
[ "$RC" -eq 0 ] && pass "75% passes at a 75% threshold" || fail "75% failed at 75% (rc=$RC): $OUT"
thresholds "$SMALL" 76 0 0 76
gate "$SMALL"
[ "$RC" -ne 0 ] && pass "75% fails at 76%" || fail "75% passed at 76%: $OUT"

# Decimal thresholds compare exactly: 2499/2500 is exactly 99.96%.
thresholds "$BIG" 99.96 0 0 99.96
gate "$BIG"
[ "$RC" -eq 0 ] && pass "exactly at a decimal threshold (99.96%) passes" || fail "99.96% failed at 99.96% (rc=$RC): $OUT"
thresholds "$BIG" 99.97 0 0 99.97
gate "$BIG"
[ "$RC" -ne 0 ] && pass "just below a decimal threshold (99.97%) fails" || fail "99.96% passed at 99.97%: $OUT"
# 40959/41000 is exactly 99.9%, but 99.9*41000 rounds up in float64.
DEC="$TMP/dec"
new_module "$DEC" 40956 41
thresholds "$DEC" 99.9 0 0 99.9
gate "$DEC"
printf '%s' "$OUT" | grep -q "40959 of 41000 statements" || fail "decimal fixture is not 40959/41000: $OUT"
[ "$RC" -eq 0 ] && pass "40959/41000 passes at exactly 99.9% (no float rounding)" || fail "40959/41000 failed at 99.9% (rc=$RC): $OUT"

# Thresholds are compared as exact decimals: 75.0000001 is above 3/4.
thresholds "$SMALL" 75.0000001 0 0 75.0000001
gate "$SMALL"
[ "$RC" -ne 0 ] && pass "75% fails at 75.0000001% (no rounding of the threshold)" || fail "75% passed at 75.0000001%: $OUT"
# Out-of-range thresholds are rejected, not silently passed.
thresholds "$SMALL" -5 0 0 75
gate "$SMALL"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "between 0 and 100" && pass "a negative threshold is rejected" || fail "negative threshold accepted (rc=$RC): $OUT"
thresholds "$SMALL" 1e300 0 0 75
gate "$SMALL"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "between 0 and 100" && pass "a huge threshold is rejected" || fail "huge threshold accepted (rc=$RC): $OUT"

# lines and statements are enforced separately: either one below fails.
thresholds "$SMALL" 75 0 0 80
gate "$SMALL"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "FAIL statements" && pass "statements threshold enforced on its own" || fail "statements 80 not enforced (rc=$RC): $OUT"
thresholds "$SMALL" 80 0 0 75
gate "$SMALL"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "FAIL lines" && pass "lines threshold enforced on its own" || fail "lines 80 not enforced (rc=$RC): $OUT"

# branches/functions are reported, never silently treated as met.
thresholds "$SMALL" 75 100 100 75
gate "$SMALL"
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "NOT ENFORCED branches" && printf '%s' "$OUT" | grep -q "NOT ENFORCED functions" \
  && pass "branches and functions reported as not enforced" || fail "unsupported dimensions not reported (rc=$RC): $OUT"

# Threshold read at run time: editing the file changes the verdict with no setup re-run.
thresholds "$SMALL" 90 90 90 90
gate "$SMALL"; R1=$RC
thresholds "$SMALL" 50 50 50 50
gate "$SMALL"; R2=$RC
[ "$R1" -ne 0 ] && [ "$R2" -eq 0 ] && pass "threshold is read from .coverage-thresholds.json at run time" || fail "threshold not read at run time (90%: rc=$R1, 50%: rc=$R2)"

# --- arguments passed through to go test ---
# Root package fully covered, sub/ package not: testing only the root would pass.
ARGS="$TMP/args"
new_module "$ARGS" 0 0
mkdir -p "$ARGS/sub"
printf 'package sub\n\nfunc G(b bool) int {\n\tif b {\n\t\treturn 1\n\t}\n\treturn 0\n}\n' > "$ARGS/sub/g.go"
thresholds "$ARGS" 100 0 0 100
args_gate() { OUT="$(cd "$ARGS" && go run .metaswarm/go-coverage-gate.go "$@" 2>&1)"; RC=$?; }
args_gate -count=1
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sub" && pass "flags only: ./... still tested (sub package counted)" || fail "flags only: sub package skipped (rc=$RC): $OUT"
args_gate -run TestF
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sub" && pass "a flag's separate value is not taken as a package" || fail "'-run TestF' treated TestF as a package (rc=$RC): $OUT"
args_gate -count=1 -args -test.v
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sub" && pass "-args: ./... goes before -args (sub package counted)" || fail "-args: ./... passed to the test binary (rc=$RC): $OUT"
args_gate -args -test.run=TestF
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sub" && pass "-args only: tokens after it are not taken as packages" || fail "-args only: sub package skipped (rc=$RC): $OUT"
args_gate -test.run TestF
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sub" && pass "'-test.run TestF': test.-prefixed value flag recognised" || fail "'-test.run TestF' treated TestF as a package (rc=$RC): $OUT"
args_gate .
[ "$RC" -eq 0 ] && pass "an explicit package list is respected" || fail "explicit '.' not respected (rc=$RC): $OUT"
# -outputdir must not move the profile the gate reads, and a stale root
# coverage.out must never be judged instead of this run's profile.
printf 'mode: set\nexample.com/m/f.go:1.1,2.2 5 1\n' > "$ARGS/coverage.out"
mkdir -p "$ARGS/artifacts"
args_gate -outputdir artifacts ./...
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "FAIL" && ! printf '%s' "$OUT" | grep -q "cannot read cover profile" \
  && pass "-outputdir: this run's profile is judged (not a stale root file)" || fail "-outputdir broke the gate (rc=$RC): $OUT"
grep -q "sub/g.go" "$ARGS/coverage.out" && pass "coverage.out at the root holds this run's profile" || fail "root coverage.out not refreshed"
args_gate -coverprofile=x.out ./...
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "sets -coverprofile itself" && pass "a -coverprofile argument is rejected" || fail "-coverprofile argument accepted (rc=$RC): $OUT"

# --- error paths ---
FAILING="$TMP/failing"
new_module "$FAILING" 0
thresholds "$FAILING" 0 0 0 0
printf 'package m\n\nimport "testing"\n\nfunc TestBroken(t *testing.T) { t.Fatal("boom") }\n' > "$FAILING/broken_test.go"
gate "$FAILING"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "go test failed" && pass "a failing go test fails the gate" || fail "failing test not propagated (rc=$RC): $OUT"

NOCFG="$TMP/nocfg"
new_module "$NOCFG" 0
gate "$NOCFG"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "cannot read .coverage-thresholds.json" && pass "missing .coverage-thresholds.json fails" || fail "missing config not reported (rc=$RC): $OUT"
printf '{ "thresholds": { "branches": 100 } }\n' > "$NOCFG/.coverage-thresholds.json"
gate "$NOCFG"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "neither thresholds.lines nor thresholds.statements" && pass "no enforceable dimension fails" || fail "branches-only config passed (rc=$RC): $OUT"

# --- the gate stays out of the user's ./... ---
LISTED="$(cd "$SMALL" && go list ./... 2>&1)"
printf '%s' "$LISTED" | grep -q "metaswarm" && fail "go list ./... includes the gate: $LISTED" || pass "go list ./... excludes .metaswarm/"
(cd "$SMALL" && go vet ./... >/dev/null 2>&1) && pass "go vet ./... passes alongside the gate" || fail "go vet ./... fails with the gate present"

# --- through setup-mandatory-files.sh and the CI template's command guard ---
VIA="$TMP/via-setup"
new_module "$VIA" 0
rm -rf "${VIA:?}/.metaswarm"
printf 'test\n' > "$VIA/CLAUDE.md"
SETUP_OUT="$(bash "$SETUP" "$VIA" 75 "go run .metaswarm/go-coverage-gate.go" --platform claude 2>&1)"
cmp -s "$GATE_SRC" "$VIA/.metaswarm/go-coverage-gate.go" && pass "setup writes .metaswarm/go-coverage-gate.go" || fail "setup did not write the gate: $SETUP_OUT"
CMD="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8')).enforcement.command)" "$VIA/.coverage-thresholds.json")"
[ "$CMD" = "go run .metaswarm/go-coverage-gate.go" ] && pass "setup records the gate as enforcement.command" || fail "enforcement.command is '$CMD'"
printf '%s' "$SETUP_OUT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.exit(JSON.parse(d).status==='ok'?0:1))" \
  && pass "setup status ok" || fail "setup status not ok: $SETUP_OUT"

# Run the "Test with coverage" step of each CI template verbatim in the module.
for ci in "$ROOT/templates/ci.yml" "$ROOT/skills/setup/templates/ci.yml"; do
  rel="${ci#"$ROOT"/}"
  STEP="$TMP/ci-step.sh"
  awk '/name: Test with coverage/{f=1; next} f && /run: \|/{r=1; next} r && /^      - name:/{exit} r{sub(/^          /,""); print}' "$ci" > "$STEP"
  grep -q "disallowed shell metacharacters" "$STEP" || { fail "$rel: could not extract the guarded test step"; continue; }
  CI_OUT="$(cd "$VIA" && bash "$STEP" 2>&1)"; CI_RC=$?
  [ "$CI_RC" -eq 0 ] && printf '%s' "$CI_OUT" | grep -q "coverage gate: passed" && pass "$rel guard runs the gate (75% at 75%)" || fail "$rel guard rejected or failed the gate (rc=$CI_RC): $CI_OUT"
  thresholds "$VIA" 76 76 76 76
  CI_OUT="$(cd "$VIA" && bash "$STEP" 2>&1)"; CI_RC=$?
  [ "$CI_RC" -ne 0 ] && printf '%s' "$CI_OUT" | grep -q "coverage gate: FAILED" && pass "$rel step fails below the threshold" || fail "$rel step did not fail at 76% (rc=$CI_RC): $CI_OUT"
  thresholds "$VIA" 75 75 75 75
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
