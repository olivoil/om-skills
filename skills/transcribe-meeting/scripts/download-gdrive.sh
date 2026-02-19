#!/bin/bash
# Download a file from Google Drive
# Usage: ./download-gdrive.sh <google-drive-url>
#
# Extracts the file ID from various Google Drive URL formats and downloads
# the file to /tmp/meeting-{id}.{ext}
#
# Outputs: local file path to stdout
#
# Requires: gdown (pip install gdown)

set -e

URL="${1:?Usage: $0 <google-drive-url>}"

# Extract file ID from various Google Drive URL formats:
#   https://drive.google.com/file/d/FILE_ID/view
#   https://drive.google.com/file/d/FILE_ID/view?usp=sharing
#   https://drive.google.com/open?id=FILE_ID
#   https://docs.google.com/uc?id=FILE_ID
FILE_ID=""

if [[ "$URL" =~ /file/d/([a-zA-Z0-9_-]+) ]]; then
    FILE_ID="${BASH_REMATCH[1]}"
elif [[ "$URL" =~ [?&]id=([a-zA-Z0-9_-]+) ]]; then
    FILE_ID="${BASH_REMATCH[1]}"
else
    echo "Error: Could not extract file ID from URL: $URL" >&2
    exit 1
fi

OUTPUT_DIR="/tmp"
OUTPUT_BASE="${OUTPUT_DIR}/meeting-${FILE_ID}"

# Check if already downloaded (any extension)
EXISTING=$(ls "${OUTPUT_BASE}".* 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
    echo "$EXISTING"
    exit 0
fi

# Download using gdown (handles large file confirmation pages)
# Use --fuzzy to accept various URL formats
gdown --fuzzy "$URL" -O "${OUTPUT_BASE}.download" --quiet 2>&2

# Detect actual file type and rename
MIME=$(file --mime-type -b "${OUTPUT_BASE}.download")
case "$MIME" in
    audio/wav|audio/x-wav)      EXT="wav" ;;
    audio/mpeg)                  EXT="mp3" ;;
    audio/mp4|audio/x-m4a)      EXT="m4a" ;;
    audio/ogg)                   EXT="ogg" ;;
    audio/flac|audio/x-flac)    EXT="flac" ;;
    audio/aac)                   EXT="aac" ;;
    video/mp4)                   EXT="mp4" ;;
    video/webm)                  EXT="webm" ;;
    *)                           EXT="audio" ;;
esac

mv "${OUTPUT_BASE}.download" "${OUTPUT_BASE}.${EXT}"
echo "${OUTPUT_BASE}.${EXT}"
