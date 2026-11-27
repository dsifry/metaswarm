#!/usr/bin/env bash
# tests/agents/test-c4-class-closure.sh
# "C4 and class closure": when a recurring theme (C4) fires, the Clarification report offers
# "close the whole class" (recommended unless the theme rests on a requirement choice). The
# next fix brief names the class, lists every instance, requires a structural test with a
# negative test, and requires a hunt for further members. Two recurrences do not trigger it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
GUIDE="guides/delivery-scope.md"
SKILL="skills/orchestrated-execution/SKILL.md"
PASS=0
FAIL=0
DONE=0
trap '[ "$DONE" = 1 ] || { echo "ABORTED before summary" >&2; exit 1; }' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# section FILE HEADING_REGEX: prints the heading and its body, up to the next heading of the same or higher level.
section() {
  awk -v re="$2" '
    $0 ~ re && !on { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on { if ($0 ~ /^```/) fence = !fence; if (!fence && match($0, /^#+ /) && RLENGTH - 1 <= lvl) exit; print }
  ' "$1"
}

# Paragraph of the guide that opens with the lead-in "**C4 and class closure.**"
closure_para() {
  awk '
    /^\*\*C4 and class closure\.\*\*/ { on = 1 }
    on && /^$/ { exit }
    on { print }
  ' "$GUIDE"
}

echo "Test 1: the guide has the 'C4 and class closure' paragraph under Clarify signals"
CS="$(section "$GUIDE" '^### Clarify signals')"
if grep -qF -- '**C4 and class closure.**' <<<"$CS"; then
  pass "Clarify signals has the C4 and class closure paragraph"
else
  fail "Clarify signals missing the C4 and class closure paragraph"
fi
P="$(closure_para)"
[ -n "$P" ] && pass "closure paragraph found in guide" || fail "closure paragraph not found in guide"

echo "Test 2: the paragraph states when the option is offered and recommended"
for s in 'When C4 fires' 'close the whole class' 'recommended option' 'misunderstanding analysis' \
  'rests on a requirement choice' "C1's question comes first"; do
  grep -qF -- "$s" <<<"$P" && pass "paragraph has '$s'" || fail "paragraph missing '$s'"
done

echo "Test 3: the paragraph lists the four fix-brief requirements (a)-(d)"
grep -qF -- '(a) name the class in one sentence, independent of the instances' <<<"$P" \
  && pass "requirement (a) present" || fail "requirement (a) missing"
grep -qF -- '(b) list every instance seen so far' <<<"$P" \
  && pass "requirement (b) present" || fail "requirement (b) missing"
grep -qF -- '(c) require a structural test that fails for any member of the class' <<<"$P" \
  && pass "requirement (c) present" || fail "requirement (c) missing"
grep -qF -- 'with a negative test' <<<"$P" \
  && pass "requirement (c) names the negative test" || fail "requirement (c) missing the negative test"
grep -qF -- '(d) require the coder to hunt for further members and report every source it checked' <<<"$P" \
  && pass "requirement (d) present" || fail "requirement (d) missing"
grep -qF -- 'the next fix brief must' <<<"$P" \
  && pass "paragraph binds the next fix brief" || fail "paragraph does not bind the next fix brief"
grep -qF -- 'If the user picks it (or the default stands)' <<<"$P" \
  && pass "paragraph states the pick-or-default condition" || fail "paragraph missing the pick-or-default condition"

echo "Test 4: the paragraph states that two recurrences do not trigger it"
grep -qiF -- 'Two recurrences alone do not trigger this' <<<"$P" \
  && pass "paragraph says two recurrences alone do not trigger it" \
  || fail "paragraph does not say two recurrences alone do not trigger it"

echo "Test 5: the Clarification report template offers close-the-class in lettered Pros/Cons option-block form"
REPORT="$(section "$GUIDE" '^### Clarification report')"
n="$(grep -c '^### Clarification report' "$GUIDE" || true)"
[ "$n" = 1 ] && pass "exactly one Clarification report template" || fail "$n Clarification report templates"
if grep -qF -- 'close the whole class' <<<"$REPORT"; then
  pass "template has the close-the-whole-class option"
else
  fail "template missing the close-the-whole-class option"
fi
# The class-closure option block must carry its own Pros and Cons lines, and the report a recommended option.
CLOSE_BLOCK="$(awk '/close the whole class/ { on = 1 } on && /^Reply with/ { exit } on { print }' <<<"$REPORT")"
for t in 'Pros:' 'Cons:' 'C4'; do
  grep -qF -- "$t" <<<"$CLOSE_BLOCK" && pass "class-closure option has '$t'" || fail "class-closure option missing '$t'"
done
grep -qF -- '(Recommended)' <<<"$REPORT" && pass "report marks a recommended option" || fail "report has no (Recommended) option"

echo "Test 6: the orchestrated-execution fix-brief checklist points at the guide"
LINE="$(grep -F -- 'C4 and class closure' "$SKILL" || true)"
if [ -n "$LINE" ]; then
  pass "SKILL.md checklist references 'C4 and class closure'"
else
  fail "SKILL.md checklist does not reference 'C4 and class closure'"
fi
grep -qF -- 'delivery-scope.md' <<<"$LINE" && pass "checklist line links the guide" || fail "checklist line does not link the guide"
grep -qF -- 'Fix-brief checklist' "$SKILL" && pass "SKILL.md still has the fix-brief checklist" || fail "fix-brief checklist heading missing"

echo "Test 7: the closure lives only in delivery-scope.md (the guide and its synced copies)"
hits="$({ grep -rlF -- '**C4 and class closure.**' --include='*.md' guides skills agents rubrics 2>/dev/null || true; })"
others="$({ grep -v '/delivery-scope\.md$' <<<"$hits" || true; } | grep -c . || true)"
[ "$others" = 0 ] && pass "closure paragraph appears only in delivery-scope.md copies" \
  || fail "closure paragraph appears in $others non-guide file(s): $(grep -v '/delivery-scope\.md$' <<<"$hits" | tr '\n' ' ')"
[ -n "$hits" ] && pass "closure paragraph found in $(grep -c . <<<"$hits") guide copies" || fail "no guide copies contain the closure paragraph"

echo
echo "Summary: $PASS passed, $FAIL failed"
DONE=1
[ "$FAIL" = 0 ]
