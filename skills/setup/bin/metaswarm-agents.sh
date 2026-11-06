#!/usr/bin/env bash
# metaswarm-agents.sh — generate project-scoped phase agents from .metaswarm/models.yaml
#
#   metaswarm-agents.sh generate [--force]   write .claude/agents/metaswarm-<role>.md
#   metaswarm-agents.sh check                report hand-edited, stale, orphan, missing files
#   metaswarm-agents.sh clean                remove generated files (header-bearing only)
#
# Can be sourced: resolve_role_model <role> <host> prints the configured model.
# Bash 3.2 compatible (no associative arrays, no mapfile).

ROLES="design-reviewer plan-reviewer researcher planner coder adversarial-reviewer pr-shepherd-agent knowledge-curator-agent"
HEADER_RE='^<!-- generated-by: metaswarm '

# --- Locate plugin root, project root, version ---

find_plugin_root() {
  local d c
  for d in "${PLUGIN_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "${extensionPath:-}"; do
    if [ -n "$d" ]; then echo "$d"; return 0; fi
  done
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    if [ -f "$d/agents/coder.md" ]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  c="$(ls -d "$HOME"/.claude/plugins/cache/*/metaswarm/*/ 2>/dev/null | sort -V | while read -r d; do
    [ -f "${d}agents/coder.md" ] && echo "${d%/}"
  done | tail -1)"
  if [ -n "$c" ]; then echo "$c"; return 0; fi
  echo "cannot locate metaswarm plugin; set CLAUDE_PLUGIN_ROOT" >&2
  exit 3
}

init_env() {
  [ -n "${MS_PLUGIN:-}" ] && return 0
  MS_PLUGIN="$(find_plugin_root)" || exit 3
  MS_PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  MS_CONFIG="$MS_PROJECT/.metaswarm/models.yaml"
  MS_AGENTS="$MS_PROJECT/.claude/agents"
  MS_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MS_PLUGIN/.claude-plugin/plugin.json" | head -1)"
}

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1; }

is_role() { case " $ROLES " in *" $1 "*) return 0 ;; esac; return 1; }

# --- models.yaml reader ---
# Fills MS_CFG with lines "role.host=value". Exits 2 with "models.yaml:<line>: <reason>".

parse_error() { echo "models.yaml:$1: $2" >&2; exit 2; }

parse_models() {
  local line n=0 body indent level key val section="" role="" prev=0
  MS_CFG=""
  [ -f "$MS_CONFIG" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in *$'\t'*) parse_error "$n" "tabs are not allowed" ;; esac
    body="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//')"
    [ -z "$body" ] && continue
    case "$body" in *"{"*) parse_error "$n" "flow maps are not supported; use block style" ;; esac
    indent="$(printf '%s' "$body" | sed 's/[^ ].*$//' | wc -c | tr -d ' ')"
    [ $((indent % 2)) -eq 0 ] || parse_error "$n" "indentation must be a multiple of 2 spaces"
    level=$((indent / 2))
    [ "$level" -le 2 ] || parse_error "$n" "nesting too deep (max 3 levels)"
    [ "$level" -le "$prev" ] || [ "$level" -eq $((prev + 1)) ] || parse_error "$n" "unexpected indentation"
    prev=$level
    body="${body# }"; body="${body# }"; body="${body# }"; body="${body# }"
    key="${body%%:*}"; val="${body#*:}"; val="${val# }"
    # Decode a quoted YAML scalar ("x" or 'x')
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    printf '%s' "$body" | grep -Eq '^[A-Za-z0-9_-]+:( .*)?$' || parse_error "$n" "expected 'key: value'"
    case $level in
      0)
        case "$key" in roles|escalation) section="$key" ;; *) parse_error "$n" "unknown top-level key '$key'" ;; esac
        [ -z "$val" ] || parse_error "$n" "'$key' takes nested keys, not a value"
        ;;
      1)
        if [ "$section" = roles ]; then
          is_role "$key" || parse_error "$n" "unknown role '$key'"
        else
          [ "$key" = coder ] || parse_error "$n" "unknown escalation role '$key'"
        fi
        [ -z "$val" ] || parse_error "$n" "'$key' takes nested keys, not a value"
        role="$key"
        ;;
      2)
        [ -n "$val" ] || parse_error "$n" "'$key' needs a value"
        case "$key" in
          claude)
            case "$val" in sonnet|opus|haiku|fable|inherit) ;; *)
              printf '%s' "$val" | grep -Eq '^claude-[a-z0-9.-]+$' || parse_error "$n" "invalid claude model '$val'" ;;
            esac ;;
          codex|gemini)
            [ "$section" = roles ] || parse_error "$n" "unknown key '$key' under escalation" ;;
          after_failures)
            [ "$section" = escalation ] || parse_error "$n" "unknown host key '$key'"
            printf '%s' "$val" | grep -Eq '^[0-9]+$' || parse_error "$n" "after_failures must be an integer" ;;
          *) parse_error "$n" "unknown host key '$key'" ;;
        esac
        MS_CFG="${MS_CFG}${section}.${role}.${key}=${val}
"
        ;;
    esac
  done < "$MS_CONFIG"
}

# cfg_get <section.role.host> prints the configured value, if any
cfg_get() { printf '%s' "$MS_CFG" | sed -n "s/^$1=//p" | head -1; }

plugin_field() { sed -n "s/^$2: //p" "$MS_PLUGIN/agents/$1.md" | head -1; }

# resolve_role_model <role> <host>: configured model, else the plugin default
# (agents/<role>.md frontmatter for claude; empty for codex/gemini = adapter built-in).
resolve_role_model() {
  local m
  init_env
  parse_models
  m="$(cfg_get "roles.$1.$2")"
  if [ -z "$m" ] && [ "$2" = claude ]; then m="$(plugin_field "$1" model)"; fi
  [ -z "$m" ] || echo "$m"
}

# --- Rendering ---

# render <role>: write the full generated file to stdout
render() {
  local role="$1" model tmp hash
  model="$(cfg_get "roles.$role.claude")"
  tmp="$(mktemp)"
  awk -v name="metaswarm-$role" -v model="$model" '
    /^---$/ { print; if (++dashes == 2) exit; next }
    /^name:/ { print "name: " name; next }
    /^model:/ && model != "" { print "model: " model; next }
    { print }
  ' "$MS_PLUGIN/agents/$role.md" > "$tmp"
  # body = everything after the closing ---
  awk 'c >= 2 { print } /^---$/ { c++ }' "$MS_PLUGIN/agents/$role.md" >> "$tmp"
  hash="$(sha < "$tmp")"
  awk -v h="<!-- generated-by: metaswarm v$MS_VERSION sha256:$hash — edit .metaswarm/models.yaml, not this file -->" \
    '{ print } /^---$/ { c++; if (c == 2) print h }' "$tmp"
  rm -f "$tmp"
}

has_header() { grep -q "$HEADER_RE" "$1" 2>/dev/null; }
header_field() { sed -n "s/^<!-- generated-by: metaswarm v\([^ ]*\) sha256:\([0-9a-f]*\) .*/\\$2/p" "$1" | head -1; }
strip_header() { awk '!d && /^<!-- generated-by: metaswarm /{d=1;next}1' "$1"; }
is_hand_edited() { [ "$(strip_header "$1" | sha)" != "$(header_field "$1" 2)" ]; }
role_of() { local b; b="$(basename "$1" .md)"; echo "${b#metaswarm-}"; }

# --- Subcommands ---

cmd_generate() {
  local force=0 role f tmp problems=0
  [ "${1:-}" = "--force" ] && force=1
  if [ ! -f "$MS_CONFIG" ]; then
    echo "no models.yaml — using plugin defaults; run /setup to customize"
    return 0
  fi
  parse_models
  # Refuse before writing anything if a target is user-authored or hand-edited
  for role in $ROLES; do
    f="$MS_AGENTS/metaswarm-$role.md"
    [ -f "$f" ] || continue
    if ! has_header "$f"; then
      echo "refusing to overwrite user-authored file (no generated-by header): $f" >&2; problems=1
    elif [ "$force" -eq 0 ] && is_hand_edited "$f"; then
      echo "hand-edited (use --force to overwrite): $f" >&2; problems=1
    fi
  done
  [ "$problems" -eq 0 ] || return 1
  mkdir -p "$MS_AGENTS"
  for role in $ROLES; do
    tmp="$(mktemp)"
    render "$role" > "$tmp"
    mv "$tmp" "$MS_AGENTS/metaswarm-$role.md"
    echo "wrote $MS_AGENTS/metaswarm-$role.md"
  done
  for f in "$MS_AGENTS"/metaswarm-*.md; do
    [ -f "$f" ] && has_header "$f" || continue
    is_role "$(role_of "$f")" && continue
    rm -f "$f"
    echo "removed orphan $f"
  done
}

cmd_check() {
  local role f drift=0 tmp
  if [ ! -f "$MS_CONFIG" ]; then
    for f in "$MS_AGENTS"/metaswarm-*.md; do
      [ -f "$f" ] && has_header "$f" || continue
      echo "leftover generated agent (no models.yaml; it still overrides the plugin default): $f"; drift=1
    done
    if [ "$drift" -ne 0 ]; then
      echo "restore .metaswarm/models.yaml and run generate, or run: metaswarm-agents.sh clean"
      return 1
    fi
    echo "no models.yaml — using plugin defaults; run /setup to customize"
    return 0
  fi
  parse_models
  for role in $ROLES; do
    f="$MS_AGENTS/metaswarm-$role.md"
    if [ ! -f "$f" ]; then
      echo "missing: $f"; drift=1
    elif ! has_header "$f"; then
      echo "conflict (user-authored file blocks generation): $f"; drift=1
    elif is_hand_edited "$f"; then
      echo "hand-edited: $f"; drift=1
    else
      tmp="$(mktemp)"; render "$role" > "$tmp"
      cmp -s "$tmp" "$f" || { echo "stale: $f"; drift=1; }
      rm -f "$tmp"
    fi
  done
  for f in "$MS_AGENTS"/metaswarm-*.md; do
    [ -f "$f" ] && has_header "$f" || continue
    is_role "$(role_of "$f")" || { echo "orphan: $f"; drift=1; }
  done
  [ "$drift" -eq 0 ] || return 1
  echo "generated agents are up to date"
}

cmd_clean() {
  local f
  for f in "$MS_AGENTS"/metaswarm-*.md; do
    [ -f "$f" ] && has_header "$f" || continue
    rm -f "$f"
    echo "removed $f"
  done
}

main() {
  init_env
  case "${1:-}" in
    generate) cmd_generate "${2:-}" ;;
    check) cmd_check ;;
    clean) cmd_clean ;;
    resolve)
      is_role "${2:-}" || { echo "unknown role: ${2:-}" >&2; exit 2; }
      resolve_role_model "$2" "${3:-claude}" ;;
    *) echo "usage: metaswarm-agents.sh generate [--force] | check | clean | resolve <role> [claude|codex|gemini]" >&2; exit 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
