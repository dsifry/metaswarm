#!/usr/bin/env bash
# tests/setup/test-setup-reconfigure.sh
# #79: a setup re-run with a changed threshold must update an existing
# .coverage-thresholds.json (thresholds and any threshold embedded in
# enforcement.command) while keeping the project's other settings. Only an
# explicit re-run passes --reconfigure; the session hook's silent self-heal
# must never change thresholds a user edited by hand.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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

# new_project NAME THRESHOLD COMMAND — an already set-up project with custom settings.
new_project() {
  P="$TMP/$1"
  mkdir -p "$P"
  printf 'metaswarm\n' > "$P/CLAUDE.md"
  node -e '
    const [file, t, cmd] = process.argv.slice(1);
    const n = Number(t);
    const cfg = {
      "$comment": "custom comment kept",
      thresholds: { lines: n, branches: n, functions: n, statements: n },
      enforcement: { command: cmd, blockPRCreation: false, blockTaskCompletion: true, description: "custom" },
      extra: { keep: true },
    };
    require("fs").writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
  ' "$P/.coverage-thresholds.json" "$2" "$3"
}

# get KEY — read a dotted key from $P/.coverage-thresholds.json
get() {
  node -e 'let v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf-8"));
    for (const k of process.argv[2].split(".")) v = v == null ? v : v[k];
    console.log(typeof v === "object" ? JSON.stringify(v) : String(v));' "$P/.coverage-thresholds.json" "$1"
}

run_setup() { OUT="$(bash "$SETUP" "$P" "$@" --platform claude 2>&1)"; RC=$?; }

json_status() { printf '%s' "$OUT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).status)}catch(e){console.log('INVALID-JSON')}})"; }

echo "=== setup re-run updates coverage thresholds (#79) ==="

# --- Without --reconfigure (session-hook self-heal): never touch an existing file ---
new_project selfheal 80 "pytest --cov --cov-fail-under=80"
BEFORE="$(cat "$P/.coverage-thresholds.json")"
run_setup 95 "pytest --cov --cov-fail-under=95"
[ "$(cat "$P/.coverage-thresholds.json")" = "$BEFORE" ] && pass "no --reconfigure: existing file unchanged" || fail "no --reconfigure: file changed"
printf '%s' "$OUT" | grep -q "already exists" && pass "no --reconfigure: reported as already existing" || fail "no --reconfigure: missing skip message: $OUT"

# --- --reconfigure with a changed threshold ---
new_project pytest 80 "pytest --cov --cov-fail-under=80"
run_setup 95 "pytest --cov --cov-fail-under=95" --reconfigure
[ "$RC" -eq 0 ] && [ "$(json_status)" = "ok" ] && pass "reconfigure: status ok" || fail "reconfigure: rc=$RC out=$OUT"
for k in lines branches functions statements; do
  [ "$(get "thresholds.$k")" = "95" ] && pass "reconfigure: thresholds.$k updated to 95" || fail "reconfigure: thresholds.$k is $(get "thresholds.$k")"
done
[ "$(get enforcement.command)" = "pytest --cov --cov-fail-under=95" ] && pass "reconfigure: --cov-fail-under in the command updated" || fail "reconfigure: command is '$(get enforcement.command)'"
[ "$(get enforcement.blockPRCreation)" = "false" ] && pass "reconfigure: enforcement.blockPRCreation kept" || fail "reconfigure: blockPRCreation lost"
[ "$(get enforcement.description)" = "custom" ] && pass "reconfigure: enforcement.description kept" || fail "reconfigure: description lost"
[ "$(get extra.keep)" = "true" ] && [ "$(get '$comment')" = "custom comment kept" ] && pass "reconfigure: other keys kept" || fail "reconfigure: other keys lost"
printf '%s' "$OUT" | grep -q "80% -> 95%" && pass "reconfigure: reports the change" || fail "reconfigure: change not reported: $OUT"
printf '%s' "$OUT" | grep -q "enforcement.command updated to: pytest --cov --cov-fail-under=95" && pass "reconfigure: reports the command update" || fail "reconfigure: command update not reported: $OUT"

# A customised command keeps its customisation; only the embedded threshold changes.
new_project custom 80 "pytest -q tests/unit --cov=src --cov-fail-under 80"
run_setup 90 "pytest --cov --cov-fail-under=90" --reconfigure
[ "$(get enforcement.command)" = "pytest -q tests/unit --cov=src --cov-fail-under 90" ] && pass "reconfigure: custom command kept, '--cov-fail-under 80' -> 90" || fail "reconfigure: custom command became '$(get enforcement.command)'"

new_project cargo 80 "cargo tarpaulin --fail-under 80"
run_setup 100 "cargo tarpaulin --fail-under 100" --reconfigure
[ "$(get enforcement.command)" = "cargo tarpaulin --fail-under 100" ] && pass "reconfigure: tarpaulin --fail-under updated" || fail "reconfigure: tarpaulin command is '$(get enforcement.command)'"

# A command that reads thresholds itself is left alone, with no warning.
new_project gogate 80 "go run .metaswarm/go-coverage-gate.go"
run_setup 90 "go run .metaswarm/go-coverage-gate.go" --reconfigure
[ "$(get enforcement.command)" = "go run .metaswarm/go-coverage-gate.go" ] && pass "reconfigure: threshold-free command unchanged" || fail "reconfigure: go command became '$(get enforcement.command)'"
printf '%s' "$OUT" | grep -q "may embed" && fail "reconfigure: spurious warning for a threshold-free command" || pass "reconfigure: no warning for a threshold-free command"
[ "$(get thresholds.lines)" = "90" ] && pass "reconfigure: go project thresholds updated" || fail "reconfigure: go project thresholds not updated"

# An existing Go project on the old non-enforcing `go test` command (#78) is
# moved to the gate on a re-run, and the gate file is written.
new_project oldgo 80 "go test -coverprofile=coverage.out ./..."
run_setup 90 "go run .metaswarm/go-coverage-gate.go" --reconfigure
[ "$(get enforcement.command)" = "go run .metaswarm/go-coverage-gate.go" ] && pass "reconfigure: old go test command replaced by the gate" || fail "reconfigure: old go command kept: '$(get enforcement.command)'"
[ -f "$P/.metaswarm/go-coverage-gate.go" ] && pass "reconfigure: gate written for an upgraded Go project" || fail "reconfigure: gate not written: $OUT"
printf '%s' "$OUT" | grep -q "never fails below the threshold" && pass "reconfigure: says why the Go command changed" || fail "reconfigure: Go command change not explained: $OUT"
# ...but a Go command the user built themselves is kept, with a warning.
new_project customgo 80 "make coverage-check"
run_setup 90 "go run .metaswarm/go-coverage-gate.go" --reconfigure
[ "$(get enforcement.command)" = "make coverage-check" ] && pass "reconfigure: custom non-go-test command kept" || fail "reconfigure: custom command replaced: '$(get enforcement.command)'"
printf '%s' "$OUT" | grep -q "go test alone never does" && pass "reconfigure: warns that a custom Go command must enforce" || fail "reconfigure: no warning for a custom Go command: $OUT"

# thresholds as an array or missing: replaced by a proper object, reported sanely.
new_project arr 80 "pytest --cov --cov-fail-under=80"
node -e 'const f=process.argv[1],c=JSON.parse(require("fs").readFileSync(f,"utf-8"));c.thresholds=[];require("fs").writeFileSync(f,JSON.stringify(c))' "$P/.coverage-thresholds.json"
run_setup 90 "pytest --cov --cov-fail-under=90" --reconfigure
[ "$(get thresholds.lines)" = "90" ] && [ "$(get thresholds.statements)" = "90" ] && pass "reconfigure: array thresholds replaced by an object" || fail "reconfigure: array thresholds: $(get thresholds)"
printf '%s' "$OUT" | grep -q "undefined" && fail "reconfigure: reports 'undefined': $OUT" || pass "reconfigure: no 'undefined' in the report"

# A carriage return in a command still yields valid JSON output.
new_project cr 80 "pytest --cov --cov-fail-under=80"
run_setup 90 $'pytest --cov\r --cov-fail-under=90' --reconfigure
[ "$(json_status)" != "INVALID-JSON" ] && pass "output stays valid JSON with control characters" || fail "control characters broke the JSON: $OUT"
P="$TMP/cr-new"; mkdir -p "$P"; printf 'metaswarm\n' > "$P/CLAUDE.md"
run_setup 90 $'pytest --cov\r\001 --cov-fail-under=90'
[ "$(json_status)" != "INVALID-JSON" ] && pass "create output stays valid JSON with control characters" || fail "create: control characters broke the JSON: $OUT"

# An embedded threshold in an unknown form is reported, not silently kept.
new_project unknown 80 "npx vitest run --coverage --coverage.thresholds.lines=80"
run_setup 90 "npx vitest run --coverage" --reconfigure
[ "$(get enforcement.command)" = "npx vitest run --coverage --coverage.thresholds.lines=80" ] && pass "reconfigure: unknown form left unchanged" || fail "reconfigure: unknown form rewritten to '$(get enforcement.command)'"
printf '%s' "$OUT" | grep -q "may embed the old threshold" && pass "reconfigure: user told the command may need updating" || fail "reconfigure: no warning for an unknown embedded threshold: $OUT"
[ "$(json_status)" != "INVALID-JSON" ] && pass "reconfigure: output with a warning is valid JSON" || fail "reconfigure: output is not valid JSON: $OUT"

# Same threshold: nothing to change.
new_project same 95 "pytest --cov --cov-fail-under=95"
BEFORE="$(cat "$P/.coverage-thresholds.json")"
run_setup 95 "pytest --cov --cov-fail-under=95" --reconfigure
[ "$(cat "$P/.coverage-thresholds.json")" = "$BEFORE" ] && pass "reconfigure: unchanged threshold leaves the file as is" || fail "reconfigure: file rewritten for an unchanged threshold"
printf '%s' "$OUT" | grep -q "already at 95%" && pass "reconfigure: reports already up to date" || fail "reconfigure: no up-to-date message: $OUT"

# Invalid existing JSON: error, file untouched.
P="$TMP/broken"; mkdir -p "$P"; printf 'metaswarm\n' > "$P/CLAUDE.md"
printf '{ not json\n' > "$P/.coverage-thresholds.json"
run_setup 90 "pytest --cov --cov-fail-under=90" --reconfigure
[ "$(cat "$P/.coverage-thresholds.json")" = "{ not json" ] && pass "reconfigure: invalid JSON left untouched" || fail "reconfigure: invalid JSON overwritten"
[ "$(json_status)" = "errors" ] && pass "reconfigure: invalid JSON reported as an error" || fail "reconfigure: invalid JSON status '$(json_status)': $OUT"

# A non-numeric threshold argument is rejected before anything is written.
new_project badarg 80 "pytest --cov --cov-fail-under=80"
BEFORE="$(cat "$P/.coverage-thresholds.json")"
run_setup abc "pytest --cov" --reconfigure
[ "$(cat "$P/.coverage-thresholds.json")" = "$BEFORE" ] && [ "$(json_status)" = "errors" ] && pass "reconfigure: non-numeric threshold rejected" || fail "reconfigure: non-numeric threshold accepted: $OUT"

# --- wiring: only the explicit re-run passes --reconfigure ---
grep -q -- "--reconfigure" "$ROOT/hooks/session-start.sh" && fail "session-start.sh self-heal passes --reconfigure" || pass "session-start.sh self-heal does not pass --reconfigure"
grep -q -- "--reconfigure" "$ROOT/skills/setup/SKILL.md" && pass "setup skill passes --reconfigure on a re-run" || fail "setup skill never passes --reconfigure"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
