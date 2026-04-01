#!/bin/bash
# Transcribe an audio file using Whisper (OpenAI API or local whisper.cpp)
# Usage: ./transcribe.sh <audio-file> [openai|local]
#
# Preprocesses audio with ffmpeg (WAV 16kHz mono), handles chunking for
# files >25MB (OpenAI API limit), and outputs JSON with timestamped segments.
#
# Output: JSON array of segments to stdout
#   [{"start": 0.0, "end": 5.2, "text": "Hello..."}, ...]
#   With pyannote VAD: [{"start": 0.0, "end": 5.2, "text": "Hello...", "speaker": "SPEAKER_00"}, ...]
#
# Environment:
#   OPENAI_API_KEY       — required for openai engine (or fetched from 1Password)
#   OBSIDIAN_VAD_MODEL   — "none" (default), "silero", "pyannote", or comma-separated chain (e.g. "pyannote,silero")
#   HF_TOKEN             — required for pyannote model
#   OBSIDIAN_VAD_VENV    — path to venv with torch+pyannote (e.g. ~/.local/share/pyannote-venv)
#
# Requires: ffmpeg, jq
# For openai engine: curl
# For local engine: whisper.cpp (whisper-cpp CLI)
# For VAD: python3, torch (+ pyannote.audio for pyannote mode)

set -e

AUDIO_FILE="${1:?Usage: $0 <audio-file> [openai|local]}"
ENGINE="${2:-openai}"
# Normalize engine aliases
case "$ENGINE" in
    whisper.cpp|whisper-cpp|whisper_cpp|local) ENGINE="local" ;;
    openai) ;;
    *) echo "Warning: Unknown engine '$ENGINE', defaulting to 'openai'" >&2; ENGINE="openai" ;;
esac

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: File not found: $AUDIO_FILE" >&2
    exit 1
fi

# --- Preprocessing: convert to WAV 16kHz mono ---
# Use hash of full path to avoid collisions (e.g. multiple "Stereo Mix.wav" from different recordings)
BASENAME=$(basename "$AUDIO_FILE" | sed 's/\.[^.]*$//')
PATH_HASH=$(echo -n "$AUDIO_FILE" | md5sum | cut -c1-8)
WAV_FILE="/tmp/${BASENAME}_${PATH_HASH}_16k.wav"

if [ ! -f "$WAV_FILE" ]; then
    echo "Preprocessing: converting to WAV 16kHz mono..." >&2
    ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y -loglevel warning >/dev/null 2>&1
fi

# --- Trim trailing silence to prevent whisper hallucination ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAV_FILE=$(bash "$SCRIPT_DIR/trim-silence.sh" "$WAV_FILE")

# --- Check file size and chunk if needed (OpenAI has 25MB limit) ---
FILE_SIZE=$(stat -c '%s' "$WAV_FILE" 2>/dev/null || stat -f '%z' "$WAV_FILE")
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

    whisper-cli \
        --model /home/olivier/.local/share/pywhispercpp/models/ggml-large-v3.bin \
        --output-json \
        --output-file "$output_file" \
        --no-speech-thold 0.80 \
        --file "$chunk_file" \
        >/dev/null 2>&1

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

# --- Run VAD if configured ---
# OBSIDIAN_VAD_MODEL can be a single model or comma-separated fallback chain
# e.g. "pyannote,silero" tries pyannote first, then silero, then gives up
VAD_MODELS="${OBSIDIAN_VAD_MODEL:-none}"
VAD_SEGMENTS="[]"

# Use venv python if OBSIDIAN_VAD_VENV is set
VAD_PYTHON="python3"
if [ -n "$OBSIDIAN_VAD_VENV" ] && [ -x "$OBSIDIAN_VAD_VENV/bin/python3" ]; then
    VAD_PYTHON="$OBSIDIAN_VAD_VENV/bin/python3"
fi

if [ "$VAD_MODELS" != "none" ]; then
    IFS=',' read -ra VAD_MODEL_LIST <<< "$VAD_MODELS"
    VAD_SUCCESS=false

    for VAD_MODEL in "${VAD_MODEL_LIST[@]}"; do
        VAD_MODEL=$(echo "$VAD_MODEL" | tr -d ' ')
        [ "$VAD_MODEL" = "none" ] && continue

        echo "Running VAD model: $VAD_MODEL..." >&2
        if VAD_SEGMENTS=$(OBSIDIAN_VAD_MODEL="$VAD_MODEL" "$VAD_PYTHON" "$SCRIPT_DIR/vad.py" "$WAV_FILE") \
           && [ -n "$VAD_SEGMENTS" ] \
           && echo "$VAD_SEGMENTS" | jq empty 2>/dev/null \
           && [ "$(echo "$VAD_SEGMENTS" | jq 'length')" -gt 0 ]; then
            VAD_SUCCESS=true
            break
        else
            echo "Warning: $VAD_MODEL failed" >&2
        fi
    done

    if [ "$VAD_SUCCESS" = false ]; then
        echo "Warning: all VAD models failed, falling back to default chunking" >&2
        VAD_SEGMENTS="[]"
    fi
fi

# Handle pyannote's {chunks, speakers} format vs plain array (silero)
SPEAKER_TIMELINE=""
if echo "$VAD_SEGMENTS" | jq -e '.chunks' >/dev/null 2>&1; then
    SPEAKER_TIMELINE=$(echo "$VAD_SEGMENTS" | jq -c '.speakers')
    VAD_SEGMENTS=$(echo "$VAD_SEGMENTS" | jq -c '.chunks')
fi

VAD_COUNT=$(echo "$VAD_SEGMENTS" | jq 'length')

# --- Transcribe ---
if [ "$VAD_COUNT" -gt 0 ]; then
    # VAD-guided transcription: transcribe each speech segment
    echo "Transcribing $VAD_COUNT VAD segments..." >&2

    CHUNK_DIR="/tmp/whisper_chunks_$$"
    mkdir -p "$CHUNK_DIR"

    # Write VAD segments and speaker timeline to temp files
    VAD_TMPFILE="${CHUNK_DIR}/vad_segments.json"
    echo "$VAD_SEGMENTS" > "$VAD_TMPFILE"
    SPEAKER_TMPFILE="${CHUNK_DIR}/speakers.json"
    if [ -n "$SPEAKER_TIMELINE" ]; then
        echo "$SPEAKER_TIMELINE" > "$SPEAKER_TMPFILE"
    fi

    ALL_SEGMENTS="[]"
    IDX=0
    TOTAL=$VAD_COUNT

    while [ "$IDX" -lt "$TOTAL" ]; do
        SEG=$(jq -c ".[$IDX]" "$VAD_TMPFILE")
        SEG_START=$(echo "$SEG" | jq -r '.start')
        SEG_END=$(echo "$SEG" | jq -r '.end')
        SEG_DURATION=$(echo "$SEG_END - $SEG_START" | bc)

        echo "  Segment $((IDX+1))/$TOTAL: ${SEG_START}s-${SEG_END}s" >&2

        CHUNK_FILE="${CHUNK_DIR}/vad_${IDX}.wav"
        ffmpeg -i "$WAV_FILE" -ss "$SEG_START" -t "$SEG_DURATION" -c:a pcm_s16le "$CHUNK_FILE" -y -loglevel warning >/dev/null 2>&1

        # Check chunk size for OpenAI limit
        CHUNK_SIZE=$(stat -c '%s' "$CHUNK_FILE" 2>/dev/null || stat -f '%z' "$CHUNK_FILE")

        if [ "$ENGINE" = "openai" ] && [ "$CHUNK_SIZE" -gt "$MAX_SIZE" ]; then
            # Sub-chunk large VAD segments for OpenAI
            SUB_DIR="${CHUNK_DIR}/sub_${IDX}"
            mkdir -p "$SUB_DIR"
            SUB_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CHUNK_FILE" | cut -d. -f1)
            SUB_OFFSET=0
            SUB_SECS=600

            while [ "$SUB_OFFSET" -lt "$SUB_DURATION" ]; do
                SUB_FILE="${SUB_DIR}/sub_${SUB_OFFSET}.wav"
                ffmpeg -i "$CHUNK_FILE" -ss "$SUB_OFFSET" -t "$SUB_SECS" -c:a pcm_s16le "$SUB_FILE" -y -loglevel warning >/dev/null 2>&1

                CHUNK_RESULT=$(transcribe_openai_chunk "$SUB_FILE" "$OPENAI_API_KEY")
                ABS_OFFSET=$(echo "$SEG_START + $SUB_OFFSET" | bc)
                ADJUSTED=$(echo "$CHUNK_RESULT" | jq --argjson offset "$ABS_OFFSET" '
                    map(.start += $offset | .end += $offset)
                ')
                ALL_SEGMENTS=$(echo "$ALL_SEGMENTS" "$ADJUSTED" | jq -s '.[0] + .[1]')

                SUB_OFFSET=$(( SUB_OFFSET + SUB_SECS ))
            done
            rm -rf "$SUB_DIR"
        else
            if [ "$ENGINE" = "openai" ]; then
                CHUNK_RESULT=$(transcribe_openai_chunk "$CHUNK_FILE" "$OPENAI_API_KEY")
            else
                CHUNK_RESULT=$(transcribe_local_chunk "$CHUNK_FILE")
            fi

            # Adjust timestamps to absolute time
            ADJUSTED=$(echo "$CHUNK_RESULT" | jq --argjson offset "$SEG_START" '
                map(.start += $offset | .end += $offset)
            ')
            ALL_SEGMENTS=$(echo "$ALL_SEGMENTS" "$ADJUSTED" | jq -s '.[0] + .[1]')
        fi

        IDX=$(( IDX + 1 ))
    done

    rm -rf "$CHUNK_DIR"

    # Attribute speakers from pyannote timeline to whisper segments
    if [ -n "$SPEAKER_TIMELINE" ] && [ -f "$SPEAKER_TMPFILE" ] 2>/dev/null; then
        echo "Attributing speakers to ${#ALL_SEGMENTS} transcript segments..." >&2
        ALL_SEGMENTS=$(echo "$ALL_SEGMENTS" | jq --slurpfile spk "$SPEAKER_TMPFILE" '
            [.[] | . as $seg |
                (($seg.start + $seg.end) / 2) as $mid |
                ($spk[0] | map(select(.start <= $mid and .end >= $mid)) | .[0].speaker // null) as $speaker |
                if $speaker then . + {speaker: $speaker} else . end
            ]
        ')
    fi

    echo "$ALL_SEGMENTS"

elif [ "$FILE_SIZE" -le "$MAX_SIZE" ] || [ "$ENGINE" = "local" ]; then
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

        ffmpeg -i "$WAV_FILE" -ss "$OFFSET" -t "$CHUNK_SECS" -c:a pcm_s16le "$CHUNK_FILE" -y -loglevel warning >/dev/null 2>&1

        echo "  Transcribing chunk at ${OFFSET}s..." >&2
        if [ "$ENGINE" = "openai" ]; then
            CHUNK_RESULT=$(transcribe_openai_chunk "$CHUNK_FILE" "$OPENAI_API_KEY")
        else
            CHUNK_RESULT=$(transcribe_local_chunk "$CHUNK_FILE")
        fi

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
