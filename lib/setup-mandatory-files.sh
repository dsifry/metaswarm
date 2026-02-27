#!/usr/bin/env bash
# lib/setup-mandatory-files.sh
# Writes the 3 mandatory setup files that the agent keeps skipping.
# Called by the setup skill after detection and user questions.
#
# Usage: setup-mandatory-files.sh <project-dir> <coverage-threshold> <coverage-command>
#
# Arguments:
#   project-dir       - Project root directory
#   coverage-threshold - Coverage percentage (e.g., 100)
#   coverage-command   - Coverage enforcement command (e.g., "pytest --cov --cov-fail-under=100")
#
# Environment:
#   CLAUDE_PLUGIN_ROOT - Plugin root directory (set by Claude Code)

set -euo pipefail

PROJECT_DIR="${1:?Usage: setup-mandatory-files.sh <project-dir> <coverage-threshold> <coverage-command>}"
COVERAGE_THRESHOLD="${2:?Missing coverage threshold}"
COVERAGE_COMMAND="${3:?Missing coverage command}"

# Resolve plugin root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE_DIR="$PLUGIN_ROOT/skills/setup/templates"

# Track what was done
created=()
skipped=()
errors=()

# --- File 1: CLAUDE.md ---
claude_md="$PROJECT_DIR/CLAUDE.md"
append_template="$TEMPLATE_DIR/CLAUDE-append.md"

if [ ! -f "$append_template" ]; then
  errors+=("CLAUDE-append.md template not found at $append_template")
else
  if [ -f "$claude_md" ]; then
    if grep -q "metaswarm" "$claude_md" 2>/dev/null; then
      skipped+=("CLAUDE.md (already has metaswarm section)")
    else
      cat "$append_template" >> "$claude_md"
      created+=("CLAUDE.md (appended metaswarm section)")
    fi
  else
    # No CLAUDE.md — write full template
    full_template="$TEMPLATE_DIR/CLAUDE.md"
    if [ -f "$full_template" ]; then
      cp "$full_template" "$claude_md"
      created+=("CLAUDE.md (written from template)")
    else
      errors+=("CLAUDE.md template not found at $full_template")
    fi
  fi
fi

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
