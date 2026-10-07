#!/usr/bin/env bash
# lib/merge-coverage.sh - Smart merge for coverage-thresholds.json
# Usage: merge-coverage.sh <project-file> <template-file> <output-file>

set -euo pipefail

PROJECT_FILE="${1:?}"
TEMPLATE_FILE="${2:?}"
OUTPUT_FILE="${3:?}"

# Use jq for JSON merging - more reliable than Node.js in this version
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not found. Please install jq." >&2
  exit 1
fi

# Read project and template
project_json=$(cat "$PROJECT_FILE")
template_json=$(cat "$TEMPLATE_FILE")

# Merge: start with project, overlay template defaults for standard fields
# Template provides defaults for thresholds and enforcement; project values take precedence
# Preserve all project-specific fields
merged=$(jq -n \
  --argjson project "$project_json" \
  --argjson template "$template_json" '
  # Start with project
  $project
  # Merge thresholds: if project has thresholds, merge; otherwise use template
  | if .thresholds then .thresholds = ($template.thresholds * .thresholds) else .thresholds = $template.thresholds end
  # Merge enforcement: if project has enforcement, merge; otherwise use template  
  | if .enforcement then .enforcement = ($template.enforcement * .enforcement) else .enforcement = $template.enforcement end
  # Add $schema and $comment from template if not present
  | if $template["$schema"] and (has("$schema") | not) then .["$schema"] = $template["$schema"] else . end
  | if $template["$comment"] and (has("$comment") | not) then .["$comment"] = $template["$comment"] else . end
')

echo "$merged" > "$OUTPUT_FILE"