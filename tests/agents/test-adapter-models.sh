#!/usr/bin/env bash
# tests/agents/test-adapter-models.sh
# Adapters take their model from .metaswarm/models.yaml via --role (health works without codex/gemini installed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ADAPTERS="$REPO_ROOT/skills/external-tools/adapters"
FIX="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

N=0
# new_proj <models-fixture|none> <legacy-fixture|none>
new_proj() {
  N=$((N + 1))
  P="$TMP_BASE/p$N"
  mkdir -p "$P/.metaswarm"
  git -C "$P" init -q
  if [ "$1" != none ]; then cp "$FIX/$1" "$P/.metaswarm/models.yaml"; fi
  if [ "$2" != none ]; then cp "$FIX/$2" "$P/.metaswarm/external-tools.yaml"; fi
}

# run_adapter <tool> <args...>: sets OUT (stdout), ERR (stderr), RC
run_adapter() {
  local tool="$1"; shift
  RC=0
  (cd "$P" && bash "$ADAPTERS/$tool.sh" "$@" >"$TMP_BASE/out" 2>"$TMP_BASE/err") || RC=$?
  OUT="$(cat "$TMP_BASE/out")"
  ERR="$(cat "$TMP_BASE/err")"
}

model_of() { printf '%s' "$OUT" | grep -o '"model": *"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }
keys_of() { printf '%s' "$OUT" | grep -o '"[a-z_]*" *:' | tr -d ' ":' | sort | tr '\n' ' '; }

for tool in codex gemini; do
  case "$tool" in codex) DEF="gpt-5.3-codex"; ROLEM="codex-coder-test"; LEG="codex-legacy-test" ;;
                  gemini) DEF="pro"; ROLEM="gemini-coder-test"; LEG="gemini-legacy-test" ;; esac
  echo "== $tool"

  new_proj adapter-models.yaml none
  run_adapter "$tool" health --role coder
  check "$tool: health --role coder exits 0" "$RC"
  [ "$(model_of)" = "$ROLEM" ]; check "$tool: health --role coder reports models.yaml model" "$?"

  run_adapter "$tool" health --role planner
  [ "$(model_of)" = "$DEF" ]; check "$tool: role without $tool key reports built-in default" "$?"

  run_adapter "$tool" health
  [ "$(model_of)" = "$DEF" ]; check "$tool: health without --role reports built-in default" "$?"
  [ "$(keys_of)" = "auth_valid model status tool version " ]; check "$tool: health without --role keeps the same JSON keys" "$?"
  run_adapter "$tool" health --role coder
  [ "$(keys_of)" = "auth_valid model status tool version " ]; check "$tool: health --role keeps the same JSON keys" "$?"

  new_proj none legacy-external-tools.yaml
  run_adapter "$tool" health --role coder
  [ "$(model_of)" = "$DEF" ]; check "$tool: legacy adapters.$tool.model is no longer read (0.14.0), built-in default used" "$?"
  printf '%s' "$ERR" | grep -q "no longer read" && printf '%s' "$ERR" | grep -q ".metaswarm/models.yaml"
  check "$tool: legacy model key warns it is no longer read, naming .metaswarm/models.yaml" "$?"

  new_proj adapter-models.yaml legacy-external-tools.yaml
  run_adapter "$tool" health --role coder
  [ "$(model_of)" = "$ROLEM" ]; check "$tool: models.yaml wins over legacy" "$?"
  [ -z "$ERR" ]; check "$tool: no deprecation warning when models.yaml wins" "$?"

  new_proj adapter-models.yaml none
  run_adapter "$tool" health --role bogus
  [ "$RC" -ne 0 ]; check "$tool: unknown --role exits non-zero" "$?"
  printf '%s' "$ERR" | grep -q "unknown role" && printf '%s' "$ERR" | grep -q "bogus"
  check "$tool: unknown --role names the role in the message" "$?"
done

echo "Test: the resolved model is passed to the real CLI invocation (fake codex/gemini log argv)"
FAKE="$TMP_BASE/fakebin"; mkdir -p "$FAKE"
for t in codex gemini; do
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/%s.argv"\nif [ "${1:-}" = "--version" ]; then echo "%s 9.9.9"; exit 0; fi\necho "{}"\n' "$TMP_BASE" "$t" "$t" > "$FAKE/$t"; chmod +x "$FAKE/$t"
done
new_proj adapter-models.yaml none
printf 'do it\n' > "$P/prompt.md"
for t in codex gemini; do
  rm -f "$TMP_BASE/$t.argv"
  (cd "$P" && PATH="$FAKE:$PATH" OPENAI_API_KEY=x GEMINI_API_KEY=x bash "$ADAPTERS/$t.sh" implement --role coder --worktree "$P" --prompt-file "$P/prompt.md" >/dev/null 2>&1) || true
  (cd "$P" && PATH="$FAKE:$PATH" OPENAI_API_KEY=x GEMINI_API_KEY=x bash "$ADAPTERS/$t.sh" review --role adversarial-reviewer --worktree "$P" --rubric-file "$P/prompt.md" --spec-file "$P/prompt.md" >/dev/null 2>&1) || true
  want_impl="$(cd "$P" && bash "$REPO_ROOT/bin/metaswarm-agents.sh" resolve coder $t)"
  want_rev="$(cd "$P" && bash "$REPO_ROOT/bin/metaswarm-agents.sh" resolve adversarial-reviewer $t)"
  argv="$(cat "$TMP_BASE/$t.argv" 2>/dev/null || true)"
  echo "$argv" | grep -E "exec|-p|--prompt|--model|-m " | grep -q -E -- "(-m|--model) $want_impl( |\$)" && pass "$t implement invocation passes model $want_impl" || fail "$t implement invocation lacks model $want_impl: $argv"
  echo "$argv" | grep -q -E -- "(-m|--model) $want_rev( |\$)" && pass "$t review invocation passes model $want_rev" || fail "$t review invocation lacks model $want_rev: $argv"
done

echo "Test: codex with nothing configured passes no -m (user's ~/.codex/config.toml model applies)"
new_proj none none
printf 'do it\n' > "$P/prompt.md"
rm -f "$TMP_BASE/codex.argv"
(cd "$P" && PATH="$FAKE:$PATH" OPENAI_API_KEY=x bash "$ADAPTERS/codex.sh" implement --worktree "$P" --prompt-file "$P/prompt.md" >/dev/null 2>&1) || true
grep -E '^exec ' "$TMP_BASE/codex.argv" | grep -q -E -- '(^| )-m ' && fail "codex passed -m with nothing configured: $(grep -E '^exec ' "$TMP_BASE/codex.argv")" || pass "codex omits -m when no model is configured"

echo "Test: symlinked install layout (npm/Codex installer symlinks skills/<dir>) still finds the resolver"
LINKROOT="$TMP_BASE/agents-home/skills"; mkdir -p "$LINKROOT"
ln -s "$REPO_ROOT/skills/external-tools" "$LINKROOT/metaswarm-external-tools"
new_proj adapter-models.yaml none
want="$(cd "$P" && bash "$REPO_ROOT/bin/metaswarm-agents.sh" resolve coder codex)"
RC=0; OUT="$(cd "$P" && PATH="/usr/bin:/bin" bash "$LINKROOT/metaswarm-external-tools/adapters/codex.sh" health --role coder 2>"$TMP_BASE/err")" || RC=$?
[ "$(model_of)" = "$want" ] && pass "symlinked layout resolves role model ($want)" || fail "symlinked layout: got '$(model_of)', want '$want'"
RC=0; OUT="$(cd "$P" && PATH="/usr/bin:/bin" bash "$LINKROOT/metaswarm-external-tools/adapters/codex.sh" health --role bogus 2>"$TMP_BASE/err")" || RC=$?
[ "$RC" != 0 ] && pass "symlinked layout: unknown role fails" || fail "symlinked layout: unknown role should fail"

echo "Test: --role given but resolver not found warns instead of silently ignoring"
COPY="$TMP_BASE/copy/external-tools"; mkdir -p "$(dirname "$COPY")"; cp -R "$REPO_ROOT/skills/external-tools" "$COPY"
new_proj adapter-models.yaml none
RC=0; OUT="$(cd "$P" && PATH="/usr/bin:/bin" bash "$COPY/adapters/codex.sh" health --role coder 2>"$TMP_BASE/err")" || RC=$?
grep -q -i "metaswarm-agents.sh" "$TMP_BASE/err" && pass "warns when resolver missing" || fail "no warning when resolver missing"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
