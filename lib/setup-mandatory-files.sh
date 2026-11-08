#!/usr/bin/env bash
# lib/setup-mandatory-files.sh
# Writes the 3 mandatory setup files that the agent keeps skipping.
# Called by the setup skill after detection and user questions.
#
# Usage: setup-mandatory-files.sh <project-dir> <coverage-threshold> <coverage-command> [--platform claude|codex|gemini|all] [--reconfigure]
#
# Arguments:
#   project-dir       - Project root directory
#   coverage-threshold - Coverage percentage (e.g., 100)
#   coverage-command   - Coverage enforcement command (e.g., "pytest --cov --cov-fail-under=100")
#   --platform        - Target platform(s): claude (default), codex, gemini, or all
#   --reconfigure     - Explicit setup re-run: update an existing .coverage-thresholds.json
#                       to the new threshold (other settings kept). Without it an existing
#                       file is never changed (the session hook's self-heal omits it).
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
RECONFIGURE=false
shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --platform)
      if [ $# -lt 2 ]; then
        echo "Error: --platform requires a value (claude, codex, gemini, or all)" >&2
        exit 1
      fi
      PLATFORM="$2"; shift 2 ;;
    --reconfigure) RECONFIGURE=true; shift ;;
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
warnings=()
errors=()

# Helper: write instruction file for a given platform
# Args: $1=platform, $2=filename, $3=append_template, $4=full_template
write_instruction_file() {
  local fname="$2" append_tmpl="$3" full_tmpl="$4"
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
# New file: written from the template. Existing file: left alone, unless
# --reconfigure (an explicit setup re-run) asks to update its thresholds and any
# threshold embedded in enforcement.command; every other setting is kept. The
# session hook's self-heal never passes --reconfigure, so it cannot overwrite
# thresholds a user edited by hand.
coverage_file="$PROJECT_DIR/.coverage-thresholds.json"
coverage_template="$TEMPLATE_DIR/coverage-thresholds.json"

# Quoted heredoc read directly (not inside $(...), which bash 3.2 misparses
# when the body has backticks): the shell expands nothing inside the script.
COVERAGE_JS=""
IFS= read -r -d '' COVERAGE_JS <<'JS' || true
const fs = require('fs');
const [mode, file, tmplPath, rawThreshold, cmd] = process.argv.slice(1);
const say = (kind, msg) => console.log(kind + '\t' + msg);
const t = Number(rawThreshold);
const DIMS = ['lines', 'branches', 'functions', 'statements'];
if (!/^\d+(\.\d+)?$/.test(rawThreshold) || t > 100) {
  say('error', `.coverage-thresholds.json: coverage threshold '${rawThreshold}' is not a number from 0 to 100`);
  process.exit(0);
}
if (mode === 'create') {
  const tmpl = JSON.parse(fs.readFileSync(tmplPath, 'utf-8'));
  for (const d of DIMS) tmpl.thresholds[d] = t;
  tmpl.enforcement.command = cmd;
  fs.writeFileSync(file, JSON.stringify(tmpl, null, 2) + '\n');
  say('created', `.coverage-thresholds.json (threshold: ${t}%, command: ${cmd})`);
  process.exit(0);
}
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(file, 'utf-8'));
} catch (e) {
  say('error', `.coverage-thresholds.json is not valid JSON, left unchanged: ${e.message}`);
  process.exit(0);
}
if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) {
  say('error', '.coverage-thresholds.json is not a JSON object, left unchanged');
  process.exit(0);
}
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
cfg.thresholds = isObj(cfg.thresholds) ? cfg.thresholds : {};
const old = DIMS.map((d) => cfg.thresholds[d]);
const oldNums = [...new Set(old.filter((v) => typeof v === 'number').map(String))];
const oldShown = oldNums.length ? oldNums.join('/') + '%' : 'unset';
for (const d of DIMS) cfg.thresholds[d] = t;

cfg.enforcement = isObj(cfg.enforcement) ? cfg.enforcement : {};
const oldCmd = typeof cfg.enforcement.command === 'string' ? cfg.enforcement.command : '';
const GO_GATE = '.metaswarm/go-coverage-gate.go';
let newCmd = oldCmd;
let goReplaced = false;
if (!oldCmd) {
  newCmd = cmd;
} else if (cmd.includes(GO_GATE) && /^\s*go\s+test(\s|$)/.test(oldCmd)) {
  // Setup used to write a bare `go test` command for Go (#78); move it to the
  // gate. The gate passes its arguments to go test, so the user's own flags and
  // packages carry over; only the cover flags it sets itself are dropped.
  const toks = oldCmd.trim().split(/\s+/).slice(2);
  const keep = [];
  for (let i = 0; i < toks.length; i++) {
    if (toks[i] === '-cover' || toks[i] === '-coverprofile' && ++i) continue;
    if (/^-cover(profile)?=/.test(toks[i]) || /^-cover=/.test(toks[i])) continue;
    keep.push(toks[i]);
  }
  const extra = keep.length === 1 && keep[0] === './...' ? [] : keep;
  newCmd = [cmd, ...extra].join(' ');
  goReplaced = true;
  say('created', `.coverage-thresholds.json enforcement.command: replaced '${oldCmd}' (go test never fails below the threshold) with: ${newCmd}`);
} else {
  // Known threshold flags: pytest-cov --cov-fail-under, tarpaulin/coverage.py --fail-under.
  newCmd = oldCmd.replace(/(--(?:cov-)?fail-under)([= ])(\d+(?:\.\d+)?)(?![\d.])/g, (m, flag, sep) => flag + sep + t);
}
cfg.enforcement.command = newCmd;

const thresholdsChanged = old.some((v) => v !== t);
if (!thresholdsChanged && newCmd === oldCmd) {
  say('skipped', `.coverage-thresholds.json (already at ${t}%)`);
} else {
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n');
  if (thresholdsChanged) say('created', `.coverage-thresholds.json (thresholds ${oldShown} -> ${t}%)`);
  if (newCmd !== oldCmd && !goReplaced) say('created', `.coverage-thresholds.json enforcement.command updated to: ${newCmd}`);
}
if (cmd.includes(GO_GATE) && !newCmd.includes(GO_GATE)) {
  say('warning', `enforcement.command '${newCmd}' was kept. Make sure it fails below the threshold: go test alone never does. Setup's Go command is: ${cmd}`);
} else if (oldCmd && !goReplaced && newCmd.split(/\s+/)[0] !== cmd.split(/\s+/)[0]) {
  say('warning', `enforcement.command '${newCmd}' was kept, but it differs from the detected command '${cmd}'. If the test runner changed, update enforcement.command by hand.`);
}
// Any old threshold still written in the command, in a form not rewritten above.
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const stale = [...new Set(old.filter((v) => typeof v === 'number' && v !== t).map(String))]
  .filter((v) => new RegExp('(^|[^\\d.])' + esc(v) + '(?![\\d.])').test(newCmd));
if (stale.length) {
  say('warning', `enforcement.command may embed the old threshold (${stale.join('/')}%): '${newCmd}'. Update it by hand to use ${t}%.`);
}
JS

coverage_mode=""
if [ -f "$coverage_file" ]; then
  if [ "$RECONFIGURE" = true ]; then
    coverage_mode="reconfigure"
  else
    skipped+=(".coverage-thresholds.json (already exists)")
  fi
elif [ ! -f "$coverage_template" ]; then
  errors+=("coverage-thresholds.json template not found at $coverage_template")
else
  coverage_mode="create"
fi

if [ -n "$coverage_mode" ]; then
  if command -v node >/dev/null 2>&1; then
    coverage_out="$(node -e "$COVERAGE_JS" "$coverage_mode" "$coverage_file" "$coverage_template" "$COVERAGE_THRESHOLD" "$COVERAGE_COMMAND" 2>&1)" \
      || coverage_out="error	.coverage-thresholds.json: node failed: ${coverage_out//$'\n'/ }"
    while IFS=$'\t' read -r kind msg; do
      case "$kind" in
        created) created+=("$msg") ;;
        skipped) skipped+=("$msg") ;;
        warning) warnings+=("$msg") ;;
        error) errors+=("$msg") ;;
        '') ;;
        *) errors+=(".coverage-thresholds.json: unexpected output: $kind $msg") ;;
      esac
    done <<< "$coverage_out"
  else
    errors+=(".coverage-thresholds.json — node not available for JSON templating")
  fi
fi

# --- File 2b: Go coverage gate (#78) ---
# `go test` has no threshold flag, so Go projects use a gate program as their
# enforcement command. Write it whenever the configured command runs it, and
# refresh it on re-runs so plugin fixes reach the project.
gate_rel=".metaswarm/go-coverage-gate.go"
if [ -f "$coverage_file" ] && grep -qF "$gate_rel" "$coverage_file" 2>/dev/null; then
  gate_template="$TEMPLATE_DIR/go-coverage-gate.go"
  gate_target="$PROJECT_DIR/$gate_rel"
  if [ ! -f "$gate_template" ]; then
    errors+=("go-coverage-gate.go template not found at $gate_template")
  elif [ -f "$gate_target" ] && cmp -s "$gate_template" "$gate_target"; then
    skipped+=("$gate_rel (already current)")
  else
    existed=false
    [ -f "$gate_target" ] && existed=true
    mkdir -p "$PROJECT_DIR/.metaswarm"
    cp "$gate_template" "$gate_target"
    if [ "$existed" = true ]; then
      created+=("$gate_rel (updated to the plugin's version)")
    else
      created+=("$gate_rel (Go coverage gate)")
    fi
  fi
fi

# --- File 3: Claude command shims (Claude/all only) ---
if [ "$PLATFORM" = "claude" ] || [ "$PLATFORM" = "all" ]; then
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
else
  skipped+=(".claude/commands shims (not needed for ${PLATFORM})")
fi

# --- Output results as JSON ---
# Messages can contain user commands, so escape them for JSON.
json_str() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  v="${v//$'\t'/\\t}"
  v="${v//$'\n'/\\n}"
  v="${v//$'\r'/\\r}"
  # Drop any other control character, which JSON strings cannot hold raw.
  v="$(printf '%s' "$v" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')"
  printf '"%s"' "$v"
}

# json_array NAME ITEMS... — print one array member of the result object.
json_array() {
  local name="$1"; shift
  echo "  \"$name\": ["
  local n=$# i=0 item comma
  for item in "$@"; do
    i=$((i + 1))
    comma=""
    [ "$i" -lt "$n" ] && comma=","
    echo "    $(json_str "$item")$comma"
  done
  printf '  ]'
}

echo "{"
echo "  \"status\": \"$([ ${#errors[@]} -eq 0 ] && echo "ok" || echo "errors")\","
# ${arr[@]+...} keeps empty arrays safe under set -u on bash 3.2.
json_array created ${created[@]+"${created[@]}"}; echo ","
json_array skipped ${skipped[@]+"${skipped[@]}"}; echo ","
json_array warnings ${warnings[@]+"${warnings[@]}"}; echo ","
json_array errors ${errors[@]+"${errors[@]}"}; echo ""
echo "}"
