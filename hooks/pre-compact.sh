#!/usr/bin/env bash
# hooks/pre-compact.sh
# PreCompact hook — reads session state + memory files and injects them
# as additionalContext so critical info survives context compaction.
#
# Also called by SessionStart (after compaction) to re-inject memory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${extensionPath:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
PROJECT_DIR="$(pwd)"

# --- Collect memory context ---
context_parts=()

# 1. Session state (task, phase, progress)
state_file="${PROJECT_DIR}/.metaswarm/session-state.json"
if [ -f "$state_file" ]; then
  if command -v node >/dev/null 2>&1; then
    state_summary=$(node -e "
      try {
        const s = JSON.parse(require('fs').readFileSync('$state_file', 'utf8'));
        if (s.task) {
          let out = '## Session Recovery State';
          out += '\n- Task: ' + s.task;
          if (s.phase) out += '\n- Phase: ' + s.phase;
          if (s.completedSteps && s.completedSteps.length > 0)
            out += '\n- Completed: ' + s.completedSteps.join(', ');
          if (s.nextSteps && s.nextSteps.length > 0)
            out += '\n- Next: ' + s.nextSteps.join(', ');
          if (s.fileScope && s.fileScope.length > 0)
            out += '\n- Files: ' + s.fileScope.join(', ');
          if (s.blockedBy) out += '\n- BLOCKED: ' + s.blockedBy;
          if (s.lastUpdated) out += '\n- State saved: ' + s.lastUpdated;
          console.log(out);
        }
      } catch {}
    " 2>/dev/null || true)
    if [ -n "$state_summary" ]; then
      context_parts+=("$state_summary")
    fi
  fi
fi

# 2. Memory files (active-state, decisions, gotchas, feedback)
memory_dir="${PROJECT_DIR}/.metaswarm/memory"
if [ -d "$memory_dir" ]; then
  for memfile in active-state.md decisions.md gotchas.md feedback.md; do
    filepath="${memory_dir}/${memfile}"
    if [ -f "$filepath" ]; then
      # Skip template-only files (templates are < 350 bytes)
      byte_count=$(wc -c < "$filepath" 2>/dev/null | tr -d ' ')
      if [ "${byte_count:-0}" -gt 350 ]; then
        context_parts+=("$(cat "$filepath")")
      fi
    fi
  done

  # Also load any extra memory files the user created
  for memfile in "$memory_dir"/*.md; do
    [ -f "$memfile" ] || continue
    basename=$(basename "$memfile")
    # Skip the standard ones already loaded
    case "$basename" in
      active-state.md|decisions.md|gotchas.md|feedback.md) continue ;;
    esac
    byte_count=$(wc -c < "$memfile" 2>/dev/null | tr -d ' ')
    if [ "${byte_count:-0}" -gt 350 ]; then
      context_parts+=("$(cat "$memfile")")
    fi
  done
fi

# 3. Knowledge base highlights (top 5 most recent gotchas/decisions)
kb_dir="${PROJECT_DIR}/knowledge"
if [ -d "$kb_dir" ] && command -v node >/dev/null 2>&1; then
  kb_summary=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const kbDir = '$kb_dir';
    const highlights = [];

    for (const file of ['gotchas.jsonl', 'decisions.jsonl', 'anti-patterns.jsonl']) {
      const fp = path.join(kbDir, file);
      if (!fs.existsSync(fp)) continue;
      try {
        const lines = fs.readFileSync(fp, 'utf8').trim().split('\n').filter(l => l.trim());
        for (const line of lines.slice(-5)) {
          try {
            const entry = JSON.parse(line);
            if (entry.id && (entry.id.includes('example') || entry.id.includes('Example'))) continue;
            if (entry.fact && entry.fact.startsWith('Example:')) continue;
            const fact = entry.fact || entry.description || entry.title || '';
            if (fact && fact.length > 10) highlights.push('- ' + fact.slice(0, 200));
          } catch {}
        }
      } catch {}
    }

    if (highlights.length > 0) {
      console.log('## Key Knowledge (gotchas, decisions, anti-patterns)\n' + highlights.slice(0, 10).join('\n'));
    }
  " 2>/dev/null || true)
  if [ -n "$kb_summary" ]; then
    context_parts+=("$kb_summary")
  fi
fi

# --- Output JSON ---
if [ ${#context_parts[@]} -gt 0 ]; then
  joined=""
  for part in "${context_parts[@]}"; do
    if [ -n "$joined" ]; then
      joined="${joined}

${part}"
    else
      joined="$part"
    fi
  done

  # Wrap in a recovery header
  joined="# metaswarm Memory (auto-loaded)
The following context was saved before compaction. Use it to resume work without starting over.

${joined}"

  if command -v node >/dev/null 2>&1; then
    escaped=$(printf '%s' "$joined" | node -e "let d='';process.stdin.on('data',c=>d+=c.toString());process.stdin.on('end',()=>process.stdout.write(JSON.stringify(d)))")
    escaped="${escaped:1:${#escaped}-2}"
  else
    escaped=$(printf '%s' "$joined" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' '\036' | sed 's/\x1e/\\n/g')
  fi

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "${escaped}"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ""
  }
}
EOF
fi

exit 0
