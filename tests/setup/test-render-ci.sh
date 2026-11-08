#!/usr/bin/env bash
# tests/setup/test-render-ci.sh
# #83: lib/render-ci.sh writes .github/workflows/ci.yml from templates/ci.yml for
# the detected stack (items 1, 3 and 5): the repo's default branch, a toolchain
# block per stack, and lint/typecheck steps that skip a missing script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RENDER="$REPO_ROOT/lib/render-ci.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

has() { grep -qF -- "$2" "$1"; }

echo "Renderer exists"
if [ -f "$RENDER" ]; then pass "lib/render-ci.sh exists"; else fail "lib/render-ci.sh is missing"; fi

if [ -f "$RENDER" ]; then
  echo "Each stack gets its own toolchain, and only that one"
  for stack in node python go rust; do
    out="$TMP/ci-$stack.yml"
    rc=0; bash "$RENDER" --stack "$stack" --branch main --out "$out" >"$TMP/render-$stack.log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then fail "$stack: render failed (rc=$rc): $(cat "$TMP/render-$stack.log")"; continue; fi
    case "$stack" in
      node)   want='actions/setup-node@';   others='actions/setup-python@ actions/setup-go@ dtolnay/rust-toolchain@' ;;
      python) want='actions/setup-python@'; others='actions/setup-node@ actions/setup-go@ dtolnay/rust-toolchain@' ;;
      go)     want='actions/setup-go@';     others='actions/setup-node@ actions/setup-python@ dtolnay/rust-toolchain@' ;;
      rust)   want='dtolnay/rust-toolchain@'; others='actions/setup-node@ actions/setup-python@ actions/setup-go@' ;;
    esac
    has "$out" "$want" && pass "$stack: uses $want" || fail "$stack: missing $want"
    leaked=""
    for o in $others; do has "$out" "$o" && leaked="$leaked $o"; done
    [ -z "$leaked" ] && pass "$stack: no other stack's toolchain" || fail "$stack: other toolchains leaked:$leaked"
    grep -q '@toolchain\|@end\|@branch' "$out" && fail "$stack: render markers left in the output" || pass "$stack: no render markers left"
    has "$out" 'enforcement.command' && has "$out" 'CMD_ARRAY' && pass "$stack: shared coverage step present" || fail "$stack: coverage step missing"
    if [ "$stack" = node ]; then
      has "$out" 'name: Lint' && pass "node: keeps the lint step" || fail "node: lint step missing"
    else
      grep -q 'npm ' "$out" && fail "$stack: still runs npm" || pass "$stack: does not run npm"
    fi
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
      python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert d["jobs"]["ci"]["steps"]' "$out" \
        && pass "$stack: output is valid YAML with steps" || fail "$stack: output is not valid YAML"
    fi
  done
  has "$TMP/ci-rust.yml" 'cargo-tarpaulin' && pass "rust: installs cargo-tarpaulin (setup's coverage command)" || fail "rust: cargo-tarpaulin not installed"
  has "$TMP/ci-go.yml" 'go-version-file: go.mod' && pass "go: Go version from go.mod" || fail "go: no go-version-file"

  echo "Branch"
  bash "$RENDER" --stack node --branch develop --out "$TMP/dev.yml" >/dev/null 2>&1 || true
  awk '/^  push:/{f=1; next} f && /^  [a-z_]+:/{exit} f' "$TMP/dev.yml" > "$TMP/push.txt" 2>/dev/null || true
  grep -qF 'branches: ["develop"]' "$TMP/push.txt" && pass "push runs on the given branch" || fail "push does not target develop: $(tr '\n' ' ' < "$TMP/push.txt")"
  awk '/^  pull_request:/{f=1; next} f && /^  [a-z_]+:/{exit} f' "$TMP/dev.yml" > "$TMP/pr.txt" 2>/dev/null || true
  grep -q 'branches' "$TMP/pr.txt" && fail "pull_request still has a branch filter" || pass "pull_request checks PRs into any branch"

  R="$TMP/repo"; mkdir -p "$R"
  (cd "$R" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
    && git update-ref refs/remotes/origin/trunk HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk)
  (cd "$R" && PATH="/usr/bin:/bin" bash "$RENDER" --stack go --out ci.yml) >/dev/null 2>&1 || true
  grep -qF 'branches: ["trunk"]' "$R/ci.yml" 2>/dev/null && pass "without --branch, uses origin/HEAD (the default branch)" || fail "default branch not detected from origin/HEAD"

  rc=0; bash "$RENDER" --stack node --branch 'main"]; evil' --out "$TMP/bad.yml" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$TMP/bad.yml" ] && pass "rejects a branch name that would break the YAML" || fail "accepted a YAML-breaking branch name"

  echo "Unsupported stacks"
  rc=0; msg="$(bash "$RENDER" --stack java --branch main --out "$TMP/java.yml" 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$TMP/java.yml" ] && printf '%s' "$msg" | grep -q 'ci-coverage-job.yml' \
    && pass "unknown stack exits 2 and points at ci-coverage-job.yml" || fail "unknown stack: rc=$rc, msg=$msg"

  echo "Node lint and typecheck skip only a missing script"
  # run_step <ci.yml> <step name>: the step's `run: |` body, dedented.
  run_step() {
    awk -v n="- name: $2" '
      index($0, n) {f = 1; next}
      f && /^ *run: \|/ {r = 1; match($0, /^ */); ind = RLENGTH + 2; next}
      r { if ($0 !~ /^ *$/ && match($0, /^ */) && RLENGTH < ind) exit; print substr($0, ind + 1) }
    ' "$1"
  }
  for step in Lint Typecheck; do
    script="$(echo "$step" | tr 'LT' 'lt')"
    body="$(run_step "$TMP/ci-node.yml" "$step")"
    [ -n "$body" ] || { fail "node: no run body for $step"; continue; }
    P="$TMP/p-$script"; mkdir -p "$P"
    printf '{"name":"x","scripts":{}}\n' > "$P/package.json"
    rc=0; (cd "$P" && bash -c "set -e; $body") >"$P/out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && grep -qi 'skip' "$P/out" && pass "node $step: a missing script is skipped" || fail "node $step: missing script not skipped (rc=$rc): $(cat "$P/out")"
    printf '{"name":"x","scripts":{"%s":"exit 3"}}\n' "$script" > "$P/package.json"
    rc=0; (cd "$P" && bash -c "set -e; $body") >"$P/out" 2>&1 || rc=$?
    [ "$rc" -ne 0 ] && pass "node $step: a failing script fails the step" || fail "node $step: a failing script passed"
  done

  echo "Python installs the project only when pyproject.toml defines one"
  PYBODY="$(run_step "$TMP/ci-python.yml" "Install dependencies")"
  mkdir -p "$TMP/stub"
  printf '#!/bin/sh\necho "pip $*" >> "$PIPLOG"\n' > "$TMP/stub/pip"
  printf '#!/bin/sh\n[ "$1 $2" = "-m pip" ] && { shift 2; echo "pip $*" >> "$PIPLOG"; }\nexit 0\n' > "$TMP/stub/python"
  chmod +x "$TMP/stub/pip" "$TMP/stub/python"
  for kind in toolonly project; do
    P="$TMP/py-$kind"; mkdir -p "$P"; : > "$P/requirements.txt"
    if [ "$kind" = toolonly ]; then printf '[tool.ruff]\nline-length = 100\n' > "$P/pyproject.toml"
    else printf '[project]\nname = "x"\nversion = "0.1"\n' > "$P/pyproject.toml"; fi
    export PIPLOG="$P/pip.log"; : > "$PIPLOG"
    rc=0; (cd "$P" && PATH="$TMP/stub:$PATH" bash -c "set -e; $PYBODY") >"$P/out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "python ($kind): install step failed (rc=$rc): $(cat "$P/out")"
    if [ "$kind" = toolonly ]; then
      grep -q 'install -e' "$PIPLOG" && fail "python: a tool-config-only pyproject.toml is pip-installed: $(tr '\n' ' ' < "$PIPLOG")" \
        || pass "python: a pyproject.toml with only [tool.*] tables isn't installed as a package"
    else
      grep -q 'install -e' "$PIPLOG" && pass "python: a pyproject.toml with [project] is installed" || fail "python: [project] not installed: $(tr '\n' ' ' < "$PIPLOG")"
    fi
  done
fi

echo "/setup wires the renderer and the required-check offer"
SETUP="$REPO_ROOT/skills/setup/SKILL.md"
grep -qF 'lib/render-ci.sh" --stack' "$SETUP" && pass "/setup renders CI with lib/render-ci.sh" || fail "/setup does not run lib/render-ci.sh"
grep -q 'ci-coverage-job.yml' "$SETUP" && pass "/setup names ci-coverage-job.yml for other stacks" || fail "/setup has no fallback for stacks without a toolchain"
if grep -q '| `./templates/ci.yml` | `.github/workflows/ci.yml` |' "$SETUP"; then fail "/setup still copies ci.yml verbatim"; else pass "/setup no longer copies ci.yml verbatim"; fi
CI_SECTION="$(sed -n '/^### 5\.4 CI/,/^### \|^---$/p' "$SETUP")"
if printf '%s\n' "$CI_SECTION" | grep -q 'AskUserQuestion' && printf '%s\n' "$CI_SECTION" | grep -qF 'lib/require-ci-check.sh'; then
  pass "/setup asks before making the CI check required, then runs lib/require-ci-check.sh"
else
  fail "/setup 5.4 CI is missing the AskUserQuestion offer or the require-ci-check.sh call"
fi
ask_line="$(printf '%s\n' "$CI_SECTION" | grep -n 'AskUserQuestion' | head -1 | cut -d: -f1 || true)"
run_line="$(printf '%s\n' "$CI_SECTION" | grep -nF 'lib/require-ci-check.sh' | head -1 | cut -d: -f1 || true)"
[ -n "$ask_line" ] && [ -n "$run_line" ] && [ "$ask_line" -lt "$run_line" ] && pass "the question comes before the call" || fail "require-ci-check.sh appears before the question"

echo "Template and its setup mirror"
cmp -s "$REPO_ROOT/templates/ci.yml" "$REPO_ROOT/skills/setup/templates/ci.yml" && pass "skills/setup/templates/ci.yml mirrors templates/ci.yml" || fail "ci.yml mirror differs"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
