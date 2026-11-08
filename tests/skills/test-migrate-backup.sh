#!/usr/bin/env bash
# tests/skills/test-migrate-backup.sh
# #90: the migrate skill moves untracked legacy files to a timestamped backup
# folder instead of deleting them, and its Rollback section restores them.
# The test runs the skill's own bash snippets against a scratch git repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$REPO_ROOT/skills/migrate/SKILL.md"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK=""
# bash 3.2 exits with the EXIT trap's status (0) when `set -u` aborts the script,
# so a crash would look like a pass. DONE is set only after the summary runs.
DONE=0
trap '[ -n "$WORK" ] && rm -rf "${WORK:?}"; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

# snippet <marker line>: the first ```bash block after the line that starts with
# the marker.
snippet() {
  awk -v m="$1" 'index($0, m) == 1 {f = 1; next} f && /^```bash$/ {g = 1; next} g && /^```$/ {exit} g' "$SKILL"
}

echo "Migrate skill: untracked legacy files are backed up, not deleted"
BACKUP_SNIP="$(snippet '**Untracked files**')"
RESTORE_SNIP="$(snippet '**Restore untracked files**')"
if [ -n "$BACKUP_SNIP" ]; then pass "Step 7 has a backup snippet for untracked files"; else fail "Step 7 has no bash snippet after **Untracked files**"; fi
if [ -n "$RESTORE_SNIP" ]; then pass "Rollback has a restore snippet"; else fail "Rollback has no bash snippet after **Restore untracked files**"; fi
if printf '%s\n' "$BACKUP_SNIP" | grep -qE '(^|[^a-z])rm -f'; then fail "backup snippet still deletes with rm -f"; else pass "backup snippet does not delete with rm -f"; fi
if grep -nE '^\*\*Untracked files\*\*.*rm -f' "$SKILL" >/dev/null; then fail "Step 7 still tells the agent to rm -f untracked files"; else pass "Step 7 no longer says rm -f for untracked files"; fi

if [ -n "$BACKUP_SNIP" ] && [ -n "$RESTORE_SNIP" ]; then
  WORK="$(mktemp -d)"
  (
    cd "$WORK"
    git init -q
    mkdir -p .claude/rubrics ".claude/plugins/metaswarm/sub dir" .metaswarm
    printf 'tracked\n' > .claude/rubrics/tracked.md
    git add . && git -c user.name=t -c user.email=t@t commit -q -m init
    printf 'rubric\n' > .claude/rubrics/untracked.md
    printf 'nested\n' > ".claude/plugins/metaswarm/sub dir/file one.md"
    mkdir -p .claude/guides && printf 'guide\n' > .claude/guides/g.md
    ln -s untracked.md .claude/rubrics/link.md
  )
  cp "$WORK/.claude/rubrics/untracked.md" "$WORK/expect-1"
  cp "$WORK/.claude/plugins/metaswarm/sub dir/file one.md" "$WORK/expect-2"
  # The agent fills in the confirmed untracked files; the snippet marks the list
  # with UNTRACKED=(...).
  RUN_BACKUP="$(printf '%s\n' "$BACKUP_SNIP" | sed -E "s#^UNTRACKED=\(.*\)\$#UNTRACKED=(.claude/rubrics/untracked.md '.claude/plugins/metaswarm/sub dir/file one.md' .claude/guides/g.md .claude/rubrics/link.md)#")"
  if printf '%s\n' "$RUN_BACKUP" | grep -q "file one.md"; then pass "backup snippet takes the file list as UNTRACKED=(...)"; else fail "backup snippet has no UNTRACKED=(...) line to fill in"; fi
  rc=0; (cd "$WORK" && bash -c "set -euo pipefail; $RUN_BACKUP") >"$WORK/backup.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && pass "backup snippet runs" || fail "backup snippet failed (rc=$rc): $(cat "$WORK/backup.out")"
  [ ! -e "$WORK/.claude/rubrics/untracked.md" ] && [ ! -e "$WORK/.claude/plugins/metaswarm/sub dir/file one.md" ] \
    && pass "untracked files are gone from their legacy paths" || fail "untracked files are still at their legacy paths"
  BDIR="$(cd "$WORK" && ls -d .metaswarm/migrate-backup-* 2>/dev/null | head -1 || true)"
  if [ -n "$BDIR" ] && cmp -s "$WORK/expect-1" "$WORK/$BDIR/.claude/rubrics/untracked.md" \
    && cmp -s "$WORK/expect-2" "$WORK/$BDIR/.claude/plugins/metaswarm/sub dir/file one.md"; then
    pass "files are kept under .metaswarm/migrate-backup-<timestamp>/ at their original paths"
  else
    fail "backup folder missing or contents differ (found: ${BDIR:-none})"
  fi
  [ -f "$WORK/.claude/rubrics/tracked.md" ] && pass "tracked files are left for git rm" || fail "backup snippet touched a tracked file"
  if grep -qF "$BDIR" "$WORK/backup.out" 2>/dev/null || grep -q 'migrate-backup-' "$WORK/backup.out"; then pass "backup snippet prints where the files went"; else fail "backup snippet doesn't print the backup folder"; fi

  if [ -z "$(git -C "$WORK" status --porcelain --untracked-files=all -- .metaswarm)" ]; then
    pass "git ignores the backup folder, so it can't be committed by accident"
  else
    fail "the backup folder shows up in git status: $(git -C "$WORK" status --porcelain --untracked-files=all -- .metaswarm | tr '\n' ' ')"
  fi
  # A file re-created at a legacy path since the backup must not be overwritten.
  printf 'recreated\n' > "$WORK/.claude/guides/g.md"

  RUN_RESTORE="$(printf '%s\n' "$RESTORE_SNIP" | sed "s#<timestamp>#${BDIR#.metaswarm/migrate-backup-}#g")"
  rc=0; (cd "$WORK" && bash -c "set -euo pipefail; $RUN_RESTORE") >"$WORK/restore.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && pass "restore snippet runs" || fail "restore snippet failed (rc=$rc): $(cat "$WORK/restore.out")"
  if cmp -s "$WORK/expect-1" "$WORK/.claude/rubrics/untracked.md" \
    && cmp -s "$WORK/expect-2" "$WORK/.claude/plugins/metaswarm/sub dir/file one.md"; then
    pass "restore puts every file back byte for byte"
  else
    fail "restore did not put the files back"
  fi
  if [ "$(cat "$WORK/.claude/guides/g.md")" = "recreated" ] && grep -q 'g.md' "$WORK/restore.out"; then
    pass "restore skips, and reports, a file that exists again"
  else
    fail "restore overwrote a re-created file or didn't report it"
  fi
  [ ! -e "$WORK/.gitignore" ] && pass "restore doesn't copy the backup's .gitignore to the repo root" || fail "restore created a root .gitignore"
  if [ -L "$WORK/.claude/rubrics/link.md" ] && [ "$(readlink "$WORK/.claude/rubrics/link.md")" = "untracked.md" ]; then
    pass "restore brings a symbolic link back as a link"
  else
    fail "restore did not bring the symbolic link back as a link"
  fi
  grep -q 'delete the folder' "$WORK/restore.out" && pass "a clean restore says the folder can go" || fail "a clean restore didn't print its completion line"

  # One file can't go back (its parent is now a regular file) and a later one
  # can: the restore must say so and must not suggest deleting the backup.
  rm -r -f "${WORK:?}/.claude/plugins/metaswarm/sub dir"
  rm -f "${WORK:?}/.claude/rubrics/untracked.md"
  printf 'blocker\n' > "$WORK/.claude/plugins/metaswarm/sub dir"
  rc=0; (cd "$WORK" && bash -c "set -euo pipefail; $RUN_RESTORE") >"$WORK/restore2.out" 2>&1 || rc=$?
  if grep -qi 'not restored' "$WORK/restore2.out" && ! grep -q 'delete the folder' "$WORK/restore2.out"; then
    pass "a partial restore reports what failed and keeps the backup"
  else
    fail "a partial restore looked successful: $(tr '\n' ' ' < "$WORK/restore2.out")"
  fi
  cmp -s "$WORK/expect-1" "$WORK/.claude/rubrics/untracked.md" && pass "files after the failed one are still restored" || fail "a failure stopped the remaining files from being restored"
fi

echo "Migrate skill: the safety notes match the behaviour"
if grep -qE 'Untracked files.*rm -f.*not in git' "$SKILL"; then fail "Rollback still says rm -f'd untracked files can't be restored"; else pass "Rollback no longer says untracked files are lost"; fi
grep -q 'migrate-backup-' <(sed -n '/^## IMPORTANT: Safety/,/^---$/p' "$SKILL") && pass "the Reversible note names the backup folder" || fail "the Reversible note doesn't mention the backup folder"
grep -q 'migrate-backup-' <(sed -n '/^## Step 10/,/^---$/p' "$SKILL") && pass "the post-migration summary names the backup folder" || fail "the post-migration summary doesn't name the backup folder"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ] || exit 1
