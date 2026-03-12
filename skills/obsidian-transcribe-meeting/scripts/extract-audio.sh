#!/bin/bash
# Extract audio from a video file to WAV
# Usage: ./extract-audio.sh <video-file> [output-dir]
#
# Output: WAV file path to stdout
#
# Extracts to 16-bit PCM, 48kHz stereo WAV (same format as Rodecaster recordings)
# Idempotent: skips if WAV exists and is newer than video
#
# Requires: ffmpeg, ffprobe

set -e

VIDEO="${1:?Usage: $0 <video-file> [output-dir]}"
OUTPUT_DIR="${2:-/tmp/meeting-archive}"

if [ ! -f "$VIDEO" ]; then
    echo "Error: File not found: $VIDEO" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

BASENAME=$(basename "$VIDEO" .mp4)
WAV="${OUTPUT_DIR}/${BASENAME}.wav"

# Idempotent: skip if WAV exists and is newer than video
if [ -f "$WAV" ] && [ "$WAV" -nt "$VIDEO" ]; then
    echo "Skipping: $WAV already exists and is up to date" >&2
    echo "$WAV"
    exit 0
fi

# Check that the video has an audio stream
AUDIO_STREAMS=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO" 2>/dev/null | wc -l)
if [ "$AUDIO_STREAMS" -eq 0 ]; then
    echo "Error: No audio stream found in $VIDEO" >&2
    exit 1
fi

echo "Extracting audio: $(basename "$VIDEO") → $(basename "$WAV")..." >&2
ffmpeg -i "$VIDEO" -vn -acodec pcm_s16le -ar 48000 -ac 2 -y "$WAV" -loglevel warning 2>&2

SIZE=$(stat -c '%s' "$WAV" 2>/dev/null || stat -f '%z' "$WAV")
echo "Created: $WAV ($(( SIZE / 1024 / 1024 ))MB)" >&2

echo "$WAV"
