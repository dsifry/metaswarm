#!/usr/bin/env bash
# tests/templates/test-ci-coverage-job.sh
# #97 item 1: templates/ci-coverage-job.yml is where /setup sends every stack it
# can't render a full ci.yml for (pnpm, yarn, bun, Poetry, uv, Pipenv, Java...).
# Its install step must pick the project's JavaScript package manager from the
# lockfile, and fail with a clear "add your toolchain" message otherwise,
# instead of always running `npm ci`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JOB="$REPO_ROOT/templates/ci-coverage-job.yml"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap 'rm -rf "${TMP:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

# install_body <job key>: the `run: |` body of that job's "Install dependencies" step, dedented.
install_body() {
  awk -v job="$1:" '
    $0 == job {j = 1; next}
    j && /^[a-z][a-z-]*:/ {exit}
    j && index($0, "- name: Install dependencies") {f = 1; next}
    f && /^ *run: \|/ {r = 1; match($0, /^ */); ind = RLENGTH + 2; next}
    f && /^ *run: / && !r {sub(/^ *run: /, ""); print; exit}
    r { if ($0 !~ /^ *$/ && match($0, /^ */) && RLENGTH < ind) exit; print substr($0, ind + 1) }
  ' "$JOB"
}

mkdir -p "$TMP/bin"
for t in corepack pnpm yarn bun npm; do
  printf '#!/bin/sh\necho "%s $*" >> "$LOG"\n' "$t" > "$TMP/bin/$t"
  chmod +x "$TMP/bin/$t"
done

for job in coverage-simple coverage-merge; do
  echo "$job: install step follows the lockfile"
  body="$(install_body "$job")"
  if [ -z "$body" ]; then fail "$job: no Install dependencies step"; continue; fi
  if [ "$(printf '%s\n' "$body" | tr -d '[:space:]')" = "npmci" ]; then
    fail "$job: install step is still a bare npm ci"
  fi
  # case: files to create | command the step must run
  while IFS='|' read -r files want; do
    P="$TMP/$job-$(echo "$files" | tr ' ./' '___')"; mkdir -p "$P"
    for f in $files; do
      case "$f" in
        berry:*) printf '__metadata:\n  version: 8\n' > "$P/${f#berry:}" ;;
        *) : > "$P/$f" ;;
      esac
    done
    export LOG="$P/log"; : > "$LOG"
    rc=0; (cd "$P" && PATH="$TMP/bin:$PATH" bash -c "set -e; $body") >"$P/out" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "$want" "$LOG"; then
      pass "$job: [$files] runs '$want'"
    else
      fail "$job: [$files] expected '$want' (rc=$rc): log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$P/out")"
    fi
  done <<'CASES'
package.json pnpm-lock.yaml|pnpm install --frozen-lockfile
package.json yarn.lock|yarn install --frozen-lockfile
package.json yarn.lock .yarnrc.yml|yarn install --immutable
package.json berry:yarn.lock|yarn install --immutable
package.json bun.lockb|bun install --frozen-lockfile
package.json bun.lock|bun install --frozen-lockfile
package.json package-lock.json|npm ci
package.json|npm install
CASES
  grep -q 'corepack enable' <<<"$body" && pass "$job: pnpm and yarn come from corepack" || fail "$job: no corepack enable for pnpm/yarn"

  # Not a JavaScript project: the step must fail and say what to do.
  P="$TMP/$job-nojs"; mkdir -p "$P"; : > "$P/pyproject.toml"
  export LOG="$P/log"; : > "$LOG"
  rc=0; (cd "$P" && PATH="$TMP/bin:$PATH" bash -c "set -e; $body") >"$P/out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && grep -qi 'toolchain' "$P/out" && [ ! -s "$LOG" ]; then
    pass "$job: without package.json it fails and asks for the project's toolchain steps"
  else
    fail "$job: non-JS project (rc=$rc): $(tr '\n' ' ' < "$P/out")"
  fi
done

echo "Header explains how to adapt the job"
grep -qi 'poetry' "$JOB" && grep -qi 'uv sync' "$JOB" && grep -qi 'pipenv' "$JOB" \
  && pass "header shows Poetry, uv and Pipenv install lines" || fail "header doesn't show Python tool install lines"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert d["coverage-simple"]["steps"] and d["coverage-merge"]["steps"]' "$JOB" \
    && pass "job template is valid YAML" || fail "job template is not valid YAML"
fi
cmp -s "$JOB" "$REPO_ROOT/skills/setup/templates/ci-coverage-job.yml" && pass "setup mirror matches" || fail "skills/setup/templates/ci-coverage-job.yml differs"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
