#!/usr/bin/env bash
# tests/commands/test-command-sources.sh
# Content checks for command sources (#64): legacy redirect shims and /external-tools-health.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap '[ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
has() { grep -qF -e "$2" "$REPO_ROOT/$1"; }

# Legacy commands are short redirect shims (items 2-5 of #64 lived in their old bodies).
SHIM_MAX_LINES=30
check_shim() { # <file> <target command>
  local f="$1" target="$2" n
  echo "Legacy shim: $f -> $target"
  n=$(wc -l <"$REPO_ROOT/$f" | tr -d ' ')
  [ "$n" -le "$SHIM_MAX_LINES" ] && pass "$f is a short shim ($n lines)" || fail "$f is a short shim ($n lines > $SHIM_MAX_LINES)"
  has "$f" "deprecated" && pass "$f says it is deprecated" || fail "$f says it is deprecated"
  has "$f" "$target" && pass "$f redirects to $target" || fail "$f redirects to $target"
  if grep -qE -e 'npx metaswarm(@latest)? (install|changelog)' "$REPO_ROOT/$f"; then
    fail "$f has no nonexistent CLI commands"
  else
    pass "$f has no nonexistent CLI commands"
  fi
}
check_shim commands/metaswarm-setup.md /setup
check_shim commands/metaswarm-update-version.md /update

# /external-tools-health runs each adapter's health command and reports its fields (item 6).
F=commands/external-tools-health.md
echo "External tools health: $F"
for adapter in codex gemini; do
  has "$F" "$adapter.sh\" health" && pass "$F runs $adapter.sh health" || fail "$F runs $adapter.sh health"
done
for field in '"status"' '"auth_valid"' '"version"' '"model"'; do
  has "$F" "$field" && pass "$F reports $field" || fail "$F reports $field"
done
for adapter in codex gemini; do
  line=$(grep -F -e "$adapter.sh\" health ||" "$REPO_ROOT/$F" || true)
  ok=1
  for k in '"status":"error"' '"version":"unknown"' '"auth_valid":"unknown"' '"model":"unknown"'; do
    printf '%s' "$line" | grep -qF -e "$k" || ok=0
  done
  [ "$ok" = 1 ] && pass "$F $adapter fallback keeps every report field" || fail "$F $adapter fallback keeps every report field"
done
has "$F" "For a \`\"status\":\"error\"\` row" && pass "$F step 4 gives adapter errors their own remedy" || fail "$F step 4 gives adapter errors their own remedy"
has "$F" "adapter error" && pass "$F reports an adapter error as such" || fail "$F reports an adapter error as such"
if has "$F" "bash bin/external-tools-verify.sh"; then
  fail "$F does not run the repo self-test as a health check"
else
  pass "$F does not run the repo self-test as a health check"
fi

# Every command has frontmatter with a description, so plugin installs list it for the model
# (`claude plugin validate` flags commands without one). Mirrors follow via --sync.
echo "Command frontmatter"
for f in "$REPO_ROOT"/commands/*.md; do
  rel="commands/$(basename "$f")"
  if [ "$(head -1 "$f")" = "---" ] && awk 'NR==1{next} /^---$/{exit} /^description: .+/{found=1} END{exit found?0:1}' "$f"; then
    pass "$rel has a frontmatter description"
  else
    fail "$rel has a frontmatter description"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
