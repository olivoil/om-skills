#!/bin/bash
# Compress a WAV file to MP3 for archival
# Usage: ./compress.sh <wav-file> [output-dir]
#
# Output: MP3 file path to stdout
#
# Default output dir: /tmp/meeting-archive/
# Converts to MP3 128kbps mono (~32MB for a 69-minute recording)
# Idempotent: skips if MP3 already exists and is newer than WAV
#
# Requires: ffmpeg

set -e

WAV="${1:?Usage: $0 <wav-file> [output-dir]}"
OUTPUT_DIR="${2:-/tmp/meeting-archive}"

if [ ! -f "$WAV" ]; then
    echo "Error: File not found: $WAV" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

BASENAME=$(basename "$WAV" .wav)
MP3="${OUTPUT_DIR}/${BASENAME}.mp3"

# Idempotent: skip if MP3 exists and is newer than WAV
if [ -f "$MP3" ] && [ "$MP3" -nt "$WAV" ]; then
    echo "Skipping: $MP3 already exists and is up to date" >&2
    echo "$MP3"
    exit 0
fi

echo "Compressing: $(basename "$WAV") → $(basename "$MP3")..." >&2
ffmpeg -i "$WAV" -ac 1 -ab 128k -y "$MP3" -loglevel warning 2>&2

SIZE=$(stat -c%s "$MP3" 2>/dev/null || stat -f%z "$MP3")
echo "Created: $MP3 ($(( SIZE / 1024 / 1024 ))MB)" >&2

echo "$MP3"
