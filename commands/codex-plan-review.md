# Codex Plan Gap Review

Run iterative Codex reviews on an implementation plan (or any design doc) using the `spec-gap-review` skill from `${CODEX_HOME:-$HOME/.codex}/skills/spec-gap-review/`. Codex reviews the plan, Claude reads P0/P1 findings and patches the plan, then Codex re-reviews — until all blocking issues are resolved or max rounds reached. During the installer transition, also accept the legacy metaswarm-prefixed path if it already exists.

## Arguments

`$ARGUMENTS` — plan path [flags]

Flags:
- `--profile <name>` — preset tuning profile: `speed` | `balanced` | `quality`. Default: read `codex.plan_review.profile` from `.metaswarm/external-tools.yaml`, fallback `quality`.
- `--rounds N` — override max review rounds (ignores profile's rounds setting).
- `--cwd <path>` — directory Codex runs in. Default: repo root detected via `git rev-parse --show-toplevel` from the plan's directory.
- `--no-commit` — skip the "stage + suggest commit" step at terminal state.
- `--critical-from-round <N>` — override profile's Critical-Only Mode start round. Use `never` to disable Critical-Only entirely.
- `--min-score N` — override profile's score floor (ACCEPT requires Overall ≥ N).

## Profiles

Three tuning presets control the speed-vs-quality tradeoff. The profile expands to a set of internal parameters; individual flags can override any one of them.

| Parameter | `speed` | `balanced` | `quality` (default) |
|---|---|---|---|
| `max_rounds` | 2 | 3 | **5** |
| `iteration_2plus_scope` | `[P0, P1]` | `[P0, P1]` | **`[P0, P1, P2]`** |
| `critical_from_round` | `2` | `2` | **`never`** (full-review deltas) |
| `min_overall_score` (ACCEPT floor) | `0` (disabled) | `0` (disabled) | **`90`** |
| Wall-clock (approx) | ~6 min | ~9 min | ~15 min |
| Codex tokens (relative) | 1× | 1.5× | 2.5× |

### When to use each

- **`speed`** — cheap sanity check on a plan you think is already solid. Catches egregious issues, doesn't chase quality.
- **`balanced`** — everyday use. Moves plans from "drafty" to "shippable with known open P2s".
- **`quality`** — important plans (features touching production invariants, anything with deploy/data risk). Keeps going until P0/P1 are closed AND Overall ≥ 90. This is the default.

### Legacy config compatibility

If `.metaswarm/external-tools.yaml` has legacy keys (`max_rounds`, `critical_from_round`) but no `profile`, those keys win and no profile is applied. To adopt profile-based config, delete the legacy keys and set `plan_review.profile: "<name>"`.

## Preflight

Run these checks before starting the loop. Stop and tell the user exactly what to fix if any fail.

1. **Codex CLI available**: `codex --version` succeeds.
2. **Codex authenticated**: `codex login status` output contains "Logged in", OR `$OPENAI_API_KEY` / `$CODEX_API_KEY` is set.
3. **Spec-gap-review skill present**: `${CODEX_HOME:-$HOME/.codex}/skills/spec-gap-review/SKILL.md` exists. During the migration window, also accept `${CODEX_HOME:-$HOME/.codex}/skills/metaswarm-spec-gap-review/SKILL.md`. If neither exists, tell the user: *"Install metaswarm's Codex skills first: `npx metaswarm init --codex` or `curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.codex/install.sh | bash`."*
4. **External tools enabled**: `.metaswarm/external-tools.yaml` in the repo has `adapters.codex.enabled: true`. If the file is missing or the flag is false, tell the user: *"Enable codex first: set `adapters.codex.enabled: true` in `.metaswarm/external-tools.yaml`."*
5. **Plan file exists** and is readable.
6. **Sibling path**: `<plan-stem>-codexreview.md` in the same directory as the plan. If a stale sibling exists from a prior unrelated run, warn the user and ask whether to overwrite or append.
7. **Stdin-close probe** (detects non-TTY stdin hang). Run:
   ```bash
   # Portable 15 s cap: prefer timeout/gtimeout; otherwise use a pure-bash watchdog.
   if command -v timeout >/dev/null 2>&1; then
     timeout 15 codex exec --sandbox read-only "echo ok" < /dev/null
   elif command -v gtimeout >/dev/null 2>&1; then
     gtimeout 15 codex exec --sandbox read-only "echo ok" < /dev/null
   else
     codex exec --sandbox read-only "echo ok" < /dev/null & probe_pid=$!
     ( sleep 15 && kill "$probe_pid" 2>/dev/null ) & kill_pid=$!
     wait "$probe_pid"; probe_exit=$?
     kill "$kill_pid" 2>/dev/null
     exit $probe_exit
   fi
   ```
   If it doesn't exit within 15 s, ERROR with phase `preflight-stdin-hang`: *"Codex is hanging before prompt execution. Verify the Step 2 invocation uses `< /dev/null` — see command docs §'Why `< /dev/null`'. This is an environment-level regression; `codex exec` will not be usable from this harness until fixed."* This probe is cheap (~3 s when healthy) and catches the most common failure mode — a Codex CLI version or harness combination that hangs on non-TTY stdin.
8. **Resolve profile to parameters**. Precedence (highest first):
   1. CLI flags (`--profile`, `--rounds`, `--critical-from-round`, `--min-score`) — always win
   2. Legacy individual yaml keys (`codex.plan_review.max_rounds`, `codex.plan_review.critical_from_round`) — used only if `profile` is not set in yaml
   3. Yaml `codex.plan_review.profile` expanded to defaults
   4. Built-in default profile: `quality`

   After resolution, the internal state for this run is:

   ```
   profile            = <resolved name>
   max_rounds         = <resolved number>
   iteration_2plus_scope = [P0, P1] or [P0, P1, P2]
   critical_from_round   = <N> or `never`
   min_overall_score     = <0 for disabled, or a floor like 90>
   ```

   **Log the resolved values at start** so the user sees which profile is active:

   ```
   [codex-plan-review] profile: quality (max_rounds=5, iter_2+_scope=[P0,P1,P2], critical_from=never, min_score=90)
   ```

## Review Loop

For round = 1 to max_rounds:

### Step 1: Build the prompt

Choose the prompt based on iteration and the resolved `critical_from_round`:

**Round 1** (always uses the baseline prompt, regardless of profile):

```
Review the implementation plan at <PLAN_PATH> using the spec-gap-review skill.
Ground the review in the current repository at <CWD>.
Save the review to <SIBLING_PATH>.
In the `## Prioritized issues` section, prefix every bullet with its gap ID, e.g. `- **G01** (P1) — <finding>`. This is required for downstream parsing.
```

**Round N** (N ≥ 2). Two variants depending on whether Critical-Only Mode is active:

**Variant A — Critical-Only delta** (used when `critical_from_round != never` AND current round ≥ `critical_from_round`; applies to `speed` and `balanced` profiles):

```
Re-review the implementation plan at <PLAN_PATH> using the spec-gap-review skill in Critical-Only Mode.
Compare against the prior review at <SIBLING_PATH>.
Update that file in place with a round-aware delta.
Focus on P0 and P1 issues only. Carry forward stable gap IDs.
In the `## Prioritized issues` section, prefix every bullet with its gap ID, e.g. `- **G01** (P1) — <finding>`. This is required for downstream parsing.
```

**Variant B — Full-review delta** (used when `critical_from_round == never`, OR current round < `critical_from_round`; applies to `quality` profile):

```
Re-review the implementation plan at <PLAN_PATH> using the spec-gap-review skill.
Compare against the prior review at <SIBLING_PATH>.
Update that file in place with a round-aware delta review.
Focus on P0, P1, and P2 issues. Carry forward stable gap IDs.
In the `## Prioritized issues` section, prefix every bullet with its gap ID, e.g. `- **G01** (P1) — <finding>`. This is required for downstream parsing.
```

Variant B produces fuller output (P2 findings included), so the patcher in Step 5 has P2 findings to act on. Critical-Only Mode (Variant A) suppresses P2 output to save tokens.

### Step 2: Invoke codex

```bash
# workspace-write is REQUIRED — the prompt instructs codex to save the sibling review file.
# Do NOT downgrade to --sandbox read-only; the write will silently fail and the loop errors out.
#
# < /dev/null is REQUIRED — see "Why `< /dev/null`" below. Without it, codex hangs
# at 0% CPU with "Reading additional input from stdin..." and never runs.
#
# 3600s (1 hr) is a pathological-case ceiling, not a quality budget. Real hangs are
# caught earlier by the hang watcher below; this trip only fires if everything else
# fails. Lower it only if you know the plan is small and want faster ERROR feedback.
#
# `timeout(1)` is NOT available on macOS by default (it ships with GNU coreutils only,
# reachable as `gtimeout` after `brew install coreutils`). Detect and fall back:
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout 3600";
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout 3600";
fi
# If neither exists, the hang-watcher below is the only ceiling. That's acceptable —
# the watcher catches the real failure modes; the 3600s ceiling is a belt on top of
# suspenders. Do NOT block the command on requiring coreutils.
#
# CODEX_LOG captures combined stdout/stderr so the hang-watcher (below) can use
# log size as one of its activity signals. Without it, $CODEX_LOG would be unset,
# `wc -c < "$CODEX_LOG"` always emits 0, and the watcher loses one of its four
# signals — risking false-positive `codex-hang` on reasoning-heavy rounds with
# no tool calls and no sibling-file writes yet.
CODEX_LOG=$(mktemp)
$TIMEOUT_CMD codex exec --sandbox workspace-write --json "<PROMPT>" < /dev/null >"$CODEX_LOG" 2>&1 &
codex_pid=$!
```

- **Sandbox must be `workspace-write`, not `read-only`.** The skill needs to write/update the sibling review file. `read-only` would block that. `workspace-write` scopes writes to cwd (the repo root set below), which is what we want — Codex can save the sibling file but can't escape the repo.
- Run with cwd = `<CWD>` (the repo root, detected from the plan's directory via `git rev-parse --show-toplevel`) so Codex can ground in the repo AND the workspace-write scope covers the plan's directory
- **Hard ceiling: 3600 s (1 hr)** via `timeout`/`gtimeout` wrapper when available — catches pathological runaways only. `quality` profile nominal wall-clock is ~15 min but can legitimately reach 30+ min on large plans with `xhigh` reasoning, so do **not** lower this to the spec's old "300 s" value (that was wrong for anything beyond a speed sanity check). On systems without `timeout` (macOS default) or `gtimeout` (macOS with `brew install coreutils`), the hang-watcher below is the only ceiling — the command still works, just without the 1 hr belt-and-suspenders.
- Pass only `HOME`, `PATH`, `OPENAI_API_KEY`, `CODEX_API_KEY` in env (minimal)
- Capture stdout for error/status only; do NOT parse stdout for the scorecard

#### Why `< /dev/null`

Codex 0.121.0+ treats **any non-TTY stdin** as "someone might pipe me input, let me wait for EOF before processing." In Claude Code's Bash tool (and any CI or agent harness), stdin is inherited from a long-running parent process and never closes. Result: the prompt argv is parsed but never executed — the process sits at 0 % CPU, 0 ESTABLISHED TCP connections, sibling file never created. The log stops at `Reading additional input from stdin...`.

Redirecting stdin from `/dev/null` delivers EOF immediately; codex skips the "stdin append" path and uses only the argv prompt. Works in TTY, non-TTY, CI, and backgrounded contexts identically.

*Do not* remove the `/dev/null` redirect on the theory that "the prompt is passed as argv, why would codex read stdin?" — codex reads stdin regardless, to support the `"<prompt> + <stdin>-appended-block"` invocation pattern documented in `codex exec --help`.

#### Hang-watcher (required)

The 3600 s `timeout` catches catastrophic hangs but wastes an hour of wall-clock. A live codex run fluctuates between three observable signals — **reasoning** (≥1 % CPU), **tool calls** (≥1 ESTABLISHED TCP), **file I/O** (sibling file or log size changes). A stuck run shows 0 on all three. Watch for that signature:

```bash
# Poll every 60 s while codex is running. If ALL THREE signals are 0 for 5
# consecutive samples (5 min), kill codex — it's hung, not working.
hang_count=0
last_log_size=0
last_sibling_size=0
while kill -0 "$codex_pid" 2>/dev/null; do
  sleep 60
  cpu=$(ps -p "$codex_pid" -o pcpu= 2>/dev/null | tr -d ' ')
  net=$(lsof -p "$codex_pid" -iTCP -sTCP:ESTABLISHED -n 2>/dev/null | wc -l | tr -d ' ')
  log_size=$(wc -c < "$CODEX_LOG" 2>/dev/null || echo 0)
  sibling_size=$(wc -c < "$SIBLING_PATH" 2>/dev/null || echo 0)
  if [[ "${cpu%%.*}" == "0" ]] \
     && [[ "$net" == "0" ]] \
     && [[ "$log_size" == "$last_log_size" ]] \
     && [[ "$sibling_size" == "$last_sibling_size" ]]; then
    hang_count=$((hang_count + 1))
    if [[ "$hang_count" -ge 5 ]]; then
      kill "$codex_pid" 2>/dev/null
      break  # classify as codex-hang below
    fi
  else
    hang_count=0
  fi
  last_log_size=$log_size
  last_sibling_size=$sibling_size
done
wait "$codex_pid"
codex_exit=$?
```

Why all four signals in the conjunction (not just CPU)? A codex run streaming reasoning tokens can appear to idle CPU while the log grows; a run doing a long file write can have 0 CPU and 0 network. Requiring all four to be flat ≥5 min is the narrowest filter that still catches the real "stdin-wait" signature observed in practice.

**If the watcher kills codex**: classify as `codex-hang` (distinct from `codex-timeout` which means the 3600 s ceiling tripped). Retry once with the same prompt. If it hangs again, ERROR with phase `codex-hang`: *"Codex stalled at 0 % CPU / 0 network / 0 file I/O for 5 min. Verify `< /dev/null` is in the invocation and that codex 0.121.0+ is installed. See command docs §'Why `< /dev/null`'."*

If codex exits non-zero:
- Exit code 124 (from `timeout`): classify as `codex-timeout`. Retry once. Second failure → ERROR phase `codex-timeout`.
- Exit code from hang-watcher `kill`: classify as `codex-hang` (above).
- Any other non-zero: first failure retry once with the same prompt; second failure stop the loop, report stderr + exit code, suggest `codex login status` to the user.

### Step 3: Read the sibling file

After a successful codex invocation, read `<SIBLING_PATH>`.

Expected structure (from spec-gap-review skill Output Shape):

| Section | What it contains |
|---|---|
| `## Round status` | round number, delta-vs-baseline flag |
| `## Executive summary` | 2–3 sentences |
| `## Rollups` | Overall /100, Quality /100, Completeness /100 + deltas |
| `## Core scorecard` | 6 rubric dimensions × (score, weight, points, delta) |
| `## Gap tracker` | stable IDs (G01, G02…) × status (closed, partial, open, new) |
| `## Detailed findings` | grouped by rubric area with file:line references |
| `## Prioritized issues` | P0, P1, P2, P3 sections |
| `## Path to 100` | exact changes needed |
| `## Recommended next actions` | top 5 highest-leverage fixes |

If the file is not usable, classify precisely — the fix for each sub-case differs:

- **File missing** (sibling was never created): Codex was blocked from writing or never started. Most common causes, in order of observed frequency:
  1. **Stdin hang** — `< /dev/null` missing from the Step 2 invocation. Check the codex log for `Reading additional input from stdin...`; if present, that's the cause. → ERROR, phase: `codex-stdin-hang`. Point the user at §'Why `< /dev/null`'.
  2. **Sandbox too restrictive** — `--sandbox read-only` instead of `workspace-write`. → ERROR, phase: `codex-write-blocked`. Tell the user to verify the sandbox flag.
  3. **Filesystem** — gitignored path, full disk, permissions. → ERROR, phase: `codex-write-blocked`.
  4. **Hang watcher fired** — see `codex-hang` classification in Step 2.
- **File present but malformed** (missing one or more required sections, especially `## Prioritized issues`): Codex produced non-spec output. Likely a Codex CLI regression, a skill-prompt mismatch, or an OOM truncation. → ERROR, phase: `file-parse`. Surface the first and last 20 lines of the sibling file so the user can diagnose.
- **File present but `Prioritized issues` bullets lack gap ID prefixes**: fall back to scanning `## Detailed findings` for GID↔severity mapping before giving up. If that also fails → ERROR, phase: `file-parse`.

### Step 4: Parse the terminal condition

**Capture score trajectory.** Before evaluating terminal conditions, record this round's Overall / Quality / Completeness scores from the `## Rollups` section. Append to a running list for use in Wrap-up terminal outputs.

**Count open blockers.** From `## Prioritized issues`, map each bullet's gap ID to its status in `## Gap tracker`:

- Count P0 entries whose gap-tracker status is `open`, `partial`, or `new` (ignore `closed`).
- Count P1 entries whose gap-tracker status is `open`, `partial`, or `new`.

If `## Prioritized issues` bullets lack GID prefixes despite the prompt instruction, fall back to `## Detailed findings` which always cites the GID next to the severity.

**Evaluate terminal conditions in this order:**

**ACCEPT** — ALL of the following:
- Open P0 count == 0
- Open P1 count == 0
- `min_overall_score == 0` (disabled) OR the current Overall score ≥ `min_overall_score`

The score-floor clause catches a subtle quality gap: a plan can have "no P0/P1 blockers" yet still sit at Overall 82 because of stable-by-design P2s. In `quality` profile, the 90 floor forces Codex to either close enough P2s to lift the score OR confirm that the remaining P2s are genuinely "deliberate design choices" (skill closes them as such, which restores the score). Terminate successfully.

**STALLED** — **BOTH** of the following are true:
- (a) The set of open gap IDs is identical to the prior round's (same IDs, same count)
- (b) The Overall readiness score is unchanged OR regressed vs. the prior round

The score-regression clause is critical: if gap IDs repeat but the Overall score improved by any margin, the loop is **narrowing** (Codex is finding new nuances within the same gaps), not stalling. Only declare STALLED when patches stop moving the scorecard. Terminate without ACCEPT.

**MAX_ROUNDS** — round == max_rounds and neither ACCEPT nor STALLED applies. Terminate without ACCEPT.

Otherwise continue to Step 5.

### Step 5: Patch the plan

**Scope of fixes depends on iteration AND the resolved profile's `iteration_2plus_scope`:**

| Iteration | Scope (all profiles) |
|---|---|
| **Iteration 1** (first Codex pass) | Every open finding: P0, P1, P2, P3 (not `closed`) |
| **Iteration 2+** | Findings whose severity is in `iteration_2plus_scope` (set by profile): `speed`/`balanced` → `[P0, P1]`; `quality` → `[P0, P1, P2]` |

If the profile includes P2 in iteration 2+ (quality), Codex is run without Critical-Only Mode so its output carries P2 findings to act on. If the profile excludes P2 (speed, balanced), Critical-Only Mode is active and P2 is only addressed when the skill promotes it to blocking per its own Critical-Only rule.

Rationale: the first review has the most signal. Most P2/P3 findings are cheap to fix alongside P0/P1 while the plan is open. In subsequent rounds, P2/P3 "noise" distracts from the blockers and risks churning on stable-by-design choices. The spec-gap-review skill's rule — *"Do not keep re-penalizing a deliberate design choice… if the choice is internally consistent, repo-aligned, and operationally workable, treat it as a tradeoff, not a standing gap"* — further supports ignoring stable P2/P3 after iteration 1.

**Drift exception for iteration 2+.** You MAY touch P2/P3 content in iteration 2+ when it's necessary to remove drift introduced by a P0/P1 fix — e.g., if a P1 invariant rewrite leaves contradictory prose in a section flagged as P2 in round 1, update the P2-flagged content to resolve the contradiction. You may NOT touch P2/P3 content in iteration 2+ for independent improvement. The test is: "Does leaving this P2/P3 content intact make my P0/P1 fix incomplete or self-contradictory?" If yes, touch it. If no, leave it.

For each finding in scope:

1. Read the referenced plan section (use the file:line citations)
2. **Verify the citation** — for each file:line reference in the finding, read the cited location in the current repo to confirm it matches what Codex described. Codex's file:line citations can be stale (after a recent edit) or misinterpreted. If a citation is wrong, the finding may still be valid but the fix target may need adjustment. Do not apply fixes based on citations you have not verified.
3. Apply the fix described in the finding OR in the `Path to 100` section
4. Verify intra-doc consistency — if the fix touches a type/schema/command, check every other reference to it in the plan
5. Note the change: one line per finding, format `- <GID> <severity>: <what changed>`

After patching, loop to Step 1 for the next iteration.

## Wrap-up

Report one of these outcomes:

### ACCEPTED (round N, score X/100)

```
CODEX PLAN REVIEW: ACCEPTED
Profile: <profile-name>
Plan: <PLAN_PATH>
Rounds run: N
Final score: Overall X/100, Quality Y/100, Completeness Z/100
Score trajectory (Overall): <R1-score> → <R2-score> → ... → <final>
Score floor (min_overall_score): <value or "disabled">
Review file: <SIBLING_PATH>
Fixes applied across rounds: <count>
```

Unless `--no-commit`:
1. `git -C <CWD> add <PLAN_PATH> <SIBLING_PATH>`
2. Print `git -C <CWD> diff --cached --stat`
3. Suggest commit message:
   `docs(plan): <plan-stem> — codex gap review PASS (N rounds, score X/100)`
4. **Do NOT auto-commit**. User commits when satisfied.

### MAX_ROUNDS (round cap hit)

```
CODEX PLAN REVIEW: MAX_ROUNDS
Profile: <profile-name>
Plan: <PLAN_PATH>
Rounds run: N (cap)
Open blocking issues: <P0 count> P0, <P1 count> P1
Final Overall score: <X>/100 (floor: <min_overall_score or "disabled">)
Score trajectory (Overall): <R1-score> → <R2-score> → ... → <final>
Last-round Overall delta: <+N / -N / 0>
Review file: <SIBLING_PATH>
```

List the remaining P0 and P1 findings. Offer three options:
1. **Accept and defer** — append a `## Deferred Gaps (codex)` section to the plan (see schema below) enumerating the remaining issues, treating them as "to be covered in implementation". Commit as `ACCEPTED (deferred)`.
2. **Revise manually and re-run** — user edits the plan, then runs `/codex-plan-review <plan-path>` again (command iteration counter resets; skill absolute round counter continues).
3. **Abort** — no changes committed. Sibling file stays for reference.

**Recommendation hint**: if the last-round Overall delta is ≥ +5, mark option (2) as recommended. The loop is converging; one more re-run is likely to reach ACCEPT. Format:

```
2. **Revise manually and re-run** ← recommended (score trending up: +<delta> last round)
```

If the last-round delta is ≤ 0 or < +5, present the three options neutrally without marking any as recommended.

Ask the user which to choose. Do not pick for them.

**Deferred Gaps (codex) schema.** When a user chooses option (1) at MAX_ROUNDS or STALLED, append this exact structure at the end of the plan (after all existing content, before any trailing whitespace). Future invocations of `/codex-plan-review` detect these IDs and either close them (if the plan evolved) or carry them forward with stable lineage.

```markdown
## Deferred Gaps (codex)

Preserved from Codex plan review on <YYYY-MM-DD>. These findings are deferred to implementation and not treated as blockers.

- **<GID>** (<severity>) — <one-line summary from the sibling file>. Review: `<relative-sibling-path>`.
- **<GID>** (<severity>) — <one-line summary from the sibling file>. Review: `<relative-sibling-path>`.
```

Each row preserves the exact gap ID from the final sibling file. `<relative-sibling-path>` is relative to the plan file (usually `./<plan-stem>-codexreview.md`).

### STALLED

```
CODEX PLAN REVIEW: STALLED
Profile: <profile-name>
Plan: <PLAN_PATH>
Rounds run: N
Reason: Open gap IDs unchanged AND Overall score unchanged-or-regressed between rounds (N-1) and N — patches are not moving the needle.
Score trajectory (Overall): <R1-score> → <R2-score> → ... → <final>
Review file: <SIBLING_PATH>
```

This usually means Claude's fix pass isn't addressing the real issue Codex is flagging. Ask the user to review the findings manually. Offer the same three options as MAX_ROUNDS (including the Deferred Gaps schema if they choose option 1). Do NOT suggest option 2 as recommended in STALLED — by definition the loop is not converging, so re-running without plan revision is unlikely to help.

### ERROR

```
CODEX PLAN REVIEW: ERROR
Phase: <preflight | codex-invocation | file-parse>
Detail: <message>
```

For preflight errors, tell the user the exact fix. For codex-invocation errors, surface the stderr tail. For file-parse errors, print the unparseable section of the sibling file.

## Division of Labor (Command vs Skill)

This command and the `spec-gap-review` Codex skill both have "round" and "loop" concepts. They are **deliberately different**, with a clean ownership split. Claude should never try to override the skill's internal logic — read its output, trust it, and act.

| Concern | Owned by | Notes |
|---|---|---|
| **Rubric & scoring** (6 dims × 0–5, /100 rollups) | Skill | Command never re-scores or overrides |
| **Gap IDs** (G01, G02…) | Skill | Command reads them, never assigns |
| **Round number in the sibling file** | Skill | Counts absolute review rounds on this plan's *file lineage* |
| **Loop iteration counter** (1 of max_rounds) | **Command** | Counts Codex invocations in *this command invocation* |
| **In-place file update** | Skill | Triggered by the command's prompt saying "save" or "update in place" |
| **Critical-Only Mode** | Skill | Activated by the command's prompt phrasing on iteration 2+ |
| **"Don't re-penalize deliberate choices" rule** | Skill | Command trusts it; doesn't second-guess stable P2/P3 |
| **Terminal condition** (0 P0 + 0 P1) | **Command** | Skill always produces findings; command decides when to stop calling it |
| **Patching the plan** | **Command** (via Claude) | Skill is read-only on the plan itself |
| **Commit staging** | **Command** | Only at ACCEPT terminal state |

### Round number disambiguation

The two counters are independent by design:

- **Skill's `Round status`**: `Round N` in the saved file counts how many times this plan's sibling file has been reviewed across its entire lifetime (every `/codex-plan-review` invocation ever).
- **Command's iteration counter**: `N of max_rounds` in command output counts Codex invocations within *this* command invocation only.

If a user runs `/codex-plan-review plan.md` once and hits MAX_ROUNDS, then runs it again days later after revisions, the skill might emit `Round 4` on the first Codex call while the command reports `iteration 1 of 3`. **Both are correct.** On iteration 1, **always** log both unconditionally (not only when they diverge — the unconditional log aids debugging and costs nothing):

```
[codex-plan-review] iteration 1 of 3
[codex-plan-review] skill reports this is round N of plan review lineage
```

**Iteration counter reset rules:**

- The iteration counter **resets to 1** on ERROR terminal (no usable sibling file was produced, so there's nothing to resume from).
- The iteration counter **continues incrementing** on ACCEPT, MAX_ROUNDS, and STALLED terminals — but since these are terminal, "continues" only applies if the user manually re-runs with the same sibling file in place. In that case the command starts fresh at `iteration 1 of 3` again; the skill's absolute round counter keeps advancing because the sibling file persists.

### How the prompts avoid competition

| Iteration | Prompt verb | Triggers skill behavior |
|---|---|---|
| 1 (no sibling exists) | "Save the review to …" | Skill treats as `Round 1 - Baseline` |
| 1 (sibling exists from prior invocation) | "Save the review to …" | Skill detects existing file, updates in place with next round number |
| 2+ (within same invocation) | "Update that file in place… Critical-Only Mode" | Skill updates delta, switches to critical-only output |

The command never tells the skill what round number to use. The skill never tells the command when to stop calling. Clean separation.

### If the sibling file exists on entry

Preflight asks whether to overwrite (start fresh) or continue (skill will pick up from last saved round). Default: continue. To force a fresh baseline, delete the sibling manually before running, or answer "overwrite" at the preflight prompt.

## Notes

- **Doc-type agnostic.** `spec-gap-review` handles PRDs, implementation guides, strategy docs, infrastructure plans, memory designs. This command doesn't care what kind of doc you pass.
- **No mid-loop commits.** Intermediate iterations are not committed. The sibling file preserves round-to-round history inside itself via gap ID status evolution (`new` → `open` → `partial` → `closed`). At ACCEPT, one commit contains the final plan + final review file.
- **Not a substitute for `plan-review-gate`.** This runs AFTER the metaswarm plan-review-gate passes — Codex is a cross-model second opinion, not a replacement for the 3 adversarial Claude reviewers.
- **Related**: `.metaswarm/external-tools.yaml` also controls code-level Codex review in orchestrated execution (Codex as implementer or reviewer in work units). That's a separate pipeline; this command only reviews planning documents.
