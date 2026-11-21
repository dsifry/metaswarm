#!/usr/bin/env bash
# hooks/explain-waiting.sh
# UserPromptSubmit hook for metaswarm plugin.
# When the user's prompt is exactly "E" or "e", injects instructions telling the
# agent to explain the next item waiting on the human (see guides/waiting-on.md).
# Any other prompt: no output. Never fails the prompt.

# Read stdin (hook JSON); tolerate empty/missing input.
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# Extract .prompt with jq or node (same optional deps as session-start.sh).
prompt=""
if command -v jq >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)
elif command -v node >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const p=JSON.parse(d).prompt;if(typeof p==="string")process.stdout.write(p)}catch{}})' 2>/dev/null || true)
else
  exit 0
fi

# Trim surrounding whitespace.
trimmed="$(printf '%s' "$prompt" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
case "$trimmed" in
  E|e) ;;
  *) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"The user typed just \"E\". This is NOT an answer to any pending question; do not treat it as a choice, approval or confirmation. They are asking you to explain what is waiting on THEM, one item at a time (convention: guides/waiting-on.md in the metaswarm plugin). Find the latest WAITING-ON: line you ended a turn with and its YOU: items (the ones the human must act on). If this is the first E after that line, explain item 1; each further E in a row moves to the next item. For the current item, in plain language: (1) what it is, (2) why it is needed, (3) the choices as a numbered list, recommended first, each with pros/cons, or the exact action/command to run, and (4) what happens if they do nothing. End with exactly: Item k of n - type E for the next. After the last item, say so and restate the full YOU list briefly. If there are no YOU: items, reply only: Nothing is waiting on you."}}
JSON
exit 0
