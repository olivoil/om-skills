#!/bin/bash
# Transcribe an audio file using Whisper (OpenAI API or local whisper.cpp)
# Usage: ./transcribe.sh <audio-file> [openai|local]
#
# Preprocesses audio with ffmpeg (WAV 16kHz mono), handles chunking for
# files >25MB (OpenAI API limit), and outputs JSON with timestamped segments.
#
# Output: JSON array of segments to stdout
#   [{"start": 0.0, "end": 5.2, "text": "Hello..."}, ...]
#
# Environment:
#   OPENAI_API_KEY — required for openai engine (or fetched from 1Password)
#
# Requires: ffmpeg, jq
# For openai engine: curl
# For local engine: whisper.cpp (whisper-cpp CLI)

set -e

AUDIO_FILE="${1:?Usage: $0 <audio-file> [openai|local]}"
ENGINE="${2:-openai}"

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: File not found: $AUDIO_FILE" >&2
    exit 1
fi

# --- Preprocessing: convert to WAV 16kHz mono ---
BASENAME=$(basename "$AUDIO_FILE" | sed 's/\.[^.]*$//')
WAV_FILE="/tmp/${BASENAME}_16k.wav"

if [ ! -f "$WAV_FILE" ]; then
    echo "Preprocessing: converting to WAV 16kHz mono..." >&2
    ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y -loglevel warning 2>&2
fi

# --- Check file size and chunk if needed (OpenAI has 25MB limit) ---
FILE_SIZE=$(stat -c%s "$WAV_FILE" 2>/dev/null || stat -f%z "$WAV_FILE")
MAX_SIZE=$((25 * 1024 * 1024))  # 25MB

transcribe_openai_chunk() {
    local chunk_file="$1"
    local api_key="$2"

    curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer ${api_key}" \
        -F "file=@${chunk_file}" \
        -F "model=whisper-1" \
        -F "response_format=verbose_json" \
        -F "timestamp_granularities[]=segment" \
    | jq '.segments // [] | map({start, end, text})'
}

transcribe_local_chunk() {
    local chunk_file="$1"
    local output_file="/tmp/whisper_output_$$"

    whisper-cpp \
        --model /usr/share/whisper.cpp/models/ggml-medium.bin \
        --output-format json \
        --output-file "$output_file" \
        --file "$chunk_file" \
        2>&2

    jq '.transcription // [] | map({start: .offsets.from, end: .offsets.to, text})' "${output_file}.json"
    rm -f "${output_file}.json"
}

# --- Get API key for OpenAI engine ---
if [ "$ENGINE" = "openai" ]; then
    if [ -z "$OPENAI_API_KEY" ]; then
        OPENAI_API_KEY=$(op read "op://Private/Obsidian/OPENAI_API_KEY" 2>/dev/null || true)
    fi
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY not set and could not read from 1Password" >&2
        exit 1
    fi
fi

# --- Transcribe ---
if [ "$FILE_SIZE" -le "$MAX_SIZE" ] || [ "$ENGINE" = "local" ]; then
    # Single file, no chunking needed (local engine handles any size)
    if [ "$ENGINE" = "openai" ]; then
        transcribe_openai_chunk "$WAV_FILE" "$OPENAI_API_KEY"
    else
        transcribe_local_chunk "$WAV_FILE"
    fi
else
    # Split into 10-minute chunks for OpenAI API
    echo "File is $(( FILE_SIZE / 1024 / 1024 ))MB, splitting into chunks..." >&2

    CHUNK_DIR="/tmp/whisper_chunks_$$"
    mkdir -p "$CHUNK_DIR"

    # Get total duration in seconds
    DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV_FILE" | cut -d. -f1)
    CHUNK_SECS=600  # 10 minutes

    ALL_SEGMENTS="[]"
    OFFSET=0

    while [ "$OFFSET" -lt "$DURATION" ]; do
        CHUNK_FILE="${CHUNK_DIR}/chunk_${OFFSET}.wav"
        echo "  Extracting chunk at ${OFFSET}s..." >&2

        ffmpeg -i "$WAV_FILE" -ss "$OFFSET" -t "$CHUNK_SECS" -c:a pcm_s16le "$CHUNK_FILE" -y -loglevel warning 2>&2

        echo "  Transcribing chunk at ${OFFSET}s..." >&2
        CHUNK_RESULT=$(transcribe_openai_chunk "$CHUNK_FILE" "$OPENAI_API_KEY")

        # Adjust timestamps by adding the chunk offset
        ADJUSTED=$(echo "$CHUNK_RESULT" | jq --argjson offset "$OFFSET" '
            map(.start += $offset | .end += $offset)
        ')

        ALL_SEGMENTS=$(echo "$ALL_SEGMENTS" "$ADJUSTED" | jq -s '.[0] + .[1]')

        OFFSET=$(( OFFSET + CHUNK_SECS ))
    done

    # Clean up chunks
    rm -rf "$CHUNK_DIR"

    echo "$ALL_SEGMENTS"
fi
