#!/usr/bin/env bash
# tests/lib/coverage-gate.sh
# Enforce 100% line/branch/function coverage for bin/metaswarm-usage and
# lib/review-rule.js (the only code in this repo whose line coverage can be
# measured; shell scripts are covered by the behavioural suites in tests/*/test-*.sh).
#
# Dev-only: the coverage threshold flags need Node.js >= 22.8. The npm installer's
# runtime requirement (package.json engines, Node 18+) is unaffected.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ver="$(node -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 8 ]; }; then
  echo "coverage gate requires Node.js >= 22.8 for --test-coverage-* thresholds (found $ver)" >&2
  exit 1
fi

cd "$ROOT"
exec node --test --experimental-test-coverage \
  --test-coverage-lines=100 --test-coverage-branches=100 --test-coverage-functions=100 \
  --test-coverage-include=bin/metaswarm-usage \
  --test-coverage-include=lib/review-rule.js \
  tests/lib/metaswarm-usage.test.mjs tests/lib/review-rule.test.mjs
