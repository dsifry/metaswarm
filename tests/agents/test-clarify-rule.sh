#!/usr/bin/env bash
# tests/agents/test-clarify-rule.sh
# Issue #103: Clarify rule, misunderstanding analysis, signal fields, round history.
# Each work unit appends the files it changes to the stale-reference list.
# WU2: guides/delivery-scope.md and its mirrors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUIDE_REL="guides/delivery-scope.md"
GUIDE="$REPO_ROOT/$GUIDE_REL"
PASS=0
FAIL=0
FIX=""
DONE=0
trap '${FIX:+rm -rf "$FIX"}; [ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# section <file> <heading-regex>: from the matching heading to the next heading of the same or higher level
section() {
  [ -f "$1" ] || return 0
  awk -v re="$2" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$1"
}

assert_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$text"; then fail "$label: missing '$s'"; return; fi
  done
  pass "$label"
}

assert_not_in() { # <label> <text> <fixed-string>...
  local label="$1" text="$2" s; shift 2
  for s in "$@"; do
    if grep -qF -- "$s" <<<"$text"; then fail "$label: contains '$s'"; return; fi
  done
  pass "$label"
}

G=""; [ -f "$GUIDE" ] && G="$(cat "$GUIDE")"

# ---------------------------------------------------------------------------
echo "Signal fields"
# ---------------------------------------------------------------------------
SF="$(section "$GUIDE" '^### Signal fields')"
assert_in "guide: Signal fields subsection lists the fields" "$SF" \
  'needs_user: yes | no' 'origin: implementation | requirement | assumption' \
  'assumption: <ledger id' 'theme: <short label>' 'canonicalTheme' 'fix_induced' 'mergedInto'
assert_in "guide: Signal fields explains scope and the re-request rule" "$SF" \
  'six core fields plus signal fields' \
  'optional on non-blockers' \
  'one re-request' \
  'treated as unknown' \
  'triggers nothing' \
  'already answers'

# ---------------------------------------------------------------------------
echo "Iteration rule: seven lines and signal notes"
# ---------------------------------------------------------------------------
IR="$(section "$GUIDE" '^## Iteration rule')"
assert_in "guide: seven ordered lines" "$IR" \
  '1. no blocker: yes findings            → PASS, advance' \
  '2. a Clarify signal (C1–C4) fires' \
  '3. round >= 10 (SAFETY_CAP)            → escalate; report "cap hit" as an overengineering signal' \
  '4. the same critical/major finding recurs after a fix attempt for it,' \
  '5. an overengineering signal is present → restate the DoD' \
  '6. this round fixed ≥1 critical/major, or ≥2 independent reviewers reported blockers' \
  '7. otherwise                           → fix blockers, re-validate, FRESH review'
assert_in "guide: C1-C4 signal notes" "$G" \
  '**C1**' '**C2**' '**C3**' '**C4**' \
  'needs_user: yes' 'not in the ledger' \
  'three rounds' 'diverge' 'fix_induced: yes' 'canonical theme' \
  'distinct blockers' 'windowStart' 'ackThemes' 'ackFindings'
assert_in "guide: themes note (canonical labels, orchestrator maps)" "$G" \
  'Themes' 'canonical theme' 'reuse one when it fits' 'do not see the earlier findings'
assert_in "guide: history file section" "$G" \
  '.beads/context/review-history/' 'status' 'active' 'clarify-pending' 'closed' \
  'pendingClarify' 'one file per gate occurrence' \
  'stable role names' 'never per-instance ids' 'exits 2' \
  'unreadable file' 'invalid JSON' 'integer >= 1' 'strictly increasing'
assert_in "guide: helper section" "$G" \
  'lib/review-rule.js' 'RULE_LINES' 'authoritative' 'applies the rule by hand' \
  '{line, action, signals, capHit}' 're-ask'

# ---------------------------------------------------------------------------
echo "Clarify section: misunderstanding analysis"
# ---------------------------------------------------------------------------
CL="$(section "$GUIDE" '^## Clarify')"
[ -n "$CL" ] && pass "guide: has a Clarify section" || fail "guide: has a Clarify section"
MA="$(section "$GUIDE" '^### Misunderstanding analysis')"
assert_in "guide: analysis traces each assumption to the user's words" "$MA" \
  "Trace each load-bearing assumption to the user's words" \
  'agent-proposed, never confirmed'
assert_in "guide: analysis states the goal with no mechanism" "$MA" \
  'State the goal in one sentence, with no mechanism in it'
assert_in "guide: analysis offers 1-3 reframings naming the 4 patterns" "$MA" \
  '1–3 alternative readings' \
  '**A level mismatch:**' '*what*' 'where or how' \
  '**Over-reading scope:**' \
  '**A proposal read as a decision:**' \
  '**A one-word acknowledgement taken as approval of a message with several parts.**'
assert_in "guide: analysis checks each blocker theme against each reframing" "$MA" \
  'For each blocker theme' 'each reframing' 'would this blocker disappear under that reframing?'
assert_in "guide: analysis asks at most about 3 tied questions" "$MA" \
  'Ask at most about 3 questions' \
  'names the reading it tests' \
  'which blockers'
assert_in "guide: analysis comes before the report" "$CL" 'before writing the Clarification report'

# ---------------------------------------------------------------------------
echo "Clarify section: report, options, re-entry"
# ---------------------------------------------------------------------------
REPORT="$(section "$GUIDE" '^### Clarification report')"
assert_in "guide: Clarification report template" "$REPORT" \
  '## Clarification needed:' 'Signals fired' 'cap hit' \
  'Goal, in one sentence' 'Assumption trace' 'Readings' 'Questions' \
  'Round history' 'Signals (C1–C4)' 'Themes' 'Rule decision' '### Options' '**Recommendation**'
assert_in "guide: report options 1-5" "$REPORT" \
  '1. **Answer**' '2. **Keep iterating**' '3. **Narrow scope**' '4. **Defer**' '5. **Cancel**'
# The report offers no way to advance with open blockers.
if grep -qiE '(^|[^a-z])(approve|approved|override)([^a-z]|$)' <<<"$REPORT"; then
  fail "guide: Clarification report offers no approve or override option"
else
  pass "guide: Clarification report offers no approve or override option"
fi
OPT2="$(grep -F '2. **Keep iterating**' <<<"$REPORT" || true)"
assert_in "guide: option 2 continues at line 3" "$OPT2" 'continue at rule line 3'
assert_not_in "guide: option 2 does not advance" "$OPT2" 'advance' 'PASS'
RE="$(section "$GUIDE" '^### Options and re-entry')"
assert_in "guide: re-entry rules" "$RE" \
  'new gate occurrence' 'cap resets' \
  'Confirmed' 'The cap is not reset' \
  'C1 cannot be acknowledged by type' 'ackFindings' \
  'window start to the next round' \
  'continues at rule line 3' 'never returns to line 1' \
  'Narrow scope' 'Defer' 'Cancel' 'Clarification never approves'
STANDING_CLAUSE='"Keep going", "use your judgment" and similar standing instructions never acknowledge a signal, answer a question or default a `needs_user` question.'
assert_in "guide: standing instructions rule" "$CL" \
  'Standing instructions' "$STANDING_CLAUSE" \
  'keep working on parts the questions do not affect'
FB="$(section "$GUIDE" '^### Feed it back')"
assert_in "guide: feed it back" "$FB" \
  'Now' 're-brainstorm' 'Common misreadings' 'skills/brainstorming-extension/SKILL.md' \
  '/self-reflect' '`gotcha`' '`misunderstanding`'
assert_in "guide: option 2 re-entry is conditional on no remaining signal" "$RE" \
  'After the acknowledgement, re-run the helper on the same round' \
  'only when no signal remains' \
  'every C1 key that fired has been answered by the user (their answer is recorded as the assumption id in `confirmed`) or is in `ackFindings`, recorded from their option-2 choice' \
  'The orchestrator never edits or removes a recorded round'"'"'s findings to clear a signal' \
  'A `needs_user` blocker clears only through `ackFindings`; `confirmed` clears only the unconfirmed-assumption part' \
  'every C4 theme that fired is in `ackThemes`' \
  'Otherwise line 2 still holds: ask the remaining questions again'
assert_in "guide: report option 2 is conditional too" "$(grep -F '2. **Keep iterating**' <<<"$REPORT")" \
  'once no signal remains' 'any unanswered question is asked again'
assert_in "guide: waiting state" "$CL" 'waiting' 'pendingClarify'

# ---------------------------------------------------------------------------
echo "Options are exactly five; thresholds pinned"
# ---------------------------------------------------------------------------
OPT_NAMES="Answer|Keep iterating|Narrow scope|Defer|Cancel"
for pair in "Clarification report:$REPORT" "Options and re-entry:$RE"; do
  label="${pair%%:*}"; text="${pair#*:}"
  got="$(grep -oE '^[0-9]+\. \*\*[^*]+\*\*' <<<"$text" | sed -E 's/^([0-9]+)\. \*\*(.*)\*\*/\1 \2/' | sed -E 's/\.$//' | tr '\n' '|')"
  want="1 Answer|2 Keep iterating|3 Narrow scope|4 Defer|5 Cancel|"
  [ "$got" = "$want" ] && pass "guide: $label lists exactly options 1-5" \
                       || fail "guide: $label lists exactly options 1-5 (got: $got)"
  o2="$(grep -E '^2\. \*\*Keep iterating' <<<"$text" | sed 's/never advances//')"
  if grep -qiE 'advances|proceeds|with open blockers' <<<"$o2"; then
    fail "guide: $label option 2 does not advance or proceed"
  else
    pass "guide: $label option 2 does not advance or proceed"
  fi
done

CS="$(section "$GUIDE" '^### Clarify signals')"
assert_in "guide: C2 threshold (non-decreasing over 3 rounds)" "$CS" \
  '**C2** (not converging)' 'non-decreasing over the last three rounds since `windowStart`' \
  't[r] ≥ t[r-1] ≥ t[r-2]' 'one reviewer reports no blockers while another reviewer'"'"'s count is higher'
assert_in "guide: C3 threshold (at least 2 distinct fix-induced blockers)" "$CS" \
  'At least 2 distinct blockers in the round have `fix_induced: yes`' 'at or after `windowStart`'
assert_in "guide: C4 threshold (3 rounds, not reset by windowStart)" "$CS" \
  'at least three rounds of the occurrence' '`windowStart` does not reset C4; only `ackThemes` does'
HS="$(section "$GUIDE" '^### The helper')"
assert_in "guide: every exit-2 bullet is present" "$HS" \
  'no argument (usage error)' \
  'an unreadable file or invalid JSON' \
  'no `rounds`, or an empty array' \
  'round numbers that are not integers >= 1 or not strictly increasing' \
  '`recurring`, `disputed`, `overengineering`, `blocker`, `needs_user` or `fix_induced` that is not yes, no, true or false' \
  '`fixedCriticalMajor` that is not a non-negative integer' \
  '`findings` that is not an array of objects' \
  '`reviewers` or `windowStart` that is not an integer >= 1' \
  '`status` other than active, clarify-pending or closed' \
  '`origin` other than implementation, requirement or assumption' \
  '`reviewer` that is not a string' \
  '`confirmed`, `ackThemes` or `ackFindings` that is not an array of strings' \
  '`mergedInto` that does not name another blocker of the same round that is itself unmerged (`null` means unmerged; merge chains and cycles are rejected)' \
  'an `assumption` that is not a non-empty string'
assert_in "guide: escalates (rule line 4) at the recurring text" "$G" \
  'Only disagreement that changes `blocker` escalates (rule line 4)'
assert_in "guide: acknowledgement clears only re-raises of the same question" "$G" \
  'An acknowledged key clears re-raises of that question, meaning the same canonical theme with `needs_user` and no assumption id, or the same assumption id' \
  'A new question fires C1, because the orchestrator gives it a new canonical theme or a new assumption id' \
  'gives a `needs_user` blocker that asks a **different question** from the acknowledged one its own new canonical theme' \
  'a new assumption gets a new ledger id'
assert_in "guide: helper usage notes" "$G" \
  'Omit a field you do not know rather than writing `null`' \
  'only `mergedInto` and `pendingClarify` accept it' \
  'fix the history file and run the helper again' \
  'Apply the rule by hand only if the helper cannot run' \
  '`action: re-ask` with `line` 2 and the current signals' \
  'Divergence needs at least 2 rounds inside the window' \
  'until two new rounds exist'
assert_in "guide: ackFindings key matches the helper" "$G" \
  '`<theme>:<assumption id>` whenever `assumption` is set, whatever the origin, and `<theme>:needs_user` otherwise' \
  '`<theme>` is `canonicalTheme`, falling back to `theme`' \
  'A key with an empty theme never counts as acknowledged, so every `needs_user` blocker needs a `canonicalTheme` for its acknowledgement to stick'
assert_in "guide: reviewers and confirmed must be kept in step" "$G" \
  '`reviewers`** must be set to the number of reviewers in the gate' \
  '`confirmed`** must mirror the ids in the assumption ledger'"'"'s Confirmed section'
assert_in "guide: helper action-to-line mapping, capHit and downgrade wording" "$G" \
  '`pass` (line 1), `clarify` (line 2), `escalate` (lines 3 and 4), `overengineering-check` (line 5), `iterate` (lines 6 and 7)' \
  '`capHit` is true when the round is 10 or later, whichever line wins' \
  'or through rule line 5'"'"'s downgrade' \
  'When it says escalate (lines 3, 4 or 5), use the escalation template' \
  'Line 2 never uses this template; it uses the Clarification report.'
assert_in "guide: exit-2 list covers a non-object round; windowStart note" "$HS" \
  'a round that is not an object'
assert_in "guide: windowStart note" "$G" \
  '`windowStart`** is the next round number' \
  'may exceed the last round until a new round is recorded'
assert_in "guide: helper actions are documented" "$HS" \
  '`pass`' '`clarify`' '`escalate`' '`overengineering-check`' '`iterate`' '`re-ask`' '`closed`'

# ---------------------------------------------------------------------------
echo "Escalation template"
# ---------------------------------------------------------------------------
ET="$(section "$GUIDE" '^## Escalation template')"
assert_in "guide: escalation Rule line has lines 3-5 only" "$ET" \
  '**Rule line**: <3 cap hit | 4 recurring/disputed | 5 overengineering signal>'
assert_not_in "guide: escalation Rule line never uses line 2" "$ET" '<2 ' '2 clarify'
assert_in "guide: escalation options gain Clarify" "$ET" \
  '5. **Clarify the requirement / re-brainstorm**' \
  '<revise|clarify|narrow scope|defer|cancel>' \
  'choosing from the five options above' \
  'Signals (C1–C4)' 'Themes' '7: iterate'
# Forbidden defaulting loopholes, scoped to the Clarify section, Standing instructions and the options.
FORBIDDEN_RE='unreachable|answers? (the |a )?needs_user|with the recommended option|accept the open blockers|defaults? after|re-asks?, (then )?default'
forbidden_found() { grep -iE -- "$FORBIDDEN_RE" <<<"$1" || true; }
OPTIONS_ONLY="$(grep -E '^[0-9]+\. \*\*' <<<"$REPORT"; grep -E '^[0-9]+\. \*\*' <<<"$RE")"
[ -z "$(forbidden_found "$CL")" ] && pass "guide: Clarify section has no defaulting loophole" \
  || fail "guide: Clarify section has no defaulting loophole: $(forbidden_found "$CL")"
[ -z "$(forbidden_found "$(section "$GUIDE" '^### Standing instructions')")" ] && pass "guide: Standing instructions have no defaulting loophole" \
  || fail "guide: Standing instructions have no defaulting loophole"
[ -z "$(forbidden_found "$OPTIONS_ONLY")" ] && ! grep -qi 'proceed' <<<"$OPTIONS_ONLY" \
  && pass "guide: report and re-entry options have no loophole and never proceed" \
  || fail "guide: report and re-entry options have no loophole and never proceed"
assert_not_in "guide: no stale 'four options'" "$ET" 'four options'

# ---------------------------------------------------------------------------
echo "Stale rule-line references"
# ---------------------------------------------------------------------------
# Files scanned (.md only). WU3 adds the gates, rubrics and agents; WU4 the instruction files.
STALE_FILES=(
  guides/delivery-scope.md
  skills/orchestrated-execution/guides/delivery-scope.md
  skills/plan-review-gate/guides/delivery-scope.md
  skills/design-review-gate/guides/delivery-scope.md
  skills/start/guides/delivery-scope.md
  skills/external-tools/guides/delivery-scope.md
)
# keyword (ERE, case-insensitive) that must appear on a line naming rule line N
kw() {
  case "$1" in
    1) echo 'PASS|no blocker' ;;
    2) echo 'clarif' ;;
    3) echo 'cap|escalate' ;;
    4) echo 'recur|disput|disagree|blocker vs|escalate' ;;
    5) echo 'overengineering|downgrade|escalate' ;;
    6|7) echo 'iterate|fresh|fixed|otherwise|re-validate' ;;
    *) echo '^$' ;;
  esac
}
# escalate_row_problems <file>: a table row whose last cell says "N: escalate" must match its round:
# 3 = cap hit (round >= 10); 4 = recurring/disputed; 5 = overengineering (the row names the reason).
escalate_row_problems() {
  awk -F'|' '
    /^\|/ && match($0, /[0-9]: escalate/) {
      n = substr($0, RSTART, 1); r = $2; gsub(/[^0-9]/, "", r); row = tolower($0); ok = 0
      if (n == 3) ok = (r + 0 >= 10)
      else if (n == 4) ok = (row ~ /recur|disput/)
      else if (n == 5) ok = (row ~ /overengineering/)
      if (!ok) printf "[%s:%d: round %s cannot be \"%s: escalate\"] ", FILENAME, NR, r, n
    }' "$1"
}

# prose_escalate_problems <file>: a line that says a "rule line N" (N = 3..5) escalates must name N's reason:
# 3 = cap, 4 = recurring/disputed (or a blocker split), 5 = overengineering.
prose_escalate_problems() {
  awk '
    { low = tolower($0) }
    low ~ /escalates?([^a-z]|$)/ {
      t = low
      while (match(t, /rule line [0-9]/)) {
        n = substr(t, RSTART + 10, 1); t = substr(t, RSTART + RLENGTH); ok = 1
        if (n == 3) ok = (low ~ /cap/)
        else if (n == 4) ok = (low ~ /recur|disput|disagree|blocker vs/)
        else if (n == 5) ok = (low ~ /overengineering/)
        if (!ok) printf "[%s:%d: escalates at rule line %s without its reason] ", FILENAME, NR, n
      }
    }' "$1"
}

# lines_list_problems <file>: every number in a "lines N, M or K" list must fit the reason words
# in its own sentence (100 characters before, 60 after): 1 pass, 2 clarif, 3 escalat/cap, 4 escalat/recur,
# 5 escalat/overengineering/downgrade, 6 and 7 iterate/fresh.
lines_list_problems() {
  awk '
    { low = tolower($0); t = low; off = 0
      while (match(t, /lines [0-9]+(, [0-9]+| or [0-9]+| and [0-9]+)+/)) {
        start = off + RSTART; len = RLENGTH; m = substr(t, RSTART, RLENGTH)
        off = off + RSTART + RLENGTH - 1; t = substr(t, RSTART + RLENGTH)
        b = substr(low, (start > 100 ? start - 100 : 1), (start > 100 ? 100 : start - 1)); sub(/.*\. /, "", b)
        a = substr(low, start + len, 60); sub(/\. .*/, "", a)
        w = b " " m " " a; tmp = m
        while (match(tmp, /[0-9]+/)) {
          n = substr(tmp, RSTART, RLENGTH); tmp = substr(tmp, RSTART + RLENGTH); ok = 1
          if (n == 1) ok = (w ~ /pass|no blocker/)
          else if (n == 2) ok = (w ~ /clarif/)
          else if (n == 3) ok = (w ~ /escalat|cap/)
          else if (n == 4) ok = (w ~ /escalat|recur|disput|disagree/)
          else if (n == 5) ok = (w ~ /escalat|overengineering|downgrade/)
          else if (n == 6 || n == 7) ok = (w ~ /iterat|fresh/)
          if (!ok) printf "[%s:%d: line %s listed without its reason] ", FILENAME, NR, n
        }
      }
    }' "$1"
}

for f in "${STALE_FILES[@]}"; do
  bad=""
  [ -f "$REPO_ROOT/$f" ] || { fail "$f: exists"; continue; }
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    text="${hit#*:}"
    for n in $(grep -oE 'rule line [0-9]|[Ll]ines? [0-9],|[Ll]ine [0-9] \(|[^0-9][0-9]: (PASS|clarify|escalate|iterate|downgrade)' <<<"$text" | grep -oE '[0-9]' | sort -u); do
      grep -qiE "$(kw "$n")" <<<"$text" || bad+="[line ${hit%%:*}: rule line $n] "
    done
  done < <(grep -nE 'rule line [0-9]|[Ll]ines? [0-9],|[Ll]ine [0-9] \(|[^0-9][0-9]: (PASS|clarify|escalate|iterate|downgrade)' "$REPO_ROOT/$f" || true)
  # Round-history "N: action" rows must pair each N with its action, and "N: escalate"
  # rows must agree with the round's reason (see escalate_row_problems).
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    n="${row%%:*}"; act="${row#* }"
    case "$n:$act" in
      1:PASS|2:clarify|3:escalate|4:escalate|5:escalate|5:downgrade|6:iterate|7:iterate) ;;
      *) bad+="[row '$row'] " ;;
    esac
  done < <(grep -oE '(^|[^0-9])[0-9]: (PASS|clarify|escalate|iterate|downgrade)' "$REPO_ROOT/$f" | grep -oE '[0-9]: [a-zA-Z]+' || true)
  bad+="$(escalate_row_problems "$REPO_ROOT/$f")"
  bad+="$(prose_escalate_problems "$REPO_ROOT/$f")"
  bad+="$(lines_list_problems "$REPO_ROOT/$f")"
  # Old phrases from the six-line rule.
  if grep -qE 'line 2, 3 or 5|Severity rule line 6' "$REPO_ROOT/$f" \
     || grep -E 'rule line 3' "$REPO_ROOT/$f" | grep -qi 'recur'; then
    bad+="[old phrase] "
  fi
  [ -z "$bad" ] && pass "$f: rule-line references agree with the seven-line rule" \
                || fail "$f: stale rule-line references: $bad"
done

# Self-test on scratch fixtures: a stale row is flagged, valid rows pass.
FIX="$(mktemp -d)"
cat > "$FIX/stale.md" <<'FX'
| Round | Verdict | Blockers | Fixed | Rule decision |
| 3     | FAIL    | 0 / 1    | 0 / 0 | 3: escalate   |
FX
cat > "$FIX/stale4.md" <<'FX'
| 3     | FAIL    | 0 / 1    | 0 / 0 | 4: escalate   |
FX
cat > "$FIX/valid.md" <<'FX'
| 10    | FAIL    | 0 / 1    | 0 / 0 | 3: escalate (cap hit) |
| 3     | FAIL    | 0 / 1    | 0 / 0 | 4: escalate (recurring) |
| 4     | FAIL    | 0 / 1    | 0 / 0 | 5: escalate (overengineering) |
| 3     | FAIL    | 0 / 1    | 0 / 0 | 7: iterate |
FX
[ -n "$(escalate_row_problems "$FIX/stale.md")" ] && pass "self-test: '3: escalate' at round 3 is flagged" \
  || fail "self-test: '3: escalate' at round 3 is flagged"
[ -n "$(escalate_row_problems "$FIX/stale4.md")" ] && pass "self-test: '4: escalate' with no stated reason is flagged" \
  || fail "self-test: '4: escalate' with no stated reason is flagged"
MUTATED="$(sed 's/never acknowledge a signal, answer a question or default a `needs_user` question/never acknowledge a signal, but may default a `needs_user` question/' <<<"$(section "$GUIDE" '^### Standing instructions')")"
if grep -qF -- "$STANDING_CLAUSE" <<<"$MUTATED"; then
  fail "self-test: a standing-instructions clause saying 'but may default' is detected"
else
  pass "self-test: a standing-instructions clause saying 'but may default' is detected"
fi
printf '%s\n' 'When it says escalate (lines 2, 4 or 5), use the escalation template.' > "$FIX/lines-stale.md"
printf '%s\n' 'When it says escalate (lines 3, 4 or 5), use the escalation template.' 'The recurring and overengineering flags are judgements for lines 4 and 5.' 'Line 2 never uses this template; it uses the Clarification report.' > "$FIX/lines-valid.md"
[ -n "$(lines_list_problems "$FIX/lines-stale.md")" ] && pass "self-test: '(lines 2, 4 or 5)' next to escalate is flagged" \
  || fail "self-test: '(lines 2, 4 or 5)' next to escalate is flagged"
[ -z "$(lines_list_problems "$FIX/lines-valid.md")" ] && pass "self-test: valid lines lists pass" \
  || fail "self-test: valid lines lists pass"
for mut in \
  'If the user is unreachable, the orchestrator answers needs_user questions with the recommended option.' \
  'Or accept the open blockers and proceed.' \
  'After 2 re-asks the orchestrator defaults after the second round.' \
  'The orchestrator re-asks, then default the answer.'; do
  [ -n "$(forbidden_found "$mut")" ] && pass "self-test: loophole caught: ${mut:0:50}" \
    || fail "self-test: loophole caught: ${mut:0:50}"
done
grep -qi 'proceed' <<<'Or accept the open blockers and proceed.' && pass "self-test: 'proceed' in an option is caught" \
  || fail "self-test: 'proceed' in an option is caught"
printf '%s\n' 'The same finding recurs and escalates (rule line 3).' > "$FIX/prose-stale.md"
printf '%s\n' 'Only disagreement that changes blocker escalates (rule line 4).' 'A recurring finding escalates (rule line 4).' 'The cap escalates (rule line 3).' > "$FIX/prose-valid.md"
[ -n "$(prose_escalate_problems "$FIX/prose-stale.md")" ] && pass "self-test: 'escalates (rule line 3)' in a recurring context is flagged" \
  || fail "self-test: 'escalates (rule line 3)' in a recurring context is flagged"
[ -z "$(prose_escalate_problems "$FIX/prose-valid.md")" ] && pass "self-test: valid prose escalation references pass" \
  || fail "self-test: valid prose escalation references pass"
[ -z "$(escalate_row_problems "$FIX/valid.md")" ] && pass "self-test: valid escalate rows pass" \
  || fail "self-test: valid escalate rows pass"

echo ""
echo "Results: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" -eq 0 ]
