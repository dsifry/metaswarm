#!/usr/bin/env bash
# tests/hooks/test-explain-waiting.sh
# Tests for hooks/explain-waiting.sh (UserPromptSubmit hook: "E" explains what is waiting on the human)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/explain-waiting.sh"
PASS=0; FAIL=0; TOTAL=0

ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

prompt_json() { node -e 'process.stdout.write(JSON.stringify({hook_event_name:"UserPromptSubmit",prompt:process.argv[1]}))' "$1"; }

run_hook() { # stdin -> stdout; sets RC
  OUT=$(printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" 2>/dev/null); RC=$?
}

valid_trigger() { # name, prompt
  run_hook "$(prompt_json "$2")"
  if [ "$RC" -ne 0 ]; then bad "$1: exit $RC"; return; fi
  if printf '%s' "$OUT" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const o=JSON.parse(d).hookSpecificOutput;process.exit(o.hookEventName==="UserPromptSubmit"&&/WAITING-ON/.test(o.additionalContext)&&/guides\/waiting-on\.md/.test(o.additionalContext)?0:1)})' 2>/dev/null; then
    ok "$1 triggers with valid JSON"
  else bad "$1: output invalid or wrong: $OUT"; fi
}

silent() { # name, raw stdin
  run_hook "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "$1 is silent"; else bad "$1: rc=$RC out=$OUT"; fi
}

echo "explain-waiting hook"
[ -f "$HOOK" ] || { bad "hook script exists"; echo "Results: $PASS/$TOTAL passed, $FAIL failed"; exit 1; }
valid_trigger "E" "E"
valid_trigger "e" "e"
valid_trigger "padded ' E \\n'" $' E \n'
silent "Explain" "$(prompt_json "Explain")"
silent "EE" "$(prompt_json "EE")"
silent "e.g." "$(prompt_json "e.g.")"
silent "empty prompt" "$(prompt_json "")"
silent "empty stdin" ""
silent "malformed JSON" "{not json"
silent "missing prompt field" '{"hook_event_name":"UserPromptSubmit"}'

if node -e 'const h=require(process.argv[1]).hooks.UserPromptSubmit;const c=h.flatMap(m=>m.hooks).map(x=>x.command);process.exit(c.some(x=>x.includes("${CLAUDE_PLUGIN_ROOT}/hooks/explain-waiting.sh"))?0:1)' "$REPO_ROOT/hooks/hooks.json"; then ok "hooks.json registers UserPromptSubmit"; else bad "hooks.json registers UserPromptSubmit"; fi
[ -f "$REPO_ROOT/guides/waiting-on.md" ] && ok "guide exists" || bad "guide exists"

echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
