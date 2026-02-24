#!/bin/bash
# Upload a file to Google Drive using rclone
# Usage: ./upload-gdrive.sh <local-file> [remote-folder]
#
# Output: Google Drive URL to stdout
#
# Default remote folder: Meeting Recordings
# Default rclone remote: gdrive (override with $RCLONE_REMOTE)
#
# Idempotent: skips upload if file already exists on Drive with same size
#
# Requires: rclone (configured with a Google Drive remote)

set -e

LOCAL_FILE="${1:?Usage: $0 <local-file> [remote-folder]}"
REMOTE_FOLDER="${2:-Meeting Recordings}"
REMOTE="${RCLONE_REMOTE:-gdrive}"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "Error: File not found: $LOCAL_FILE" >&2
    exit 1
fi

if ! command -v rclone &>/dev/null; then
    echo "Error: rclone is not installed" >&2
    exit 1
fi

FILENAME=$(basename "$LOCAL_FILE")
REMOTE_PATH="${REMOTE}:${REMOTE_FOLDER}/${FILENAME}"

# Check if already uploaded (same name and size)
LOCAL_SIZE=$(stat -c '%s' "$LOCAL_FILE" 2>/dev/null || stat -f '%z' "$LOCAL_FILE")
REMOTE_SIZE=$(rclone size --json "${REMOTE_PATH}" 2>/dev/null | jq -r '.bytes // 0' 2>/dev/null || echo "0")

if [ "$REMOTE_SIZE" -eq "$LOCAL_SIZE" ] 2>/dev/null && [ "$REMOTE_SIZE" -gt 0 ]; then
    echo "Skipping: ${FILENAME} already exists on Drive with same size" >&2
else
    echo "Uploading: ${FILENAME} → ${REMOTE}:${REMOTE_FOLDER}/..." >&2
    rclone copyto "$LOCAL_FILE" "${REMOTE_PATH}" --progress 2>&2
    echo "Upload complete." >&2
fi

# Get the shared link
LINK=$(rclone link "${REMOTE_PATH}" 2>/dev/null || true)

if [ -n "$LINK" ]; then
    echo "$LINK"
else
    # Fallback: construct a Drive URL from the file ID
    FILE_ID=$(rclone lsf --format "i" "${REMOTE_PATH}" 2>/dev/null | head -1)
    if [ -n "$FILE_ID" ]; then
        echo "https://drive.google.com/file/d/${FILE_ID}/view"
    else
        echo "Error: Upload succeeded but could not get Drive URL" >&2
        exit 1
    fi
fi
