#!/bin/bash
# Find Rodecaster recordings for a given date on the mounted SD card
# Usage: ./find-recordings.sh YYYY-MM-DD
#
# Output: JSON array to stdout
#   [{"folder": "9 - 18 Feb 2026", "path": "/.../Stereo Mix.wav",
#     "duration_secs": 4132, "created_at": "2026-02-18T12:23:15", "recording_id": "9"}]
#
# Environment:
#   RODECASTER_MOUNT — override mount point (default: auto-detect /run/media/*/RODECaster/)
#
# Requires: jq, date

set -e

TARGET_DATE="${1:?Usage: $0 YYYY-MM-DD}"

# Validate date format
if ! date -d "$TARGET_DATE" +%Y-%m-%d >/dev/null 2>&1; then
    echo "Error: Invalid date: $TARGET_DATE" >&2
    exit 1
fi

# --- Mount discovery ---
if [ -n "$RODECASTER_MOUNT" ]; then
    MOUNT="$RODECASTER_MOUNT"
    if [ ! -d "$MOUNT" ]; then
        echo "Error: RODECASTER_MOUNT directory not found: $MOUNT" >&2
        exit 1
    fi
else
    # Check both SD card mount (via card reader) and Rodecaster transfer mode (via USB).
    # Use find(1) for discovery since bash glob expansion can silently fail in
    # sandboxed environments (e.g. Claude Code sandbox restricts /run/media).
    MOUNTS=()
    if [ -d /run/media/ ]; then
        while IFS= read -r -d '' m; do
            MOUNTS+=("$m")
        done < <(find /run/media/ -maxdepth 3 -type d -name "RODECaster" -print0 2>/dev/null)
        # Deduplicate
        if [ ${#MOUNTS[@]} -gt 0 ]; then
            MOUNTS=($(printf '%s\n' "${MOUNTS[@]}" | sort -u))
        fi
    fi
    if [ ${#MOUNTS[@]} -eq 0 ]; then
        echo "Error: No RODECaster SD card found. Set RODECASTER_MOUNT=/path/to/RODECaster if auto-detect fails." >&2
        echo "Checked: /run/media/*/*/RODECaster/ and /run/media/*/RodeCaster/RODECaster/" >&2
        exit 1
    fi
    if [ ${#MOUNTS[@]} -gt 1 ]; then
        echo "Error: Multiple RODECaster mounts found: ${MOUNTS[*]}" >&2
        echo "Set RODECASTER_MOUNT to pick one." >&2
        exit 1
    fi
    MOUNT="${MOUNTS[0]%/}"
fi

# --- Scan folders ---
RESULTS="[]"

for dir in "$MOUNT"/*/; do
    [ -d "$dir" ] || continue

    FOLDER=$(basename "$dir")

    # Parse folder name: "{N} - {D} {Mon} {YYYY}" e.g. "9 - 18 Feb 2026"
    if [[ "$FOLDER" =~ ^([0-9]+)\ -\ ([0-9]+)\ ([A-Za-z]+)\ ([0-9]{4})$ ]]; then
        REC_ID="${BASH_REMATCH[1]}"
        DAY="${BASH_REMATCH[2]}"
        MON="${BASH_REMATCH[3]}"
        YEAR="${BASH_REMATCH[4]}"

        # Convert to YYYY-MM-DD
        FOLDER_DATE=$(date -d "$DAY $MON $YEAR" +%Y-%m-%d 2>/dev/null || continue)

        if [ "$FOLDER_DATE" != "$TARGET_DATE" ]; then
            continue
        fi

        WAV_PATH="${dir}Stereo Mix.wav"
        if [ ! -f "$WAV_PATH" ]; then
            echo "Warning: No Stereo Mix.wav in $FOLDER" >&2
            continue
        fi

        META_PATH="${dir}Meta.xml"
        DURATION_SECS=0
        CREATED_AT=""

        if [ -f "$META_PATH" ]; then
            # Extract duration (float, truncate to int)
            DURATION_RAW=$(grep -oP '<duration>\K[^<]+' "$META_PATH" 2>/dev/null || echo "0")
            DURATION_SECS=$(printf '%.0f' "$DURATION_RAW")

            # Extract creation timestamp (milliseconds since epoch)
            CREATION_MS=$(grep -oP '<creation>\K[^<]+' "$META_PATH" 2>/dev/null || echo "0")
            if [ "$CREATION_MS" != "0" ]; then
                CREATION_SECS=$(( CREATION_MS / 1000 ))
                CREATED_AT=$(date -d "@$CREATION_SECS" +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "")
            fi
        fi

        ENTRY=$(jq -n \
            --arg folder "$FOLDER" \
            --arg path "$WAV_PATH" \
            --argjson duration "$DURATION_SECS" \
            --arg created "$CREATED_AT" \
            --arg id "$REC_ID" \
            '{folder: $folder, path: $path, duration_secs: $duration, created_at: $created, recording_id: $id}')

        RESULTS=$(echo "$RESULTS" | jq --argjson entry "$ENTRY" '. + [$entry]')
    fi
done

echo "$RESULTS"
