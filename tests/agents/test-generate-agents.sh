#!/usr/bin/env bash
# tests/agents/test-generate-agents.sh
# Tests for bin/metaswarm-agents.sh (generate / check / clean) and models.yaml parsing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOL="$REPO_ROOT/bin/metaswarm-agents.sh"
FIXTURE="$SCRIPT_DIR/fixtures/models.yaml"
ROLES="design-reviewer plan-reviewer researcher planner coder adversarial-reviewer pr-shepherd-agent knowledge-curator-agent"
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/.claude-plugin/plugin.json" | head -1)"
PASS=0
FAIL=0
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

N=0
new_proj() {
  N=$((N + 1))
  P="$TMP_BASE/p$N"
  mkdir -p "$P/.metaswarm"
  git -C "$P" init -q
  if [ "${1:-fixture}" = "fixture" ]; then cp "$FIXTURE" "$P/.metaswarm/models.yaml"; fi
}

# run <args...> in $P; sets OUT and RC
run() {
  RC=0
  OUT="$(cd "$P" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

agent_file() { echo "$P/.claude/agents/metaswarm-$1.md"; }
plugin_model() { sed -n 's/^model: //p' "$REPO_ROOT/agents/$1.md" | head -1; }
count_agents() { ls "$P/.claude/agents" 2>/dev/null | wc -l | tr -d ' '; }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1; }

echo "Running metaswarm-agents.sh tests..."

echo "Test 1: generate writes expected files"
new_proj
run generate
check "generate exits 0" "$RC"
all_present=0
for r in $ROLES; do [ -f "$(agent_file $r)" ] || all_present=1; done
check "one file per roster role" "$all_present"
f="$(agent_file coder)"
grep -q '^name: metaswarm-coder$' "$f" && pass "name is project-scoped" || fail "name is project-scoped"
grep -q '^model: haiku$' "$f" && pass "model comes from models.yaml" || fail "model comes from models.yaml"
desc="$(sed -n 's/^description: //p' "$REPO_ROOT/agents/coder.md" | head -1)"
grep -qF "description: $desc" "$f" && pass "description from plugin" || fail "description from plugin"
f="$(agent_file design-reviewer)"
grep -q '^disallowedTools: Write, Edit, NotebookEdit$' "$f" && pass "disallowedTools from plugin" || fail "disallowedTools from plugin"
body_line="$(sed -n '/^# Design Reviewer/p' "$REPO_ROOT/agents/design-reviewer.md" | head -1)"
[ "$(grep -cF "$body_line" "$f")" = "1" ] && pass "plugin body copied once" || fail "plugin body copied once"
hdr="$(grep '^<!-- generated-by: metaswarm ' "$f")"
case "$hdr" in
  "<!-- generated-by: metaswarm v$VERSION sha256:"*" — edit .metaswarm/models.yaml, not this file -->") pass "header has plugin version" ;;
  *) fail "header has plugin version: $hdr" ;;
esac
# header sits right after the frontmatter; hash covers everything else
second_dash="$(grep -n '^---$' "$f" | sed -n '2p' | cut -d: -f1)"
sed -n "$((second_dash + 1))p" "$f" | grep -q '^<!-- generated-by: metaswarm ' && pass "header is first body line" || fail "header is first body line"
want="$(awk '!d && /^<!-- generated-by: metaswarm /{d=1;next}1' "$f" | sha)"
case "$hdr" in *"sha256:$want "*) pass "header hash covers the rest of the file" ;; *) fail "header hash covers the rest of the file" ;; esac

echo "Test 2: second run is byte-identical"
cp -R "$P/.claude/agents" "$TMP_BASE/snap$N"
run generate
check "second generate exits 0" "$RC"
diff -r "$P/.claude/agents" "$TMP_BASE/snap$N" >/dev/null && pass "output byte-identical" || fail "output byte-identical"

echo "Test 3: defaults and overrides"
[ "$(sed -n 's/^model: //p' "$(agent_file researcher)")" = "$(plugin_model researcher)" ] && pass "missing role gets plugin default" || fail "missing role gets plugin default"
grep -q '^model: opus$' "$(agent_file design-reviewer)" && pass "reviewer set to opus is opus" || fail "reviewer set to opus is opus"
grep -q '^model: claude-opus-4-5$' "$(agent_file plan-reviewer)" && pass "full model id accepted" || fail "full model id accepted"

echo "Test 4: parse errors exit 2 with line number and write nothing"
parse_case() { # desc, expected line, yaml
  new_proj none
  printf '%b' "$3" > "$P/.metaswarm/models.yaml"
  run generate
  [ "$RC" = "2" ] && has "models.yaml:$2:" && [ ! -d "$P/.claude/agents" ] && pass "$1" || fail "$1 (rc=$RC out=$OUT)"
}
parse_case "flow map" 2 'roles:\n  coder: {claude: opus}\n'
parse_case "tab" 2 'roles:\n\tcoder:\n'
parse_case "odd indentation" 2 'roles:\n coder:\n'
parse_case "too-deep indentation" 4 'roles:\n  coder:\n    claude: opus\n      x: y\n'
parse_case "unknown top-level key" 1 'bogus:\n'
parse_case "unknown role" 2 'roles:\n  validator:\n    claude: opus\n'
parse_case "unknown host key" 3 'roles:\n  coder:\n    openai: gpt\n'
parse_case "bad claude value" 3 'roles:\n  coder:\n    claude: gpt-4\n'
parse_case "non-integer after_failures" 3 'escalation:\n  coder:\n    after_failures: two\n'

echo "Test 5: empty or comment-only models.yaml means defaults"
new_proj none
printf '# only a comment\n\n' > "$P/.metaswarm/models.yaml"
run generate
check "empty-ish file exits 0" "$RC"
ok=0
for r in $ROLES; do [ "$(sed -n 's/^model: //p' "$(agent_file $r)")" = "$(plugin_model $r)" ] || ok=1; done
check "all roles use plugin defaults" "$ok"

echo "Test 6: no models.yaml"
new_proj none
run generate
[ "$RC" = "0" ] && has "no models.yaml — using plugin defaults; run /setup to customize" && [ ! -d "$P/.claude" ] && pass "message, no writes, exit 0" || fail "no models.yaml (rc=$RC out=$OUT)"

echo "Test 7: check"
new_proj
run generate
run check
check "clean tree exits 0" "$RC"
f="$(agent_file coder)"
echo "extra" >> "$f"
run check
[ "$RC" = "1" ] && has "hand-edited" && has "metaswarm-coder.md" && pass "hand-edited detected" || fail "hand-edited detected ($OUT)"
run generate
[ "$RC" = "1" ] && has "metaswarm-coder.md" && pass "generate refuses hand-edited file" || fail "generate refuses hand-edited file ($OUT)"
grep -q '^extra$' "$f" && pass "hand edit preserved without --force" || fail "hand edit preserved without --force"
run generate --force
[ "$RC" = "0" ] && ! grep -q '^extra$' "$f" && pass "--force overwrites hand-edited file" || fail "--force overwrites ($OUT)"
# stale: config changed
sed -i.bak 's/claude: haiku/claude: sonnet/' "$P/.metaswarm/models.yaml"; rm -f "$P/.metaswarm/models.yaml.bak"
run check
[ "$RC" = "1" ] && has "stale" && has "metaswarm-coder.md" && pass "config change is stale" || fail "config change is stale ($OUT)"
run generate
run check
check "regenerate clears stale" "$RC"
# stale: version in header differs (hash recomputed so it is not hand-edited)
rest="$(awk '!d && /^<!-- generated-by: metaswarm /{d=1;next}1' "$f")"
newhash="$(printf '%s\n' "$rest" | sha)"
sed -i.bak "s/^<!-- generated-by: metaswarm v[^ ]* sha256:[0-9a-f]*/<!-- generated-by: metaswarm v0.0.1 sha256:$newhash/" "$f"; rm -f "$f.bak"
run check
[ "$RC" = "1" ] && has "stale" && pass "old header version is stale" || fail "old header version is stale ($OUT)"
run generate
# missing
rm "$(agent_file planner)"
run check
[ "$RC" = "1" ] && has "missing" && has "metaswarm-planner.md" && pass "missing detected" || fail "missing detected ($OUT)"
run generate
# orphan
cp "$(agent_file coder)" "$P/.claude/agents/metaswarm-validator.md"
run check
[ "$RC" = "1" ] && has "orphan" && has "metaswarm-validator.md" && pass "orphan detected" || fail "orphan detected ($OUT)"

echo "Test 8: generate deletes only header-bearing orphans"
printf -- '---\nname: metaswarm-ghost\ndescription: mine\n---\nuser file\n' > "$P/.claude/agents/metaswarm-ghost.md"
run generate
[ ! -e "$P/.claude/agents/metaswarm-validator.md" ] && pass "header orphan deleted" || fail "header orphan deleted"
[ -e "$P/.claude/agents/metaswarm-ghost.md" ] && pass "headerless orphan-named file kept" || fail "headerless orphan-named file kept"

echo "Test 9: same-named user file is never overwritten"
new_proj
mkdir -p "$P/.claude/agents"
printf -- '---\nname: metaswarm-coder\ndescription: mine\n---\nuser coder\n' > "$P/.claude/agents/metaswarm-coder.md"
run generate
[ "$RC" = "1" ] && has "metaswarm-coder.md" && pass "exits 1 naming the file" || fail "exits 1 naming the file ($OUT)"
grep -q '^user coder$' "$P/.claude/agents/metaswarm-coder.md" && pass "user file untouched" || fail "user file untouched"
run generate --force
[ "$RC" = "1" ] && grep -q '^user coder$' "$P/.claude/agents/metaswarm-coder.md" && pass "untouched even with --force" || fail "untouched even with --force"

echo "Test 10: clean removes only header files"
new_proj
run generate
printf 'mine\n' > "$P/.claude/agents/my-own.md"
printf -- '---\nname: metaswarm-coder-custom\n---\nmine\n' > "$P/.claude/agents/metaswarm-custom.md"
run clean
check "clean exits 0" "$RC"
left="$(ls "$P/.claude/agents" | tr '\n' ' ')"
[ "$left" = "metaswarm-custom.md my-own.md " ] && pass "only generated files removed" || fail "only generated files removed: $left"

echo "Test 11: resolve_role_model is sourceable"
new_proj
got="$(cd "$P" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash -c ". '$TOOL'; resolve_role_model design-reviewer codex; resolve_role_model coder claude; resolve_role_model researcher claude; resolve_role_model researcher codex")"
[ "$got" = "$(printf 'gpt-5.3-codex\nhaiku\n%s\n' "$(plugin_model researcher)")" ] && pass "resolves config, then plugin default, empty for unset codex" || fail "resolve_role_model: $got"

echo "Test 12: check flags a same-named user-authored file (same verdict as generate)"
new_proj
run generate
printf -- '---\nname: metaswarm-coder\ndescription: mine\n---\nuser coder\n' > "$P/.claude/agents/metaswarm-coder.md"
run check
[ "$RC" = "1" ] && has "metaswarm-coder.md" && pass "check exits 1 naming the conflicting user file" || fail "check on user-authored conflict: rc=$RC $OUT"

echo "Test 13: resolve subcommand (process call, safe for adapters)"
new_proj
run resolve coder claude
[ "$RC" = "0" ] && [ "$OUT" = "haiku" ] && pass "resolve coder claude -> haiku" || fail "resolve coder claude: rc=$RC '$OUT'"
run resolve design-reviewer codex
[ "$OUT" = "gpt-5.3-codex" ] && pass "resolve design-reviewer codex" || fail "resolve design-reviewer codex: '$OUT'"
run resolve nosuchrole claude
[ "$RC" != "0" ] && pass "resolve unknown role fails" || fail "resolve unknown role should fail"

echo "Test 14: skills/commands resolve the script path (PLUGIN_ROOT is not set in other skills)"
BAD=""
for f in skills/status/SKILL.md skills/migrate/SKILL.md skills/setup/SKILL.md commands/update.md commands/metaswarm-update-version.md commands/metaswarm-setup.md; do
  grep -n 'metaswarm-agents.sh' "$REPO_ROOT/$f" | grep -v 'Do NOT copy' | grep -v -F 'command -v metaswarm-agents.sh' | grep -q . && BAD="$BAD $f"
done
[ -z "$BAD" ] && pass "every call site resolves metaswarm-agents.sh via PATH with plugin-root fallback" || fail "unresolved \${PLUGIN_ROOT} call sites:$BAD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
