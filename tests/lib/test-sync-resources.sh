#!/usr/bin/env bash
# tests/lib/test-sync-resources.sh
# Tests for sync-resources.js build script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
  fi
}

# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
CLEANUP=""
trap 'eval "$CLEANUP"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

echo "Testing sync-resources.js..."

# Test 0: .claude/commands/ mirrors every commands/*.md (issue #61).
# In this repo, project commands are the only copies Claude Code loads, so drift
# silently serves stale workflow rules. Runs before --sync so drift is caught.
echo "Test 0: .claude/commands mirrors commands/*.md (minus exclusions)"
# Excluded: status.md shadows Claude Code's built-in /status; metaswarm-setup and
# metaswarm-update-version are npm-era legacy commands (removed by skills/migrate).
MIRROR_EXCLUDE=" status.md metaswarm-setup.md metaswarm-update-version.md "
for src in "$REPO_ROOT"/commands/*.md; do
  name="$(basename "$src")"
  if [[ "$MIRROR_EXCLUDE" == *" $name "* ]]; then
    if [ -e "$REPO_ROOT/.claude/commands/$name" ]; then result="PRESENT"; else result="ABSENT"; fi
    assert_eq ".claude/commands/$name is excluded from the mirror" "ABSENT" "$result"
    continue
  fi
  if cmp -s "$src" "$REPO_ROOT/.claude/commands/$name"; then
    result="SAME"
  else
    result="DIFF"
  fi
  assert_eq ".claude/commands/$name matches commands/$name" "SAME" "$result"
done

# Test 0a: no project command shadows a Claude Code built-in slash command
echo "Test 0a: no .claude/commands file shadows a built-in command"
for builtin in status help clear compact config init review memory model cost doctor login logout permissions agents hooks mcp resume export context usage security-review; do
  if [ -e "$REPO_ROOT/.claude/commands/$builtin.md" ]; then result="SHADOWS"; else result="OK"; fi
  assert_eq ".claude/commands/$builtin.md does not shadow /$builtin" "OK" "$result"
done

# Tests 0b, 0c, 2 and 3 run --sync or mutate files, so they run in an isolated copy of
# the repo: the developer's checkout is never written to (only read-only --check below).
SANDBOX="$(mktemp -d)"
CLEANUP='rm -rf "${SANDBOX:?}"'
tar -C "$REPO_ROOT" --exclude=./.git --exclude=./node_modules --exclude=./.goodtogo -cf - . | tar -C "$SANDBOX" -xf -
run_sync() { # <mode>: runs sync-resources in the sandbox; sets SYNC_RC, SYNC_OUT
  SYNC_RC=0
  SYNC_OUT=$(cd "$SANDBOX" && node lib/sync-resources.js "$1" 2>&1) || SYNC_RC=$?
}
expect_rc() { # <desc> <expected rc>: asserts SYNC_RC, printing the output on failure
  assert_eq "$1" "$2" "$SYNC_RC"
  [ "$SYNC_RC" = "$2" ] || printf '    sync output:\n%s\n' "$SYNC_OUT"
}

# Test 0b: --check detects drift in a mirrored command
echo "Test 0b: --check fails when a mirrored command drifts"
printf '\ndrift\n' >> "$SANDBOX/.claude/commands/prime.md"
run_sync --check
expect_rc "Check fails on drifted .claude/commands copy" "1"
run_sync --sync
expect_rc "Sync repairs the drifted copy" "0"
if cmp -s "$SANDBOX/commands/prime.md" "$SANDBOX/.claude/commands/prime.md"; then result="SAME"; else result="DIFF"; fi
assert_eq "Drifted copy restored from source" "SAME" "$result"

# Test 0c: orphaned mirrors (#64). A .claude/commands/*.md with no source in commands/
# and not on the exclusion list is an orphan: --check reports it, --sync removes it.
# Excluded names and non-.md files are never touched.
echo "Test 0c: orphaned .claude/commands mirrors"
CMDS="$SANDBOX/.claude/commands"
printf 'stale mirror\n' > "$CMDS/zz-orphan.md"
run_sync --check
expect_rc "--check fails on an orphaned mirror" "1"
if printf '%s' "$SYNC_OUT" | grep -qF -e 'ORPHAN: .claude/commands/zz-orphan.md'; then result="REPORTED"; else result="SILENT"; fi
assert_eq "--check names the orphan" "REPORTED" "$result"
printf 'legacy copy\n' > "$CMDS/metaswarm-setup.md"
printf 'not a command\n' > "$CMDS/zz-notes.txt"
run_sync --sync
expect_rc "--sync succeeds" "0"
if [ -e "$CMDS/zz-orphan.md" ]; then result="KEPT"; else result="REMOVED"; fi
assert_eq "--sync removes the orphan" "REMOVED" "$result"
if [ -e "$CMDS/metaswarm-setup.md" ]; then result="KEPT"; else result="REMOVED"; fi
assert_eq "--sync leaves an excluded name alone" "KEPT" "$result"
if [ -e "$CMDS/zz-notes.txt" ]; then result="KEPT"; else result="REMOVED"; fi
assert_eq "--sync leaves non-.md files alone" "KEPT" "$result"
if [ -e "$CMDS/prime.md" ]; then result="KEPT"; else result="REMOVED"; fi
assert_eq "--sync keeps mirrors that have a source" "KEPT" "$result"
run_sync --check
if printf '%s' "$SYNC_OUT" | grep -qF -e 'ORPHAN'; then result="FLAGGED"; else result="CLEAN"; fi
assert_eq "--check does not flag excluded or non-.md files" "CLEAN" "$result"

# Test 0d: the orphan finder takes its root, mirror settings and fs as parameters (DI).
echo "Test 0d: findOrphanedCommandMirrors with injected root and mirror"
DI_ROOT="$SANDBOX/di"
mkdir -p "$DI_ROOT/src" "$DI_ROOT/dst"
: > "$DI_ROOT/src/a.md"; : > "$DI_ROOT/dst/a.md"; : > "$DI_ROOT/dst/b.md"; : > "$DI_ROOT/dst/skip.md"
DI_OUT=$(cd "$REPO_ROOT" && node -e '
  const { findOrphanedCommandMirrors } = require("./lib/sync-resources.js");
  const out = findOrphanedCommandMirrors(process.argv[1], { src: "src", dest: "dst", exclude: ["skip.md"] });
  console.log(JSON.stringify(out));' "$DI_ROOT" 2>&1) || true
assert_eq "Injected root/mirror: only the unsourced, non-excluded file" '["dst/b.md"]' "$DI_OUT"

# Test 1: Check mode should pass when files are in sync (read-only, real checkout)
echo "Test 1: Check mode passes when synced"
if (cd "$REPO_ROOT" && node lib/sync-resources.js --check >/dev/null 2>&1); then
  result="PASS"
else
  result="FAIL"
fi
assert_eq "Check mode passes" "PASS" "$result"

# Test 2: Sync mode runs without error (sandbox)
echo "Test 2: Sync mode runs without error"
run_sync --sync
expect_rc "Sync mode succeeds" "0"

# Test 3: After syncing, check mode should still pass (sandbox)
echo "Test 3: Check after sync still passes"
run_sync --check
expect_rc "Check after sync passes" "0"

# Test 4: No arguments prints usage and exits non-zero
echo "Test 4: No arguments prints usage"
result=$(cd "$REPO_ROOT" && node lib/sync-resources.js 2>&1 || true)
TOTAL=$((TOTAL + 1))
if echo "$result" | grep -q "Usage"; then
  PASS=$((PASS + 1))
  echo "  PASS: Prints usage without arguments"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Expected usage message, got: $result"
fi

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
