#!/usr/bin/env bash
# lib/require-ci-check.sh — make the metaswarm CI check required on the default
# branch (#83), so a PR can't merge while coverage fails.
#
# Usage: require-ci-check.sh [--check NAME] [--repo OWNER/NAME]
#
# Adds a repository ruleset named "metaswarm: required CI check" that targets
# the default branch and requires the status check NAME (default "CI checks",
# the job name in templates/ci.yml). Rulesets add to existing branch protection
# and other rulesets; nothing existing is changed. If the ruleset already
# exists, it does nothing. The required check also applies to direct pushes to
# the default branch (no bypass list), so commits land there through PRs. Needs an authenticated `gh` with admin rights on the
# repo. When it can't make the change, it prints the manual steps and exits 1.

set -euo pipefail

RULESET_NAME="metaswarm: required CI check"
check="CI checks"
repo=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) [ $# -ge 2 ] || { echo "require-ci-check: --check needs a value" >&2; exit 1; }; check="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || { echo "require-ci-check: --repo needs a value" >&2; exit 1; }; repo="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "require-ci-check: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# The check name goes into a JSON string; keep it to plain printable text.
case "$check" in
  *'"'*|*'\'*|"") echo "require-ci-check: unsupported check name: $check" >&2; exit 1 ;;
esac

ruleset_json() {
  cat <<EOF
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "$check" } ]
      }
    }
  ]
}
EOF
}

manual() {
  {
    cat <<EOF
require-ci-check: could not add the required check ($1).
To require it by hand: in the repository's Settings → Rules → Rulesets, add a
branch ruleset that targets the default branch, turn on "Require status checks
to pass", and add the check "$check". Or save this as ruleset.json and run,
with admin rights:  gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset.json
EOF
    ruleset_json
  } >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || manual "gh is not installed"
gh auth status >/dev/null 2>&1 || manual "gh is not logged in"
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$repo" ] || manual "could not tell which GitHub repository this is"
fi

existing="$(gh api "repos/$repo/rulesets" --paginate --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || true)"
if [ -n "$existing" ]; then
  echo "require-ci-check: ruleset \"$RULESET_NAME\" already exists on $repo (id $existing); nothing to do"
  exit 0
fi

payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
ruleset_json > "$payload"

if ! err="$(gh api -X POST "repos/$repo/rulesets" --input "$payload" 2>&1 >/dev/null)"; then
  manual "GitHub refused: ${err:-unknown error}"
fi
echo "require-ci-check: $repo now requires \"$check\" on its default branch (ruleset \"$RULESET_NAME\")"
