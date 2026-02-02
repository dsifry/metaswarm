#!/bin/bash
#
# PR Comments Filter Script
# Filters actionable vs non-actionable PR review comments
#
# Usage: bin/pr-comments-filter.sh <PR_NUMBER>
#
# Outputs:
#   - Count of non-actionable comments (confirmations, acknowledgments)
#   - Count and details of actionable comments by priority
#
# Requires: gh CLI (authenticated), jq

set -e

# Load environment variables if .env exists
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# === ARGUMENT VALIDATION ===
if [ -z "$1" ]; then
  echo "Usage: $0 <PR_NUMBER>"
  echo "Example: $0 746"
  exit 1
fi

PR_NUMBER="$1"

# Validate PR number is a positive integer
if ! [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: PR_NUMBER must be a positive integer"
  exit 1
fi

# === DEPENDENCY CHECKS ===
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) not installed"
  echo "Install from: https://cli.github.com/"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq not installed"
  echo "Install: brew install jq (Mac) or apt install jq (Linux)"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "Error: Not authenticated with GitHub CLI"
  echo "Run: gh auth login"
  exit 1
fi

# === GET REPO INFO ===
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)

# Verify PR exists
if ! gh pr view "$PR_NUMBER" &> /dev/null; then
  echo "Error: PR #$PR_NUMBER not found in $OWNER/$REPO_NAME"
  exit 1
fi

echo "=== PR COMMENT FILTER ==="
echo "Repository: $OWNER/$REPO_NAME"
echo "PR Number: $PR_NUMBER"
echo ""

# === FETCH COMMENTS ===
TEMP_COMMENTS=$(mktemp)
TEMP_RAW=$(mktemp)
trap 'rm -f "$TEMP_COMMENTS" "$TEMP_RAW"' EXIT

# Paginated API returns separate JSON arrays per page - merge them with jq --slurp
gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments" --paginate > "$TEMP_RAW"
jq --slurp 'add // []' "$TEMP_RAW" > "$TEMP_COMMENTS"

TOTAL_COUNT=$(jq 'length' "$TEMP_COMMENTS")
echo "Total comments: $TOTAL_COUNT"

# === NON-ACTIONABLE PATTERNS ===
echo ""
echo "--- Non-Actionable Comments (will be skipped) ---"

# CodeRabbit confirmations
NA_CONFIRMATIONS=$(jq '[.[] | select(.body | test("review_comment_addressed"; "i"))] | length' "$TEMP_COMMENTS")
echo "  CodeRabbit confirmations: $NA_CONFIRMATIONS"

# Bot confirmations
NA_BOT_CONFIRMS=$(jq '[.[] | select(.body | test("Confirmed"; "i"))] | length' "$TEMP_COMMENTS")
echo "  Bot confirmations: $NA_BOT_CONFIRMS"

# Thank you replies
NA_THANK_YOU=$(jq '[.[] | select(.in_reply_to_id != null) | select(.body | test("Thank you for"; "i"))] | length' "$TEMP_COMMENTS")
echo "  Bot thank-you replies: $NA_THANK_YOU"

# Learnings context (no severity marker)
NA_LEARNINGS=$(jq '[.[] | select(.body | test("Learnings used"; "i")) | select(.body | test("_⚠️|_🔴|_🟠|_🟡|_🔵|_🧹|_🛠️") | not)] | length' "$TEMP_COMMENTS")
echo "  Learnings context: $NA_LEARNINGS"

# Fingerprinting
NA_FINGERPRINT=$(jq '[.[] | select(.body | test("fingerprinting:"; "i"))] | length' "$TEMP_COMMENTS")
echo "  CodeRabbit fingerprinting: $NA_FINGERPRINT"

# Human "Fixed in commit" responses
NA_HUMAN_FIXED=$(jq '[.[] | select(.user.login | test("bot"; "i") | not) | select(.body | test("Fixed in commit"; "i"))] | length' "$TEMP_COMMENTS")
echo "  Human 'Fixed in commit': $NA_HUMAN_FIXED"

# === ACTIONABLE COMMENTS BY PRIORITY ===
echo ""
echo "--- Actionable Comments by Priority ---"

# Critical
CRITICAL_COUNT=$(jq '[.[] | select(.in_reply_to_id == null) | select(.body | test("_🔴 Critical_"))] | length' "$TEMP_COMMENTS")
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "CRITICAL: $CRITICAL_COUNT - FIX IMMEDIATELY"
else
  echo "CRITICAL: 0"
fi

# High
HIGH_COUNT=$(jq '[.[] | select(.in_reply_to_id == null) | select(.body | test("_⚠️ Potential issue_.*_🟠 Major_"))] | length' "$TEMP_COMMENTS")
if [ "$HIGH_COUNT" -gt 0 ]; then
  echo "HIGH: $HIGH_COUNT - Fix before merge"
else
  echo "HIGH: 0"
fi

# Medium
MEDIUM_COUNT=$(jq '[.[] | select(.in_reply_to_id == null) | select(.body | test("_🟡 Minor_|_🛠️ Refactor suggestion_.*_🟠 Major_"))] | length' "$TEMP_COMMENTS")
if [ "$MEDIUM_COUNT" -gt 0 ]; then
  echo "MEDIUM: $MEDIUM_COUNT - Should fix"
else
  echo "MEDIUM: 0"
fi

# Low
LOW_COUNT=$(jq '[.[] | select(.in_reply_to_id == null) | select(.body | test("_🔵 Trivial_|_🧹 Nitpick_"))] | length' "$TEMP_COMMENTS")
if [ "$LOW_COUNT" -gt 0 ]; then
  echo "LOW: $LOW_COUNT - Fix if quick"
else
  echo "LOW: 0"
fi

# Human reviewer comments
HUMAN_COUNT=$(jq '[.[] | select(.in_reply_to_id == null) | select(.user.login | test("bot"; "i") | not)] | length' "$TEMP_COMMENTS")
if [ "$HUMAN_COUNT" -gt 0 ]; then
  echo "HUMAN: $HUMAN_COUNT - Always process"
else
  echo "HUMAN: 0"
fi

# === DETAILED ACTIONABLE COMMENTS ===
echo ""
echo "--- Actionable Comment Details ---"

# Critical details
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo ""
  echo "CRITICAL COMMENTS:"
  jq -r '.[] | select(.in_reply_to_id == null) | select(.body | test("_🔴 Critical_")) |
    "  ID: \(.id) | \(.path):\(.line // .original_line // "?")\n  @\(.user.login): \(.body[0:100])...\n"' "$TEMP_COMMENTS"
fi

# High priority details
if [ "$HIGH_COUNT" -gt 0 ]; then
  echo ""
  echo "HIGH PRIORITY COMMENTS:"
  jq -r '.[] | select(.in_reply_to_id == null) | select(.body | test("_⚠️ Potential issue_.*_🟠 Major_")) |
    "  ID: \(.id) | \(.path):\(.line // .original_line // "?")\n  @\(.user.login): \(.body[0:100])...\n"' "$TEMP_COMMENTS"
fi

# Medium priority details
if [ "$MEDIUM_COUNT" -gt 0 ]; then
  echo ""
  echo "MEDIUM PRIORITY COMMENTS:"
  jq -r '.[] | select(.in_reply_to_id == null) | select(.body | test("_🟡 Minor_|_🛠️ Refactor suggestion_.*_🟠 Major_")) |
    "  ID: \(.id) | \(.path):\(.line // .original_line // "?")\n  @\(.user.login): \(.body[0:100])...\n"' "$TEMP_COMMENTS"
fi

# Low priority details
if [ "$LOW_COUNT" -gt 0 ]; then
  echo ""
  echo "LOW PRIORITY COMMENTS:"
  jq -r '.[] | select(.in_reply_to_id == null) | select(.body | test("_🔵 Trivial_|_🧹 Nitpick_")) |
    "  ID: \(.id) | \(.path):\(.line // .original_line // "?")\n  @\(.user.login): \(.body[0:100])...\n"' "$TEMP_COMMENTS"
fi

# Human reviewer details
if [ "$HUMAN_COUNT" -gt 0 ]; then
  echo ""
  echo "HUMAN REVIEWER COMMENTS:"
  jq -r '.[] | select(.in_reply_to_id == null) | select(.user.login | test("bot"; "i") | not) |
    "  ID: \(.id) | \(.path):\(.line // .original_line // "?")\n  @\(.user.login): \(.body[0:100])...\n"' "$TEMP_COMMENTS"
fi

echo ""
echo "=== SUMMARY ==="
TOTAL_ACTIONABLE=$((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))
echo "Total actionable (bot): $TOTAL_ACTIONABLE"
echo "Total actionable (human): $HUMAN_COUNT"
echo "Total to process: $((TOTAL_ACTIONABLE + HUMAN_COUNT))"
