#!/bin/bash
# Version: 2
# Fetch GitHub activity for a specific date
# Usage: ./fetch-github-activity.sh YYYY-MM-DD [username]
#
# Outputs JSON with:
# - PRs authored (created or updated on the date) with title and description
# - PRs reviewed on the date with title and description
# - Events with timestamps (push, review, comment activity)
#
# Requires: gh CLI authenticated

set -e

DATE="${1:?Usage: $0 YYYY-MM-DD [username]}"

# Get username - resolve @me to actual username for events API
if [ -z "$2" ] || [ "$2" = "@me" ]; then
    USERNAME=$(gh api /user --jq '.login' 2>/dev/null)
    if [ -z "$USERNAME" ]; then
        echo "Error: Could not determine GitHub username. Check gh auth status." >&2
        exit 1
    fi
    SEARCH_AUTHOR="@me"
else
    USERNAME="$2"
    SEARCH_AUTHOR="$2"
fi

# Validate date format
if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Error: Date must be in YYYY-MM-DD format" >&2
    exit 1
fi

# Calculate next day for date range queries (Linux and macOS compatible)
NEXT_DATE=$(date -d "$DATE + 1 day" +%Y-%m-%d 2>/dev/null || date -v+1d -j -f "%Y-%m-%d" "$DATE" +%Y-%m-%d)

# Build JSON output
OUTPUT=$(cat <<EOF
{
  "date": "$DATE",
  "username": "$USERNAME",
  "prs_authored": $(gh search prs --author "$SEARCH_AUTHOR" --created "$DATE" --json number,title,body,repository,state,url,createdAt --limit 50 2>/dev/null | jq '[.[] | {number, title, body: (.body | if . then (. | split("\n") | map(select(. != "")) | .[0:3] | join(" ") | .[0:300]) else null end), repo: .repository.nameWithOwner, state, url, createdAt}]' || echo '[]'),
  "prs_active": $(gh search prs --author "$SEARCH_AUTHOR" --updated "$DATE..$NEXT_DATE" --json number,title,body,repository,state,url,updatedAt --limit 50 2>/dev/null | jq --arg date "$DATE" '[.[] | select(.updatedAt[:10] == $date) | {number, title, body: (.body | if . then (. | split("\n") | map(select(. != "")) | .[0:3] | join(" ") | .[0:300]) else null end), repo: .repository.nameWithOwner, state, url, updatedAt}]' || echo '[]'),
  "prs_reviewed": $(gh search prs --reviewed-by "$SEARCH_AUTHOR" --updated "$DATE..$NEXT_DATE" --json number,title,body,repository,state,url,author --limit 50 2>/dev/null | jq --arg me "$USERNAME" '[.[] | select(.author.login != $me) | {number, title, body: (.body | if . then (. | split("\n") | map(select(. != "")) | .[0:3] | join(" ") | .[0:300]) else null end), repo: .repository.nameWithOwner, state, url, author: .author.login}]' || echo '[]'),
  "events": $(gh api "/users/$USERNAME/events" --paginate 2>/dev/null | jq --arg date "$DATE" '
    [.[] | select(.created_at[:10] == $date)] |
    map({
      type,
      repo: .repo.name,
      timestamp: .created_at,
      action: .payload.action,
      ref: .payload.ref,
      pr_number: (.payload.pull_request.number // .payload.issue.number // null),
      pr_title: (.payload.pull_request.title // .payload.issue.title // null),
      review_state: .payload.review.state,
      comment_body: (.payload.comment.body // null | if . then (. | split("\n")[0] | .[0:100]) else null end)
    }) |
    .[0:100]
  ' || echo '[]')
}
EOF
)

echo "$OUTPUT" | jq '.'
