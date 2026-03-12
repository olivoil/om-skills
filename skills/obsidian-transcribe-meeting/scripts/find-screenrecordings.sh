#!/bin/bash
# Find screen recordings for a given date
# Usage: ./find-screenrecordings.sh YYYY-MM-DD
#
# Output: JSON array to stdout
#   [{"path": "/home/.../screenrecording-2026-02-19_09-36-07.mp4",
#     "created_at": "2026-02-19T09:36:07", "duration_secs": 1800,
#     "filename": "screenrecording-2026-02-19_09-36-07.mp4"}]
#
# Environment:
#   SCREENRECORDING_DIR — override search directory (default: $HOME/Videos/)
#
# Requires: jq, ffprobe

set -e

TARGET_DATE="${1:?Usage: $0 YYYY-MM-DD}"

# Validate date format
if ! date -d "$TARGET_DATE" +%Y-%m-%d >/dev/null 2>&1; then
    echo "Error: Invalid date: $TARGET_DATE" >&2
    exit 1
fi

SEARCH_DIR="${SCREENRECORDING_DIR:-$HOME/Videos}"

if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory not found: $SEARCH_DIR" >&2
    exit 1
fi

RESULTS="[]"

for file in "$SEARCH_DIR"/screenrecording-"${TARGET_DATE}"_*.mp4; do
    [ -f "$file" ] || continue

    FILENAME=$(basename "$file")

    # Parse timestamp from filename: screenrecording-2026-02-19_09-36-07.mp4
    if [[ "$FILENAME" =~ ^screenrecording-([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})\.mp4$ ]]; then
        DATE_PART="${BASH_REMATCH[1]}"
        HOUR="${BASH_REMATCH[2]}"
        MIN="${BASH_REMATCH[3]}"
        SEC="${BASH_REMATCH[4]}"
        CREATED_AT="${DATE_PART}T${HOUR}:${MIN}:${SEC}"
    else
        echo "Warning: Could not parse timestamp from $FILENAME" >&2
        continue
    fi

    # Get duration via ffprobe
    DURATION_RAW=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || echo "0")
    DURATION_SECS=$(printf '%.0f' "$DURATION_RAW")

    ENTRY=$(jq -n \
        --arg path "$file" \
        --arg created "$CREATED_AT" \
        --argjson duration "$DURATION_SECS" \
        --arg filename "$FILENAME" \
        '{path: $path, created_at: $created, duration_secs: $duration, filename: $filename}')

    RESULTS=$(echo "$RESULTS" | jq --argjson entry "$ENTRY" '. + [$entry]')
done

echo "$RESULTS"
