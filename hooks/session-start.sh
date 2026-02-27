#!/usr/bin/env bash
# hooks/session-start.sh
# SessionStart + PreCompact hook for metaswarm plugin
# Outputs JSON with hookSpecificOutput.additionalContext

set -euo pipefail

# --- Phase 1: BEADS dedup check ---
# If standalone BEADS plugin is installed, skip knowledge priming (let BEADS handle it)
beads_standalone=false
beads_plugin_cache="${HOME}/.claude/plugins/cache"
if [ -d "$beads_plugin_cache" ]; then
  # Look for a BEADS plugin with name "beads" in plugin.json
  while IFS= read -r -d '' pjson; do
    pname=""
    if command -v jq >/dev/null 2>&1; then
      pname=$(jq -r '.name // empty' "$pjson" 2>/dev/null || true)
    elif command -v node >/dev/null 2>&1; then
      pname=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8')).name||'')}catch{console.log('')}" "$pjson" 2>/dev/null || true)
    fi
    # Neither jq nor node available — skip dedup check (safe default: allow both to prime)
    if [ "$pname" = "beads" ]; then
      beads_standalone=true
      break
    fi
  done < <(find "$beads_plugin_cache" -path "*/.claude-plugin/plugin.json" -print0 2>/dev/null || true)
fi

# --- Phase 2: New project detection ---
new_project=false
if [ ! -f ".metaswarm/project-profile.json" ]; then
  new_project=true
fi

# --- Phase 3: Legacy install detection ---
legacy_install=false
if [ -f ".claude/plugins/metaswarm/.claude-plugin/plugin.json" ]; then
  legacy_install=true
fi

# --- Phase 3.5: Self-heal mandatory files ---
# If project profile exists but mandatory files are missing, run the setup script.
# This catches cases where the agent skipped file creation during setup.
if [ "$new_project" = false ] && [ "$legacy_install" = false ]; then
  plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
  setup_script="${plugin_root}/lib/setup-mandatory-files.sh"
  needs_heal=false

  # Check the 3 mandatory files
  if ! grep -q "metaswarm" CLAUDE.md 2>/dev/null; then
    needs_heal=true
  fi
  if [ ! -f ".coverage-thresholds.json" ]; then
    needs_heal=true
  fi
  if [ ! -f ".claude/commands/start-task.md" ] || ! grep -q "metaswarm" ".claude/commands/start-task.md" 2>/dev/null; then
    needs_heal=true
  fi

  if [ "$needs_heal" = true ] && [ -f "$setup_script" ]; then
    # Read coverage command from project profile
    cov_cmd=""
    cov_threshold="100"
    if command -v node >/dev/null 2>&1 && [ -f ".metaswarm/project-profile.json" ]; then
      cov_info=$(node -e "
        try {
          const p = JSON.parse(require('fs').readFileSync('.metaswarm/project-profile.json','utf-8'));
          const t = p.choices?.coverage_threshold || p.coverage?.threshold || p.thresholds?.coverage || 100;
          const c = p.commands?.coverage || 'pytest --cov --cov-fail-under=' + t;
          console.log(t + '|' + c);
        } catch { console.log('100|pytest --cov --cov-fail-under=100'); }
      " 2>/dev/null || echo "100|pytest --cov --cov-fail-under=100")
      cov_threshold="${cov_info%%|*}"
      cov_cmd="${cov_info##*|}"
    fi
    [ -z "$cov_cmd" ] && cov_cmd="pytest --cov --cov-fail-under=${cov_threshold}"

    # Run the setup script silently
    bash "$setup_script" "$(pwd)" "$cov_threshold" "$cov_cmd" >/dev/null 2>&1 || true
  fi
fi

# --- Phase 4: Build context message ---
context_parts=()

if [ "$new_project" = true ]; then
  context_parts+=("Metaswarm is installed but this project hasn't been set up yet. Run \`/metaswarm:setup\` to configure it, or \`/metaswarm:start-task\` to begin working.")
fi

if [ "$legacy_install" = true ]; then
  context_parts+=("This project has metaswarm installed via the old npm method. The marketplace plugin is now active and provides all the same skills and commands. Run \`/metaswarm:migrate\` to clean up the redundant copies — this is a safe, reversible operation that only removes duplicate framework files (your project files are never touched).")
fi

# Knowledge priming (only if project is set up and BEADS isn't separately priming)
if [ "$new_project" = false ] && [ "$beads_standalone" = false ]; then
  if command -v bd >/dev/null 2>&1; then
    bd_output=$(bd prime 2>/dev/null || true)
    if [ -n "$bd_output" ]; then
      context_parts+=("$bd_output")
    fi
  fi
fi

# --- Build and output JSON ---
# Use node for JSON escaping (works on macOS Bash 3.2 where bash parameter
# expansion with $'\n' is unreliable). Node is available on most systems and
# is already a soft dependency for the BEADS dedup check above.
if [ ${#context_parts[@]} -gt 0 ]; then
  # Join parts with double newline
  joined=""
  for part in "${context_parts[@]}"; do
    if [ -n "$joined" ]; then
      joined="${joined}

${part}"
    else
      joined="$part"
    fi
  done

  if command -v node >/dev/null 2>&1; then
    # Use node for reliable JSON escaping of arbitrary content
    escaped=$(printf '%s' "$joined" | node -e "let d='';process.stdin.on('data',c=>d+=c.toString());process.stdin.on('end',()=>process.stdout.write(JSON.stringify(d)))")
    # escaped includes surrounding quotes from JSON.stringify — strip them
    escaped="${escaped:1:${#escaped}-2}"
  else
    # Fallback: basic escaping via sed (covers \, ", newlines, tabs)
    escaped=$(printf '%s' "$joined" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' '\036' | sed 's/\x1e/\\n/g')
  fi

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${escaped}"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ""
  }
}
EOF
fi

exit 0
