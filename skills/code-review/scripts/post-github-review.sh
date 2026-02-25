#!/bin/bash
# Post a GitHub PR review with inline comments via the gh API.
#
# Usage:
#   bash post-github-review.sh \
#     --owner "olivoil" --repo "my-app" --pr 123 \
#     --commit "abc123" --body "Review summary" \
#     --comments /tmp/comments.json \
#     [--event PENDING|APPROVE|REQUEST_CHANGES|COMMENT]
#
# Defaults to PENDING (draft review) if --event is omitted.
#
# Comments JSON format:
#   [{"path": "src/app.js", "line": 42, "body": "Issue description"}]

set -euo pipefail

OWNER=""
REPO=""
PR=""
COMMIT=""
EVENT=""
BODY=""
COMMENTS_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --owner)    OWNER="$2";         shift 2 ;;
    --repo)     REPO="$2";          shift 2 ;;
    --pr)       PR="$2";            shift 2 ;;
    --commit)   COMMIT="$2";        shift 2 ;;
    --event)    EVENT="$2";         shift 2 ;;
    --body)     BODY="$2";          shift 2 ;;
    --comments) COMMENTS_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required parameters
for param in OWNER REPO PR COMMIT BODY; do
  if [[ -z "${!param}" ]]; then
    echo "Error: --${param,,} is required" >&2
    exit 1
  fi
done

# Build the review payload with jq
PAYLOAD=$(jq -n \
  --arg commit_id "$COMMIT" \
  --arg body "$BODY" \
  '{commit_id: $commit_id, body: $body}')

# Add event (default to PENDING for draft reviews)
EVENT="${EVENT:-PENDING}"
PAYLOAD=$(echo "$PAYLOAD" | jq --arg event "$EVENT" '. + {event: $event}')

# Add comments if file provided and non-empty
if [[ -n "$COMMENTS_FILE" && -f "$COMMENTS_FILE" ]]; then
  COMMENT_COUNT=$(jq 'length' "$COMMENTS_FILE")
  if [[ "$COMMENT_COUNT" -gt 0 ]]; then
    PAYLOAD=$(echo "$PAYLOAD" | jq --slurpfile comments "$COMMENTS_FILE" '. + {comments: $comments[0]}')
  fi
fi

# Post the review
RESPONSE=$(echo "$PAYLOAD" | gh api \
  "repos/${OWNER}/${REPO}/pulls/${PR}/reviews" \
  --method POST \
  --input -)

# Extract and print the review URL
REVIEW_ID=$(echo "$RESPONSE" | jq -r '.id')
echo "https://github.com/${OWNER}/${REPO}/pull/${PR}#pullrequestreview-${REVIEW_ID}"
