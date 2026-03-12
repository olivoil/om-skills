#!/bin/bash
# Match screen recordings with Rodecaster recordings by time overlap
# Usage: ./match-recordings.sh <screenrecs-json-file> <rodecaster-json-file>
#
# Both arguments are file paths containing JSON arrays.
# Use "-" to read from stdin (only for one argument).
#
# Output: JSON array of matched groups to stdout
#   [{"mode": "omarchy+rodecaster", "video": {...}, "audio": {...}, "transcribe_from": "rodecaster"},
#    {"mode": "omarchy-only", "video": {...}, "audio": null, "transcribe_from": "omarchy"},
#    {"mode": "rodecaster-only", "video": null, "audio": {...}, "transcribe_from": "rodecaster"}]
#
# Matching logic: screen recording and Rodecaster recording are paired if
# their start times are within 5 minutes of each other.
#
# Requires: jq

set -e

SCREEN_FILE="${1:?Usage: $0 <screenrecs-json-file> <rodecaster-json-file>}"
RODECASTER_FILE="${2:?Usage: $0 <screenrecs-json-file> <rodecaster-json-file>}"

# Read JSON arrays
if [ "$SCREEN_FILE" = "-" ]; then
    SCREEN_JSON=$(cat)
else
    SCREEN_JSON=$(cat "$SCREEN_FILE")
fi

if [ "$RODECASTER_FILE" = "-" ]; then
    RODECASTER_JSON=$(cat)
else
    RODECASTER_JSON=$(cat "$RODECASTER_FILE")
fi

TOLERANCE=300

jq -n \
    --argjson screen "$SCREEN_JSON" \
    --argjson rodecaster "$RODECASTER_JSON" \
    --argjson tolerance "$TOLERANCE" \
'
def to_sod:
    split("T") | .[1] | split(":") | map(tonumber) |
    .[0] * 3600 + .[1] * 60 + .[2];

def abs: if . < 0 then -. else . end;

($screen | length) as $slen |
($rodecaster | length) as $rlen |

# Build a list of {si, ri, diff} for all pairs within tolerance
[range($slen) as $si | range($rlen) as $ri |
    ($screen[$si].created_at | to_sod) as $st |
    ($rodecaster[$ri].created_at | to_sod) as $rt |
    (($st - $rt) | abs) as $diff |
    select($diff <= $tolerance) |
    {si: $si, ri: $ri, diff: $diff}
] | sort_by(.diff) as $candidates |

# Greedy match: take best pairs, no duplicates
reduce $candidates[] as $c (
    {pairs: {}, used_s: [], used_r: []};
    if ((.used_s | map(. == $c.si) | any) or (.used_r | map(. == $c.ri) | any)) then .
    else
        .pairs += {($c.si | tostring): $c.ri} |
        .used_s += [$c.si] |
        .used_r += [$c.ri]
    end
) as $matched |

# Build output groups
[
    # Matched pairs → omarchy+rodecaster
    ($matched.pairs | to_entries[] |
        .key as $si | .value as $ri |
        {
            mode: "omarchy+rodecaster",
            video: $screen[$si | tonumber],
            audio: $rodecaster[$ri],
            transcribe_from: "rodecaster"
        }
    ),
    # Unmatched screen recordings → omarchy-only
    (range($slen) |
        . as $si |
        select(($matched.used_s | map(. == $si) | any) | not) |
        {
            mode: "omarchy-only",
            video: $screen[$si],
            audio: null,
            transcribe_from: "omarchy"
        }
    ),
    # Unmatched rodecaster recordings → rodecaster-only
    (range($rlen) |
        . as $ri |
        select(($matched.used_r | map(. == $ri) | any) | not) |
        {
            mode: "rodecaster-only",
            video: null,
            audio: $rodecaster[$ri],
            transcribe_from: "rodecaster"
        }
    )
]
'
