#!/bin/bash
# Upload a video to YouTube as a private video
# Usage: ./upload-youtube.sh <video-file> <title> [description] [date]
#
# Output: YouTube URL to stdout
#
# Uploads as private (only visible to your Google account).
# Uses youtubeuploader with OAuth credentials at ~/.config/youtubeuploader/
#
# Idempotent: caches upload result in /tmp/youtube-result-{basename}.json
#
# Requires: youtubeuploader

set -e

VIDEO="${1:?Usage: $0 <video-file> <title> [description] [date]}"
TITLE="${2:?Usage: $0 <video-file> <title> [description] [date]}"
DESCRIPTION="${3:-}"
RECORDING_DATE="${4:-}"

if [ ! -f "$VIDEO" ]; then
    echo "Error: File not found: $VIDEO" >&2
    exit 1
fi

# Check for youtubeuploader
if ! command -v youtubeuploader &>/dev/null; then
    echo "Error: youtubeuploader is not installed" >&2
    echo "Install: go install github.com/porjo/youtubeuploader@latest" >&2
    exit 1
fi

# Check for OAuth credentials
SECRETS_DIR="$HOME/.config/youtubeuploader"
SECRETS_FILE="$SECRETS_DIR/client_secrets.json"
TOKEN_FILE="$SECRETS_DIR/request.token"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "Error: YouTube OAuth not configured" >&2
    echo "" >&2
    echo "Setup steps:" >&2
    echo "1. Google Cloud Console → create project → enable YouTube Data API v3" >&2
    echo "2. OAuth consent screen → add test user (your Google account)" >&2
    echo "3. Create OAuth client ID (Desktop app) → download JSON" >&2
    echo "4. Save as: $SECRETS_FILE" >&2
    echo "5. Run: youtubeuploader -filename /dev/null -secrets $SECRETS_FILE -cache $TOKEN_FILE" >&2
    echo "6. Browser opens for consent → token cached for future use" >&2
    exit 1
fi

# Create a symlink with a clean filename so YouTube uses the meeting title
# (youtubeuploader may use the filename as fallback title)
CLEAN_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 -]//g' | tr ' ' '-')
UPLOAD_FILE="/tmp/${RECORDING_DATE:-upload}-${CLEAN_TITLE}.mp4"
ln -sf "$(realpath "$VIDEO")" "$UPLOAD_FILE"

BASENAME=$(basename "$UPLOAD_FILE")
CACHE_FILE="/tmp/youtube-result-${BASENAME}.json"

# Idempotent: check cache
if [ -f "$CACHE_FILE" ]; then
    CACHED_URL=$(jq -r '.url // empty' "$CACHE_FILE" 2>/dev/null || true)
    if [ -n "$CACHED_URL" ]; then
        echo "Skipping: Already uploaded → $CACHED_URL" >&2
        echo "$CACHED_URL"
        exit 0
    fi
fi

# Build metadata JSON
META_FILE=$(mktemp /tmp/youtube-meta-XXXXXX.json)
trap 'rm -f "$META_FILE" "$UPLOAD_FILE"' EXIT

META_JSON=$(jq -n \
    --arg title "$TITLE" \
    --arg desc "$DESCRIPTION" \
    --arg date "$RECORDING_DATE" \
    '{
        snippet: {
            title: $title,
            description: $desc,
            tags: ["meeting", "recording"],
            categoryId: "22"
        },
        status: {
            privacyStatus: "private"
        }
    } |
    if $date != "" then
        .recordingDetails = {recordingDate: $date}
    else . end')

echo "$META_JSON" > "$META_FILE"

echo "Uploading to YouTube: $(basename "$UPLOAD_FILE") as '$TITLE'..." >&2

# Run youtubeuploader
OUTPUT=$(youtubeuploader \
    -filename "$UPLOAD_FILE" \
    -metaJSON "$META_FILE" \
    -secrets "$SECRETS_FILE" \
    -cache "$TOKEN_FILE" \
    2>&1) || {
    echo "Error: YouTube upload failed" >&2
    echo "$OUTPUT" >&2
    exit 1
}

# Extract video ID from youtubeuploader output
# youtubeuploader prints the video ID on success
VIDEO_ID=$(echo "$OUTPUT" | grep -oP 'id:\s*\K[A-Za-z0-9_-]+' || true)

if [ -z "$VIDEO_ID" ]; then
    # Try alternative output format
    VIDEO_ID=$(echo "$OUTPUT" | grep -oP 'youtube\.com/watch\?v=\K[A-Za-z0-9_-]+' || true)
fi

if [ -z "$VIDEO_ID" ]; then
    # Last resort: look for any YouTube-style ID in the output
    VIDEO_ID=$(echo "$OUTPUT" | grep -oP '[A-Za-z0-9_-]{11}' | tail -1 || true)
fi

if [ -z "$VIDEO_ID" ]; then
    echo "Error: Upload may have succeeded but could not extract video ID" >&2
    echo "Output: $OUTPUT" >&2
    exit 1
fi

URL="https://youtu.be/${VIDEO_ID}"

# Cache result
jq -n --arg url "$URL" --arg id "$VIDEO_ID" --arg file "$BASENAME" \
    '{url: $url, video_id: $id, filename: $file}' > "$CACHE_FILE"

echo "Uploaded: $URL" >&2
echo "$URL"
