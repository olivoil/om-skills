#!/bin/bash
# FreshBooks API Script
# Creates time entries via API instead of browser automation

set -e

CONFIG_DIR="$HOME/.config/freshbooks"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.json"
TOKENS_FILE="$CONFIG_DIR/tokens.json"
CACHE_FILE="$CONFIG_DIR/cache.json"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Create default config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"default_client": "EXSquared"}' > "$CONFIG_FILE"
fi

# ============================================================
# CREDENTIAL HANDLING
# ============================================================

resolve_credential() {
    local value="$1"
    if [[ "$value" == op://* ]]; then
        op read "$value"
    else
        echo "$value"
    fi
}

check_tokens() {
    if [ ! -f "$TOKENS_FILE" ]; then
        echo "Error: No tokens file found. Run 'freshbooks-oauth.sh authorize' first." >&2
        exit 1
    fi
}

get_access_token() {
    check_tokens
    jq -r '.access_token' "$TOKENS_FILE"
}

# Auto-refresh if token is expired
maybe_refresh_token() {
    check_tokens
    local created_at=$(jq -r '.created_at' "$TOKENS_FILE")
    local expires_in=$(jq -r '.expires_in' "$TOKENS_FILE")
    local now=$(date +%s)
    local expires_at=$((created_at + expires_in - 300))  # 5 min buffer

    if [ "$now" -gt "$expires_at" ]; then
        echo "Token expired, refreshing..." >&2

        local CLIENT_ID=$(resolve_credential "$(jq -r '.client_id' "$CREDENTIALS_FILE")")
        local CLIENT_SECRET=$(resolve_credential "$(jq -r '.client_secret' "$CREDENTIALS_FILE")")
        local REFRESH_TOKEN=$(jq -r '.refresh_token' "$TOKENS_FILE")

        local RESPONSE=$(curl -s -X POST "https://api.freshbooks.com/auth/oauth/token" \
            -H "Content-Type: application/json" \
            -d "{
                \"grant_type\": \"refresh_token\",
                \"client_id\": \"$CLIENT_ID\",
                \"client_secret\": \"$CLIENT_SECRET\",
                \"refresh_token\": \"$REFRESH_TOKEN\"
            }")

        local ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
        if [ -n "$ERROR" ]; then
            echo "Error refreshing token: $ERROR" >&2
            exit 1
        fi

        echo "$RESPONSE" | jq '{
            access_token: .access_token,
            refresh_token: .refresh_token,
            expires_in: .expires_in,
            created_at: (now | floor)
        }' > "$TOKENS_FILE"

        echo "Token refreshed" >&2
    fi
}

# ============================================================
# API HELPERS
# ============================================================

api_get() {
    local endpoint="$1"
    maybe_refresh_token
    local token=$(get_access_token)
    curl -s -H "Authorization: Bearer $token" \
         -H "Content-Type: application/json" \
         "https://api.freshbooks.com$endpoint"
}

api_post() {
    local endpoint="$1"
    local data="$2"
    maybe_refresh_token
    local token=$(get_access_token)
    curl -s -X POST \
         -H "Authorization: Bearer $token" \
         -H "Content-Type: application/json" \
         -d "$data" \
         "https://api.freshbooks.com$endpoint"
}

# ============================================================
# BUSINESS & PROJECT INFO
# ============================================================

get_business_id() {
    # Check cache first
    if [ -f "$CACHE_FILE" ]; then
        local cached=$(jq -r '.business_id // empty' "$CACHE_FILE")
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    local response=$(api_get "/auth/api/v1/users/me")
    local business_id=$(echo "$response" | jq -r '.response.business_memberships[0].business.id')

    if [ "$business_id" = "null" ] || [ -z "$business_id" ]; then
        echo "Error: Could not get business_id" >&2
        exit 1
    fi

    # Cache it
    if [ -f "$CACHE_FILE" ]; then
        jq --arg bid "$business_id" '.business_id = $bid' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    else
        echo "{\"business_id\": \"$business_id\", \"projects\": {}}" > "$CACHE_FILE"
    fi

    echo "$business_id"
}

get_identity_id() {
    # Check cache first
    if [ -f "$CACHE_FILE" ]; then
        local cached=$(jq -r '.identity_id // empty' "$CACHE_FILE")
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    local response=$(api_get "/auth/api/v1/users/me")
    local identity_id=$(echo "$response" | jq -r '.response.id')

    if [ "$identity_id" = "null" ] || [ -z "$identity_id" ]; then
        echo "Error: Could not get identity_id" >&2
        exit 1
    fi

    # Cache it
    if [ -f "$CACHE_FILE" ]; then
        jq --arg iid "$identity_id" '.identity_id = $iid' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    else
        echo "{\"identity_id\": \"$identity_id\", \"projects\": {}}" > "$CACHE_FILE"
    fi

    echo "$identity_id"
}

get_account_id() {
    # Check cache first
    if [ -f "$CACHE_FILE" ]; then
        local cached=$(jq -r '.account_id // empty' "$CACHE_FILE")
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    local response=$(api_get "/auth/api/v1/users/me")
    local account_id=$(echo "$response" | jq -r '.response.business_memberships[0].business.account_id')

    if [ "$account_id" = "null" ] || [ -z "$account_id" ]; then
        echo "Error: Could not get account_id" >&2
        exit 1
    fi

    # Cache it
    if [ -f "$CACHE_FILE" ]; then
        jq --arg aid "$account_id" '.account_id = $aid' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    fi

    echo "$account_id"
}

list_projects() {
    local business_id=$(get_business_id)
    api_get "/projects/business/$business_id/projects?per_page=100" | jq '.projects[] | {id, title, client_id}'
}

list_clients() {
    local account_id=$(get_account_id)
    api_get "/accounting/account/$account_id/users/clients?per_page=100" | jq '.response.result.clients[] | {id: .id, name: .organization}'
}

get_client_id() {
    local client_name="$1"
    local account_id=$(get_account_id)

    # Check cache first
    if [ -f "$CACHE_FILE" ]; then
        local cached=$(jq -r --arg name "$client_name" '.clients[$name] // empty' "$CACHE_FILE")
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    # Fetch all clients and find by name (case-insensitive)
    local response=$(api_get "/accounting/account/$account_id/users/clients?per_page=100")
    local client_id=$(echo "$response" | jq -r --arg name "$client_name" \
        '.response.result.clients[] | select(.organization | ascii_downcase == ($name | ascii_downcase)) | .id' | head -1)

    if [ -z "$client_id" ]; then
        echo "Error: Client '$client_name' not found" >&2
        echo "Available clients:" >&2
        echo "$response" | jq -r '.response.result.clients[].organization' | head -10 >&2
        return 1
    fi

    # Cache it
    if [ -f "$CACHE_FILE" ]; then
        jq --arg name "$client_name" --arg cid "$client_id" '.clients[$name] = $cid' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    fi

    echo "$client_id"
}

get_project_id() {
    local project_name="$1"
    local business_id=$(get_business_id)

    # Check cache first
    if [ -f "$CACHE_FILE" ]; then
        local cached=$(jq -r --arg name "$project_name" '.projects[$name] // empty' "$CACHE_FILE")
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    # Fetch all projects and find by name (case-insensitive)
    local response=$(api_get "/projects/business/$business_id/projects?per_page=100")
    local project_id=$(echo "$response" | jq -r --arg name "$project_name" \
        '.projects[] | select(.title | ascii_downcase == ($name | ascii_downcase)) | .id' | head -1)

    if [ -z "$project_id" ]; then
        echo "Error: Project '$project_name' not found" >&2
        echo "Available projects:" >&2
        echo "$response" | jq -r '.projects[].title' | head -10 >&2
        return 1
    fi

    # Cache it
    if [ -f "$CACHE_FILE" ]; then
        jq --arg name "$project_name" --arg pid "$project_id" '.projects[$name] = $pid' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    fi

    echo "$project_id"
}

# ============================================================
# TIME ENTRIES
# ============================================================

# Get default client from config
get_default_client() {
    if [ -f "$CONFIG_FILE" ]; then
        jq -r '.default_client // "EXSquared"' "$CONFIG_FILE"
    else
        echo "EXSquared"
    fi
}

# Create a time entry
# Usage: create_time_entry --client <name> [--project <name>] --date <YYYY-MM-DD> --hours <hours> [--note <note>]
create_time_entry() {
    local project_name=""
    local client_name=""
    local date=""
    local hours=""
    local note=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|-p)
                project_name="$2"
                shift 2
                ;;
            --client|-c)
                client_name="$2"
                shift 2
                ;;
            --date|-d)
                date="$2"
                shift 2
                ;;
            --hours|-h)
                hours="$2"
                shift 2
                ;;
            --note|-n)
                note="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$date" ]; then
        echo "Error: --date is required" >&2
        return 1
    fi
    if [ -z "$hours" ]; then
        echo "Error: --hours is required" >&2
        return 1
    fi

    # Use default client if not specified
    if [ -z "$client_name" ]; then
        client_name=$(get_default_client)
    fi

    local business_id=$(get_business_id)
    local identity_id=$(get_identity_id)

    # Always get client_id (required for invoicing)
    local client_id=$(get_client_id "$client_name")
    if [ -z "$client_id" ]; then
        return 1
    fi

    # Convert hours to seconds (using awk for decimal support)
    local duration=$(awk "BEGIN {printf \"%.0f\", $hours * 3600}")

    local payload=""
    if [ -n "$project_name" ]; then
        # Both client and project
        local project_id=$(get_project_id "$project_name")
        if [ -z "$project_id" ]; then
            return 1
        fi
        payload=$(jq -n \
            --arg cid "$client_id" \
            --arg pid "$project_id" \
            --arg iid "$identity_id" \
            --arg date "$date" \
            --arg duration "$duration" \
            --arg note "$note" \
            '{
                time_entry: {
                    is_logged: true,
                    duration: ($duration | tonumber),
                    note: $note,
                    started_at: ($date + "T09:00:00.000Z"),
                    client_id: ($cid | tonumber),
                    project_id: ($pid | tonumber),
                    identity_id: ($iid | tonumber)
                }
            }')
    else
        # Client only (no project)
        payload=$(jq -n \
            --arg cid "$client_id" \
            --arg iid "$identity_id" \
            --arg date "$date" \
            --arg duration "$duration" \
            --arg note "$note" \
            '{
                time_entry: {
                    is_logged: true,
                    duration: ($duration | tonumber),
                    note: $note,
                    started_at: ($date + "T09:00:00.000Z"),
                    client_id: ($cid | tonumber),
                    identity_id: ($iid | tonumber)
                }
            }')
    fi

    local response=$(api_post "/timetracking/business/$business_id/time_entries" "$payload")

    local error=$(echo "$response" | jq -r '.error // .message // empty')
    if [ -n "$error" ]; then
        echo "Error creating time entry: $error" >&2
        echo "$response" | jq . >&2
        return 1
    fi

    echo "$response" | jq '{
        id: .time_entry.id,
        client_id: .time_entry.client_id,
        project_id: .time_entry.project_id,
        date: .time_entry.started_at,
        hours: ((.time_entry.duration // 0) / 3600),
        note: .time_entry.note
    }'
}

# List time entries for a date range
# Usage: list_time_entries --from <YYYY-MM-DD> --to <YYYY-MM-DD>
list_time_entries() {
    local start_date=""
    local end_date=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from|-f)
                start_date="$2"
                shift 2
                ;;
            --to|-t)
                end_date="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [ -z "$start_date" ] || [ -z "$end_date" ]; then
        echo "Error: --from and --to are required" >&2
        return 1
    fi

    local business_id=$(get_business_id)

    api_get "/timetracking/business/$business_id/time_entries?started_from=${start_date}T00:00:00Z&started_to=${end_date}T23:59:59Z" \
        | jq '.time_entries[] | {
            id,
            project_id,
            client_id,
            started_at,
            hours: ((.duration // 0) / 3600),
            note
        }'
}

# ============================================================
# MAIN
# ============================================================

case "${1:-}" in
    config)
        if [ -z "${2:-}" ]; then
            # Show current config
            echo "Config file: $CONFIG_FILE"
            cat "$CONFIG_FILE" | jq .
        else
            # Set config value: config <key> <value>
            if [ -z "${3:-}" ]; then
                echo "Usage: $0 config <key> <value>" >&2
                exit 1
            fi
            jq --arg k "$2" --arg v "$3" '.[$k] = $v' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            echo "Set $2 = $3"
        fi
        ;;
    business)
        get_business_id
        ;;
    identity)
        get_identity_id
        ;;
    projects)
        list_projects
        ;;
    clients)
        list_clients
        ;;
    project-id)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 project-id <project_name>" >&2
            exit 1
        fi
        get_project_id "$2"
        ;;
    client-id)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 client-id <client_name>" >&2
            exit 1
        fi
        get_client_id "$2"
        ;;
    create-time-entry)
        shift  # Remove the command name
        create_time_entry "$@"
        ;;
    list-time-entries)
        shift  # Remove the command name
        list_time_entries "$@"
        ;;
    *)
        echo "FreshBooks Time Entry API"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  projects                  - List all projects"
        echo "  clients                   - List all clients"
        echo "  project-id <name>         - Get project ID by name"
        echo "  client-id <name>          - Get client ID by name"
        echo ""
        echo "  create-time-entry         - Create a time entry"
        echo "    --client, -c <name>       FreshBooks client (see config.json)"
        echo "    --project, -p <name>      FreshBooks project (optional)"
        echo "    --date, -d <YYYY-MM-DD>   Date of the entry (required)"
        echo "    --hours, -h <hours>       Hours worked (required)"
        echo "    --note, -n <note>         Description (optional)"
        echo ""
        echo "  list-time-entries         - List time entries"
        echo "    --from, -f <YYYY-MM-DD>   Start date (required)"
        echo "    --to, -t <YYYY-MM-DD>     End date (required)"
        echo ""
        echo "  config                    - Show current config"
        echo "  config <key> <value>      - Set config value"
        echo "  business                  - Get business ID"
        echo "  identity                  - Get identity ID"
        echo ""
        echo "Config ($CONFIG_FILE):"
        echo "  default_client            - Client used when --client is not specified"
        echo ""
        echo "Examples:"
        echo "  # With project (client from config.json)"
        echo "  $0 create-time-entry --project 'Technomic' --date '2026-01-06' --hours 7.5 --note 'Development'"
        echo ""
        echo "  # Client only (no project, e.g., internal meetings)"
        echo "  $0 create-time-entry --date '2026-01-06' --hours 2.0 --note 'Meeting'"
        echo ""
        echo "  # Different client"
        echo "  $0 create-time-entry --client 'Rocksauce Studios' --date '2026-01-06' --hours 1.0"
        echo ""
        echo "  $0 list-time-entries --from '2026-01-05' --to '2026-01-11'"
        echo ""
        ;;
esac
