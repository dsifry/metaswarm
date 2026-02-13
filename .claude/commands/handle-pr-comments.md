# /project:handle-pr-comments

Handle review comments on pull requests with appropriate responses and resolutions.

## Usage

```text
/project:handle-pr-comments <pr-number>
```

## Overview

This command helps systematically address PR review comments from automated tools (like CodeRabbit) and human reviewers. It ensures consistent, professional responses that acknowledge the AI assistance.

---

## CRITICAL: Complete PR Lifecycle Protocol

**A PR is NOT complete until ALL of the following are true:**

1. All CI checks pass
2. **EVERY** code review comment has been addressed (including trivial/nitpicks)
3. **EVERY** comment thread has received an individual response
4. All threads are marked as resolved (after reviewer approval)
5. Any work > 1 day has a GitHub issue created
6. No pending reviewer comments awaiting response
7. ALL tests pass, there are no pre-existing issues or flaky tests - these are excuses. Fix the underlying issues, don't disable tests.
8. **No new reviews after last commit with actionable items** (Section 1d)

### Mandatory Comment Handling Rules

| Comment Type           | Action                     | DO NOT Skip                 |
| ---------------------- | -------------------------- | --------------------------- |
| Critical/Major         | Fix immediately            | Never                       |
| High/Medium            | Fix before merge           | Never                       |
| Minor                  | Fix                        | Never                       |
| **Trivial/Nitpick**    | **FIX THESE TOO**          | These matter!               |
| **Out-of-scope**       | **INVESTIGATE THOROUGHLY** | Often the BEST insights!    |
| Human comments         | Always address             | Never                       |

### Work Sizing Decision

For EACH comment:

- **< 1 day of work** -> Implement the fix in this PR
- **> 1 day of work** OR architectural change -> Create a new GitHub issue, link it in your response

### Iteration Loop

```text
REPEAT until (all_threads_resolved AND no_new_comments AND no_new_reviews_after_commit):
  1. Fetch ALL inline comments (including trivial, out-of-scope)
  1b. CHECK REVIEW BODIES for "Outside diff range" comments (Section 1c)
      - These are NOT threads - they're in the review body text
      - Commonly missed because they don't appear as threads!
  2. Check for NEW REVIEWS after last commit (Section 1d)
  3. For each comment: fix OR create issue OR respond with disagreement
  4. Run validation: lint, typecheck, and tests
  5. Commit and push
  6. Respond to EVERY thread individually
  6b. For "Outside diff range" comments: leave a general PR comment acknowledging
  7. CRITICAL: WAIT FOR CI/CD, then RE-CHECK for NEW comments/reviews
     - Monitor CI/CD pipeline: `gh pr checks $PR_NUMBER --watch`
     - Wait until ALL checks complete (not just pass - complete)
     - Automated reviewers (CodeRabbit) post comments during/after their check
     - Check BOTH inline threads AND review bodies for new feedback
     - Check for NEW REVIEWS with "Actionable comments posted: X" (X > 0)
  8. If new comments OR new reviews exist -> GO TO STEP 1
  9. If no new comments/reviews AND all checks complete -> verify all threads resolved, then complete
```

**THE #1 WORKFLOW FAILURE**: Stopping after responding without checking for new comments/reviews.
**THE #2 WORKFLOW FAILURE**: Missing "Outside diff range" comments in review bodies.

Automated reviewers POST NEW COMMENTS after analyzing your fix commit. You MUST loop back.
"Outside diff range" comments are in REVIEW BODIES, not threads. You MUST check them (Section 1c).

**Thread Resolution Policy**:

- Resolve when: code committed + responded + reviewer acknowledged
- Resolve immediately if declining a suggestion (with explanation)
- Never auto-resolve without reviewer acknowledgment

---

## Cross-Platform Compatibility

**IMPORTANT**: This command is designed to work on both Windows (Git Bash) and Mac/Linux with automatic fallback logic.

**How it works**:

- **First choice**: Uses `jq` if available (more powerful, supports complex queries)
- **Fallback**: Uses `gh api -q` (GitHub CLI's built-in jq subset) for simpler queries
- Compatible with Windows Git Bash, Mac, and Linux
- No additional dependencies required beyond `gh` CLI (but `jq` is recommended for full functionality)

## Rate Limit Considerations

GitHub has separate rate limits for REST API and GraphQL API:

- **REST API**: 5,000 requests/hour with PAT
- **GraphQL API**: 5,000 points/hour with PAT (complex queries cost multiple points)

This command uses **REST API exclusively** to avoid GraphQL rate limit issues. If you encounter rate limits, check both:

```bash
# Check REST API rate limit
gh api rate_limit -q '.rate'

# Check GraphQL API rate limit (separate from REST)
gh api graphql -f query='{ rateLimit { limit remaining resetAt } }' -q '.data.rateLimit'
```

## Critical Workflow Notes

**IMPORTANT**: Comment IDs can change after you push commits. Always:

1. Get initial comment IDs
2. Make your fixes and commit
3. **RE-FETCH comment IDs** before posting responses (comments may have been updated/replaced)
4. Post responses to CURRENT comment IDs (not stale ones from before your commit)
5. **WAIT for reviewer confirmation** - Do NOT resolve threads immediately after your reply
6. Only resolve threads when: (a) reviewer confirms they're satisfied, OR (b) you're explicitly declining/ignoring the suggestion

**Resolution Policy**:

- **Wait for reviewer approval** before resolving addressed feedback
- **Resolve immediately** only if declining a suggestion (explain why in your reply)
- **Never auto-resolve** after posting a fix - let the reviewer verify

**Pattern**: Use GraphQL for thread operations (variables via -f/-F; parse with `-q` on fetch or `jq` for stored JSON) and REST for posting replies.

## Workflow

### 1. Check for New Comments (Cross-Platform)

**Pattern**: Use GraphQL for thread operations (variables via -f/-F; parse with `-q` on fetch or `jq` for stored JSON) and REST for posting replies.

```bash
# === VALIDATION: Ensure required tools and context ===
echo "=== VALIDATING ENVIRONMENT ==="

# Check gh CLI is installed
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) not installed or not in PATH"
  echo "Install from: https://cli.github.com/"
  exit 1
fi

# Verify authentication
if ! gh auth status &> /dev/null; then
  echo "ERROR: Not authenticated with GitHub CLI"
  echo "Run: gh auth login"
  exit 1
fi

# Test repo access
if ! gh repo view &> /dev/null; then
  echo "ERROR: Not in a git repository or no GitHub remote configured"
  echo "Navigate to your repository directory first"
  exit 1
fi

echo "GitHub CLI installed and authenticated"
echo ""

# Check for jq and set appropriate JSON parser
if command -v jq &> /dev/null; then
  USE_JQ=true
  echo "jq found - using full jq functionality"
else
  USE_JQ=false
  echo "jq not found - using gh api -q fallback (limited functionality)"
fi
echo ""

# Set PR number variable to avoid repetition and reduce errors
# IMPORTANT: Replace XXX with your actual PR number
PR_NUMBER=XXX

# Validate PR_NUMBER (must be positive integer)
if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "XXX" ] || ! [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: Invalid PR_NUMBER='$PR_NUMBER'"
  echo "Usage: Set PR_NUMBER to a valid pull request number (e.g., PR_NUMBER=512)"
  echo "PR numbers must be positive integers (1, 2, 3, ...)"
  echo "HINT: Replace 'PR_NUMBER=XXX' with your actual PR number like 'PR_NUMBER=512'"
  exit 1
fi

# Get repo owner and name
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)

# Verify PR exists
if ! gh pr view "$PR_NUMBER" &> /dev/null; then
  echo "ERROR: PR #$PR_NUMBER not found in $OWNER/$REPO_NAME"
  echo "Check the PR number and try again"
  exit 1
fi

echo "Validation passed"
echo ""
echo "Repository: $OWNER/$REPO_NAME"
echo "PR Number: $PR_NUMBER"

# === STEP 1: COUNT COMMENTS (using gh api -q) ===
echo ""
echo "=== COMMENT COUNTS ==="
ISSUE_COUNT=$(gh api "repos/$OWNER/$REPO_NAME/issues/$PR_NUMBER/comments" --paginate -q 'length')
REVIEW_COUNT=$(gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments" --paginate -q 'length')
echo "Issue comments (general PR comments): $ISSUE_COUNT"
echo "Review comments (inline code comments): $REVIEW_COUNT"

# === STEP 2: LIST ALL REVIEW COMMENTS WITH DETAILS ===
echo ""
echo "=== REVIEW COMMENTS ==="

# Use temp file approach (eval-safe for all shells and platforms)
TEMP_COMMENTS="/tmp/pr_${PR_NUMBER}_comments_$$.json"

# Write API output to temp file with error handling
if ! gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments" --paginate > "$TEMP_COMMENTS" 2>/dev/null; then
  echo "ERROR: Failed to write to $TEMP_COMMENTS"
  echo "Check disk space: df -h /tmp"
  echo "Check permissions: ls -ld /tmp"
  exit 1
fi

if [ "$USE_JQ" = true ]; then
  jq -r '.[] | "ID: \(.id) - [\(.path):\(.line // .original_line // "?")]", "  @\(.user.login): \(.body[0:100])...", "  URL: https://github.com/'"$OWNER"'/'"$REPO_NAME"'/pull/'"$PR_NUMBER"'#discussion_r\(.id)", "---"' < "$TEMP_COMMENTS"
else
  grep -o '"id":[0-9]*' "$TEMP_COMMENTS" | cut -d: -f2 | while read -r id; do
    echo "Comment ID: $id"
    echo "  (Use: gh api repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments --paginate -q '.[] | select(.id == $id)')"
    echo "---"
  done
fi

rm -f "$TEMP_COMMENTS"

# === STEP 2b: GET REVIEW THREAD IDs (for resolution tracking) ===
echo ""
echo "=== REVIEW THREADS (with resolution status) ==="

CURSOR=""
HAS_NEXT=true

while [ "$HAS_NEXT" = "true" ]; do
  if [ -z "$CURSOR" ]; then
    RESPONSE=$(gh api graphql \
      -f owner="$OWNER" \
      -f repoName="$REPO_NAME" \
      -F prNumber=$PR_NUMBER \
      -f query='query($owner: String!, $repoName: String!, $prNumber: Int!) {
        repository(owner: $owner, name: $repoName) {
          pullRequest(number: $prNumber) {
            reviewThreads(first: 50) {
              pageInfo {
                hasNextPage
                endCursor
              }
              nodes {
                id
                isResolved
                comments(first: 1) {
                  nodes {
                    databaseId
                    path
                    author { login }
                  }
                }
              }
            }
          }
        }
      }')
  else
    RESPONSE=$(gh api graphql \
      -f owner="$OWNER" \
      -f repoName="$REPO_NAME" \
      -F prNumber=$PR_NUMBER \
      -f cursor="$CURSOR" \
      -f query='query($owner: String!, $repoName: String!, $prNumber: Int!, $cursor: String!) {
        repository(owner: $owner, name: $repoName) {
          pullRequest(number: $prNumber) {
            reviewThreads(first: 50, after: $cursor) {
              pageInfo {
                hasNextPage
                endCursor
              }
              nodes {
                id
                isResolved
                comments(first: 1) {
                  nodes {
                    databaseId
                    path
                    author { login }
                  }
                }
              }
            }
          }
        }
      }')
  fi

  if [ "$USE_JQ" = true ]; then
    echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] |
      "Thread: \(.id)",
      "  Resolved: \(.isResolved)",
      "  Comment ID: \(.comments.nodes[0].databaseId)",
      "  File: \(.comments.nodes[0].path)",
      "  Author: @\(.comments.nodes[0].author.login)",
      "---"'
  else
    if [ -z "$CURSOR" ]; then
      echo "jq not found - showing first 50 threads only (pagination disabled)"
    fi
    echo "$RESPONSE" | grep -o '"databaseId":[0-9]*' | head -1 | cut -d: -f2 | while read -r dbId; do
      echo "Thread data requires jq for full display"
      echo "  Comment ID: $dbId"
      echo "  (Install jq for full thread information)"
      echo "---"
    done
  fi

  if [ "$USE_JQ" = true ]; then
    HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
  else
    HAS_NEXT="false"
  fi

  if [ "$HAS_NEXT" = "true" ]; then
    if [ "$USE_JQ" = true ]; then
      CURSOR=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
      echo "=== Fetching next page of threads... ==="
    fi
  fi
done
```

### 1b. Filter Actionable vs Non-Actionable Comments

**CRITICAL**: Before processing comments, filter out non-actionable ones to avoid wasting time on confirmations and acknowledgments.

```bash
# Run the filter script
bin/pr-comments-filter.sh $PR_NUMBER
```

This script:

- Filters out non-actionable comments (confirmations, acknowledgments, fingerprinting)
- Categorizes actionable comments by priority
- Shows comment IDs and details for processing

**Priority levels:**

| Priority     | Marker                                              | Action           |
| ------------ | --------------------------------------------------- | ---------------- |
| **CRITICAL** | `_Potential issue_ \| _Critical_`                   | Fix immediately  |
| **HIGH**     | `_Potential issue_ \| _Major_`                      | Fix before merge |
| **MEDIUM**   | `_Minor_` or `_Refactor suggestion_ \| _Major_`     | Fix              |
| **LOW**      | `_Trivial_` / `_Nitpick_`                           | **Fix**          |
| **HUMAN**    | Non-bot comments                                    | Always process   |

> **Note**: ALL comment types require fixes. See Complete PR Lifecycle Protocol - trivial/nitpicks are NOT optional.

### 1c. Extract "Outside Diff Range" Comments from Review Bodies (CRITICAL)

**COMMONLY MISSED**: CodeRabbit posts "Outside diff range" comments in the **review body**, not as inline threads. These are actionable feedback that MUST be addressed.

```bash
PR_NUMBER=XXX  # Replace with your PR number
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)

echo "=== OUTSIDE DIFF RANGE COMMENTS (from review bodies) ==="
gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews" --paginate | \
  jq -r '.[] | select(.body | test("Outside diff range"; "i")) |
    "Review ID: \(.id)\nAuthor: \(.user.login)\n\n\(.body)\n\n---"'
```

**What to look for in the output**:

- `<summary>Outside diff range comments (N)</summary>` sections
- File paths and line numbers referenced
- Specific actionable feedback (not just "run validation")

**These comments are NOT in threads** - they cannot be replied to inline. You must:

1. Address the feedback in your code
2. Commit and push
3. Leave a general PR comment acknowledging you addressed them

### 1d. Check for New Reviews After Commit (CRITICAL)

**WHY THIS MATTERS**: CodeRabbit and other review bots post **review summaries** that indicate actionable comments. These are separate from inline comments and threads. If you only check threads, you'll miss new reviews posted after your commit.

```bash
# === CHECK FOR NEW REVIEWS AFTER YOUR COMMIT ===
LATEST_SHA=$(gh pr view $PR_NUMBER --json headRefOid -q .headRefOid)
COMMIT_TIME=$(gh api "repos/$OWNER/$REPO_NAME/commits/$LATEST_SHA" -q .commit.committer.date)
echo "Latest commit: $LATEST_SHA at $COMMIT_TIME"

echo ""
echo "=== REVIEWS AFTER LAST COMMIT ==="

gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews" --paginate > /tmp/pr_${PR_NUMBER}_reviews_$$.json

python3 << PYEOF
import json
from datetime import datetime

commit_time = datetime.fromisoformat("$COMMIT_TIME".replace('Z', '+00:00'))

with open('/tmp/pr_${PR_NUMBER}_reviews_$$.json') as f:
    reviews = json.load(f)

new_reviews = []
for review in reviews:
    submitted = datetime.fromisoformat(review['submitted_at'].replace('Z', '+00:00'))
    if submitted > commit_time:
        new_reviews.append({
            'id': review['id'],
            'author': review['user']['login'],
            'state': review['state'],
            'submitted': review['submitted_at'],
            'body': review['body'][:200] if review['body'] else ''
        })

if new_reviews:
    print(f"Found {len(new_reviews)} review(s) after last commit:")
    for r in new_reviews:
        print(f"\n  Review ID: {r['id']}")
        print(f"  Author: @{r['author']}")
        print(f"  State: {r['state']}")
        print(f"  Submitted: {r['submitted']}")
        if 'Actionable comments posted:' in r['body']:
            print(f"  CONTAINS ACTIONABLE COMMENTS!")
        print(f"  Body: {r['body'][:150]}...")
else:
    print("No new reviews after last commit")
PYEOF

rm -f /tmp/pr_${PR_NUMBER}_reviews_$$.json
```

**What to look for**:

| Review Content                          | Action Required                                     |
| --------------------------------------- | --------------------------------------------------- |
| "Actionable comments posted: 0"         | No action needed                                    |
| "Actionable comments posted: X" (X > 0) | **NEW COMMENTS TO ADDRESS** - check inline comments |
| "Fix all issues with AI agents" section | Contains specific fix instructions                  |
| Human reviewer comments                 | Always address                                      |

### 2. Posting Inline Replies

**CRITICAL WORKFLOW ORDER**:

1. **BEFORE making fixes**: Get initial comment IDs and thread information
2. **Make your fixes**: Code changes, commit, push
3. **REFRESH comment IDs**: Re-fetch CURRENT comments (IDs may have changed after your commit!)
4. **Post responses**: Use CURRENT comment IDs to post replies
5. **WAIT for reviewer**: Do NOT resolve threads - let reviewer verify your fix
6. **Resolve only when**: Reviewer approves OR you're declining the suggestion

**Correct API Pattern**: Use GitHub REST API for posting comment replies:

```bash
PR_NUMBER=XXX
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)
CURRENT_USER=$(gh api user -q .login)

echo "=== CURRENT REVIEW COMMENTS (after your fixes) ==="
gh api "repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments" --paginate \
  -q '.[] | "ID: \(.id) | Path: \(.path):\(.line) | @\(.user.login): \(.body[0:80])..."'

COMMENT_ID=<current-comment-id>

gh api "/repos/$OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
  -X POST \
  -f body="Fixed in commit <commit-hash>.

*(Response by Claude on behalf of @$CURRENT_USER)*"
```

### 3. Response Templates

**Important**: All comments must include attribution: `*(Response by Claude on behalf of @$CURRENT_USER)*`

### 4. Post-Push Verification (MANDATORY)

**CRITICAL**: After EVERY push, you MUST check for NEW comments before declaring complete.

```bash
PR_NUMBER=XXX
echo "Waiting for CI/CD checks to complete..."
gh pr checks $PR_NUMBER --watch
```

Then re-check for new comments using the workflow in Section 1.

### 5. Best Practices

1. **Be Thorough**: Address **ALL** comments - including trivial/nitpicks and out-of-scope
2. **Be Complete**: Address all parts of multi-part suggestions (don't cherry-pick)
3. **Be Iterative**: Follow the Iteration Loop - don't declare complete until ALL threads resolved
4. **Be Responsive**: Reply to **EVERY** comment thread individually (not batch responses)
5. **Be Specific**: Reference exact commits, files, and line numbers
6. **Be Professional**: Thank reviewers for catching important issues
7. **Be Transparent**: Always include the Claude attribution
8. **Be Humble**: Acknowledge when you need help or clarification
9. **Create Issues**: For work > 1 day, create a GitHub issue instead of deferring indefinitely

### 6. When is the PR Truly Complete?

A PR is **NOT ready for merge** until:

1. All CI checks pass
2. **EVERY** comment (including trivial/nitpicks/out-of-scope) has been addressed
3. **EVERY** thread has an individual response
4. All threads are marked resolved (after reviewer approval)
5. GitHub issues created for any deferred work (> 1 day)
6. No pending reviewer comments awaiting response
7. **No new reviews after last commit with actionable items**

**If ANY of these are false, continue iterating.** Do not declare complete prematurely.
