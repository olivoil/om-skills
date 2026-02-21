#!/bin/bash
# Find user screenshots taken during a meeting's timeframe
# Usage: ./find-screenshots.sh YYYY-MM-DD HH:MM:SS DURATION_SECS
#
# Arguments:
#   $1 — date (YYYY-MM-DD)
#   $2 — meeting start time (HH:MM:SS)
#   $3 — meeting duration in seconds
#
# Output: JSON array to stdout
#   [{"path": "/home/.../screenshot-2026-02-20_09-40-15.png",
#     "timestamp": "2026-02-20T09:40:15", "offset_secs": 248}]
#
# Environment:
#   OMARCHY_SCREENSHOT_DIR — override search directory
#   XDG_PICTURES_DIR — fallback search directory
#   Default: $HOME/Pictures/
#
# Requires: jq

set -e

TARGET_DATE="${1:?Usage: $0 YYYY-MM-DD HH:MM:SS DURATION_SECS}"
START_TIME="${2:?Usage: $0 YYYY-MM-DD HH:MM:SS DURATION_SECS}"
DURATION_SECS="${3:?Usage: $0 YYYY-MM-DD HH:MM:SS DURATION_SECS}"

# Validate date format
if ! date -d "$TARGET_DATE" +%Y-%m-%d >/dev/null 2>&1; then
    echo "Error: Invalid date: $TARGET_DATE" >&2
    exit 1
fi

# Determine screenshots directory
if [ -n "$OMARCHY_SCREENSHOT_DIR" ]; then
    SEARCH_DIR="$OMARCHY_SCREENSHOT_DIR"
elif [ -n "$XDG_PICTURES_DIR" ]; then
    SEARCH_DIR="$XDG_PICTURES_DIR"
else
    SEARCH_DIR="$HOME/Pictures"
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo "[]"
    exit 0
fi

# Calculate time window with 5 min buffer on each side
START_EPOCH=$(date -d "${TARGET_DATE}T${START_TIME}" +%s)
BUFFER=300
WINDOW_START=$((START_EPOCH - BUFFER))
WINDOW_END=$((START_EPOCH + DURATION_SECS + BUFFER))

RESULTS="[]"

# Match screenshot-YYYY-MM-DD_HH-MM-SS.png pattern
for file in "$SEARCH_DIR"/screenshot-"${TARGET_DATE}"_*.png; do
    [ -f "$file" ] || continue

    FILENAME=$(basename "$file")

    if [[ "$FILENAME" =~ ^screenshot-([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})\.png$ ]]; then
        DATE_PART="${BASH_REMATCH[1]}"
        HOUR="${BASH_REMATCH[2]}"
        MIN="${BASH_REMATCH[3]}"
        SEC="${BASH_REMATCH[4]}"
        TIMESTAMP="${DATE_PART}T${HOUR}:${MIN}:${SEC}"

        SCREENSHOT_EPOCH=$(date -d "${DATE_PART}T${HOUR}:${MIN}:${SEC}" +%s)

        # Check if within meeting window
        if [ "$SCREENSHOT_EPOCH" -ge "$WINDOW_START" ] && [ "$SCREENSHOT_EPOCH" -le "$WINDOW_END" ]; then
            OFFSET=$((SCREENSHOT_EPOCH - START_EPOCH))

            ENTRY=$(jq -n \
                --arg path "$file" \
                --arg timestamp "$TIMESTAMP" \
                --argjson offset "$OFFSET" \
                '{path: $path, timestamp: $timestamp, offset_secs: $offset}')

            RESULTS=$(echo "$RESULTS" | jq --argjson entry "$ENTRY" '. + [$entry]')
        fi
    fi
done

echo "$RESULTS"
