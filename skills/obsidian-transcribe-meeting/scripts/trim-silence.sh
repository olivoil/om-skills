#!/bin/bash
# Trim trailing silence from an audio file to prevent whisper hallucination
# Usage: ./trim-silence.sh <wav-file>
#
# Uses ffmpeg silencedetect to find trailing silence (>30s at -40dB threshold),
# then truncates with a 3-second buffer. Outputs the trimmed file path to stdout
# (or original path if no significant trailing silence found).
#
# Requires: ffmpeg

set -e

WAV_FILE="${1:?Usage: $0 <wav-file>}"

if [ ! -f "$WAV_FILE" ]; then
    echo "Error: File not found: $WAV_FILE" >&2
    exit 1
fi

# Get total duration
DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV_FILE")
DURATION_INT=${DURATION%.*}

# Detect silence periods (>30s of silence at -40dB)
SILENCE_OUTPUT=$(ffmpeg -i "$WAV_FILE" -af "silencedetect=noise=-40dB:d=30" -f null - 2>&1 || true)

# Find the last silence_start — that's the start of trailing silence
LAST_SILENCE_START=$(echo "$SILENCE_OUTPUT" | grep -oP 'silence_start: \K[0-9.]+' | tail -1 || true)

if [ -z "$LAST_SILENCE_START" ]; then
    # No significant silence found
    echo "$WAV_FILE"
    exit 0
fi

LAST_SILENCE_START_INT=${LAST_SILENCE_START%.*}

# Only trim if silence is at the tail end (starts in the last 25% of the file)
THRESHOLD=$(( DURATION_INT * 75 / 100 ))
if [ "$LAST_SILENCE_START_INT" -lt "$THRESHOLD" ]; then
    # Silence is in the middle, not trailing — don't trim
    echo "$WAV_FILE"
    exit 0
fi

# Trim with 3-second buffer after the silence starts
TRIM_AT=$(echo "$LAST_SILENCE_START + 3" | bc)
BASENAME=$(basename "$WAV_FILE" .wav)
TRIMMED_FILE="/tmp/${BASENAME}_trimmed.wav"

echo "Trimming trailing silence: cutting at ${TRIM_AT}s (total was ${DURATION_INT}s)" >&2

ffmpeg -i "$WAV_FILE" -t "$TRIM_AT" -c:a copy "$TRIMMED_FILE" -y -loglevel warning 2>&1 >&2

echo "$TRIMMED_FILE"
