#!/usr/bin/env bash
# lib/setup-mandatory-files.sh
# Writes the 3 mandatory setup files that the agent keeps skipping.
# Called by the setup skill after detection and user questions.
#
# Usage: setup-mandatory-files.sh <project-dir> <coverage-threshold> <coverage-command> [--platform claude|codex|gemini|all]
#
# Arguments:
#   project-dir       - Project root directory
#   coverage-threshold - Coverage percentage (e.g., 100)
#   coverage-command   - Coverage enforcement command (e.g., "pytest --cov --cov-fail-under=100")
#   --platform        - Target platform(s): claude (default), codex, gemini, or all
#
# Environment:
#   CLAUDE_PLUGIN_ROOT - Plugin root directory (set by Claude Code)
#   extensionPath      - Extension root directory (set by Gemini CLI)

set -euo pipefail

PROJECT_DIR="${1:?Usage: setup-mandatory-files.sh <project-dir> <coverage-threshold> <coverage-command> [--platform claude|codex|gemini|all]}"
COVERAGE_THRESHOLD="${2:?Missing coverage threshold}"
COVERAGE_COMMAND="${3:?Missing coverage command}"

# Parse optional --platform flag (default: claude)
PLATFORM="claude"
shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-claude}"; shift 2 ;;
    *) shift ;;
  esac
done

# Resolve plugin root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE_DIR="$PLUGIN_ROOT/skills/setup/templates"

# Track what was done
created=()
skipped=()
errors=()

# Helper: write instruction file for a given platform
# Args: $1=platform, $2=filename, $3=append_template, $4=full_template
write_instruction_file() {
  local plat="$1" fname="$2" append_tmpl="$3" full_tmpl="$4"
  local target="$PROJECT_DIR/$fname"

  if [ ! -f "$append_tmpl" ]; then
    errors+=("${fname} append template not found at $append_tmpl")
    return
  fi

  if [ -f "$target" ]; then
    if grep -q "metaswarm" "$target" 2>/dev/null; then
      skipped+=("${fname} (already has metaswarm section)")
    else
      cat "$append_tmpl" >> "$target"
      created+=("${fname} (appended metaswarm section)")
    fi
  else
    if [ -f "$full_tmpl" ]; then
      cp "$full_tmpl" "$target"
      created+=("${fname} (written from template)")
    else
      errors+=("${fname} template not found at $full_tmpl")
    fi
  fi
}

# --- File 1: Instruction file(s) based on platform ---
case "$PLATFORM" in
  claude)
    write_instruction_file "claude" "CLAUDE.md" "$TEMPLATE_DIR/CLAUDE-append.md" "$TEMPLATE_DIR/CLAUDE.md"
    ;;
  codex)
    write_instruction_file "codex" "AGENTS.md" "$TEMPLATE_DIR/AGENTS-append.md" "$TEMPLATE_DIR/AGENTS.md"
    ;;
  gemini)
    write_instruction_file "gemini" "GEMINI.md" "$TEMPLATE_DIR/GEMINI-append.md" "$TEMPLATE_DIR/GEMINI.md"
    ;;
  all)
    write_instruction_file "claude" "CLAUDE.md" "$TEMPLATE_DIR/CLAUDE-append.md" "$TEMPLATE_DIR/CLAUDE.md"
    write_instruction_file "codex" "AGENTS.md" "$TEMPLATE_DIR/AGENTS-append.md" "$TEMPLATE_DIR/AGENTS.md"
    write_instruction_file "gemini" "GEMINI.md" "$TEMPLATE_DIR/GEMINI-append.md" "$TEMPLATE_DIR/GEMINI.md"
    ;;
  *)
    errors+=("Unknown platform: $PLATFORM (expected: claude, codex, gemini, or all)")
    ;;
esac

# --- File 2: .coverage-thresholds.json ---
coverage_file="$PROJECT_DIR/.coverage-thresholds.json"
coverage_template="$TEMPLATE_DIR/coverage-thresholds.json"

if [ -f "$coverage_file" ]; then
  skipped+=(".coverage-thresholds.json (already exists)")
else
  if [ ! -f "$coverage_template" ]; then
    errors+=("coverage-thresholds.json template not found at $coverage_template")
  else
    # Read template and replace values
    if command -v node >/dev/null 2>&1; then
      node -e "
        const fs = require('fs');
        const tmpl = JSON.parse(fs.readFileSync(process.argv[1], 'utf-8'));
        const threshold = parseInt(process.argv[2], 10);
        const cmd = process.argv[3];
        tmpl.thresholds.lines = threshold;
        tmpl.thresholds.branches = threshold;
        tmpl.thresholds.functions = threshold;
        tmpl.thresholds.statements = threshold;
        tmpl.enforcement.command = cmd;
        fs.writeFileSync(process.argv[4], JSON.stringify(tmpl, null, 2) + '\n');
      " "$coverage_template" "$COVERAGE_THRESHOLD" "$COVERAGE_COMMAND" "$coverage_file"
      created+=(".coverage-thresholds.json (threshold: ${COVERAGE_THRESHOLD}%, command: ${COVERAGE_COMMAND})")
    else
      errors+=(".coverage-thresholds.json — node not available for JSON templating")
    fi
  fi
fi

# --- File 3: 6 command shims in .claude/commands/ ---
commands_dir="$PROJECT_DIR/.claude/commands"
mkdir -p "$commands_dir"

shims=(
  "start-task:start-task"
  "start:start-task"
  "prime:prime"
  "review-design:review-design"
  "self-reflect:self-reflect"
  "pr-shepherd:pr-shepherd"
  "brainstorm:brainstorm"
)

for entry in "${shims[@]}"; do
  file_name="${entry%%:*}"
  command_name="${entry##*:}"
  shim_path="$commands_dir/${file_name}.md"
  shim_content="<!-- Created by metaswarm setup. Routes to the metaswarm plugin. Safe to delete if you uninstall metaswarm. -->

Invoke the \`/metaswarm:${command_name}\` skill to handle this request. Pass along any arguments the user provided."

  if [ -f "$shim_path" ]; then
    existing=$(cat "$shim_path")
    if [ "$existing" = "$shim_content" ]; then
      skipped+=(".claude/commands/${file_name}.md (already correct)")
    else
      # Overwrite — existing content is from a different plugin/project
      printf '%s' "$shim_content" > "$shim_path"
      created+=(".claude/commands/${file_name}.md (overwritten with metaswarm routing)")
    fi
  else
    printf '%s' "$shim_content" > "$shim_path"
    created+=(".claude/commands/${file_name}.md")
  fi
done

# --- Output results as JSON ---
echo "{"
echo "  \"status\": \"$([ ${#errors[@]} -eq 0 ] && echo "ok" || echo "errors")\","

echo "  \"created\": ["
for i in "${!created[@]}"; do
  comma=""
  [ "$i" -lt $(( ${#created[@]} - 1 )) ] && comma=","
  echo "    \"${created[$i]}\"$comma"
done
echo "  ],"

echo "  \"skipped\": ["
for i in "${!skipped[@]}"; do
  comma=""
  [ "$i" -lt $(( ${#skipped[@]} - 1 )) ] && comma=","
  echo "    \"${skipped[$i]}\"$comma"
done
echo "  ],"

echo "  \"errors\": ["
for i in "${!errors[@]}"; do
  comma=""
  [ "$i" -lt $(( ${#errors[@]} - 1 )) ] && comma=","
  echo "    \"${errors[$i]}\"$comma"
done
echo "  ]"

echo "}"
