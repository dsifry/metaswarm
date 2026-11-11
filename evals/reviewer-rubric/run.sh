#!/usr/bin/env bash
# Eval for #105: does a fresh reviewer subagent apply its rubric and role
# criteria when the orchestrator's prompt does not name them?
#
# Usage: evals/reviewer-rubric/run.sh <label> [trials=3] [plugin-dir=repo root] [scenario...]
# Calls the model (costs money); run manually, never in CI.
#
# Each scenario (scenarios/<name>/) has fixture.sh (builds a tiny git repo),
# prompt.txt (a paraphrased reviewer prompt that names no rubric, like the
# ones orchestrators write in practice) and meta.json (agent type, rubric name
# and the regex checks for its planted defects). A headless `claude -p` session
# loads metaswarm from <plugin-dir> and spawns the reviewer with that prompt.
set -euo pipefail

LABEL="${1:?usage: run.sh <label> [trials] [plugin-dir] [scenario...]}"
TRIALS="${2:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "${3:-$HERE/../..}" && pwd)"
shift $(( $# < 3 ? $# : 3 ))
if [ $# -gt 0 ]; then SCENARIOS=("$@"); else
  SCENARIOS=(); for d in "$HERE"/scenarios/*/; do SCENARIOS+=("$(basename "$d")"); done
fi
OUT_ROOT="${EVAL_OUT:-$HERE/results}/$LABEL"

for sc in "${SCENARIOS[@]}"; do
  SD="$HERE/scenarios/$sc"
  OUT="$OUT_ROOT/$sc"
  mkdir -p "$OUT"
  AGENT="$(node -e 'console.log(require(process.argv[1]).agent)' "$SD/meta.json")"
  MAIN_PROMPT="Use the Agent tool exactly once with subagent_type \"$AGENT\" and pass it exactly the prompt between the markers, unchanged. Then print the reviewer's reply verbatim and nothing else.
<<<PROMPT
$(cat "$SD/prompt.txt")
PROMPT>>>"
  SCORES=()  # summarise only this run's trials, not leftovers from an earlier run under the same label
  for i in $(seq 1 "$TRIALS"); do
    fx="$(mktemp -d "${TMPDIR:-/tmp}/rr-fixture.XXXXXX")"
    ( cd "$fx" && git init -q -b main && git config user.email eval@example.com \
        && git config user.name eval && printf '# fixture\n' > README.md \
        && git add -A && git commit -qm init && bash "$SD/fixture.sh" )
    log="$OUT/trial-$i.jsonl"
    ( cd "$fx" && claude -p "$MAIN_PROMPT" \
        --plugin-dir "$PLUGIN_DIR" --add-dir "$PLUGIN_DIR" \
        --setting-sources project \
        --allowedTools "Agent Read Grep Glob Bash(git *) Bash(cat *) Bash(ls *) Bash(dirname *) Bash(command *) Bash(sed *) Bash(head *) Bash(grep *) Bash(find *)" \
        --output-format stream-json --verbose --max-budget-usd 3 \
        > "$log" 2>"$OUT/trial-$i.err" ) || echo "$sc trial $i: claude exited $?" >&2
    rm -rf "${fx:?}"
    node "$HERE/score.js" "$SD/meta.json" "$log" > "$OUT/trial-$i.score.json" || true
    echo "$sc #$i $(cat "$OUT/trial-$i.score.json")"
    SCORES+=("$OUT/trial-$i.score.json")
  done
  node "$HERE/score.js" --summary "${SCORES[@]}" > "$OUT/summary.json"
done
node "$HERE/score.js" --report "$OUT_ROOT" | tee "$OUT_ROOT/report.md"
