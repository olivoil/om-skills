#!/bin/bash
# Merge video and audio into a single MP4
# Usage: ./merge-av.sh <video-file> <audio-file> [output-dir]
#
# Output: Merged MP4 path to stdout
#
# Replaces the video's audio track with the provided audio file.
# Video stream is copied (no re-encoding), audio is encoded to AAC 192kbps.
# Uses -shortest to trim to the shorter of the two streams.
# Idempotent: skips if output is newer than both inputs.
#
# Requires: ffmpeg

set -e

VIDEO="${1:?Usage: $0 <video-file> <audio-file> [output-dir]}"
AUDIO="${2:?Usage: $0 <video-file> <audio-file> [output-dir]}"
OUTPUT_DIR="${3:-/tmp/meeting-archive}"

if [ ! -f "$VIDEO" ]; then
    echo "Error: Video file not found: $VIDEO" >&2
    exit 1
fi

if [ ! -f "$AUDIO" ]; then
    echo "Error: Audio file not found: $AUDIO" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

VIDEO_BASE=$(basename "$VIDEO" .mp4)
OUTPUT="${OUTPUT_DIR}/${VIDEO_BASE}-merged.mp4"

# Idempotent: skip if output is newer than both inputs
if [ -f "$OUTPUT" ] && [ "$OUTPUT" -nt "$VIDEO" ] && [ "$OUTPUT" -nt "$AUDIO" ]; then
    echo "Skipping: $OUTPUT already exists and is up to date" >&2
    echo "$OUTPUT"
    exit 0
fi

echo "Merging: $(basename "$VIDEO") + $(basename "$AUDIO") → $(basename "$OUTPUT")..." >&2
ffmpeg -i "$VIDEO" -i "$AUDIO" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest -y "$OUTPUT" -loglevel warning 2>&2

SIZE=$(stat -c '%s' "$OUTPUT" 2>/dev/null || stat -f '%z' "$OUTPUT")
echo "Created: $OUTPUT ($(( SIZE / 1024 / 1024 ))MB)" >&2

echo "$OUTPUT"
