# Tribunal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use jpegg:build to implement this plan task-by-task.

**Goal:** Fork metaswarm into Tribunal with layered configuration, brainstorming debate, and intelligent agent selection.

**Architecture:** Extend metaswarm's existing skill/command/agent system with three new features, then rename all references from "metaswarm" to "tribunal". The layered config consolidates existing scattered config files into a single `tribunal.yaml`. The debate skill inserts between research and design review. Agent selection wraps the existing external-tools routing with decay-weighted scoring.

**Tech Stack:** Bash (hooks, tests), Node.js (CLI), Markdown (skills, commands, agents), YAML (config), JSONL (stats logging)

---

## Task 1: License & Attribution

**Files:**
- Modify: `LICENSE`
- Create: `ATTRIBUTION.md`

**Step 1: Update LICENSE with dual copyright**

Replace the copyright line in `LICENSE` with:

```
MIT License

Copyright (c) 2026 jpeggdev
Copyright (c) 2025 Dave Sifry (metaswarm)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 2: Create ATTRIBUTION.md**

```markdown
# Attribution

Tribunal is a fork of [metaswarm](https://github.com/dsifry/metaswarm)
by Dave Sifry, licensed under the MIT License.

Original project: https://github.com/dsifry/metaswarm
Fork point: commit 03ce5da (2026-03-08)
```

**Step 3: Commit**

```bash
git add LICENSE ATTRIBUTION.md
git commit -m "docs: add dual copyright and attribution to metaswarm"
```

---

## Task 2: Layered Configuration — `tribunal.yaml` Schema & Resolution

**Files:**
- Create: `skills/config/SKILL.md`
- Create: `templates/tribunal.yaml`
- Modify: `.gitignore` (add `tribunal-stats.jsonl`)

**Step 1: Write the test for config resolution**

Create `tests/config/test-config-resolution.sh`:

```bash
#!/usr/bin/env bash
# tests/config/test-config-resolution.sh
# Validate tribunal.yaml deep-merge resolution logic

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Config Resolution Tests"
echo "======================="
echo ""

# --- Test: resolve-config.js exists ---
if [ -f "$ROOT/lib/resolve-config.js" ]; then
  pass "resolve-config.js exists"
else
  fail "resolve-config.js not found"
fi

# --- Test: common-only resolution (no tool override) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
  sandbox: docker
  coverage:
    lines: 100
    branches: 100
YAML

RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")

if [ "$TIMEOUT" = "300" ]; then
  pass "common-only: timeout_seconds = 300"
else
  fail "common-only: expected 300, got $TIMEOUT"
fi

# --- Test: scalar override ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
  sandbox: docker
claude:
  timeout_seconds: 600
YAML

RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")

if [ "$TIMEOUT" = "600" ]; then
  pass "scalar override: claude timeout_seconds = 600"
else
  fail "scalar override: expected 600, got $TIMEOUT"
fi

# --- Test: nested object merge (not replace) ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  coverage:
    lines: 100
    branches: 100
    functions: 100
gemini:
  coverage:
    branches: 90
YAML

RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "gemini" 2>&1)
LINES=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.lines)")
BRANCHES=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.branches)")
FUNCTIONS=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.functions)")

if [ "$LINES" = "100" ] && [ "$BRANCHES" = "90" ] && [ "$FUNCTIONS" = "100" ]; then
  pass "nested merge: gemini overrides branches only, lines+functions inherited"
else
  fail "nested merge: expected 100/90/100, got $LINES/$BRANCHES/$FUNCTIONS"
fi

# --- Test: array replace (not merge) ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  debate:
    agents:
      - architect
      - security
      - cto
claude:
  debate:
    agents:
      - architect
      - security
      - cto
      - designer
YAML

RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1)
COUNT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.debate.agents.length)")

if [ "$COUNT" = "4" ]; then
  pass "array replace: claude debate agents = 4 (replaced, not merged)"
else
  fail "array replace: expected 4, got $COUNT"
fi

# --- Test: missing tool block uses common as-is ---
cat > "$TMPDIR/tribunal.yaml" << 'YAML'
common:
  timeout_seconds: 300
claude:
  timeout_seconds: 600
YAML

RESULT=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "codex" 2>&1)
TIMEOUT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.timeout_seconds)")

if [ "$TIMEOUT" = "300" ]; then
  pass "missing tool block: codex falls back to common"
else
  fail "missing tool block: expected 300, got $TIMEOUT"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash tests/config/test-config-resolution.sh`
Expected: FAIL — `resolve-config.js not found`

**Step 3: Write the config resolution library**

Create `lib/resolve-config.js`:

```javascript
#!/usr/bin/env node
// lib/resolve-config.js
// Resolves tribunal.yaml by deep-merging common with tool-specific overrides.
// Usage: node resolve-config.js <path-to-tribunal.yaml> <tool-name>
// Output: JSON to stdout

'use strict';

const fs = require('fs');
const path = require('path');

function parseYaml(text) {
  // Minimal YAML parser for tribunal.yaml structure.
  // Supports: scalars, nested objects, arrays (- item syntax), quoted strings.
  // Does NOT support: anchors, tags, multi-line strings, flow syntax.
  const lines = text.split('\n');
  const root = {};
  const stack = [{ indent: -1, obj: root }];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.replace(/\s+$/, '');

    // Skip empty lines and comments
    if (!trimmed || trimmed.match(/^\s*#/)) continue;

    const indent = line.match(/^(\s*)/)[1].length;
    const content = trimmed.trim();

    // Pop stack to find parent at correct indentation
    while (stack.length > 1 && stack[stack.length - 1].indent >= indent) {
      stack.pop();
    }
    const parent = stack[stack.length - 1];

    // Array item
    if (content.startsWith('- ')) {
      const value = content.slice(2).trim();
      if (!parent.arrayKey) continue;
      const arr = parent.obj[parent.arrayKey];
      if (Array.isArray(arr)) {
        arr.push(parseScalar(value));
      }
      continue;
    }

    // Key-value pair
    const colonIdx = content.indexOf(':');
    if (colonIdx === -1) continue;

    const key = content.slice(0, colonIdx).trim();
    const rawValue = content.slice(colonIdx + 1).trim();

    if (rawValue === '' || rawValue === '|' || rawValue === '>') {
      // Nested object — check if next non-empty line is an array item
      const nextLine = findNextContentLine(lines, i + 1);
      if (nextLine && nextLine.trim().startsWith('- ')) {
        parent.obj[key] = [];
        stack.push({ indent, obj: parent.obj, arrayKey: key });
      } else {
        parent.obj[key] = {};
        stack.push({ indent, obj: parent.obj[key] });
      }
    } else {
      parent.obj[key] = parseScalar(rawValue);
    }
  }

  return root;
}

function findNextContentLine(lines, startIdx) {
  for (let i = startIdx; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (trimmed && !trimmed.startsWith('#')) return lines[i];
  }
  return null;
}

function parseScalar(value) {
  if (value === 'true') return true;
  if (value === 'false') return false;
  if (value === 'null') return null;
  // Remove quotes
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  // Number
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value);
  return value;
}

function deepMerge(base, override) {
  const result = { ...base };
  for (const key of Object.keys(override)) {
    const baseVal = base[key];
    const overVal = override[key];

    if (Array.isArray(overVal)) {
      // Arrays: override replaces entirely
      result[key] = [...overVal];
    } else if (overVal && typeof overVal === 'object' && !Array.isArray(overVal) &&
               baseVal && typeof baseVal === 'object' && !Array.isArray(baseVal)) {
      // Objects: recursive merge
      result[key] = deepMerge(baseVal, overVal);
    } else {
      // Scalars: override wins
      result[key] = overVal;
    }
  }
  return result;
}

function resolveConfig(yamlPath, toolName) {
  const text = fs.readFileSync(yamlPath, 'utf8');
  const parsed = parseYaml(text);
  const common = parsed.common || {};
  const toolOverride = parsed[toolName] || {};
  return deepMerge(common, toolOverride);
}

// CLI entry point
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node resolve-config.js <tribunal.yaml> <tool-name>');
    process.exit(1);
  }
  const result = resolveConfig(args[0], args[1]);
  console.log(JSON.stringify(result, null, 2));
}

module.exports = { resolveConfig, deepMerge, parseYaml };
```

**Step 4: Run test to verify it passes**

Run: `bash tests/config/test-config-resolution.sh`
Expected: All 5 tests PASS

**Step 5: Create the default tribunal.yaml template**

Create `templates/tribunal.yaml`:

```yaml
# tribunal.yaml — Layered configuration for Tribunal
# Common settings apply to all CLI tools. Tool-specific blocks override common.
# Resolution: effective_config = deep_merge(common, tool_specific[active_cli])
#
# Scalars: tool-specific wins
# Objects: recursively merged
# Arrays: tool-specific replaces entirely

common:
  timeout_seconds: 300
  sandbox: docker

  coverage:
    lines: 100
    branches: 100
    functions: 100
    statements: 100

  enforcement:
    command: "pnpm test:coverage"
    block_pr_creation: true
    block_task_completion: true

  debate:
    rounds: 2
    agents:
      - architect
      - security
      - cto
    allow_extra_round: true

  agent_selection:
    strategy: weighted_decay
    decay_rate: 0.1
    min_samples: 3
    static_priority:
      default:
        - gemini
        - codex
        - claude
      implementation:
        - gemini
        - codex
        - claude
      review:
        - claude
        - gemini
        - codex
      planning:
        - claude
        - codex
        - gemini
      testing:
        - gemini
        - codex
        - claude

  escalation:
    max_retries: 3
    max_total_attempts: 7
    alert_user_on_exhaustion: true

  health_check:
    per_task: true

# claude:
#   timeout_seconds: 600
#   role: orchestrator

# gemini:
#   timeout_seconds: 180
#   sandbox: none
#   coverage:
#     branches: 90

# codex:
#   sandbox: platform
```

**Step 6: Add tribunal-stats.jsonl to .gitignore**

Append to `.gitignore`:

```
# Tribunal agent performance stats (local per-machine)
tribunal-stats.jsonl
```

**Step 7: Create the config skill document**

Create `skills/config/SKILL.md`:

```markdown
---
name: config
description: Layered configuration resolution for Tribunal — deep-merges common settings with CLI tool-specific overrides
auto_activate: false
triggers:
  - "tribunal config"
  - "resolve config"
---

# Config Resolution Skill

## Purpose

Resolves `tribunal.yaml` by reading the `common` block and deep-merging with the active CLI tool's override block. Produces a single effective configuration used by all other skills.

---

## Config File: `tribunal.yaml`

Lives at project root. Structure:

```yaml
common:
  key: value        # applies to all tools
claude:
  key: override     # overrides common for Claude Code
gemini:
  key: override     # overrides common for Gemini CLI
codex:
  key: override     # overrides common for Codex CLI
```

## Resolution Rules

1. **Scalars**: tool-specific wins
2. **Objects**: recursively merged (tool block only overrides keys it declares)
3. **Arrays**: tool-specific replaces entirely (no array merging)
4. **Missing tool block**: common is used as-is

## Usage

```bash
# From session-start hook or any skill:
node lib/resolve-config.js tribunal.yaml claude
# Output: JSON with effective config
```

## Config Sections

| Section | Used By |
|---------|---------|
| `coverage` | orchestrated-execution (validation phase) |
| `enforcement` | orchestrated-execution (PR/task blocking) |
| `debate` | debate skill (round count, agent list) |
| `agent_selection` | agent-selection skill (scoring, priorities) |
| `escalation` | agent-selection skill (retry limits) |
| `health_check` | external-tools skill (per-task checks) |
| `timeout_seconds` | external-tools skill (adapter timeout) |
| `sandbox` | external-tools skill (adapter sandbox mode) |
```

**Step 8: Commit**

```bash
git add tests/config/test-config-resolution.sh lib/resolve-config.js templates/tribunal.yaml skills/config/SKILL.md .gitignore
git commit -m "feat: add layered config resolution with tribunal.yaml"
```

---

## Task 3: Brainstorming Debate Skill

**Files:**
- Create: `skills/debate/SKILL.md`
- Modify: `skills/brainstorming-extension/SKILL.md` (add handoff to debate)
- Modify: `skills/start/SKILL.md` (insert debate phase in pipeline)

**Step 1: Create the debate skill**

Create `skills/debate/SKILL.md`:

```markdown
---
name: debate
description: Multi-agent brainstorming debate — agents propose solutions, critique each other, and reach consensus before design review
auto_activate: true
triggers:
  - after:research
  - "debate"
  - "brainstorm debate"
---

# Brainstorming Debate Skill

## Purpose

Runs a structured multi-agent debate after the research phase and before the design review gate. Agents propose competing solutions, critique each other's approaches, and the orchestrator synthesizes a ranked recommendation for the user to approve.

---

## Where It Fits

```text
Research phase complete
    ↓
DEBATE PHASE (this skill)
    ↓
Design Review Gate (5 agents approve/reject the chosen approach)
    ↓
Planning → Execution → PR
```

---

## Configuration

Read from `tribunal.yaml` (resolved via `lib/resolve-config.js`):

```yaml
common:
  debate:
    rounds: 2                          # fixed round count
    agents: [architect, security, cto] # who participates
    allow_extra_round: true            # user can request one more
```

---

## Procedure

### Pre-Debate: Load Context

The orchestrator gathers:
- Research findings (from Researcher agent output)
- Task description (from issue or user request)
- Relevant knowledge (from `bd prime`)

### Round 1: Proposals

Spawn each debate agent **in parallel**. Each receives the same context and prompt:

**Prompt template:**

```markdown
You are the [AGENT ROLE] participating in a design debate.

## Task
[Task description]

## Research Findings
[Research output]

## Your Job
Propose a solution to this task. Be specific and concrete.

## Output Format (follow exactly)

## Proposal from [Your Role]
### Approach
[Description of the solution — what to build and how]
### Trade-offs
- Pro: [advantage 1]
- Pro: [advantage 2]
- Con: [disadvantage 1]
- Con: [disadvantage 2]
### Estimated complexity
[Low / Medium / High]
### Risk areas
[What could go wrong]
```

Collect all proposals. If any agent fails to respond, log it and continue with remaining proposals.

### Round 2: Critiques

Share ALL proposals with each debate agent **in parallel**. Each receives:

**Prompt template:**

```markdown
You are the [AGENT ROLE] reviewing proposals in a design debate.

## Task
[Task description]

## All Proposals
[All Round 1 proposals, labeled by agent]

## Your Job
Critique all proposals. Rank them. Defend or revise your own position.

## Output Format (follow exactly)

## Critique from [Your Role]
### Ranking
1. [Best proposal's agent] — [why this is best]
2. [Second best's agent] — [why]
3. [Third's agent] — [why]
### Revised position
[Stick with mine / Switch to X's / Hybrid of X+Y — explain why]
### Blocking concerns
[Any issues that would make a proposal fail in practice, or "None"]
```

Collect all critiques.

### Synthesis

The orchestrator (NOT a subagent) consolidates:

1. **Tally rankings** — count how many times each proposal was ranked #1, #2, #3
2. **Check for consensus** — if all agents ranked the same proposal #1, it's consensus
3. **Identify blocking concerns** — any concern raised by any agent
4. **Draft recommendation** — orchestrator picks the top-ranked proposal

Present to user:

```markdown
## Debate Summary (Round [N] of [total])

### [Consensus / Split Decision]

**Top ranked: [Agent]'s approach** ([X]/[total] agents ranked it #1)
[Brief description of the approach]

**Runner-up: [Agent]'s approach** ([Y]/[total] agents ranked it #1)
[Brief description]

### Key Trade-offs
- [Top approach] is [pro] but [con]
- [Runner-up] is [pro] but [con]

### Blocking Concerns
- [Concern 1, raised by Agent X]
- [Concern 2, raised by Agent Y]
— or —
- None raised

### Recommendation
[Orchestrator's pick and reasoning]

**Options:**
1. Proceed with recommendation
2. Pick a different approach
3. Request another debate round
```

### User Decision

- **Option 1**: Selected approach feeds into design review gate
- **Option 2**: User specifies which approach; that feeds into design review gate
- **Option 3**: Run additional round (only if `allow_extra_round: true` and hasn't been used yet). Extra round uses same critique format with updated context from prior rounds.

### Post-Debate

The winning approach is formatted as a design document and handed to the design review gate. The full debate transcript (proposals + critiques + synthesis) is saved alongside the design doc for reference.

---

## Agent Failure Handling

- If an agent fails in Round 1: proceed without its proposal (min 2 proposals needed)
- If an agent fails in Round 2: its ranking is excluded from tally
- If fewer than 2 agents respond in Round 1: skip debate, alert user, fall back to single-agent design

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | What to Do Instead |
|---|---|---|
| Letting agents see each other's proposals in Round 1 | Anchoring bias — later agents copy the first | Spawn all Round 1 agents in parallel with identical context |
| Orchestrator picking the winner without user input | User must approve the direction | Always present options and wait for user decision |
| Running unlimited rounds | Token cost grows, agents start repeating themselves | Fixed rounds (default 2) + one optional extra round |
| Skipping the debate for "simple" tasks | Simple tasks benefit from multiple perspectives too | Always run debate if configured; user can reduce agent count in config |

---

## Related Skills

- `research` — upstream: provides findings that feed into debate context
- `design-review-gate` — downstream: reviews the chosen approach
- `brainstorming-extension` — bridges external brainstorming into this pipeline
- `config` — reads debate configuration from tribunal.yaml
```

**Step 2: Update brainstorming-extension to hand off to debate**

Modify `skills/brainstorming-extension/SKILL.md` — in the "Procedure: After Brainstorming Completes" section, update Step 2 to route through debate first:

Find the section that says "### Step 2: Invoke the Design Review Gate" and add a pre-step:

```markdown
### Step 2: Run Debate Phase (if configured)

Check `tribunal.yaml` for debate configuration. If `debate.rounds > 0` and `debate.agents` is non-empty:

1. Invoke the `debate` skill with the design document and research findings
2. Wait for user to select an approach
3. The selected approach replaces the original design document

If debate is not configured (no tribunal.yaml or debate section), skip directly to the design review gate.

### Step 3: Invoke the Design Review Gate
```

(Renumber subsequent steps.)

**Step 3: Update start skill pipeline**

Modify `skills/start/SKILL.md` — in the agent roster table, add a row for the debate:

```markdown
| **Debate Agents**        | Propose & critique solutions   | Research complete (before design review) |
```

And in the pipeline flow, insert the debate phase between Research & Planning and Design Review Gate.

**Step 4: Commit**

```bash
git add skills/debate/SKILL.md skills/brainstorming-extension/SKILL.md skills/start/SKILL.md
git commit -m "feat: add multi-agent brainstorming debate skill"
```

---

## Task 4: Intelligent Agent Selection Skill

**Files:**
- Create: `skills/agent-selection/SKILL.md`
- Create: `lib/agent-scorer.js`
- Create: `tests/agent-selection/test-agent-scorer.sh`
- Create: `commands/stats.md`
- Create: `commands/benchmark.md`

**Step 1: Write the test for agent scoring**

Create `tests/agent-selection/test-agent-scorer.sh`:

```bash
#!/usr/bin/env bash
# tests/agent-selection/test-agent-scorer.sh
# Validate agent scoring with weighted decay

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Agent Scorer Tests"
echo "=================="
echo ""

# --- Test: agent-scorer.js exists ---
if [ -f "$ROOT/lib/agent-scorer.js" ]; then
  pass "agent-scorer.js exists"
else
  fail "agent-scorer.js not found"
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test: no history returns static priority ---
cat > "$TMPDIR/stats.jsonl" << 'JSONL'
JSONL

RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)

FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")

if [ "$FIRST" = "gemini" ]; then
  pass "no history: returns static priority (gemini first)"
else
  fail "no history: expected gemini first, got $FIRST"
fi

# --- Test: tool with high recent success rate ranks higher ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)

cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":false,"tags":[]}
JSONL

RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)

FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")

if [ "$FIRST" = "codex" ]; then
  pass "scoring: codex (100% success) ranks above gemini (0% success)"
else
  fail "scoring: expected codex first, got $FIRST"
fi

# --- Test: decay weights recent results more ---
OLD_DATE="2026-02-01T00:00:00Z"

cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$OLD_DATE","tool":"gemini","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
{"timestamp":"$NOW","tool":"codex","task_type":"implementation","success":true,"tags":[]}
JSONL

RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "gemini,codex" \
  --static-priority "gemini,codex" \
  --min-samples 3 \
  --decay-rate 0.1 2>&1)

FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")

if [ "$FIRST" = "codex" ]; then
  pass "decay: recent codex successes outweigh old gemini successes"
else
  fail "decay: expected codex first, got $FIRST"
fi

# --- Test: failure pattern penalty ---
cat > "$TMPDIR/stats.jsonl" << JSONL
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":true,"tags":["api","rest"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"codex","task_type":"implementation","success":false,"tags":["database","async"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
{"timestamp":"$YESTERDAY","tool":"gemini","task_type":"implementation","success":true,"tags":["database","migration"]}
JSONL

RESULT=$(node "$ROOT/lib/agent-scorer.js" \
  --stats "$TMPDIR/stats.jsonl" \
  --task-type "implementation" \
  --available "codex,gemini" \
  --static-priority "codex,gemini" \
  --min-samples 3 \
  --decay-rate 0.1 \
  --task-tags "database,async" 2>&1)

FIRST=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.ranking[0].tool)")

if [ "$FIRST" = "gemini" ]; then
  pass "failure penalty: gemini wins for database tasks despite codex having higher base rate"
else
  fail "failure penalty: expected gemini first for database tasks, got $FIRST"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash tests/agent-selection/test-agent-scorer.sh`
Expected: FAIL — `agent-scorer.js not found`

**Step 3: Write the agent scorer**

Create `lib/agent-scorer.js`:

```javascript
#!/usr/bin/env node
// lib/agent-scorer.js
// Scores available CLI tools for a task using weighted decay + failure pattern matching.
// Usage: node agent-scorer.js --stats <path> --task-type <type> --available <tools> ...
// Output: JSON with ranked tools and scores

'use strict';

const fs = require('fs');

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const key = argv[i].replace(/^--/, '').replace(/-/g, '_');
    args[key] = argv[i + 1];
  }
  return args;
}

function loadStats(statsPath) {
  if (!fs.existsSync(statsPath)) return [];
  const lines = fs.readFileSync(statsPath, 'utf8').trim().split('\n').filter(Boolean);
  return lines.map(line => JSON.parse(line));
}

function daysBetween(dateStr, now) {
  const then = new Date(dateStr).getTime();
  return Math.max(0, (now - then) / (1000 * 60 * 60 * 24));
}

function tagOverlap(taskTags, entryTags) {
  if (!taskTags.length || !entryTags.length) return 0;
  const set = new Set(entryTags);
  const matches = taskTags.filter(t => set.has(t)).length;
  return matches / Math.max(taskTags.length, 1);
}

function scoreTools(stats, taskType, available, staticPriority, minSamples, decayRate, taskTags) {
  const now = Date.now();
  const ranking = [];

  for (const tool of available) {
    const entries = stats.filter(e => e.tool === tool && e.task_type === taskType);

    if (entries.length < minSamples) {
      // Not enough data — use static priority position as score
      const pos = staticPriority.indexOf(tool);
      const score = pos === -1 ? 0 : (staticPriority.length - pos) / staticPriority.length;
      ranking.push({ tool, score, basis: 'static', samples: entries.length });
      continue;
    }

    // Weighted decay score
    let weightedSum = 0;
    let weightSum = 0;

    for (const entry of entries) {
      const age = daysBetween(entry.timestamp, now);
      const weight = Math.exp(-decayRate * age);
      weightedSum += (entry.success ? 1.0 : 0.0) * weight;
      weightSum += weight;
    }

    let score = weightSum > 0 ? weightedSum / weightSum : 0;

    // Failure pattern penalty
    if (taskTags.length > 0) {
      const recentFailures = entries.filter(e => {
        if (e.success) return false;
        const age = daysBetween(e.timestamp, now);
        if (age > 14) return false; // only consider last 14 days
        return tagOverlap(taskTags, e.tags || []) > 0.5;
      });

      if (recentFailures.length > 0) {
        const penalty = Math.max(0.3, 1.0 - (recentFailures.length * 0.15));
        score *= penalty;
      }
    }

    ranking.push({ tool, score, basis: 'weighted_decay', samples: entries.length });
  }

  // Sort by score descending
  ranking.sort((a, b) => b.score - a.score);
  return ranking;
}

if (require.main === module) {
  const args = parseArgs(process.argv);
  const stats = loadStats(args.stats || '');
  const taskType = args.task_type || 'default';
  const available = (args.available || '').split(',').filter(Boolean);
  const staticPriority = (args.static_priority || '').split(',').filter(Boolean);
  const minSamples = parseInt(args.min_samples || '3', 10);
  const decayRate = parseFloat(args.decay_rate || '0.1');
  const taskTags = (args.task_tags || '').split(',').filter(Boolean);

  const ranking = scoreTools(stats, taskType, available, staticPriority, minSamples, decayRate, taskTags);
  console.log(JSON.stringify({ ranking }, null, 2));
}

module.exports = { scoreTools, loadStats };
```

**Step 4: Run test to verify it passes**

Run: `bash tests/agent-selection/test-agent-scorer.sh`
Expected: All 5 tests PASS

**Step 5: Create the agent-selection skill document**

Create `skills/agent-selection/SKILL.md`:

```markdown
---
name: agent-selection
description: Intelligent CLI tool selection using weighted decay scoring and failure pattern matching
auto_activate: false
triggers:
  - "select agent"
  - "pick tool"
  - "route task"
---

# Agent Selection Skill

## Purpose

Selects the best CLI tool (Claude Code, Gemini CLI, Codex CLI) for each task based on historical performance with decay-weighted scoring. Recent results weigh more than old ones, and tools that fail on specific task types get penalized for similar future tasks.

---

## Configuration

From `tribunal.yaml`:

```yaml
common:
  agent_selection:
    strategy: weighted_decay
    decay_rate: 0.1              # higher = forget faster
    min_samples: 3               # below this, use static priority
    static_priority:
      default: [gemini, codex, claude]
      implementation: [gemini, codex, claude]
      review: [claude, gemini, codex]
      planning: [claude, codex, gemini]
      testing: [gemini, codex, claude]
  escalation:
    max_retries: 3
    max_total_attempts: 7
    alert_user_on_exhaustion: true
```

---

## Scoring Algorithm

### Weighted Decay Score

```
score(tool, task_type) = Σ (outcome_i × weight_i) / Σ weight_i

weight_i = e^(-λ × age_in_days)
outcome_i = 1.0 (success) or 0.0 (failure)
λ = decay_rate from config
```

### Failure Pattern Penalty

Before selecting, check if the current task's tags overlap with recent failures:

- Look at failures in the last 14 days for this tool + task type
- If >50% tag overlap with current task: apply penalty
- Penalty = max(0.3, 1.0 - failures × 0.15)
- This means a tool can score well overall but get deprioritized for specific kinds of tasks

### Minimum Samples Fallback

If a tool has fewer than `min_samples` results for this task type, use its position in `static_priority` as its score instead. This prevents one lucky result from overriding sensible defaults.

---

## Selection Flow

```text
Task arrives (type + tags)
    ↓
Health check all configured tools (per-task if health_check.per_task: true)
    ↓
Filter to healthy tools only
    ↓
Score each tool (decay-weighted or static fallback)
    ↓
Apply failure pattern penalties
    ↓
Pick highest scoring tool
    ↓
Dispatch task
    ↓
On completion: log result to tribunal-stats.jsonl
    ↓
On failure: log with failure_reason, failure_category, tags
           → pick next highest scoring tool (skip the one that just failed)
    ↓
After max_total_attempts: alert user with full failure history
```

---

## Logging Format

Each task result is appended to `tribunal-stats.jsonl`:

```jsonl
{"timestamp":"2026-03-08T14:30:00Z","tool":"gemini","task_type":"implementation","success":true,"duration_seconds":45,"files_changed":3,"tags":["api","rest"]}
{"timestamp":"2026-03-08T14:32:00Z","tool":"codex","task_type":"implementation","success":false,"duration_seconds":120,"files_changed":0,"failure_reason":"generated synchronous code for async database migration","failure_category":"async_patterns","tags":["database","migration","async"],"tool_self_report":"completed successfully"}
```

**Who fills in failure context:**
- **Orchestrator** (always): `failure_category`, `tags` — based on observed validation failures
- **Failed tool** (captured but untrusted): `tool_self_report`

---

## Usage from Orchestrator

```bash
# Get ranked tools for a task
node lib/agent-scorer.js \
  --stats tribunal-stats.jsonl \
  --task-type implementation \
  --available "gemini,codex,claude" \
  --static-priority "gemini,codex,claude" \
  --min-samples 3 \
  --decay-rate 0.1 \
  --task-tags "database,async"
```

Output:
```json
{
  "ranking": [
    { "tool": "claude", "score": 0.85, "basis": "weighted_decay", "samples": 12 },
    { "tool": "gemini", "score": 0.72, "basis": "weighted_decay", "samples": 8 },
    { "tool": "codex", "score": 0.31, "basis": "weighted_decay", "samples": 15 }
  ]
}
```

---

## Related Skills

- `config` — reads tribunal.yaml for scoring parameters
- `external-tools` — dispatches to selected tool
- `orchestrated-execution` — calls agent selection before each work unit
```

**Step 6: Create the stats command**

Create `commands/stats.md`:

```markdown
# Agent Performance Stats

View, reset, or export agent performance data used by the intelligent agent selection system.

## Usage

```text
/stats                     Show current scores per tool per task type
/stats reset [tool]        Wipe history for a specific tool or all tools
/stats export              Dump raw JSONL to stdout
```

## Behavior

### `/stats` (no arguments)

1. Read `tribunal-stats.jsonl` from project root
2. Read `tribunal.yaml` to get scoring parameters (decay_rate, min_samples)
3. For each task type with data, run `lib/agent-scorer.js` to compute current scores
4. Display a summary table:

```markdown
## Agent Performance Scores

### implementation (15 samples)
| Tool   | Score | Basis          | Samples | Recent Trend |
|--------|-------|----------------|---------|--------------|
| claude | 0.85  | weighted_decay | 12      | ↑            |
| gemini | 0.72  | weighted_decay | 8       | →            |
| codex  | 0.31  | weighted_decay | 15      | ↓            |

### review (8 samples)
| Tool   | Score | Basis  | Samples | Recent Trend |
|--------|-------|--------|---------|--------------|
| claude | 0.92  | weighted_decay | 5 | ↑          |
| gemini | —     | static | 1       | —            |
```

### `/stats reset [tool]`

- With tool name: delete all entries for that tool from `tribunal-stats.jsonl`
- Without tool name: confirm with user, then delete entire file
- Report how many entries were removed

### `/stats export`

Output the raw contents of `tribunal-stats.jsonl` for external analysis.

## Related

- `/benchmark` — research tool capabilities from the web
- `agent-selection` skill — the scoring system these stats feed
```

**Step 7: Create the benchmark command**

Create `commands/benchmark.md`:

```markdown
# Benchmark Research

Research what the internet thinks about each CLI tool's strengths across different task types, and optionally update static priority defaults.

## Usage

```text
/benchmark                        Research all task types
/benchmark --task-type coding     Focus on a specific type
```

## Behavior

1. Search the web for recent benchmarks, blog posts, and community discussions comparing Claude Code, Gemini CLI, and Codex CLI performance
2. Focus on categories: coding/implementation, code review, planning/architecture, testing, debugging
3. Synthesize findings into a ranked summary with sources

### Output Format

```markdown
## Tribunal Benchmark Report (YYYY-MM-DD)

### Coding / Implementation
1. **Claude Code** — [summary of strengths]
2. **Gemini CLI** — [summary of strengths]
3. **Codex CLI** — [summary of strengths]
Sources: [link1], [link2]

### Code Review
1. **Claude Code** — [summary]
2. **Codex CLI** — [summary]
3. **Gemini CLI** — [summary]
Sources: [link3], [link4]

### Planning / Architecture
...

### Testing
...
```

4. After presenting results, offer:

```markdown
Update static_priority in tribunal.yaml based on these findings? [Y/n]
```

5. If user approves, update the `static_priority` section in `tribunal.yaml` to match the benchmark rankings per task type

**Future enhancement:** Allow benchmark results to influence live weighted scores as a prior, not just static defaults.

## Related

- `/stats` — view current performance data from actual usage
- `agent-selection` skill — uses static_priority as fallback when insufficient data
```

**Step 8: Commit**

```bash
git add tests/agent-selection/test-agent-scorer.sh lib/agent-scorer.js skills/agent-selection/SKILL.md commands/stats.md commands/benchmark.md
git commit -m "feat: add intelligent agent selection with decay scoring"
```

---

## Task 5: Global Rename — metaswarm → tribunal

This task renames all references across 93+ files. Do this last so all new features use the new name from the start.

**Files:**
- Modify: 93+ files containing "metaswarm" (case-insensitive)
- Rename: `cli/metaswarm.js` → `cli/tribunal.js`
- Rename: `commands/metaswarm/` → `commands/tribunal/`
- Rename: `commands/metaswarm-setup.md` → `commands/tribunal-setup.md`
- Rename: `commands/metaswarm-update-version.md` → `commands/tribunal-update-version.md`
- Modify: `package.json` (name, bin, description, repository, keywords)
- Modify: `.claude-plugin/plugin.json` (name, description, homepage, repository)
- Modify: `gemini-extension.json`
- Modify: `.codex/install.sh`
- Modify: `hooks/session-start.sh`
- Modify: `lib/setup-mandatory-files.sh`
- Modify: `lib/platform-detect.js`
- Modify: all templates in `templates/` and `skills/setup/templates/`
- Modify: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
- Modify: `README.md`
- Modify: all skill SKILL.md files
- Modify: all agent .md files (references only)

**Step 1: Rename CLI entry point**

```bash
git mv cli/metaswarm.js cli/tribunal.js
```

**Step 2: Rename Gemini command directory**

```bash
git mv commands/metaswarm commands/tribunal
```

**Step 3: Rename command shim files**

```bash
git mv commands/metaswarm-setup.md commands/tribunal-setup.md
git mv commands/metaswarm-update-version.md commands/tribunal-update-version.md
```

**Step 4: Global string replacement**

Run a find-and-replace across all text files for these patterns (in order — most specific first to avoid partial replacements):

| Find | Replace |
|------|---------|
| `dsifry/metaswarm` | `jpeggdev/tribunal` |
| `METASWARM_MARKER` | `TRIBUNAL_MARKER` |
| `## metaswarm` | `## tribunal` |
| `.metaswarm/` | `.tribunal/` |
| `.metaswarm` | `.tribunal` |
| `metaswarm:` | `tribunal:` |
| `metaswarm-` | `tribunal-` |
| `metaswarm` | `tribunal` |
| `Metaswarm` | `Tribunal` |
| `METASWARM` | `TRIBUNAL` |
| `David Sifry` | (keep as-is — this is attribution, not branding) |
| `david@sifry.com` | (keep as-is) |

**Important**: Do NOT replace in:
- `ATTRIBUTION.md` (references original project by name)
- `docs/plans/2026-03-08-tribunal-extensions-design.md` (references metaswarm as the upstream)
- `.git/` directory
- Any binary files

**Step 5: Update package.json**

```json
{
  "name": "tribunal",
  "version": "0.11.0",
  "description": "Cross-platform installer for Tribunal — multi-agent orchestration for Claude Code, Codex CLI, and Gemini CLI",
  "bin": {
    "tribunal": "cli/tribunal.js"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/jpeggdev/tribunal"
  },
  "keywords": [
    "claude-code", "codex-cli", "gemini-cli", "agents",
    "orchestration", "tdd", "quality-gates", "tribunal"
  ]
}
```

**Step 6: Update plugin.json**

```json
{
  "name": "tribunal",
  "version": "0.11.0",
  "description": "Multi-agent orchestration framework — debate-driven design, intelligent agent selection, layered configuration",
  "author": { "name": "jpeggdev" },
  "homepage": "https://github.com/jpeggdev/tribunal",
  "repository": "https://github.com/jpeggdev/tribunal",
  "license": "MIT"
}
```

**Step 7: Update README.md header**

Replace the first few lines with:

```markdown
# Tribunal

Multi-agent orchestration framework for Claude Code, Codex CLI, and Gemini CLI. Tribunal is built on [metaswarm](https://github.com/dsifry/metaswarm) by Dave Sifry.

Features debate-driven design, intelligent agent selection with decay-weighted scoring, and layered configuration.
```

**Step 8: Run all existing tests to verify nothing broke**

```bash
bash tests/cli/test-installer.sh
bash tests/hooks/test-session-start.sh
bash tests/config/test-config-resolution.sh
bash tests/agent-selection/test-agent-scorer.sh
```

Expected: All tests PASS

**Step 9: Commit**

```bash
git add -A
git commit -m "refactor: rename metaswarm to tribunal across all files"
```

---

## Task 6: Rename GitHub Repository

**Step 1: Rename the remote repo**

```bash
gh repo rename tribunal --repo jpeggdev/metaswarm --yes
```

**Step 2: Update local remote URLs**

```bash
git remote set-url origin git@github.com:jpeggdev/tribunal.git
git remote set-url upstream git@github.com:dsifry/metaswarm.git
```

**Step 3: Push all changes**

```bash
git push origin main
```

**Step 4: Verify**

```bash
gh repo view jpeggdev/tribunal --json name,url
```

Expected: `{"name":"tribunal","url":"https://github.com/jpeggdev/tribunal"}`

---

## Task 7: Migration Command

**Files:**
- Create: `commands/migrate.md`
- Modify: `cli/tribunal.js` (add migrate command)

**Step 1: Write the test**

Create `tests/cli/test-migrate.sh`:

```bash
#!/usr/bin/env bash
# tests/cli/test-migrate.sh
# Validate tribunal migrate command

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "Migration Tests"
echo "==============="
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test: migrates .coverage-thresholds.json into tribunal.yaml ---
mkdir -p "$TMPDIR/.metaswarm"

cat > "$TMPDIR/.coverage-thresholds.json" << 'JSON'
{
  "thresholds": {
    "lines": 95,
    "branches": 90,
    "functions": 100,
    "statements": 95
  },
  "enforcement": {
    "command": "npm test -- --coverage",
    "blockPRCreation": true,
    "blockTaskCompletion": true
  }
}
JSON

cat > "$TMPDIR/.metaswarm/project-profile.json" << 'JSON'
{"stack": "node", "name": "test-project"}
JSON

node "$ROOT/lib/migrate-config.js" "$TMPDIR" 2>&1

if [ -f "$TMPDIR/tribunal.yaml" ]; then
  pass "tribunal.yaml created"
else
  fail "tribunal.yaml not created"
fi

if [ -d "$TMPDIR/.tribunal" ]; then
  pass ".metaswarm/ renamed to .tribunal/"
else
  fail ".tribunal/ directory not found"
fi

# Check coverage values were migrated
LINES=$(node "$ROOT/lib/resolve-config.js" "$TMPDIR/tribunal.yaml" "claude" 2>&1 | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.coverage.lines)")

if [ "$LINES" = "95" ]; then
  pass "coverage.lines migrated correctly (95)"
else
  fail "coverage.lines: expected 95, got $LINES"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash tests/cli/test-migrate.sh`
Expected: FAIL — `migrate-config.js not found`

**Step 3: Write the migration script**

Create `lib/migrate-config.js`:

```javascript
#!/usr/bin/env node
// lib/migrate-config.js
// Migrates metaswarm config files to tribunal.yaml
// Usage: node migrate-config.js <project-dir>

'use strict';

const fs = require('fs');
const path = require('path');

function migrate(projectDir) {
  const report = { created: [], renamed: [], skipped: [], errors: [] };

  // 1. Read .coverage-thresholds.json
  const coveragePath = path.join(projectDir, '.coverage-thresholds.json');
  let coverage = null;
  if (fs.existsSync(coveragePath)) {
    try {
      coverage = JSON.parse(fs.readFileSync(coveragePath, 'utf8'));
    } catch (e) {
      report.errors.push(`Failed to parse ${coveragePath}: ${e.message}`);
    }
  }

  // 2. Read .metaswarm/external-tools.yaml (basic extraction)
  const extToolsPath = path.join(projectDir, '.metaswarm', 'external-tools.yaml');
  let hasExtTools = fs.existsSync(extToolsPath);

  // 3. Build tribunal.yaml
  const lines = [
    '# tribunal.yaml — Migrated from metaswarm config',
    '# See templates/tribunal.yaml for full documentation',
    '',
    'common:',
  ];

  if (coverage && coverage.thresholds) {
    const t = coverage.thresholds;
    lines.push('  coverage:');
    if (t.lines !== undefined) lines.push(`    lines: ${t.lines}`);
    if (t.branches !== undefined) lines.push(`    branches: ${t.branches}`);
    if (t.functions !== undefined) lines.push(`    functions: ${t.functions}`);
    if (t.statements !== undefined) lines.push(`    statements: ${t.statements}`);
  }

  if (coverage && coverage.enforcement) {
    const e = coverage.enforcement;
    lines.push('  enforcement:');
    if (e.command) lines.push(`    command: "${e.command}"`);
    if (e.blockPRCreation !== undefined) lines.push(`    block_pr_creation: ${e.blockPRCreation}`);
    if (e.blockTaskCompletion !== undefined) lines.push(`    block_task_completion: ${e.blockTaskCompletion}`);
  }

  lines.push('  timeout_seconds: 300');
  lines.push('  sandbox: docker');
  lines.push('');
  lines.push('  debate:');
  lines.push('    rounds: 2');
  lines.push('    agents:');
  lines.push('      - architect');
  lines.push('      - security');
  lines.push('      - cto');
  lines.push('    allow_extra_round: true');
  lines.push('');
  lines.push('  agent_selection:');
  lines.push('    strategy: weighted_decay');
  lines.push('    decay_rate: 0.1');
  lines.push('    min_samples: 3');
  lines.push('    static_priority:');
  lines.push('      default:');
  lines.push('        - gemini');
  lines.push('        - codex');
  lines.push('        - claude');
  lines.push('');
  lines.push('  escalation:');
  lines.push('    max_retries: 3');
  lines.push('    max_total_attempts: 7');
  lines.push('    alert_user_on_exhaustion: true');
  lines.push('');
  lines.push('  health_check:');
  lines.push('    per_task: true');

  if (hasExtTools) {
    lines.push('');
    lines.push('# TODO: Review .metaswarm/external-tools.yaml and move adapter configs');
    lines.push('# into tool-specific sections below (claude:, gemini:, codex:)');
  }

  lines.push('');

  const yamlPath = path.join(projectDir, 'tribunal.yaml');
  fs.writeFileSync(yamlPath, lines.join('\n') + '\n');
  report.created.push('tribunal.yaml');

  // 4. Rename .metaswarm/ to .tribunal/
  const metaswarmDir = path.join(projectDir, '.metaswarm');
  const tribunalDir = path.join(projectDir, '.tribunal');
  if (fs.existsSync(metaswarmDir)) {
    if (fs.existsSync(tribunalDir)) {
      report.skipped.push('.tribunal/ already exists');
    } else {
      fs.renameSync(metaswarmDir, tribunalDir);
      report.renamed.push('.metaswarm/ → .tribunal/');
    }
  }

  return report;
}

if (require.main === module) {
  const projectDir = process.argv[2] || process.cwd();
  const report = migrate(projectDir);
  console.log(JSON.stringify(report, null, 2));
}

module.exports = { migrate };
```

**Step 4: Run test to verify it passes**

Run: `bash tests/cli/test-migrate.sh`
Expected: All 3 tests PASS

**Step 5: Create the migrate command doc**

Create `commands/migrate-from-metaswarm.md`:

```markdown
# Migrate from Metaswarm

Upgrade a metaswarm project to Tribunal. Converts config files and renames directories.

## Usage

```text
/migrate-from-metaswarm
```

## Behavior

1. Read `.coverage-thresholds.json` → extract coverage thresholds and enforcement settings
2. Read `.metaswarm/external-tools.yaml` → flag for manual review
3. Generate `tribunal.yaml` with migrated values + new defaults (debate, agent_selection, escalation)
4. Rename `.metaswarm/` → `.tribunal/`
5. Report what changed

```bash
node lib/migrate-config.js .
```

## What Gets Migrated

| Source | Destination |
|--------|-------------|
| `.coverage-thresholds.json` → `thresholds` | `tribunal.yaml` → `common.coverage` |
| `.coverage-thresholds.json` → `enforcement` | `tribunal.yaml` → `common.enforcement` |
| `.metaswarm/project-profile.json` | `.tribunal/project-profile.json` (renamed) |
| `.metaswarm/external-tools.yaml` | Flagged as TODO in tribunal.yaml |

## What Needs Manual Review

- External tools adapter config (`external-tools.yaml`) should be reviewed and moved into tool-specific sections in `tribunal.yaml`
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` references (updated by the global rename, but verify)

## Related

- `/setup` — set up a new Tribunal project from scratch
- `config` skill — how tribunal.yaml resolution works
```

**Step 6: Commit**

```bash
git add tests/cli/test-migrate.sh lib/migrate-config.js commands/migrate-from-metaswarm.md
git commit -m "feat: add migration command from metaswarm to tribunal"
```

---

## Task Summary

| Task | Description | Dependencies |
|------|-------------|--------------|
| 1 | License & Attribution | None |
| 2 | Layered Configuration | None |
| 3 | Brainstorming Debate Skill | None |
| 4 | Intelligent Agent Selection | None |
| 5 | Global Rename (metaswarm → tribunal) | Tasks 1-4 |
| 6 | Rename GitHub Repository | Task 5 |
| 7 | Migration Command | Task 2, 5 |

Tasks 1-4 are independent and can run in parallel. Task 5 depends on all of them. Tasks 6-7 depend on Task 5.
