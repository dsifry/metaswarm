#!/usr/bin/env bash
# hooks/session-start.sh
# SessionStart + PreCompact hook for metaswarm plugin
# Outputs JSON with hookSpecificOutput.additionalContext

set -euo pipefail

# --- Phase 0: Self-locate plugin root ---
# Works with Codex ($PLUGIN_ROOT), Claude Code ($CLAUDE_PLUGIN_ROOT),
# Gemini CLI ($extensionPath), or direct invocation (derive from script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${PLUGIN_ROOT:-}"
PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${extensionPath:-$(cd "$SCRIPT_DIR/.." && pwd)}}}"
METASWARM_PLATFORM="${METASWARM_PLATFORM:-}"
if [ -z "$METASWARM_PLATFORM" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    METASWARM_PLATFORM="claude"
  elif [ -n "${extensionPath:-}" ]; then
    METASWARM_PLATFORM="gemini"
  elif [ -n "$CODEX_PLUGIN_ROOT" ] || [ -n "${CODEX_HOME:-}" ]; then
    METASWARM_PLATFORM="codex"
  else
    METASWARM_PLATFORM="claude"
  fi
fi

# --- Phase 1: BEADS dedup check ---
# If the standalone beads plugin is installed, it already runs `bd prime` (bd workflow
# context) on SessionStart/PreCompact, so this hook skips its own `bd prime` call below.
beads_standalone=false
beads_plugin_caches=("${HOME}/.claude/plugins/cache" "${CODEX_HOME:-${HOME}/.codex}/plugins/cache")
for beads_plugin_cache in "${beads_plugin_caches[@]}"; do
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
    done < <(find "$beads_plugin_cache" \( -path "*/.claude-plugin/plugin.json" -o -path "*/.codex-plugin/plugin.json" \) -print0 2>/dev/null || true)
  fi
  [ "$beads_standalone" = true ] && break
done

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
  setup_script="${PLUGIN_ROOT}/lib/setup-mandatory-files.sh"
  needs_heal=false

  case "$METASWARM_PLATFORM" in
    codex) instruction_file="AGENTS.md" ;;
    gemini) instruction_file="GEMINI.md" ;;
    *) instruction_file="CLAUDE.md" ;;
  esac

  if ! grep -q "metaswarm" "$instruction_file" 2>/dev/null; then
    needs_heal=true
  fi
  if [ ! -f ".coverage-thresholds.json" ]; then
    needs_heal=true
  fi
  # A Go project's enforcement command runs the gate program (#87). If the file
  # is gone, restore it. Self-heal runs the setup script in create mode, so it
  # rewrites the gate but leaves the existing thresholds file as it is.
  if [ ! -f ".metaswarm/go-coverage-gate.go" ] \
    && grep -qF ".metaswarm/go-coverage-gate.go" ".coverage-thresholds.json" 2>/dev/null; then
    needs_heal=true
  fi
  if { [ "$METASWARM_PLATFORM" = "claude" ] || [ "$METASWARM_PLATFORM" = "all" ]; } \
    && { [ ! -f ".claude/commands/start-task.md" ] || ! grep -q "metaswarm" ".claude/commands/start-task.md" 2>/dev/null; }; then
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
    bash "$setup_script" "$(pwd)" "$cov_threshold" "$cov_cmd" --platform "$METASWARM_PLATFORM" >/dev/null 2>&1 || true
  fi
fi

# --- Phase 4: Build context message ---
context_parts=()

setup_cmd='$setup'
start_cmd='$start'
migrate_cmd='$migrate'
case "$METASWARM_PLATFORM" in
  claude)
    setup_cmd='/setup'
    start_cmd='/start-task'
    migrate_cmd='/migrate'
    ;;
  gemini)
    setup_cmd='/metaswarm:setup'
    start_cmd='/metaswarm:start-task'
    migrate_cmd='/metaswarm:migrate'
    ;;
esac

if [ "$new_project" = true ]; then
  context_parts+=("Metaswarm is installed but this project hasn't been set up yet. Run \`${setup_cmd}\` to configure it, or \`${start_cmd}\` to begin working.")
fi

if [ "$legacy_install" = true ]; then
  context_parts+=("This project has metaswarm installed via the old npm method. The marketplace plugin is now active and provides all the same skills and commands. Run \`${migrate_cmd}\` to clean up the redundant copies — this is a safe, reversible operation that only removes duplicate framework files (your project files are never touched).")
fi

# Generated agent files carry the plugin version in their header; flag any that differ
# (e.g. after a marketplace auto-update). Version comparison only, no hashing.
plugin_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 || true)
if [ -n "$plugin_version" ]; then
  for agent_file in .claude/agents/metaswarm-*.md; do
    [ -f "$agent_file" ] || continue
    agent_version=$(sed -n 's/^<!-- generated-by: metaswarm v\([^ ]*\) sha256:.*/\1/p' "$agent_file" | head -1 || true)
    if [ -n "$agent_version" ] && [ "$agent_version" != "$plugin_version" ]; then
      context_parts+=("metaswarm agents are stale — run /update")
      break
    fi
  done
fi

# bd workflow context: run `bd prime` only if the project is set up and the beads plugin
# isn't already running it. metaswarm's knowledge base is surfaced separately below.
if [ "$new_project" = false ] && [ "$beads_standalone" = false ]; then
  if command -v bd >/dev/null 2>&1; then
    bd_output=$(bd prime 2>/dev/null || true)
    if [ -n "$bd_output" ]; then
      context_parts+=("$bd_output")
    fi
  fi
fi

# metaswarm knowledge base (.beads/knowledge/*.jsonl), in every setup, beads plugin or not:
# inline the MUST FOLLOW rules (fact or recommendation containing NEVER/ALWAYS/MUST as a
# word), within KB_MAX_RULES rules and KB_MAX_BYTES bytes, then point at /prime for the
# rest. One streaming jq pass counts every fact but keeps only the rules that fit. Without
# a working jq (or if jq fails) only the pointer is added. An empty or missing store adds
# nothing.
KB_DIR=".beads/knowledge"
KB_MAX_RULES=10
KB_MAX_BYTES=2048
case "$METASWARM_PLATFORM" in
  gemini) prime_hint='`/metaswarm:prime <topic>`' ;;
  codex) prime_hint='`$start` (it primes knowledge for the task)' ;;
  *) prime_hint='`/prime <topic>`' ;;
esac
kb_files=()
if [ -d "$KB_DIR" ]; then
  for kb_file in "$KB_DIR"/*.jsonl; do
    [ -f "$kb_file" ] && kb_files+=("$kb_file")
  done
fi
if [ ${#kb_files[@]} -gt 0 ]; then
  kb_total=""
  kb_section=""
  kb_out=""
  if command -v jq >/dev/null 2>&1 && jq -n 1 >/dev/null 2>&1 \
    && kb_out=$(jq -R -n -r --argjson maxr "$KB_MAX_RULES" --argjson maxb "$KB_MAX_BYTES" '
      def clean: tostring | gsub("[[:cntrl:]]+"; " ");
      def fit($n): if utf8bytelength <= $n then .
        else (.[0:((length * $n / utf8bytelength) | floor)] | until(utf8bytelength <= $n; .[0:length - 1])) end;
      reduce (inputs | select(test("^[[:space:]]*#") | not) | fromjson?
              | select(type == "object" and (.fact | type) == "string")) as $f
        ({total: 0, bytes: 0, rules: [], full: false};
         .total += 1
         | if .full then .
           else ($f.recommendation | if type == "string" then . else "" end) as $rec
             | if (($f.fact + " " + $rec) | test("(^|[^A-Za-z0-9_])(NEVER|ALWAYS|MUST)([^A-Za-z0-9_]|$)")) then
                 ("- [" + (($f.type // "fact") | clean) + "] " + ($f.fact | clean)
                   + (if $rec != "" then " -> " + ($rec | clean) else "" end)) as $line
                 | (if (.rules | length) == 0 and ($line | utf8bytelength) > $maxb
                    then ($line | fit($maxb - 3)) + "…" else $line end) as $line
                 | if (.rules | length) >= $maxr
                     or ((.rules | length) > 0 and .bytes + ($line | utf8bytelength) + 1 > $maxb)
                   then .full = true
                   else .rules += [$line] | .bytes += ($line | utf8bytelength) + 1 end
               else . end
           end)
      | (.total | tostring), .rules[]' "${kb_files[@]}" 2>/dev/null); then
    kb_total=$(printf '%s\n' "$kb_out" | head -n 1)
    kb_section=$(printf '%s\n' "$kb_out" | sed '1d')
  else
    # No working jq: count lines that look like JSON objects, pointer only.
    kb_total=$(cat "${kb_files[@]}" 2>/dev/null | grep -c '^[[:space:]]*{' || true)
  fi
  case "$kb_total" in ''|*[!0-9]*) kb_total=0 ;; esac
  kb_shown=0
  [ -n "$kb_section" ] && kb_shown=$(printf '%s\n' "$kb_section" | grep -c . || true)
  kb_rest=$((kb_total - kb_shown))
  [ "$kb_rest" -lt 0 ] && kb_rest=0
  if [ "$kb_shown" -gt 0 ]; then
    kb_noun="facts"; [ "$kb_rest" -eq 1 ] && kb_noun="fact"
    kb_msg="metaswarm knowledge, MUST FOLLOW rules (from .beads/knowledge/):
${kb_section}
"
    if [ "$kb_rest" -gt 0 ]; then
      kb_msg="${kb_msg}${kb_rest} more ${kb_noun} in .beads/knowledge/ — run ${prime_hint} to load the ones relevant to your task."
    else
      kb_msg="${kb_msg}Run ${prime_hint} for topic-filtered knowledge."
    fi
    context_parts+=("$kb_msg")
  elif [ "$kb_total" -gt 0 ]; then
    kb_noun="facts"; [ "$kb_total" -eq 1 ] && kb_noun="fact"
    context_parts+=("metaswarm knowledge: ${kb_total} ${kb_noun} in .beads/knowledge/ — run ${prime_hint} before planning or implementing.")
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
