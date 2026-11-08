#!/usr/bin/env bash
# lib/render-ci.sh — write a project's GitHub Actions CI workflow from
# templates/ci.yml (#83).
#
# Usage: render-ci.sh --stack node|python|go|rust [--branch NAME] [--out FILE]
#                     [--template FILE]
#
#   --stack     keeps that stack's "# @toolchain <stack>" block, drops the others
#   --branch    branch for push.branches; default: the repo's default branch
#               (origin/HEAD, then `gh repo view`, then main)
#   --out       output file (default .github/workflows/ci.yml); its directory is created
#   --template  template to render (default: the plugin's skills/setup/templates/ci.yml)
#
# Exit codes: 0 written, 1 usage or validation error, 2 no CI toolchain for the
# stack (use templates/ci-coverage-job.yml in the project's own CI instead).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack=""
branch=""
out=".github/workflows/ci.yml"
template="$PLUGIN_ROOT/skills/setup/templates/ci.yml"

die() { echo "render-ci: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || die "--stack needs a value"; stack="$2"; shift 2 ;;
    --branch) [ $# -ge 2 ] || die "--branch needs a value"; branch="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || die "--out needs a value"; out="$2"; shift 2 ;;
    --template) [ $# -ge 2 ] || die "--template needs a value"; template="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$stack" ] || die "--stack is required (node, python, go or rust)"
[ -f "$template" ] || die "template not found: $template"
if ! grep -qxF "      # @toolchain $stack" "$template"; then
  echo "render-ci: no CI toolchain for '$stack'. Add the coverage job from templates/ci-coverage-job.yml to your own CI instead." >&2
  exit 2
fi

if [ -z "$branch" ]; then
  branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [ -z "$branch" ] && command -v gh >/dev/null 2>&1; then
    branch="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
  fi
  if [ -z "$branch" ]; then
    branch="main"
    echo "render-ci: warning: couldn't read the default branch (no origin/HEAD, no gh); guessing main. Pass --branch if that's wrong." >&2
  fi
fi
# A git branch name that is also safe inside a double-quoted YAML string.
case "$branch" in
  *[!A-Za-z0-9._/-]*|-*|"") die "branch name not supported in the workflow: $branch" ;;
esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v keep="$stack" -v branch="$branch" '
  /^#~/ { next }
  /^ *# @toolchain / { cur = $3; next }
  /^ *# @end$/ { cur = ""; skipblank = 1; next }
  cur != "" && cur != keep { next }
  skipblank && /^$/ { skipblank = 0; if (prevblank) next }
  { skipblank = 0 }
  / # @branch$/ { sub(/branches: \[[^]]*\] # @branch$/, "branches: [\"" branch "\"]") }
  { prevblank = ($0 ~ /^$/); print }
' "$template" > "$tmp"

mkdir -p "$(dirname "$out")"
mv "$tmp" "$out"
trap - EXIT
echo "render-ci: wrote $out ($stack toolchain, push on \"$branch\")"
