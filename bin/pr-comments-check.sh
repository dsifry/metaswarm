#!/bin/bash
# PR Comments Check - Verifies all review comments have been addressed
# Usage: bin/pr-comments-check.sh <PR_NUMBER>
# Returns: 0 if all addressed, 1 if unaddressed comments exist, 2 if API error

set -e

PR_NUMBER=${1:-$(gh pr view --json number -q .number 2>/dev/null || true)}

if [ -z "$PR_NUMBER" ]; then
  echo "Usage: bin/pr-comments-check.sh <PR_NUMBER>"
  echo "Or run from a branch with an open PR"
  exit 1
fi

OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)

echo "Checking PR #$PR_NUMBER for unaddressed comments..."
echo ""

UNADDRESSED=0

# Check inline code review comments
echo "=== Inline Code Review Comments ==="

# Fetch all comments first, fail if API error
COMMENTS_JSON=$(gh api --paginate repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments 2>&1) || {
  echo "API ERROR: Failed to fetch PR comments"
  echo "   $COMMENTS_JSON"
  exit 2
}

# Extract top-level comment IDs
COMMENT_IDS=$(echo "$COMMENTS_JSON" | jq -r '.[] | select(.in_reply_to_id == null) | .id')

if [ -z "$COMMENT_IDS" ]; then
  echo "No inline code review comments found"
else
  for comment_id in $COMMENT_IDS; do
    author=$(echo "$COMMENTS_JSON" | jq -r ".[] | select(.id == $comment_id) | .user.login")
    body=$(echo "$COMMENTS_JSON" | jq -r ".[] | select(.id == $comment_id) | .body[:80]")

    # Count replies - default to 0 if empty or error
    reply_count=$(echo "$COMMENTS_JSON" | jq "[.[] | select(.in_reply_to_id == $comment_id)] | length")
    reply_count=${reply_count:-0}

    # Ensure reply_count is a valid integer
    if ! [[ "$reply_count" =~ ^[0-9]+$ ]]; then
      echo "WARNING: Could not determine reply count for comment $comment_id, treating as unaddressed"
      reply_count=0
    fi

    if [ "$reply_count" -eq 0 ]; then
      echo "UNADDRESSED: Comment $comment_id by $author"
      echo "   $body..."
      UNADDRESSED=$((UNADDRESSED + 1))
    else
      echo "OK: Comment $comment_id by $author - $reply_count reply(s)"
    fi
  done
fi

echo ""
echo "=== General PR Discussion Comments ==="
# List discussion comments (bot comments typically don't need replies)
ISSUE_COMMENTS=$(gh api --paginate repos/$OWNER/$REPO_NAME/issues/$PR_NUMBER/comments 2>&1) || {
  echo "WARNING: Could not fetch discussion comments"
  echo "   $ISSUE_COMMENTS"
}

if [ -n "$ISSUE_COMMENTS" ] && [ "$ISSUE_COMMENTS" != "[]" ]; then
  echo "$ISSUE_COMMENTS" | jq -r '.[] | "INFO: \(.user.login): \(.body[:60])..."' 2>/dev/null || echo "No discussion comments"
else
  echo "No discussion comments"
fi

echo ""
if [ $UNADDRESSED -gt 0 ]; then
  echo "BLOCKED: $UNADDRESSED unaddressed comment(s) found"
  echo "   Address each comment before declaring PR ready"
  exit 1
else
  echo "All inline review comments have been addressed"
  exit 0
fi
